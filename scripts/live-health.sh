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

info "Booting $(basename "$ISO") for live health checks (timeout ${TIMEOUT}s)"
# shellcheck disable=SC2054  # commas are part of QEMU option values
qemu-system-x86_64 \
    -machine "q35,accel=$ACCEL" -cpu max -smp 2 -m "$RAM" \
    -display none -vga std \
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

wait_for() { # pattern, seconds
    local deadline=$(( $(date +%s) + $2 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        kill -0 "$QPID" 2>/dev/null || return 2
        grep -aqE "$1" "$LOG" && return 0
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
say "export PS1=; stty -echo 2>/dev/null; echo SIMOS_SHELL_READY"
if ! wait_for 'SIMOS_SHELL_READY' 180; then
    red "serial root login failed"; tail -30 "$LOG"; exit 1
fi
green "    serial root shell obtained"

run() { say "echo '##BEGIN $1'; { $2 ; } 2>&1; echo '##END $1'"; sleep "${3:-6}"; }

info "Collecting live-system state"
run default-target   'systemctl get-default'                                  5
run failed-units     'systemctl --failed --no-legend --plain'                 8
run graphical        'systemctl is-active graphical.target'                   5
run displaymanager   'systemctl is-active display-manager.service; systemctl is-active sddm.service' 6
run sessions         'loginctl list-sessions --no-legend; loginctl list-users --no-legend' 6
run liveuser         'id liveuser'                                            5
run hyprland         'pgrep -a Hyprland || echo NO_HYPRLAND'                   5
run session-procs    'pgrep -a -f "waybar|hyprpaper|mako|hyprpolkitagent|nm-applet" || echo NO_SESSION_PROCS' 5
run portals          'pgrep -a -f "xdg-desktop-portal" || echo NO_PORTALS'     5
run networkmanager   'systemctl is-active NetworkManager; nmcli -t general status; nmcli -t device status' 8
run dns              'getent hosts archlinux.org || echo DNS_FAIL'            10
run pipewire         'runuser -u liveuser -- env XDG_RUNTIME_DIR=/run/user/1000 wpctl status 2>&1 | head -20 || echo WPCTL_FAIL' 8
run calamares-bin    'test -x /usr/bin/calamares && echo CALAMARES_PRESENT || echo CALAMARES_MISSING' 5
run calamares-cfg    'test -f /usr/share/simulationos/calamares/settings.conf && echo CALAMARES_CFG_PRESENT || echo CALAMARES_CFG_MISSING' 5
run desktop-entry    'test -f /usr/share/applications/simulationos-install.desktop && echo DESKTOP_PRESENT || echo DESKTOP_MISSING' 5
run sddm-journal     'journalctl -u sddm --no-pager -n 25 2>&1 | tail -25'    8
run hypr-journal     'journalctl --no-pager -n 25 -g -i hyprland 2>&1 | tail -25 || true' 8

say "echo SIMOS_CHECKS_DONE"
wait_for 'SIMOS_CHECKS_DONE' 240 || red "checks did not complete cleanly (log may be partial)"

say "systemctl poweroff"; sleep 10
kill "$QPID" 2>/dev/null; kill "$CATPID" 2>/dev/null

# ------------------------------------------------------------------- verdict
printf '\n== live system acceptance\n'
ERRORS=0
sect() { sed -n "/##BEGIN $1/,/##END $1/p" "$LOG" 2>/dev/null; }
assert() { # label, section, pattern
    if sect "$2" | grep -aqE "$3"; then green "  ok      $1"; else red "  FAILED  $1"; ERRORS=$((ERRORS+1)); fi
}
report() { printf '  ----- %s\n' "$1"; sect "$1" | sed '1d;$d' | sed 's/^/        /' | head -25; }

assert "default target is graphical" default-target 'graphical.target'
assert "graphical.target active"     graphical      '^active'
assert "display-manager active"      displaymanager '^active'
assert "liveuser exists"             liveuser       'uid=1000'
assert "Hyprland running"            hyprland       'Hyprland'
assert "session components running"  session-procs  'waybar|hyprpaper|mako|hyprpolkitagent'
assert "xdg-desktop-portal running"  portals        'xdg-desktop-portal'
assert "NetworkManager active"       networkmanager '^active'
assert "DNS resolves"                dns            'archlinux\.org'
assert "PipeWire running"            pipewire       'PipeWire|Audio'
assert "Calamares installed"         calamares-bin  'CALAMARES_PRESENT'
assert "installer config present"    calamares-cfg  'CALAMARES_CFG_PRESENT'
assert "installer launcher present"  desktop-entry  'DESKTOP_PRESENT'

printf '\n== diagnostics\n'
for s in failed-units sessions sddm-journal hypr-journal networkmanager pipewire; do report "$s"; done

printf '\n'
if [ "$ERRORS" -gt 0 ]; then
    red "LIVE HEALTH FAILED: $ERRORS check(s) - full log: $LOG"; exit 1
fi
green "LIVE HEALTH PASSED - full log: $LOG"
