#!/usr/bin/env bash
#
# test-iso.sh - boot a SimulationOS ISO in QEMU.
#
# Defaults to UEFI (OVMF) because that is the primary target; --bios exercises
# the legacy syslinux path. --install attaches a blank disk so a full
# installation can be performed, and --boot-disk then boots ONLY that disk,
# which is the real acceptance test for the installed system.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"

FIRMWARE="uefi"
ISO=""
DISK="$OUT/simulationos-test.qcow2"
DISK_SIZE="${SIMOS_TEST_DISK_SIZE:-30G}"
ATTACH_DISK=0
BOOT_DISK_ONLY=0
RAM="${SIMOS_TEST_RAM:-4096}"
CPUS="${SIMOS_TEST_CPUS:-2}"

usage() {
    cat <<'EOF'
usage: test-iso.sh [options] [path/to.iso]

  --uefi           boot via OVMF (default)
  --bios           boot via legacy BIOS / syslinux
  --install        attach a blank virtual disk for an installation run
  --boot-disk      boot ONLY the virtual disk (no ISO attached) - verifies
                   the installed system boots independently of the medium
  --ram MB         guest memory  (default 4096)
  --cpus N         guest vCPUs   (default 2)

If no ISO path is given, the newest out/simulationos-*.iso is used.

Typical acceptance run:
  ./scripts/test-iso.sh --install      # boot ISO, install to the blank disk
  ./scripts/test-iso.sh --boot-disk    # reboot from the disk alone
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --uefi)      FIRMWARE="uefi" ;;
        --bios)      FIRMWARE="bios" ;;
        --install)   ATTACH_DISK=1 ;;
        --boot-disk) BOOT_DISK_ONLY=1; ATTACH_DISK=1 ;;
        --ram)       RAM="$2"; shift ;;
        --cpus)      CPUS="$2"; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           ISO="$1" ;;
    esac
    shift
done

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v qemu-system-x86_64 >/dev/null \
    || die "qemu-system-x86_64 not found. Install qemu-full (Arch) or qemu-system-x86 (Debian/Fedora)."

if [ "$BOOT_DISK_ONLY" -eq 0 ]; then
    [ -n "$ISO" ] || ISO="$(ls -1t "$OUT"/simulationos-*.iso 2>/dev/null | head -1 || true)"
    [ -n "$ISO" ] || die "No ISO given and none found in $OUT. Run scripts/build-iso.sh first."
    [ -f "$ISO" ] || die "ISO not found: $ISO"
fi

# virtio-vga-gl + gl=on gives Hyprland a GPU to render on. Without it the
# session falls back to llvmpipe, which works but is slow.
# shellcheck disable=SC2054  # commas are part of QEMU option values, not separators
QEMU=(qemu-system-x86_64
      -machine q35,accel=kvm:tcg
      -cpu max
      -smp "$CPUS"
      -m "$RAM"
      -device virtio-vga-gl
      -display gtk,gl=on
      -device intel-hda -device hda-duplex
      -device virtio-net-pci,netdev=n0 -netdev user,id=n0
      -device qemu-xhci -device usb-tablet)

if [ "$FIRMWARE" = "uefi" ]; then
    OVMF_CODE=""
    for c in /opt/homebrew/share/qemu/edk2-x86_64-code.fd \
             /usr/local/share/qemu/edk2-x86_64-code.fd \
             /usr/share/edk2/x64/OVMF_CODE.4m.fd \
             /usr/share/edk2/x64/OVMF_CODE.fd \
             /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
             /usr/share/OVMF/OVMF_CODE_4M.fd \
             /usr/share/OVMF/OVMF_CODE.fd; do
        [ -f "$c" ] && { OVMF_CODE="$c"; break; }
    done
    [ -n "$OVMF_CODE" ] \
        || die "OVMF firmware not found. Install 'edk2-ovmf' (Arch) or 'ovmf' (Debian/Fedora), or use --bios."

    OVMF_VARS_SRC=""
    for v in /opt/homebrew/share/qemu/edk2-i386-vars.fd \
             /usr/local/share/qemu/edk2-i386-vars.fd \
             /usr/share/edk2/x64/OVMF_VARS.4m.fd \
             /usr/share/edk2/x64/OVMF_VARS.fd \
             /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
             /usr/share/OVMF/OVMF_VARS_4M.fd \
             /usr/share/OVMF/OVMF_VARS.fd; do
        [ -f "$v" ] && { OVMF_VARS_SRC="$v"; break; }
    done
    [ -n "$OVMF_VARS_SRC" ] || die "OVMF variable template not found alongside $OVMF_CODE."

    mkdir -p "$OUT"
    OVMF_VARS="$OUT/OVMF_VARS.simulationos.fd"
    # A per-test writable copy, so UEFI boot entries written by the installer
    # persist across runs (needed for the --boot-disk acceptance test).
    [ -f "$OVMF_VARS" ] || cp "$OVMF_VARS_SRC" "$OVMF_VARS"

    QEMU+=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
           -drive "if=pflash,format=raw,unit=1,file=$OVMF_VARS")
fi

if [ "$ATTACH_DISK" -eq 1 ]; then
    if [ ! -f "$DISK" ]; then
        printf '==> Creating blank test disk %s (%s)\n' "$DISK" "$DISK_SIZE"
        mkdir -p "$OUT"
        qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
    fi
    QEMU+=(-drive "file=$DISK,if=virtio,format=qcow2")
fi

if [ "$BOOT_DISK_ONLY" -eq 1 ]; then
    printf '==> Booting ONLY the installed disk, no ISO attached\n'
    QEMU+=(-boot order=c)
else
    QEMU+=(-drive "file=$ISO,media=cdrom,readonly=on" -boot order=d)
    printf '==> Booting %s (%s)\n' "$(basename "$ISO")" "$FIRMWARE"
fi

printf '==> %s\n' "${QEMU[*]}"
exec "${QEMU[@]}"
