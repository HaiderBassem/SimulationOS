#!/usr/bin/env bash
#
# live-health.sh - L4b live-system acceptance.
#
# Boots the ISO, logs in on the serial console and runs real health checks
# INSIDE the guest: graphical.target, SDDM, the liveuser session, Hyprland,
# NetworkManager, PipeWire, portals and polkit.
#
# Package presence is not acceptance; this asserts on running state.
#
# The live medium ships root with an empty password (standard archiso), which
# is what makes an unattended serial login possible. That is a property of the
# live medium only - simulationos-deloop locks root on the installed system.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"
ISO="${1:-$(ls -1t "$OUT"/simulationos-*.iso 2>/dev/null | head -1)}"
TIMEOUT="${SIMOS_LIVE_TIMEOUT:-1800}"
RAM="${SIMOS_LIVE_RAM:-4096}"
ACCEL="${SIMOS_QEMU_ACCEL:-kvm:tcg}"
LOG="$OUT/live-health.log"
PIPE="${TMPDIR:-/tmp}/simos-serial"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }

[ -n "$ISO" ] && [ -f "$ISO" ] || { red "no ISO found in $OUT"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { red "qemu-system-x86_64 not installed"; exit 1; }

rm -f "$PIPE.in" "$PIPE.out"
mkfifo "$PIPE.in" "$PIPE.out"
: > "$LOG"

OVMF_CODE=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd \
         /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
         /opt/homebrew/share/qemu/edk2-x86_64-code.fd; do
    [ -f "$c" ] && { OVMF_CODE="$c"; break; }
done
OVMF_VARS_SRC=""
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd \
         /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
         /opt/homebrew/share/qemu/edk2-i386-vars.fd; do
    [ -f "$v" ] && { OVMF_VARS_SRC="$v"; break; }
done
[ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS_SRC" ] || { red "OVMF firmware not found"; exit 1; }
VARS="$OUT/OVMF_VARS.live-health.fd"; cp -f "$OVMF_VARS_SRC" "$VARS"

# "kvm:tcg" -> "-accel kvm -accel tcg": use KVM when the host offers it.
ACCEL_ARGS=""
for a in $(printf '%s' "$ACCEL" | tr ':' ' '); do ACCEL_ARGS="$ACCEL_ARGS -accel $a"; done

# Graphics: virtio-gpu, not "std". Hyprland needs a DRM device it can create a
# renderer on; on plain VGA (bochs) every process starts but nothing is drawn,
# which a process check cannot see. The "renders" assertion below guards that.
info "Booting $(basename "$ISO") for live health checks (timeout ${TIMEOUT}s)"
# shellcheck disable=SC2054,SC2086  # commas are part of QEMU option values; ACCEL_ARGS is a word list
qemu-system-x86_64 \
    -machine q35 $ACCEL_ARGS -cpu max -smp 2 -m "$RAM" \
    -display none -vga "${SIMOS_QEMU_VGA:-virtio}" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$VARS" \
    -serial "pipe:$PIPE" \
    -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
    -audiodev none,id=nosnd -device intel-hda -device hda-duplex,audiodev=nosnd \
    -drive "file=$ISO,media=cdrom,readonly=on" -boot order=d -no-reboot &
QPID=$!
# shellcheck disable=SC2064
trap "kill $QPID 2>/dev/null; rm -f '$PIPE.in' '$PIPE.out'" EXIT

# Stream the guest's serial output into the log.
cat "$PIPE.out" >>"$LOG" &
CATPID=$!
exec 3>"$PIPE.in"
say() { printf '%s\n' "$1" >&3; }

# Strip NULs, CSI colour codes, OSC sequences (systemd shell integration)
# and turn CR into LF so line anchors mean what they say.
clean_log() {
    tr -d '\000' < "$LOG" \
      | sed -e 's/\x1b\][^\x07]*\x07//g' \
            -e 's/\x1b\][^\x1b]*\x1b\\//g' \
            -e 's/\x1b\[[0-9;?=]*[a-zA-Z]//g' \
            -e 's/\r/\n/g' \
      | awk '{gsub(/##BEGIN /,"\n##BEGIN "); gsub(/##END /,"\n##END "); print}'
}

wait_for() { # pattern, seconds
    local deadline=$(( $(date +%s) + $2 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        kill -0 "$QPID" 2>/dev/null || return 2
        clean_log | grep -aqE "$1" && return 0
        sleep 3
    done
    return 1
}

info "Waiting for the login prompt"
wait_for 'simulationos login:|login:' "$TIMEOUT"; rc=$?
if [ "$rc" -eq 2 ]; then
    red "QEMU exited before the guest reached a login prompt."
    red "This is usually a QEMU invocation problem, not a SimulationOS problem."
    red "Serial output captured so far:"; tail -30 "$LOG"
    exit 1
elif [ "$rc" -ne 0 ]; then
    red "timed out after ${TIMEOUT}s waiting for a login prompt"
    red "(hosted runners have no KVM, so this runs under TCG emulation)"
    tail -30 "$LOG"
    exit 1
fi
green "    login prompt reached"

# Log in as root (empty password on the live medium) and mark the session so
# the checks can be located unambiguously in the log.
say ""; sleep 2
say "root"; sleep 8
say "export PS1= PAGER=cat SYSTEMD_PAGER=cat SYSTEMD_PAGERSECURE=0 SYSTEMD_COLORS=0 TERM=dumb"
sleep 3
say "stty -echo 2>/dev/null; printf 'SIMOS_SHELL_%s\\n' READY"
if ! wait_for '^SIMOS_SHELL_READY' 240; then
    red "serial root login failed"; tail -30 "$LOG"; exit 1
fi
green "    serial root shell obtained"

# Send a command and wait for its END marker, so slow guests cannot cause
# commands to interleave. Never blocks forever.
# The serial line echoes whatever we type. If the marker literals appeared in
# the command text, every marker would match the ECHO rather than the output:
# wait_for would return instantly and the assertions would match echoed
# command text instead of real results (a silent false pass).
#
# So the markers are ASSEMBLED AT RUNTIME with printf. The typed line contains
# "##BEG%s"/"##EN%s"; only genuine guest output can contain "##BEGIN label"
# and "##END label".
run() {
    local label="$1" cmd="$2" limit="${3:-180}"
    say "printf '##BEG%s %s\\n' IN $label; { $cmd ; } 2>&1; printf '##EN%s %s\\n' D $label"
    if ! wait_for "^##END $label" "$limit"; then
        printf '  (timed out collecting %s)\n' "$label" >&2
    fi
}

# hyprctl needs the instance signature of the liveuser session.
HC='sig=$(ls /run/user/1000/hypr 2>/dev/null | head -1); hc() { runuser -u liveuser -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl "$@"; }'

# "Ready" means the desktop is DRAWN: the bar and the wallpaper have mapped
# their surfaces. A process existing is not enough - under emulation Waybar
# can take a long time between starting and showing its bar.
info "Waiting for the graphical session to settle (inside the guest)"
run wait-desktop "$HC"'; for i in $(seq 1 120); do if systemctl is-active --quiet graphical.target && pgrep -x Hyprland >/dev/null 2>&1 && hc layers 2>/dev/null | grep -q "namespace: waybar" && hc layers 2>/dev/null | grep -q "namespace: wallpaper"; then echo DESKTOP_READY; break; fi; sleep 5; done; systemctl is-active graphical.target' 900

info "Collecting live-system state"
run default-target   'systemctl get-default'
run failed-units     'systemctl --failed --no-legend --plain'
run graphical        'systemctl is-active graphical.target'
run displaymanager   'systemctl is-active display-manager.service; systemctl is-active sddm.service'
run sessions         'loginctl list-sessions --no-legend; loginctl list-users --no-legend'
run liveuser         'id liveuser'
run hyprland         'pgrep -a Hyprland || echo NO_HYPRLAND'
run session-procs    'pgrep -a -f "waybar|swaybg|mako|hyprpolkitagent|nm-applet" || echo NO_SESSION_PROCS'
run portals          'runuser -u liveuser -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop >/dev/null 2>&1 && echo PORTAL_ACTIVATES || echo PORTAL_NO_ACTIVATE; pgrep -a -f xdg-desktop-portal || true'
run networkmanager   'systemctl is-active NetworkManager; nmcli -t general status; nmcli -t device status'
run dns              'getent hosts archlinux.org || echo DNS_FAIL'
run pipewire         'runuser -u liveuser -- env XDG_RUNTIME_DIR=/run/user/1000 wpctl status 2>&1 | head -20 || echo WPCTL_FAIL'
run hypr-config      "$HC"'; hc configerrors | grep -v "^[[:space:]]*$" | head -20; hc configerrors | grep -qi "error" && echo HYPR_CONFIG_ERRORS || echo HYPR_CONFIG_CLEAN'
run hypr-render      "$HC"'; if grep -qE "no renderer for gl formats|Failed to initialize renderer state" /run/user/1000/hypr/$sig/hyprland.log; then echo HYPR_NO_RENDERER; else echo HYPR_RENDERS; fi; ls /dev/dri'
run hypr-layers      "$HC"'; hc layers | grep -oE "namespace: (waybar|wallpaper)" | sort -u'
# The installer must be able to START, not merely exist: every Calamares
# binary and module has to resolve its shared libraries.
run calamares-libs   'export LD_LIBRARY_PATH=/usr/lib/simulationos/calamares-compat; miss=$(for f in /usr/bin/calamares /usr/lib/libcalamares*.so /usr/lib/calamares/modules/*/*.so; do ldd "$f" 2>/dev/null; done | awk "/not found/{print \$1}" | sort -u | tr "\n" " "); if [ -z "$miss" ]; then echo CALAMARES_LIBS_OK; else echo "CALAMARES_LIBS_MISSING $miss"; fi; unset LD_LIBRARY_PATH'
run calamares-qml    'test -d /usr/share/simulationos/calamares/qml/. && echo CALAMARES_QML_OK || echo CALAMARES_QML_MISSING'
run install-source   'test -r /run/archiso/bootmnt/arch/x86_64/airootfs.sfs && echo SFS_PRESENT || echo SFS_MISSING'
run calamares-bin    'test -x /usr/bin/calamares && echo CALAMARES_PRESENT || echo CALAMARES_MISSING'
run calamares-cfg    'test -f /usr/share/simulationos/calamares/settings.conf && echo CALAMARES_CFG_PRESENT || echo CALAMARES_CFG_MISSING'
run desktop-entry    'test -f /usr/share/applications/simulationos-install.desktop && echo DESKTOP_PRESENT || echo DESKTOP_MISSING'
run sddm-journal     'journalctl -u sddm --no-pager -n 25 2>&1 | tail -25'
run hypr-journal     'journalctl --no-pager -b -n 200 2>&1 | grep -i -m 20 hyprland || echo NO_HYPRLAND_JOURNAL'

say "echo SIMOS_CHECKS_DONE"
wait_for 'SIMOS_CHECKS_DONE' 240 || red "checks did not complete cleanly (log may be partial)"

say "systemctl poweroff"; sleep 10
kill "$QPID" 2>/dev/null; kill "$CATPID" 2>/dev/null

# ------------------------------------------------------------------- verdict
printf '\n== live system acceptance\n'
ERRORS=0
sect() { clean_log | sed -n "/^##BEGIN $1\$/,/^##END $1\$/p" 2>/dev/null; }
assert() { # label, section, pattern
    if sect "$2" | grep -aqE "$3"; then green "  ok      $1"; else red "  FAILED  $1"; ERRORS=$((ERRORS+1)); fi
}
report() { printf '  ----- %s\n' "$1"; sect "$1" | sed '1d;$d' | sed 's/^/        /' | head -25; }

assert "desktop reached readiness"   wait-desktop   'DESKTOP_READY'
assert "default target is graphical" default-target 'graphical.target'
assert "graphical.target active"     graphical      '^active$'
assert "display-manager active"      displaymanager '^active$'
assert "liveuser exists"             liveuser       'uid=1000'
assert "Hyprland running"            hyprland       'Hyprland'
assert "Hyprland config has no errors" hypr-config  '^HYPR_CONFIG_CLEAN'
assert "Hyprland has a renderer"     hypr-render    '^HYPR_RENDERS'
assert "bar is drawn"                hypr-layers    'namespace: waybar'
assert "wallpaper is drawn"          hypr-layers    'namespace: wallpaper'
assert "session components running"  session-procs  'waybar'
assert "wallpaper daemon running"    session-procs  'swaybg'
assert "notification daemon running" session-procs  'mako'
assert "polkit agent running"        session-procs  'hyprpolkitagent'
assert "xdg-desktop-portal present"  portals        'PORTAL_ACTIVATES|xdg-desktop-portal'
assert "NetworkManager active"       networkmanager '^active$'
assert "DNS resolves"                dns            'archlinux\.org'
assert "PipeWire running"            pipewire       'PipeWire|Audio'
assert "Calamares installed"         calamares-bin  'CALAMARES_PRESENT'
assert "Calamares libraries resolve" calamares-libs '^CALAMARES_LIBS_OK'
assert "Calamares qml directory"     calamares-qml  'CALAMARES_QML_OK'
assert "install source readable"     install-source 'SFS_PRESENT'
assert "installer config present"    calamares-cfg  'CALAMARES_CFG_PRESENT'
assert "installer launcher present"  desktop-entry  'DESKTOP_PRESENT'

printf '\n== diagnostics\n'
for s in failed-units sessions sddm-journal hypr-journal hypr-config hypr-render hypr-layers calamares-libs networkmanager pipewire; do report "$s"; done

printf '\n'
if [ "$ERRORS" -gt 0 ]; then
    red "LIVE HEALTH FAILED: $ERRORS check(s) - full log: $LOG"; exit 1
fi
green "LIVE HEALTH PASSED - full log: $LOG"
