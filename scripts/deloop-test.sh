#!/usr/bin/env bash
#
# deloop-test.sh - verify the de-live contract.
#
# simulationos-deloop turns a verbatim copy of the live filesystem into a safe
# installed system. Because the offline installer uses unpackfs, every live
# concession (empty root password, NOPASSWD sudo, permissive polkit, SDDM
# autologin, the archiso initramfs hook) is present on the target until deloop
# removes it.
#
# This extracts the SquashFS from the real ISO, runs deloop inside it exactly
# as Calamares would, and asserts the security properties of the result. It
# covers the same gates as the post-install checks without needing to drive
# the graphical installer.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"
ISO="${1:-$(ls -1t "$OUT"/simulationos-*.iso 2>/dev/null | head -1)}"
WORK="${SIMOS_DELOOP_WORK:-/var/tmp/simos-deloop}"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }

[ -n "$ISO" ] && [ -f "$ISO" ] || { red "no ISO found in $OUT"; exit 1; }
[ "$(id -u)" -eq 0 ] || { red "must run as root (chroot); try: sudo $0"; exit 1; }
command -v unsquashfs >/dev/null || { red "unsquashfs not found (install squashfs-tools)"; exit 1; }
command -v bsdtar     >/dev/null || { red "bsdtar not found (install libarchive-tools)"; exit 1; }

# Guard rail: this script deletes its work directory, so it must be a scratch
# path and nothing else.
case "$WORK" in
    /var/tmp/*|/tmp/*) ;;
    *) red "refusing to use work directory $WORK (must be under /var/tmp or /tmp)"; exit 1 ;;
esac

rm -rf -- "$WORK"
mkdir -p "$WORK/root"

info "Extracting the SquashFS from $(basename "$ISO")"
IDIR="$(sed -n 's/^install_dir="\(.*\)"/\1/p' "$REPO/profiledef.sh" | head -1)"
IARCH="$(sed -n 's/^arch="\(.*\)"/\1/p' "$REPO/profiledef.sh" | head -1)"
bsdtar -xOf "$ISO" "${IDIR}/${IARCH}/airootfs.sfs" > "$WORK/airootfs.sfs" \
    || { red "could not extract airootfs.sfs from the ISO"; exit 1; }
unsquashfs -f -d "$WORK/root" "$WORK/airootfs.sfs" >/dev/null \
    || { red "unsquashfs failed"; exit 1; }
green "    rootfs extracted to $WORK/root"

R="$WORK/root"
DELOOP=/usr/share/simulationos/calamares/scripts/simulationos-deloop
[ -x "$R$DELOOP" ] || { red "deloop script missing from the ISO: $DELOOP"; exit 1; }

# --------------------------------------------------------------- preconditions
printf '\n== live-medium preconditions (what deloop must remove)\n'
pre_bad=0
check_pre() { if eval "$2"; then green "  present $1"; else red "  ABSENT  $1 (precondition not met)"; pre_bad=1; fi; }
check_pre "SDDM live autologin"      "[ -f '$R/etc/sddm.conf.d/20-simulationos-live-autologin.conf' ]"
check_pre "NOPASSWD sudoers"         "[ -f '$R/etc/sudoers.d/10-simulationos-live' ]"
check_pre "permissive polkit rule"   "[ -f '$R/etc/polkit-1/rules.d/49-simulationos-live-nopasswd.rules' ]"
check_pre "archiso initramfs hook"   "[ -f '$R/etc/mkinitcpio.conf.d/archiso.conf' ]"
check_pre "root has empty password"  "grep -q '^root::' '$R/etc/shadow'"
check_pre "liveuser account"         "grep -q '^liveuser:' '$R/etc/passwd'"
check_pre "installer launcher"       "[ -x '$R/usr/local/bin/simulationos-install' ]"
[ "$pre_bad" -eq 0 ] || { red "extracted rootfs is not in the expected live state"; exit 1; }

# ----------------------------------------------------------- run the transform
info "Running simulationos-deloop inside the chroot (as Calamares does)"
for m in proc sys dev; do mount --rbind "/$m" "$R/$m" 2>/dev/null; done
# Calamares removes the live account first (removeuser module); mirror that.
chroot "$R" /usr/bin/userdel -r liveuser >/dev/null 2>&1 || true
chroot "$R" "$DELOOP" 2>&1 | sed 's/^/    /'
DELOOP_RC=${PIPESTATUS[0]}
for m in dev sys proc; do umount -R "$R/$m" 2>/dev/null; done
[ "$DELOOP_RC" -eq 0 ] || { red "deloop exited $DELOOP_RC"; exit 1; }

# ------------------------------------------------------------------ acceptance
printf '\n== installed-system acceptance gates\n'
ERRORS=0
gate() { if eval "$2"; then green "  ok      $1"; else red "  FAILED  $1"; ERRORS=$((ERRORS+1)); fi; }

gate "liveuser removed from /etc/passwd"      "! grep -q '^liveuser:' '$R/etc/passwd'"
gate "/home/liveuser removed"                 "[ ! -d '$R/home/liveuser' ]"
gate "SDDM live autologin removed"            "[ ! -f '$R/etc/sddm.conf.d/20-simulationos-live-autologin.conf' ]"
gate "tty1 autologin drop-in removed"         "[ ! -f '$R/etc/systemd/system/getty@tty1.service.d/autologin.conf' ]"
gate "NOPASSWD sudoers removed"               "[ ! -f '$R/etc/sudoers.d/10-simulationos-live' ]"
gate "password-prompting wheel rule added"    "grep -q '^%wheel ALL=(ALL:ALL) ALL' '$R/etc/sudoers.d/10-simulationos-wheel'"
gate "no NOPASSWD rule left in sudoers.d"     "! grep -rq 'NOPASSWD' '$R/etc/sudoers.d/'"
gate "permissive polkit rule removed"         "[ ! -f '$R/etc/polkit-1/rules.d/49-simulationos-live-nopasswd.rules' ]"
gate "root account locked"                    "grep -qE '^root:[!*]' '$R/etc/shadow'"
gate "root no longer has an empty password"   "! grep -q '^root::' '$R/etc/shadow'"
gate "archiso initramfs hook removed"         "[ ! -f '$R/etc/mkinitcpio.conf.d/archiso.conf' ]"
gate "no archiso hook in mkinitcpio config"   "! grep -rqs 'archiso' '$R/etc/mkinitcpio.conf.d/' '$R/etc/mkinitcpio.conf'"
gate "archiso live units removed"             "[ ! -f '$R/etc/systemd/system/livecd-talk.service' ] && [ ! -f '$R/etc/systemd/system/pacman-init.service' ]"
gate "installer launcher removed"             "[ ! -e '$R/usr/local/bin/simulationos-install' ]"
gate "installer desktop entry removed"        "[ ! -e '$R/usr/share/applications/simulationos-install.desktop' ]"
gate "display-manager still enabled"          "[ -L '$R/etc/systemd/system/display-manager.service' ]"
gate "default.target still graphical"         "readlink '$R/etc/systemd/system/default.target' | grep -q graphical"
gate "SimulationOS identity intact"           "grep -q 'ID=simulationos' '$R/etc/os-release'"
gate "desktop skel intact for new users"      "[ -f '$R/etc/skel/.config/hypr/hyprland.conf' ]"

printf '\n'
rm -rf -- "$WORK"
if [ "$ERRORS" -gt 0 ]; then
    red "DELOOP CONTRACT FAILED: $ERRORS gate(s)"
    exit 1
fi
green "DELOOP CONTRACT PASSED: the de-live transformation is correct"
