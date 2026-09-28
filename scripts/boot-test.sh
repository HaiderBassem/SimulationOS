#!/usr/bin/env bash
#
# boot-test.sh - L4 automated boot test.
#
# "QEMU started" is not evidence that an OS booted. This boots the ISO
# headlessly with the kernel console on a serial port and waits for proof that
# the system actually reached a usable state, then reports which checks passed.
#
# It never waits forever: every run ends in PASS, FAIL or TIMEOUT.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"
ISO="${1:-$(ls -1t "$OUT"/simulationos-*.iso 2>/dev/null | head -1)}"
FIRMWARE="${SIMOS_BOOT_TEST_FIRMWARE:-uefi}"
TIMEOUT="${SIMOS_BOOT_TEST_TIMEOUT:-600}"
RAM="${SIMOS_BOOT_TEST_RAM:-3072}"
LOG="$OUT/boot-test-${FIRMWARE}.log"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }

[ -n "$ISO" ] && [ -f "$ISO" ] || { red "no ISO found in $OUT"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { red "qemu-system-x86_64 not installed"; exit 1; }

mkdir -p "$OUT"
[ "${SIMOS_BOOT_ANALYZE_ONLY:-0}" = "1" ] || : > "$LOG"

# shellcheck disable=SC2054  # commas are part of QEMU option values
QEMU=(qemu-system-x86_64
      -machine "q35,accel=${SIMOS_QEMU_ACCEL:-kvm:tcg}"
      -cpu max -smp 2 -m "$RAM"
      -display none -vga std
      -serial "file:$LOG"
      -device virtio-net-pci,netdev=n0 -netdev user,id=n0
      -drive "file=$ISO,media=cdrom,readonly=on" -boot order=d
      -no-reboot)

if [ "$FIRMWARE" = "uefi" ]; then
    CODE=""
    for c in /opt/homebrew/share/qemu/edk2-x86_64-code.fd \
             /usr/local/share/qemu/edk2-x86_64-code.fd \
             /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
             /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd; do
        [ -f "$c" ] && { CODE="$c"; break; }
    done
    [ -n "$CODE" ] || { red "OVMF not found; install edk2-ovmf or use SIMOS_BOOT_TEST_FIRMWARE=bios"; exit 1; }
    VARS_SRC=""
    for v in /opt/homebrew/share/qemu/edk2-i386-vars.fd \
             /usr/local/share/qemu/edk2-i386-vars.fd \
             /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
             /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS_4M.fd; do
        [ -f "$v" ] && { VARS_SRC="$v"; break; }
    done
    VARS="$OUT/OVMF_VARS.boot-test.fd"; cp -f "$VARS_SRC" "$VARS"
    QEMU+=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE"
           -drive "if=pflash,format=raw,unit=1,file=$VARS")
fi

# Markers proving progressively deeper boot stages. Crucially this also
# watches for failure signatures, so a kernel panic is reported rather than
# looking identical to "still booting".
SUCCESS='Reached target Graphical Interface|reached target graphical|login:|servicename=display-manager'
FAILURE='Kernel panic|Unable to mount root|end Kernel panic|You are in emergency mode|Failed to start Light Display Manager|Entering emergency mode'

if [ "${SIMOS_BOOT_ANALYZE_ONLY:-0}" = "1" ]; then
    info "Analysing the existing log $LOG without booting"
    QPID=0
else
info "Booting $(basename "$ISO") headlessly ($FIRMWARE, timeout ${TIMEOUT}s)"
"${QEMU[@]}" &
QPID=$!
# shellcheck disable=SC2064
trap "kill $QPID 2>/dev/null" EXIT


fi

deadline=$(( $(date +%s) + TIMEOUT ))
if [ "${SIMOS_BOOT_ANALYZE_ONLY:-0}" = "1" ]; then deadline=0; fi
result="TIMEOUT"
if [ "${SIMOS_BOOT_ANALYZE_ONLY:-0}" = "1" ]; then
    grep -qE "$FAILURE" "$LOG" 2>/dev/null && result="FAIL"
    grep -qE "$SUCCESS" "$LOG" 2>/dev/null && result="PASS"
fi
while [ "$(date +%s)" -lt "$deadline" ]; do
    [ "$QPID" -eq 0 ] && break
    kill -0 "$QPID" 2>/dev/null || { result="QEMU_EXITED"; break; }
    if grep -qE "$FAILURE" "$LOG" 2>/dev/null; then result="FAIL"; break; fi
    if grep -qE "$SUCCESS" "$LOG" 2>/dev/null; then result="PASS"; break; fi
    sleep 3
done
[ "$QPID" -ne 0 ] && { kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; }

printf '\n== boot stages observed\n'
# Two kinds of stage: ones whose absence is a real problem, and ones that are
# simply not visible on the serial console because tty0 is the primary console
# (systemd sends its status there). Reporting the latter as MISS reads as a
# failure when the boot is healthy, so they are labelled distinctly.
check() {
    if grep -qE "$2" "$LOG" 2>/dev/null; then green "  ok      $1"; else red "  MISSING $1"; fi
}
info_check() {
    if grep -qE "$2" "$LOG" 2>/dev/null; then
        green "  ok      $1"
    else
        printf '  n/a     %s (not emitted to serial; tty0 is the primary console)\n' "$1"
    fi
}
info_check "kernel started"            'Linux version'
check "linux-cachyos kernel"      'linux-cachyos|cachyos'
info_check "archiso initramfs ran"     'archiso|Mounting .*airootfs|/run/archiso'
info_check "systemd started"           'systemd\[1\]'
info_check "reached multi-user"        'Reached target Multi-User|reached target multi-user'
check "getty/login prompt reached" 'login:'
check "SimulationOS branding shown" 'SimulationOS'
info_check "reached graphical target"   'Reached target Graphical Interface|servicename=display-manager|servicename=sddm' 
if grep -q 'Kernel panic' "$LOG" 2>/dev/null; then
    red "  MISS  no kernel panic"
else
    green "  ok    no kernel panic"
fi

printf '\n'
case "$result" in
    PASS)        green "BOOT TEST PASSED ($FIRMWARE) - log: $LOG"; exit 0 ;;
    FAIL)        red "BOOT TEST FAILED ($FIRMWARE) - failure signature in $LOG"
                 grep -nE "$FAILURE" "$LOG" | head -5; exit 1 ;;
    QEMU_EXITED) red "BOOT TEST FAILED: QEMU exited before reaching a target - log: $LOG"
                 tail -20 "$LOG"; exit 1 ;;
    *)           red "BOOT TEST TIMEOUT after ${TIMEOUT}s ($FIRMWARE) - log: $LOG"
                 tail -20 "$LOG"; exit 1 ;;
esac
