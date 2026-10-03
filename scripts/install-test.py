#!/usr/bin/env python3
"""install-test.py - end-to-end installation acceptance for SimulationOS.

Drives the REAL user journey in QEMU and proves each link of the chain:

    ISO -> live Hyprland -> "Install SimulationOS" -> Calamares (GUI)
        -> install to a blank disk -> power off -> ISO DETACHED
        -> GRUB -> linux-cachyos -> systemd -> SDDM -> user login -> Hyprland
        -> reboot -> boots again -> clean power off

Method (the same technique CachyOS uses with quickemu/quicktest, without the
extra tooling): the guest is controlled like a person would control it -
QEMU `send-key` for the keyboard, an absolute-pointer tablet for the mouse,
`screendump` + tesseract OCR to read the screen. A serial console is used
only to OBSERVE (live medium: root shell; installed system: a shell obtained
by logging in graphically and running sudo with the user's password - which is
itself the proof that login and sudo authentication work).

Nothing in the installed system is modified to make the test pass, and the
ISO is not attached during any installed-system boot.

Usage:
    scripts/install-test.py [path/to.iso]          full run
    scripts/install-test.py --phase install        live + install only
    scripts/install-test.py --phase boot           installed-disk boots only
    scripts/install-test.py --keep                 leave the VM running on failure

Results: out/install-test/{results.json,summary.md,*.png,*.log}
Exit status is non-zero if any required check is not VERIFIED.

Needs: qemu-system-x86_64, OVMF/edk2 firmware, tesseract. Python stdlib only.
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEST_USER = "simulationtest"
TEST_PASS = "Sim0S-alpha-test"
TEST_HOST = "simos-test"

OVMF_CODE = [
    "/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_CODE.fd",
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd", "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd",
    "/opt/homebrew/share/qemu/edk2-x86_64-code.fd", "/usr/local/share/qemu/edk2-x86_64-code.fd",
]
OVMF_VARS = [
    "/usr/share/OVMF/OVMF_VARS_4M.fd", "/usr/share/OVMF/OVMF_VARS.fd",
    "/usr/share/edk2/x64/OVMF_VARS.4m.fd", "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd",
    "/opt/homebrew/share/qemu/edk2-i386-vars.fd", "/usr/local/share/qemu/edk2-i386-vars.fd",
]

STATUSES = ("VERIFIED", "FAILED", "BLOCKED", "NOT TESTED")

# The acceptance matrix, in report order. Every key starts as NOT TESTED.
MATRIX = [
    "Live ISO UEFI boot", "Live graphical.target", "Live SDDM", "Live autologin", "Live Hyprland",
    "Live Hyprland config", "Installer launcher", "Calamares UI", "Partition", "Mount", "unpackfs",
    "Machine ID", "fstab", "Locale", "Keyboard", "Timezone", "User creation", "removeuser",
    "simulationos-deloop", "Normal mkinitcpio", "GRUB install", "NetworkManager enablement",
    "SDDM enablement", "Calamares completion", "Shutdown", "ISO detached", "Installed GRUB boot",
    "Installed linux-cachyos", "Installed initramfs", "Installed systemd", "Installed SDDM",
    "Installed user login", "Installed Hyprland", "Network", "Audio", "liveuser absent",
    "live autologin absent", "NOPASSWD absent", "root locked", "sudo requires password",
    "pacman", "System health", "second reboot", "shutdown",
]


def log(msg):
    print(f"[{datetime.datetime.now():%H:%M:%S}] {msg}", flush=True)


class Fail(Exception):
    """A step failed in a way that makes continuing pointless."""


# ------------------------------------------------------------------- results
class Results:
    def __init__(self, outdir):
        self.outdir = outdir
        self.data = {k: {"status": "NOT TESTED", "evidence": ""} for k in MATRIX}

    def set(self, key, ok, evidence=""):
        status = ok if ok in STATUSES else ("VERIFIED" if ok else "FAILED")
        self.data.setdefault(key, {})
        self.data[key] = {"status": status, "evidence": str(evidence).strip()[:400]}
        mark = {"VERIFIED": "\033[32mok     \033[0m", "FAILED": "\033[31mFAILED \033[0m"}.get(status, status + " ")
        log(f"  {mark} {key}" + (f"  ({self.data[key]['evidence'][:110]})" if evidence else ""))
        self.save()
        return status == "VERIFIED"

    def save(self):
        with open(os.path.join(self.outdir, "results.json"), "w") as fh:
            json.dump({"generated_utc": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
                       "checks": self.data}, fh, indent=2)
        with open(os.path.join(self.outdir, "summary.md"), "w") as fh:
            fh.write("| Check | Status | Evidence |\n|---|---|---|\n")
            for key, val in self.data.items():
                ev = val["evidence"].replace("|", "\\|").replace("\n", " ")
                fh.write(f"| {key} | {val['status']} | {ev} |\n")

    def failed(self, keys=None):
        keys = keys or list(self.data)
        return [k for k in keys if self.data[k]["status"] != "VERIFIED"]


# ----------------------------------------------------------------------- QMP
class QMP:
    def __init__(self, path, timeout=60):
        deadline = time.time() + timeout
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(path)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.3)
        self.sock.settimeout(60)
        self.buf = b""
        self._read()                       # greeting
        self.cmd("qmp_capabilities")

    def _read(self):
        while True:
            while b"\n" not in self.buf:
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise ConnectionError("QMP connection closed")
                self.buf += chunk
            line, self.buf = self.buf.split(b"\n", 1)
            if line.strip():
                msg = json.loads(line)
                if "event" in msg:
                    continue
                return msg

    def cmd(self, name, **args):
        req = {"execute": name}
        if args:
            req["arguments"] = args
        self.sock.sendall(json.dumps(req).encode() + b"\n")
        msg = self._read()
        if "error" in msg:
            raise RuntimeError(f"QMP {name}: {msg['error']}")
        return msg.get("return")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


# QEMU key names for characters that need a specific key or Shift.
_KEYS = {
    " ": "spc", "-": "minus", "=": "equal", "[": "bracket_left", "]": "bracket_right",
    ";": "semicolon", "'": "apostrophe", "`": "grave_accent", "\\": "backslash",
    ",": "comma", ".": "dot", "/": "slash", "\n": "ret", "\t": "tab",
}
_SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9",
    ")": "0", "_": "minus", "+": "equal", "{": "bracket_left", "}": "bracket_right",
    ":": "semicolon", '"': "apostrophe", "~": "grave_accent", "|": "backslash",
    "<": "comma", ">": "dot", "?": "slash",
}


# -------------------------------------------------------------------- screen
def ppm_to_png(ppm_path, png_path, scale=1):
    """Convert a binary PPM (P6) to PNG, optionally nearest-neighbour upscaled."""
    with open(ppm_path, "rb") as fh:
        data = fh.read()
    tokens, pos = [], 0
    while len(tokens) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        tokens.append(data[pos:end])
        pos = end
    pos += 1
    if tokens[0] != b"P6":
        raise ValueError("not a P6 PPM")
    w, h = int(tokens[1]), int(tokens[2])
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        row = data[pos + y * stride: pos + (y + 1) * stride]
        if scale == 2:
            wide = bytearray(stride * 2)
            for c in range(3):
                wide[c::6] = row[c::3]
                wide[c + 3::6] = row[c::3]
            row = bytes(wide)
            raw += b"\x00" + row + b"\x00" + row
        else:
            raw += b"\x00" + row

    def chunk(tag, body):
        out = struct.pack(">I", len(body)) + tag + body
        return out + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 3)) + chunk(b"IEND", b"")
    with open(png_path, "wb") as fh:
        fh.write(png)
    return w, h


def _norm(text):
    return re.sub(r"[^a-z0-9]+", "", text.lower())


class Screen:
    """Look at the guest display and act on it."""

    def __init__(self, qmp, outdir):
        self.qmp, self.outdir = qmp, outdir
        self.count = 0
        self.size = (1280, 800)
        self.have_ocr = shutil.which("tesseract") is not None

    # -- capture
    def _dump(self, name):
        self.count += 1
        base = os.path.join(self.outdir, f"{self.count:03d}-{name}")
        ppm = base + ".ppm"
        self.qmp.cmd("screendump", filename=ppm)
        for _ in range(50):
            if os.path.exists(ppm) and os.path.getsize(ppm) > 100:
                break
            time.sleep(0.1)
        self.size = ppm_to_png(ppm, base + ".png")
        return base, ppm

    def shot(self, name):
        base, ppm = self._dump(name)
        os.remove(ppm)
        return base + ".png"

    def words(self, name="ocr"):
        """OCR the screen. Returns (png_path, [(text, x, y, w, h, line_id)])."""
        base, ppm = self._dump(name)
        big = base + ".x2.png"
        ppm_to_png(ppm, big, scale=2)          # UI text is small; 2x helps OCR a lot
        os.remove(ppm)
        out = []
        if self.have_ocr:
            res = subprocess.run(["tesseract", big, "stdout", "--psm", "11", "-l", "eng", "tsv"],
                                 capture_output=True, text=True)
            for line in res.stdout.splitlines()[1:]:
                f = line.split("\t")
                if len(f) < 12 or not f[11].strip():
                    continue
                out.append((f[11].strip(), int(f[6]) // 2, int(f[7]) // 2, int(f[8]) // 2, int(f[9]) // 2,
                            (f[2], f[3], f[4])))
        os.remove(big)
        return base + ".png", out

    def text(self, name="ocr"):
        return " ".join(w[0] for w in self.words(name)[1])

    def find(self, phrase, name="find"):
        """Return the centre (x, y) of `phrase` on screen, or None."""
        want = _norm(phrase)
        _, words = self.words(name)
        for i in range(len(words)):
            acc = ""
            for j in range(i, min(i + 8, len(words))):
                if words[j][5] != words[i][5]:
                    break
                acc += _norm(words[j][0])
                if acc == want or (len(want) > 5 and want in acc):
                    x0, y0 = words[i][1], min(w[2] for w in words[i:j + 1])
                    x1 = words[j][1] + words[j][3]
                    y1 = max(w[2] + w[4] for w in words[i:j + 1])
                    return (x0 + x1) // 2, (y0 + y1) // 2
                if not want.startswith(acc):
                    break
        return None

    def wait_text(self, phrases, timeout, name="wait", interval=4):
        """Wait until any of `phrases` is visible. Returns the phrase or None."""
        if isinstance(phrases, str):
            phrases = [phrases]
        deadline = time.time() + timeout
        while True:
            seen = _norm(self.text(name))
            for p in phrases:
                if _norm(p) in seen:
                    return p
            if time.time() > deadline:
                return None
            time.sleep(interval)

    # -- input
    def key(self, combo, hold=80):
        keys = [{"type": "qcode", "data": k} for k in combo.split("+")]
        self.qmp.cmd("send-key", keys=keys, **{"hold-time": hold})
        time.sleep(0.25)

    def type(self, text, delay=0.06):
        for ch in text:
            if ch in _SHIFTED:
                combo = "shift+" + _SHIFTED[ch]
            elif ch.isupper():
                combo = "shift+" + ch.lower()
            else:
                combo = _KEYS.get(ch, ch)
            keys = [{"type": "qcode", "data": k} for k in combo.split("+")]
            self.qmp.cmd("send-key", keys=keys, **{"hold-time": 60})
            time.sleep(delay)
        time.sleep(0.3)

    def move(self, x, y):
        w, h = self.size
        self.qmp.cmd("input-send-event", events=[
            {"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / w)}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / h)}}])
        time.sleep(0.2)

    def click(self, x, y):
        self.move(x, y)
        for down in (True, False):
            self.qmp.cmd("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
            time.sleep(0.12)
        time.sleep(0.4)

    def click_text(self, phrase, name="click", dx=0, dy=0):
        pos = self.find(phrase, name)
        if pos is None:
            return False
        self.click(pos[0] + dx, pos[1] + dy)
        return True


# -------------------------------------------------------------------- serial
class Serial:
    """Serial console of the guest: type lines, read what came back.

    Output is read from QEMU's own chardev logfile, so nothing is lost while
    no client is connected.
    """

    def __init__(self, sock_path, log_path):
        self.sock_path, self.log_path = sock_path, log_path
        self.sock = None
        self.seq = 0

    def connect(self, timeout=60):
        deadline = time.time() + timeout
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.sock_path)
                self.sock.setblocking(False)
                return
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.3)

    def send(self, line):
        self._drain()
        self.sock.setblocking(True)
        self.sock.sendall(line.encode() + b"\n")
        self.sock.setblocking(False)

    def _drain(self):
        try:
            while self.sock.recv(65536):
                pass
        except (BlockingIOError, OSError):
            pass

    def clean(self):
        try:
            with open(self.log_path, "rb") as fh:
                data = fh.read()
        except FileNotFoundError:
            return ""
        text = data.replace(b"\x00", b"").decode("utf-8", "replace")
        text = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", text)     # OSC
        text = re.sub(r"\x1b\[[0-9;?=]*[a-zA-Z]", "", text)             # CSI
        return text.replace("\r", "\n")

    def wait_for(self, pattern, timeout, alive=None):
        deadline = time.time() + timeout
        rx = re.compile(pattern, re.M)
        while True:
            self._drain()
            m = rx.search(self.clean())
            if m:
                return m
            if alive and not alive():
                return None
            if time.time() > deadline:
                return None
            time.sleep(1.5)

    def run(self, cmd, timeout=180):
        """Run a shell command in the logged-in serial shell; return (rc, output).

        The markers are assembled by printf in the guest, so the echoed command
        line can never be mistaken for the command's output.
        """
        self.seq += 1
        tag = f"T{self.seq:04d}"
        self.send(f"printf '\\n##BEG%s {tag}\\n' IN; {{ {cmd} ; }} 2>&1; printf '\\n##EN%s {tag} rc=%s\\n' D \"$?\"")
        m = self.wait_for(rf"^##END {tag} rc=(\d+)", timeout)
        text = self.clean()
        start = text.rfind(f"##BEGIN {tag}")
        if m is None or start < 0:
            return None, text[-1500:]
        end = text.find(f"##END {tag}", start)
        segment = text[start:end]
        body = segment.split("\n", 1)[1] if "\n" in segment else ""
        return int(m.group(1)), body.strip()


# ------------------------------------------------------------------------ VM
class VM:
    def __init__(self, workdir, disk, iso=None, ram=4096, cpus=None, accel=None, tag="vm"):
        self.workdir, self.disk, self.iso, self.tag = workdir, disk, iso, tag
        self.ram = ram
        self.cpus = cpus or min(4, os.cpu_count() or 2)
        self.accel = accel or os.environ.get("SIMOS_QEMU_ACCEL", "kvm:tcg")
        # Unix socket paths are limited to ~104 bytes; fall back to a short
        # temporary directory when the work directory is deep.
        sockdir = workdir
        if len(os.path.join(workdir, f"{tag}.serial")) > 96:
            sockdir = tempfile.mkdtemp(prefix="simos-")
        self.qmp_path = os.path.join(sockdir, f"{tag}.qmp")
        self.ser_path = os.path.join(sockdir, f"{tag}.serial")
        self.ser_log = os.path.join(workdir, f"{tag}-serial.log")
        self.vars = os.path.join(workdir, "OVMF_VARS.fd")
        self.proc = None

    def start(self):
        code = next((p for p in OVMF_CODE if os.path.exists(p)), None)
        vars_src = next((p for p in OVMF_VARS if os.path.exists(p)), None)
        if not code or not vars_src:
            raise Fail("OVMF/edk2 firmware not found")
        if not os.path.exists(self.vars):
            shutil.copyfile(vars_src, self.vars)      # kept across boots: holds the EFI boot entries
        for p in (self.qmp_path, self.ser_path, self.ser_log):
            if os.path.exists(p):
                os.remove(p)
        args = [
            "qemu-system-x86_64",
            "-machine", "q35", "-cpu", "max", "-smp", str(self.cpus), "-m", str(self.ram),
            # virtio-gpu, not "std": Hyprland needs a DRM device it can create a
            # renderer on. On plain VGA (bochs) it starts but draws nothing.
            "-display", "none", "-vga", os.environ.get("SIMOS_QEMU_VGA", "virtio"),
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={self.vars}",
            "-drive", f"file={self.disk},if=virtio,format=qcow2,cache=unsafe,discard=unmap",
            "-device", "virtio-net-pci,netdev=n0", "-netdev", "user,id=n0",
            "-audiodev", "none,id=nosnd", "-device", "intel-hda", "-device", "hda-duplex,audiodev=nosnd",
            "-device", "qemu-xhci", "-device", "usb-tablet",
            "-chardev", f"socket,id=ser0,path={self.ser_path},server=on,wait=off,logfile={self.ser_log}",
            "-serial", "chardev:ser0",
            "-qmp", f"unix:{self.qmp_path},server=on,wait=off",
        ]
        # "kvm:tcg" = try KVM, fall back to emulation (hosted runners, macOS).
        for accel in self.accel.split(":"):
            args += ["-accel", accel]
        if self.iso:
            args += ["-drive", f"file={self.iso},media=cdrom,readonly=on", "-boot", "order=d,menu=off"]
        with open(os.path.join(self.workdir, f"{self.tag}-qemu.cmd"), "w") as fh:
            fh.write(" ".join(args) + "\n")
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL,
                                     stderr=open(os.path.join(self.workdir, f"{self.tag}-qemu.err"), "w"))
        time.sleep(1.5)
        if self.proc.poll() is not None:
            raise Fail(f"QEMU exited immediately (see {self.tag}-qemu.err)")

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def wait_exit(self, timeout):
        try:
            self.proc.wait(timeout=timeout)
            return True
        except subprocess.TimeoutExpired:
            return False

    def kill(self):
        if self.alive():
            self.proc.kill()
            self.proc.wait()


# ================================================================== the test
def kvm_usable():
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


class Timeouts:
    """Budgets in seconds. Emulation (no KVM) is roughly 6x slower."""

    def __init__(self):
        k = 1 if kvm_usable() else int(os.environ.get("SIMOS_TCG_FACTOR", "6"))
        self.boot = 420 * k          # firmware -> login prompt / greeter
        self.desktop = 300 * k       # greeter/login -> usable desktop
        self.ui = 90 * k             # one installer page
        self.install = 1800 * k      # all Calamares jobs
        self.shutdown = 120 * k
        self.cmd = 60 * k


def first_line(text):
    return (text or "").strip().splitlines()[0].strip() if (text or "").strip() else ""


def lines(text):
    return [ln.strip() for ln in (text or "").splitlines() if ln.strip()]


class Guest:
    """One running VM with its screen and serial console."""

    def __init__(self, outdir, disk, iso, tag):
        self.vm = VM(outdir, disk, iso=iso, tag=tag)
        self.vm.start()
        self.qmp = QMP(self.vm.qmp_path)
        self.screen = Screen(self.qmp, outdir)
        self.screen.count = len(glob.glob(os.path.join(outdir, "[0-9][0-9][0-9]-*.png")))
        self.serial = Serial(self.vm.ser_path, self.vm.ser_log)
        self.serial.connect()

    def sh(self, cmd, timeout=120):
        rc, out = self.serial.run(cmd, timeout)
        return rc, out

    def ok(self, cmd, timeout=120):
        return self.sh(cmd, timeout)[0] == 0

    def close(self):
        self.qmp.close()
        self.vm.kill()


# Calamares appends to its session log; $L is only the run that is in progress.
THIS_RUN = ("L=/tmp/calamares-this-run.log; awk '/=== START CALAMARES/ { buf = \"\" } { buf = buf $0 \"\\n\" } "
            "END { printf \"%s\", buf }' /root/.cache/calamares/session.log > $L 2>/dev/null; ")


# ------------------------------------------------------------- phase: install
def phase_install(args, res, outdir, T):
    disk = os.path.join(outdir, "simulationos-test.qcow2")
    for stale in (disk, os.path.join(outdir, "OVMF_VARS.fd")):
        if os.path.exists(stale):
            os.remove(stale)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", disk, "30G"], check=True)

    log(f"Booting the live ISO: {os.path.basename(args.iso)} ({'KVM' if kvm_usable() else 'TCG emulation'})")
    g = Guest(outdir, disk, args.iso, "live")
    ser, sc = g.serial, g.screen
    try:
        # ---- live boot
        if not ser.wait_for(r"login:", T.boot, alive=g.vm.alive):
            res.set("Live ISO UEFI boot", False, "no login prompt on the serial console")
            raise Fail("the live system did not boot")
        ser.send("")
        time.sleep(2)
        ser.send("root")
        time.sleep(6)
        ser.send("export PS1= PAGER=cat SYSTEMD_PAGER=cat SYSTEMD_PAGERSECURE=0 SYSTEMD_COLORS=0 TERM=dumb; stty -echo")
        time.sleep(2)
        rc, out = g.sh("test -d /sys/firmware/efi && uname -r", T.cmd)
        res.set("Live ISO UEFI boot", rc == 0 and "cachyos" in (out or ""), f"UEFI, kernel {first_line(out)}")
        if rc != 0:
            raise Fail("no usable root shell on the live serial console")

        log("Waiting for the live desktop")
        g.sh("for i in $(seq 1 120); do systemctl is-active --quiet graphical.target && pgrep -x Hyprland >/dev/null "
             "&& pgrep -x waybar >/dev/null && break; sleep 3; done", T.desktop + 60)
        time.sleep(8)
        rc, out = g.sh("systemctl is-active graphical.target; systemctl get-default")
        res.set("Live graphical.target", "active" in lines(out)[:1] and "graphical.target" in (out or ""), " / ".join(lines(out)))
        rc, out = g.sh("systemctl is-active sddm.service display-manager.service")
        res.set("Live SDDM", lines(out)[:2] == ["active", "active"], "sddm.service " + " / ".join(lines(out)))
        rc, out = g.sh("loginctl list-sessions --no-legend | grep -E 'liveuser.*seat0' | head -1")
        res.set("Live autologin", rc == 0 and "liveuser" in (out or ""), first_line(out) or "no liveuser session on seat0")

        hc = ("sig=$(ls -t /run/user/1000/hypr 2>/dev/null | head -1); hc() { runuser -u liveuser -- env "
              "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl \"$@\"; }; ")
        rc, out = g.sh(hc + "pgrep -x Hyprland >/dev/null && echo RUNNING; "
                       "grep -qE 'no renderer for gl formats|Failed to initialize renderer state' "
                       "/run/user/1000/hypr/$sig/hyprland.log && echo NO_RENDERER; "
                       "hc layers | grep -oE 'namespace: (waybar|wallpaper)' | sort -u; "
                       "pgrep -x -u liveuser 'waybar|swaybg|mako|nm-applet|hyprpolkitagent' -l | awk '{print $2}' | sort -u | tr '\\n' ' '")
        o = out or ""
        res.set("Live Hyprland", "RUNNING" in o and "NO_RENDERER" not in o and "namespace: waybar" in o
                and "namespace: wallpaper" in o and all(p in o for p in ("mako", "swaybg", "nm-applet", "hyprpolkitagen")),
                " ".join(lines(o)))
        rc, out = g.sh(hc + "hc configerrors")
        res.set("Live Hyprland config", rc == 0 and not lines(out), "hyprctl configerrors: " + ("none" if not lines(out) else first_line(out)))
        sc.shot("live-desktop")

        # ---- installer launcher: the application-menu entry (.desktop file)
        log("Launching the installer from the application menu")
        bar_button = sc.find("Install SimulationOS", "live-bar") is not None
        sc.key("meta_l+d")
        time.sleep(4 if kvm_usable() else 8)
        sc.type("Install Sim")
        time.sleep(2)
        sc.shot("launcher-menu")
        sc.key("ret")
        opened = sc.wait_text("Welcome to the SimulationOS", T.ui * 2, "installer-welcome")
        rc, out = g.sh("pgrep -a -x calamares")
        cmdline_ok = "-c /usr/share/simulationos/calamares" in (out or "")
        res.set("Installer launcher", bool(opened) and cmdline_ok and bar_button,
                f"menu entry -> pkexec -> {first_line(out)[:70]}; bar button visible: {bar_button}")
        if not opened:
            rc, out = g.sh("tail -5 /home/liveuser/simulationos-install.log")
            raise Fail("Calamares did not open: " + (out or "")[-300:])

        # ---- Calamares pages
        def page(marker, name):
            got = sc.wait_text(marker, T.ui, name)
            if not got:
                res.set("Calamares UI", False, f"page '{name}' not reached")
                raise Fail(f"installer page '{name}' not reached")

        sc.key("alt+n")
        page(["The system language will be set", "Region:"], "installer-location")
        sc.key("alt+n")
        page(["Keyboard model", "Type here to test"], "installer-keyboard")
        sc.key("alt+n")
        page("Erase disk", "installer-partition")
        if not sc.click_text("Erase disk", "installer-partition-click"):
            raise Fail("could not select 'Erase disk'")
        page(["After:", "EFI system"], "installer-partition-erase")
        layout = sc.text("installer-partition-layout")
        sc.key("alt+n")
        page("What is your name", "installer-users")
        pos = sc.find("What is your name", "installer-users-label")
        sc.click(pos[0], pos[1] + 27)                 # the name field sits under its label
        sc.type("Simulation Test")
        sc.key("tab"); sc.key("ctrl+a"); sc.type(TEST_USER)
        sc.key("tab"); sc.key("ctrl+a"); sc.type(TEST_HOST)
        sc.key("tab"); sc.type(TEST_PASS)
        sc.key("tab"); sc.type(TEST_PASS)
        time.sleep(2)
        sc.shot("installer-users-filled")
        sc.key("alt+n")
        page("This is an overview", "installer-summary")
        summary = sc.text("installer-summary-text")
        sc.key("alt+i")
        page("not be able to undo", "installer-confirm")
        res.set("Calamares UI", True, "welcome, location, keyboard, partition, users, summary navigated")
        golden = all(w in _norm(layout + summary) for w in ("ext4", "efi"))
        log("Starting the installation" + ("" if golden else " (WARNING: summary does not show EFI + ext4)"))
        sc.key("alt+i")

        # ---- wait for the jobs
        deadline = time.time() + T.install
        last, failed, done = "", "", False
        while time.time() < deadline:
            time.sleep(20)
            rc, out = g.sh(THIS_RUN + "grep -c 'Installation failed' $L; "
                           "grep 'Starting job' $L | tail -1 | sed 's/.*Starting job //'; "
                           "grep -c 'installed system verified' $L", T.cmd)
            ls = lines(out)
            if len(ls) >= 3:
                if ls[1] != last:
                    last = ls[1]
                    log(f"    job {last}")
                if ls[0] != "0":
                    failed = last
                    break
            if sc.wait_text(["All done", "Installation Failed"], 0, "installer-progress") == "All done":
                done = True
                break
        sc.shot("installer-end")
        rc, slog = g.sh(THIS_RUN + "cat $L", T.cmd * 2)
        with open(os.path.join(outdir, "calamares-session.log"), "w") as fh:
            fh.write(slog or "")
        if not done:
            rc, out = g.sh(THIS_RUN + "grep -A6 'Installation failed' $L | head -12")
            res.set("Calamares completion", False, f"failed in job {failed or last}: {' '.join(lines(out))[:260]}")
            raise Fail(f"installation failed in job {failed or last}")
        res.set("Calamares completion", "installed system verified" in (slog or ""),
                "finished page reached; target verification job passed")

        # ---- inspect what was written, from the live system
        log("Inspecting the installed disk")
        inspect_target(g, res, T)

        # ---- power off
        ser.send("systemctl poweroff")
        res.set("Shutdown", g.vm.wait_exit(T.shutdown), "live system powered off cleanly after the installation")
    finally:
        try:
            sc.shot("live-final")
        except Exception:                                # the VM may already be gone
            pass
        g.close()


def inspect_target(g, res, T):
    """Mount the freshly installed disk read-only and check each installer job's result."""
    sh = g.sh
    rc, out = sh("mkdir -p /mnt/t && mount -o ro /dev/vda2 /mnt/t && mount -o ro /dev/vda1 /mnt/t/boot/efi && echo MOUNTED")
    if "MOUNTED" not in (out or ""):
        res.set("Mount", False, "could not mount /dev/vda2 and /dev/vda1: " + (out or "")[-200:])
        return
    rc, out = sh("lsblk -rno NAME,FSTYPE,PARTTYPENAME /dev/vda; blkid -o value -s PTTYPE /dev/vda")
    o = out or ""
    res.set("Partition", "vda1 vfat EFI" in o.replace("\\x20", " ") and "vda2 ext4" in o and "gpt" in o, " | ".join(lines(o)))
    rc, out = sh("findmnt -rno TARGET,SOURCE,FSTYPE /mnt/t /mnt/t/boot/efi")
    res.set("Mount", len(lines(out)) == 2, " | ".join(lines(out)))
    rc, out = sh("grep -c '^NAME=\"SimulationOS\"' /mnt/t/etc/os-release; du -sxm /mnt/t | cut -f1; test -x /mnt/t/usr/bin/Hyprland && echo HYPR")
    ls = lines(out)
    res.set("unpackfs", len(ls) >= 3 and ls[0] == "1" and int(ls[1]) > 3000 and "HYPR" in ls,
            f"root filesystem {ls[1] if len(ls) > 1 else '?'} MiB, SimulationOS os-release, Hyprland present")
    rc, out = sh("cat /mnt/t/etc/machine-id; cat /etc/machine-id")
    ls = lines(out)
    res.set("Machine ID", len(ls) == 2 and re.fullmatch(r"[0-9a-f]{32}", ls[0]) is not None and ls[0] != ls[1],
            f"target {ls[0] if ls else '?'} differs from the live medium")
    rc, out = sh("grep -v '^#' /mnt/t/etc/fstab | grep -v '^$'; echo ---; blkid -o value -s UUID /dev/vda1 /dev/vda2")
    body, _, uuids = (out or "").partition("---")
    uu = lines(uuids)
    fst = lines(body)
    res.set("fstab", len(uu) == 2 and all(any(u in ln for ln in fst) for u in uu) and len(fst) == 2
            and not re.search(r"archiso|airootfs|/run/|loop", body), " | ".join(fst))
    rc, out = sh("cat /mnt/t/etc/locale.conf | head -1; grep -c -v '^#' /mnt/t/etc/locale.gen")
    res.set("Locale", "LANG=" in (out or ""), " / ".join(lines(out)[:1]) + " (locale.gen entries: " + (lines(out)[-1] if lines(out) else "?") + ")")
    rc, out = sh("grep -h -E '^(KEYMAP|XKBLAYOUT)=' /mnt/t/etc/vconsole.conf /mnt/t/etc/default/keyboard")
    res.set("Keyboard", "KEYMAP=" in (out or "") and "XKBLAYOUT=" in (out or ""), " ".join(lines(out)))
    rc, out = sh("readlink /mnt/t/etc/localtime; readlink /etc/localtime")
    res.set("Timezone", "zoneinfo/" in first_line(out), "target /etc/localtime -> " + first_line(out))
    rc, out = sh(f"grep '^{TEST_USER}:' /mnt/t/etc/passwd; stat -c '%u %a' /mnt/t/home/{TEST_USER}; "
                 f"grep -E '^wheel:.*{TEST_USER}' /mnt/t/etc/group | cut -d: -f1; "
                 f"awk -F: '$1==\"{TEST_USER}\"{{print substr($2,1,3)}}' /mnt/t/etc/shadow; "
                 f"test -f /mnt/t/home/{TEST_USER}/.config/hypr/hyprland.lua && echo SKEL; cat /mnt/t/etc/hostname")
    o = out or ""
    res.set("User creation", f"/home/{TEST_USER}:/bin/bash" in o and "1000 700" in o and "wheel" in o and "$" in o
            and "SKEL" in o and TEST_HOST in o, " | ".join(lines(o)))
    rc, out = sh("grep -c '^liveuser:' /mnt/t/etc/passwd; test -e /mnt/t/home/liveuser && echo HOME_LEFT; "
                 "grep -cE '(^|[:,])liveuser(,|$)' /mnt/t/etc/group")
    res.set("removeuser", lines(out) == ["0", "0"], "liveuser absent from passwd, group and /home")
    rc, out = sh("cd /mnt/t; for f in etc/sudoers.d/10-simulationos-live etc/polkit-1/rules.d/49-simulationos-live-nopasswd.rules "
                 "etc/sddm.conf.d/20-simulationos-live-autologin.conf etc/systemd/system/getty@tty1.service.d/autologin.conf "
                 "etc/mkinitcpio.conf.d/archiso.conf usr/local/bin/simulationos-install usr/share/simulationos/calamares "
                 "usr/lib/simulationos/calamares-compat usr/bin/calamares; do test -e $f && echo LEFT:$f; done; "
                 "awk -F: '$1==\"root\"{print \"root:\" substr($2,1,1)}' etc/shadow; "
                 "grep -rhsE '^[^#]*NOPASSWD' etc/sudoers etc/sudoers.d | head -1; cat etc/sudoers.d/10-simulationos-wheel | grep -v '^#'")
    o = out or ""
    res.set("simulationos-deloop", "LEFT:" not in o and "root:!" in o and "NOPASSWD" not in o and "%wheel ALL=(ALL:ALL) ALL" in o,
            "live sudo/polkit/autologin/archiso config and installer removed; root locked; wheel must authenticate"
            if "LEFT:" not in o else " ".join(lines(o)))
    rc, out = sh("ls -l /mnt/t/boot/vmlinuz-linux-cachyos /mnt/t/boot/initramfs-linux-cachyos.img | awk '{print $5, $9}'; "
                 "grep '^HOOKS' /mnt/t/etc/mkinitcpio.conf; lsinitcpio /mnt/t/boot/initramfs-linux-cachyos.img | grep -c archiso")
    ls = lines(out)
    res.set("Normal mkinitcpio", len(ls) == 4 and ls[-1] == "0" and "archiso" not in ls[2],
            f"{ls[2] if len(ls) > 2 else ''}; archiso files in the image: {ls[-1] if ls else '?'}")
    rc, out = sh("U=$(blkid -o value -s UUID /dev/vda2); grep -c \"root=UUID=$U\" /mnt/t/boot/grub/grub.cfg; "
                 "grep -c 'vmlinuz-linux-cachyos' /mnt/t/boot/grub/grub.cfg; grep -c 'initramfs-linux-cachyos.img' /mnt/t/boot/grub/grub.cfg; "
                 "find /mnt/t/boot/efi/EFI -iname '*.efi' | sed 's|/mnt/t/boot/efi/||' | sort | tr '\\n' ' '; echo; "
                 "efibootmgr | grep -i simulationos | head -1")
    ls = lines(out)
    res.set("GRUB install", len(ls) >= 5 and all(x != "0" for x in ls[:3]) and "grubx64.efi" in ls[3].lower()
            and "boot/bootx64.efi" in ls[3].lower() and "simulationos" in ls[4].lower(),
            f"grub.cfg boots linux-cachyos by root UUID; ESP: {ls[3] if len(ls) > 3 else '?'}; {ls[4] if len(ls) > 4 else 'no EFI entry'}")
    rc, out = sh("readlink /mnt/t/etc/systemd/system/multi-user.target.wants/NetworkManager.service")
    res.set("NetworkManager enablement", "NetworkManager.service" in (out or ""), first_line(out))
    rc, out = sh("readlink /mnt/t/etc/systemd/system/display-manager.service; readlink /mnt/t/etc/systemd/system/default.target; "
                 "grep -A3 '^\\[Autologin\\]' /mnt/t/etc/sddm.conf | grep -E '^User=' ")
    o = out or ""
    res.set("SDDM enablement", "sddm.service" in o and "graphical.target" in o and "User=liveuser" not in o,
            " | ".join(lines(o)))
    sh("umount -R /mnt/t")


# ---------------------------------------------------------------- phase: boot
GREETER = ["User name", "Password", "Login"]


def greeter_login(g, T, name):
    """Log in at the SDDM greeter the way a person would. Returns True once typed."""
    sc = g.screen
    if not sc.wait_text(GREETER, T.boot, f"{name}-greeter", interval=5):
        return False
    time.sleep(3)
    sc.shot(f"{name}-greeter-ready")
    # Put the cursor in the user-name field explicitly: the greeter remembers
    # the last user, so which field has focus differs between boots.
    pos = sc.find("User name", f"{name}-greeter-user")
    if pos:
        sc.click(pos[0] + 40, pos[1] + 30)
    sc.key("ctrl+a")
    sc.type(TEST_USER)
    sc.key("tab")
    sc.type(TEST_PASS)
    sc.shot(f"{name}-greeter-filled")
    sc.key("ret")
    return True


def desktop_shell(g, T, name):
    """Open a terminal in the user's session and get a serial login from it.

    Returns (terminal_seen, sudo_prompt_seen, serial_ok).
    """
    sc, ser = g.screen, g.serial
    prompt = f"{TEST_USER}@{TEST_HOST}"
    terminal = False
    deadline = time.time() + T.desktop
    while time.time() < deadline and not terminal:
        time.sleep(10)
        seen = _norm(sc.text(f"{name}-desktop"))
        if any(_norm(w) in seen for w in ("User name", "Login failed")):
            continue                                   # still at the greeter
        sc.key("meta_l+ret")
        terminal = bool(sc.wait_text(prompt, T.ui, f"{name}-terminal", interval=5))
    if not terminal:
        return False, False, False
    sc.shot(f"{name}-terminal-open")
    # Real sudo, real password prompt, typed by "the user".
    sc.type("sudo systemctl start serial-getty@ttyS0.service\n")
    asked = bool(sc.wait_text("password for", T.ui, f"{name}-sudo-prompt", interval=3))
    sc.type(TEST_PASS + "\n")
    if not ser.wait_for(r"login:", T.ui * 2):
        return terminal, asked, False
    ser.send(TEST_USER)
    ser.wait_for(r"Password:", T.ui)
    time.sleep(1)
    ser.send(TEST_PASS)
    time.sleep(5)
    ser.send("export PS1= PAGER=cat SYSTEMD_PAGER=cat SYSTEMD_PAGERSECURE=0 SYSTEMD_COLORS=0 TERM=dumb SIMOS_FETCH_SHOWN=1; stty -echo")
    time.sleep(2)
    rc, out = g.sh("id -un", T.cmd)
    return terminal, asked, (rc == 0 and first_line(out) == TEST_USER)


def phase_boot(args, res, outdir, T):
    disk = os.path.join(outdir, "simulationos-test.qcow2")
    if not os.path.exists(disk):
        raise Fail(f"no installed disk at {disk}; run the install phase first")

    # ============================================================ first boot
    log("Booting the installed disk ALONE (no ISO attached)")
    g = Guest(outdir, disk, None, "installed")
    sc = g.screen
    with open(os.path.join(outdir, "installed-qemu.cmd")) as fh:
        cmdline = fh.read()
    res.set("ISO detached", "media=cdrom" not in cmdline and ".iso" not in cmdline,
            "QEMU started with the qcow2 disk only (see installed-qemu.cmd)")
    try:
        # GRUB's menu is only on screen for a few seconds: capture fast, read later.
        grub_shots = []
        t0 = time.time()
        while time.time() - t0 < (25 if kvm_usable() else 90):
            grub_shots.append(sc.shot("installed-firmware"))
            time.sleep(1)
        grub_seen = False
        for path in grub_shots:
            if grub_seen or not sc.have_ocr:
                os.remove(path)
                continue
            out = subprocess.run(["tesseract", path, "stdout", "--psm", "6", "-l", "eng"], capture_output=True, text=True).stdout
            if "GRUB" in out and "SimulationOS" in out.replace(" ", ""):
                grub_seen = True
                os.replace(path, os.path.join(outdir, "installed-grub-menu.png"))
            else:
                os.remove(path)

        typed = greeter_login(g, T, "boot1")
        res.set("Installed SDDM", typed, "SDDM greeter displayed (no autologin)" if typed else "no greeter appeared")
        if not typed:
            raise Fail("the installed system did not reach the SDDM greeter")
        terminal, asked, serial_ok = desktop_shell(g, T, "boot1")
        res.set("Installed user login", terminal, f"{TEST_USER} logged in through SDDM; terminal prompt visible"
                if terminal else "no user session after entering the credentials")
        if not serial_ok:
            res.set("Installed Hyprland", terminal, "terminal opened in Hyprland, but no shell could be obtained for further checks")
            raise Fail("could not obtain a shell in the installed system")
        installed_checks(g, res, T, grub_seen, asked)

        # ========================================================= second boot
        log("Rebooting the installed system")
        rc, boot1 = g.sh("cat /proc/sys/kernel/random/boot_id")
        g.serial.send("sudo -n systemctl reboot")
        time.sleep(20 if kvm_usable() else 60)
        typed = greeter_login(g, T, "boot2")
        terminal, asked, serial_ok = (False, False, False)
        if typed:
            terminal, asked, serial_ok = desktop_shell(g, T, "boot2")
        ok2, ev = False, "the system did not come back to a usable session after reboot"
        if serial_ok:
            rc, out = g.sh("cat /proc/sys/kernel/random/boot_id; systemctl is-active graphical.target sddm.service NetworkManager.service; "
                           "pgrep -x Hyprland >/dev/null && echo HYPR; test -e /run/archiso && echo ARCHISO")
            ls = lines(out)
            ok2 = bool(ls) and ls[0] != first_line(boot1) and ls[1:4] == ["active"] * 3 and "HYPR" in ls and "ARCHISO" not in ls
            ev = "new boot id; graphical.target, SDDM, NetworkManager active; Hyprland session running" if ok2 else " | ".join(ls)
        res.set("second reboot", ok2, ev)

        # ============================================================ power off
        if serial_ok:
            g.sh(f"printf '%s\\n' '{TEST_PASS}' | sudo -S -p '' -v")
            g.serial.send("sudo -n systemctl poweroff")
            res.set("shutdown", g.vm.wait_exit(T.shutdown), "systemctl poweroff completed; the VM exited by itself")
    finally:
        try:
            sc.shot("installed-final")
        except Exception:
            pass
        g.close()


def installed_checks(g, res, T, grub_seen, sudo_asked):
    """Assertions on the running installed system, as the installed user."""
    sh = g.sh

    # sudo must require authentication BEFORE we authenticate.
    rc, out = sh("sudo -k; sudo -n true")
    refused = rc != 0
    rc, out = sh(f"printf '%s\\n' '{TEST_PASS}' | sudo -S -p '' -v && sudo -n id -u")
    res.set("sudo requires password", refused and first_line(out) == "0",
            f"'sudo -n true' refused without a password; works after entering it"
            + ("; password prompt seen in the terminal" if sudo_asked else ""))

    rc, out = sh("uname -r; cat /proc/cmdline; efibootmgr 2>/dev/null | grep -E '^BootCurrent|SimulationOS' | head -2")
    o = out or ""
    res.set("Installed linux-cachyos", "cachyos" in first_line(o) and "vmlinuz-linux-cachyos" in o, f"kernel {first_line(o)}")
    res.set("Installed GRUB boot", "BOOT_IMAGE=/boot/vmlinuz-linux-cachyos" in o and "root=UUID=" in o,
            ("GRUB menu seen on screen; " if grub_seen else "") + "kernel command line set by GRUB: "
            + (lines(o)[1] if len(lines(o)) > 1 else ""))
    rc, out = sh("findmnt -rno SOURCE,FSTYPE /; findmnt -rno SOURCE,FSTYPE /boot/efi; test -e /run/archiso && echo ARCHISO; "
                 "sudo -n lsinitcpio /boot/initramfs-linux-cachyos.img | grep -c archiso; "
                 "grep -rs archiso /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/mkinitcpio.d | head -1")
    ls = lines(out)
    res.set("Installed initramfs", len(ls) >= 3 and "/dev/vda2 ext4" in ls[0] and "vfat" in ls[1] and "ARCHISO" not in ls and "0" in ls[2:3],
            f"root on {ls[0] if ls else '?'}, ESP {ls[1] if len(ls) > 1 else '?'}; no archiso in image or config; /run/archiso absent")
    rc, out = sh("systemctl is-system-running; systemctl get-default; systemctl --failed --no-legend --plain | awk '{print $1}'; "
                 "echo ---; systemctl --user --failed --no-legend --plain | awk '{print $1}'")
    sysp, _, userp = (out or "").partition("---")
    sl = lines(sysp)
    failed_units = sl[2:] + lines(userp)
    res.set("Installed systemd", len(sl) >= 2 and sl[0] in ("running", "degraded", "starting") and sl[1] == "graphical.target",
            f"state {sl[0] if sl else '?'}, default target {sl[1] if len(sl) > 1 else '?'}")
    res.set("System health", not failed_units and sl[:1] == ["running"],
            "no failed system or user units" if not failed_units else "failed units: " + " ".join(failed_units))
    rc, out = sh("systemctl is-active sddm.service; systemctl is-enabled sddm.service; "
                 "grep -rhsE '^User=.+' /etc/sddm.conf /etc/sddm.conf.d | head -1")
    ls = lines(out)
    res.set("Installed SDDM", ls[:2] == ["active", "enabled"] and len(ls) == 2,
            "sddm active and enabled; greeter shown; no autologin user configured")
    rc, out = sh(f"id {TEST_USER}; loginctl list-sessions --no-legend | grep -E '{TEST_USER}.*seat0' | head -1; "
                 f"stat -c '%U %a' /home/{TEST_USER}; hostname")
    o = out or ""
    res.set("Installed user login", "wheel" in o and "seat0" in o and f"{TEST_USER} 700" in o and TEST_HOST in o,
            " | ".join(lines(o))[:300])

    hc = "export XDG_RUNTIME_DIR=/run/user/$(id -u); export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1); "
    rc, out = sh(hc + "pgrep -x Hyprland >/dev/null && echo RUNNING; hyprctl configerrors | grep -c .; "
                 "hyprctl layers | grep -oE 'namespace: (waybar|wallpaper)' | sort -u | tr '\\n' ' '; echo; "
                 "pgrep -x -u $(id -u) 'waybar|swaybg|mako|nm-applet|hyprpolkitagent' -l | awk '{print $2}' | sort -u | tr '\\n' ' '; echo; "
                 "hyprctl getoption input:kb_layout | head -1; grep -rl -E 'liveuser|/mnt/m\\.2' ~/.config 2>/dev/null | head -1")
    ls = lines(out)
    o = out or ""
    res.set("Installed Hyprland", "RUNNING" in ls[:1] and ls[1:2] == ["0"] and "namespace: waybar" in o and "namespace: wallpaper" in o
            and all(p in o for p in ("mako", "swaybg", "nm-applet", "hyprpolkitagen")) and "liveuser" not in ls[-1],
            f"Hyprland running for {TEST_USER}, 0 config errors, bar + wallpaper drawn; components: {ls[3] if len(ls) > 3 else '?'}")

    rc, out = sh("systemctl is-enabled NetworkManager.service; systemctl is-active NetworkManager.service; nmcli -t -f STATE general; "
                 "nmcli -t -f DEVICE,STATE device | head -2 | tr '\\n' ' '; echo; getent hosts archlinux.org | head -1")
    ls = lines(out)
    res.set("Network", ls[:2] == ["enabled", "active"] and "connected" in (ls[2] if len(ls) > 2 else "") and "archlinux.org" in (out or ""),
            " | ".join(ls))
    rc, out = sh("systemctl --user is-active pipewire.service wireplumber.service pipewire-pulse.service | tr '\\n' ' '; echo; "
                 "wpctl status | grep -E 'PipeWire|Sinks|Dummy|Built-in|Speaker|Audio' | head -4 | tr '\\n' ' '")
    ls = lines(out)
    res.set("Audio", ls[:1] == ["active active active"] and "PipeWire" in (out or ""),
            "pipewire, wireplumber, pipewire-pulse active; " + (ls[1][:160] if len(ls) > 1 else ""))

    rc, out = sh("id liveuser 2>&1 | head -1; test -e /home/liveuser && echo HOME_LEFT; grep -c liveuser /etc/passwd /etc/group /etc/shadow 2>/dev/null")
    res.set("liveuser absent", "no such user" in (out or "") and "HOME_LEFT" not in (out or ""), first_line(out))
    rc, out = sh("grep -rhsE 'liveuser' /etc/sddm.conf /etc/sddm.conf.d /etc/systemd/system/getty@tty1.service.d 2>/dev/null | head -2; "
                 "test -e /etc/sddm.conf.d/20-simulationos-live-autologin.conf && echo LEFT")
    res.set("live autologin absent", not lines(out), "no liveuser autologin in SDDM or getty configuration")
    rc, out = sh("sudo -n sh -c \"grep -rhsE '^[^#]*NOPASSWD' /etc/sudoers /etc/sudoers.d; ls /etc/polkit-1/rules.d\"")
    res.set("NOPASSWD absent", rc == 0 and "NOPASSWD" not in (out or "") and "49-simulationos-live" not in (out or ""),
            "no NOPASSWD sudo rule and no live polkit rule")
    rc, out = sh("sudo -n passwd -S root")
    res.set("root locked", len((out or "").split()) > 1 and (out or "").split()[1] in ("L", "LK"), first_line(out))

    rc, out = sh("grep -E '^SigLevel' /etc/pacman.conf | head -1; sudo -n pacman -Sy 2>&1 | tail -2 | tr '\\n' ' '; echo; "
                 "pacman -Si linux-cachyos 2>/dev/null | grep -E '^(Repository|Version)' | tr -s ' ' | tr '\\n' ' '; echo; "
                 "pacman -Q cachyos-calamares 2>&1 | head -1; pacman -Qk 2>/dev/null | grep -v ' 0 missing' | head -5 | tr '\\n' ';'", T.cmd * 4)
    ls = lines(out)
    o = out or ""
    res.set("pacman", "Required" in ls[0] and "Repository : cachyos" in o and "was not found" in o,
            f"{ls[0]}; database sync ok; linux-cachyos resolvable from [cachyos]; installer package removed; "
            + ("missing files: " + ls[-1][:160] if "missing" in ls[-1] else "pacman -Qk clean"))

    # Installer choices must have persisted on the running system.
    rc, out = sh("timedatectl show -p Timezone --value; cat /etc/locale.conf | head -1; localectl status | grep -E 'Keymap|X11 Layout' | tr -s ' ' | tr '\\n' ' '")
    ls = lines(out)
    if len(ls) >= 2 and (ls[0] in ("UTC", "") or "LANG=" not in ls[1]):
        res.set("Timezone", False, f"running system reports timezone '{ls[0]}'")
    log("    installed settings: " + " | ".join(ls))


# ----------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="SimulationOS installation acceptance test")
    ap.add_argument("iso", nargs="?", help="ISO to test (default: newest out/simulationos-*.iso)")
    ap.add_argument("--phase", choices=("all", "install", "boot"), default="all")
    ap.add_argument("--out", default=os.path.join(os.environ.get("SIMOS_OUT_DIR", os.path.join(REPO, "out")), "install-test"))
    args = ap.parse_args()

    for tool in ("qemu-system-x86_64", "qemu-img", "tesseract"):
        if not shutil.which(tool):
            sys.exit(f"install-test: required tool not found: {tool}")
    if args.phase != "boot":
        if not args.iso:
            isos = sorted(glob.glob(os.path.join(os.path.dirname(args.out), "simulationos-*.iso")), key=os.path.getmtime)
            args.iso = isos[-1] if isos else None
        if not args.iso or not os.path.isfile(args.iso):
            sys.exit("install-test: no ISO given and none found in out/")

    outdir = args.out
    os.makedirs(outdir, exist_ok=True)
    res = Results(outdir)
    if args.phase == "boot" and os.path.exists(os.path.join(outdir, "results.json")):
        with open(os.path.join(outdir, "results.json")) as fh:
            res.data.update(json.load(fh).get("checks", {}))
    else:
        for old in glob.glob(os.path.join(outdir, "*.png")) + glob.glob(os.path.join(outdir, "*.log")):
            os.remove(old)

    T = Timeouts()
    log(f"Acceleration: {'KVM' if kvm_usable() else 'TCG emulation (slow; timeouts scaled)'}; results in {outdir}")
    stopped = ""
    try:
        if args.phase in ("all", "install"):
            phase_install(args, res, outdir, T)
        if args.phase in ("all", "boot"):
            phase_boot(args, res, outdir, T)
    except Fail as exc:
        stopped = str(exc)
        log(f"\033[31mSTOPPED: {stopped}\033[0m")
    except Exception as exc:                              # harness error: report, never hide
        stopped = f"harness error: {exc!r}"
        log(f"\033[31m{stopped}\033[0m")
        import traceback
        traceback.print_exc()
    res.save()

    scope = MATRIX
    if args.phase == "install":
        scope = MATRIX[:MATRIX.index("ISO detached")]
    elif args.phase == "boot":
        scope = MATRIX[MATRIX.index("ISO detached"):]
    print("\n== installation acceptance matrix")
    for key in MATRIX:
        val = res.data[key]
        colour = {"VERIFIED": "\033[32m", "FAILED": "\033[31m"}.get(val["status"], "\033[33m")
        print(f"  {colour}{val['status']:<10}\033[0m {key:<28} {val['evidence'][:150]}")
    bad = res.failed(scope)
    print()
    if bad or stopped:
        if stopped:
            print(f"stopped at: {stopped}")
        print("not verified: " + ", ".join(bad))
        print("\033[31mSIMULATIONOS INSTALLATION ACCEPTANCE FAILED\033[0m")
        sys.exit(1)
    print("\033[32mSIMULATIONOS INSTALLATION ACCEPTANCE PASSED\033[0m"
          + ("" if args.phase == "all" else f" (phase: {args.phase})"))


if __name__ == "__main__":
    main()
