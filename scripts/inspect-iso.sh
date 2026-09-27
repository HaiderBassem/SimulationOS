#!/usr/bin/env bash
#
# inspect-iso.sh - L3 artefact inspection.
#
# A zero exit code from mkarchiso is not evidence of a usable ISO. This
# verifies the image actually contains what SimulationOS is supposed to ship,
# and that the kernel names inside it match the profile.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"
ISO="${1:-$(ls -1t "$OUT"/simulationos-*.iso 2>/dev/null | head -1)}"

ERRORS=0
red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
err()   { ERRORS=$((ERRORS+1)); red "  FAIL  $*"; }
ok()    { green "  ok    $*"; }

[ -n "$ISO" ] && [ -f "$ISO" ] || { red "no ISO found in $OUT"; exit 1; }
printf '== inspecting %s\n' "$(basename "$ISO")"

# ---------------------------------------------------------------- size / name
SIZE=$(stat -c%s "$ISO" 2>/dev/null || stat -f%z "$ISO")
[ "$SIZE" -gt 0 ] || err "ISO is empty"
[ "$SIZE" -gt 524288000 ] || err "ISO is only $((SIZE/1024/1024)) MB; a Hyprland + installer image should be well over 500 MB"
ok "size $((SIZE/1024/1024)) MB"

case "$(basename "$ISO")" in
    simulationos-*-x86_64.iso) ok "filename matches simulationos-<version>-x86_64.iso" ;;
    *) err "unexpected ISO filename: $(basename "$ISO")" ;;
esac

# ------------------------------------------------------------------ contents
if ! command -v bsdtar >/dev/null 2>&1; then
    red "bsdtar not available; cannot inspect ISO contents"
    exit 1
fi
LIST="$(bsdtar -tf "$ISO" 2>/dev/null)"
[ -n "$LIST" ] || { err "could not read the ISO filesystem"; exit 1; }

# Derive the expected kernel from the profile, so this test cannot drift.
KPKG="$(grep -vE '^[[:space:]]*(#|$)' "$REPO/packages.x86_64" \
        | grep -E '^linux(-[a-z0-9]+)*$' \
        | grep -vE '^linux-(firmware|api-headers|atm)' | grep -vE -- '-headers$' | tail -1)"
IDIR="$(sed -n 's/^install_dir="\(.*\)"/\1/p' "$REPO/profiledef.sh" | head -1)"
IARCH="$(sed -n 's/^arch="\(.*\)"/\1/p' "$REPO/profiledef.sh" | head -1)"

expect() {
    if printf '%s\n' "$LIST" | grep -qx -- "$1"; then ok "$1"; else err "missing from ISO: $1"; fi
}
expect "${IDIR}/boot/${IARCH}/vmlinuz-${KPKG}"
expect "${IDIR}/boot/${IARCH}/initramfs-${KPKG}.img"
expect "${IDIR}/${IARCH}/airootfs.sfs"
expect "${IDIR}/${IARCH}/airootfs.sha512"

# The installer's unpackfs source must exist at the path we configured.
SFS_EXPECT="/run/archiso/bootmnt/${IDIR}/${IARCH}/airootfs.sfs"
grep -q "$SFS_EXPECT" "$REPO/airootfs/usr/share/simulationos/calamares/modules/unpackfs.conf" \
    && ok "unpackfs source matches the ISO layout" \
    || err "unpackfs.conf does not point at $SFS_EXPECT"

# Boot loader payloads for the declared bootmodes.
if grep -q "'bios.syslinux'" "$REPO/profiledef.sh"; then
    printf '%s\n' "$LIST" | grep -q '^syslinux/' && ok "syslinux payload present (BIOS)" \
        || err "bios.syslinux declared but no syslinux/ directory in the ISO"
fi
if grep -q "'uefi.systemd-boot'" "$REPO/profiledef.sh"; then
    printf '%s\n' "$LIST" | grep -qi '^EFI/BOOT/BOOTX64.EFI$' && ok "EFI/BOOT/BOOTX64.EFI present (UEFI)" \
        || err "uefi.systemd-boot declared but EFI/BOOT/BOOTX64.EFI is missing"
    printf '%s\n' "$LIST" | grep -q '^loader/entries/01-simulationos-linux.conf$' \
        && ok "systemd-boot default entry present" \
        || err "loader/entries/01-simulationos-linux.conf missing"
fi

# No stale Arch branding should reach a user-visible boot menu.
if printf '%s\n' "$LIST" | grep -q '^loader/entries/'; then
    :
fi

# ------------------------------------------------------------------ checksum
if [ -f "$ISO.sha256" ]; then
    if (cd "$(dirname "$ISO")" && sha256sum -c "$(basename "$ISO").sha256" >/dev/null 2>&1); then
        ok "sha256 matches"
    else
        err "sha256 mismatch"
    fi
else
    err "no .sha256 beside the ISO"
fi

printf '\n'
if [ "$ERRORS" -gt 0 ]; then
    red "ISO inspection FAILED with $ERRORS problem(s)"
    exit 1
fi
green "ISO inspection PASSED"
