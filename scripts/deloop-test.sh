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
# then builds the initramfs the way the installer does and proves it is a
# normal one. Finally it checks, against the real binaries in the image, that
# the installer can load its libraries and that the shipped Hyprland
# configuration is valid.
#
# It complements install-test.py (the real graphical installation): this runs
# in a couple of minutes and pinpoints which contract broke.
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
check_pre "/boot empty in the SquashFS" "[ -z \"\$(ls -A '$R/boot' 2>/dev/null)\" ]"
[ "$pre_bad" -eq 0 ] || { red "extracted rootfs is not in the expected live state"; exit 1; }

ERRORS=0
gate() { if eval "$2"; then green "  ok      $1"; else red "  FAILED  $1"; ERRORS=$((ERRORS+1)); fi; }
inroot() { chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root "$@"; }

for m in proc sys dev; do mount --rbind "/$m" "$R/$m" 2>/dev/null; done
# shellcheck disable=SC2064
trap "for m in dev sys proc; do umount -R '$R/'\$m 2>/dev/null; done" EXIT

# ------------------------------------------------- live medium: installer runs
# Checked BEFORE deloop, against the image exactly as the live session sees it.
printf '\n== installer and desktop contracts (live image)\n'
COMPAT=/usr/lib/simulationos/calamares-compat
CALDIR=/usr/share/simulationos/calamares
ELFS="/usr/bin/calamares $(cd "$R" && find usr/lib -maxdepth 1 -name 'libcalamares*.so' -printf '/%p ' 2>/dev/null) $(cd "$R" && find usr/lib/calamares/modules -name '*.so' -printf '/%p ' 2>/dev/null)"
MISSING="$(for f in $ELFS; do inroot env LD_LIBRARY_PATH="$COMPAT" ldd "$f" 2>/dev/null; done | awk '/not found/{print $1}' | sort -u | tr '\n' ' ')"
gate "Calamares and every module resolve their libraries${MISSING:+ (missing: $MISSING)}" "[ -z '$MISSING' ]"
gate "Calamares config has a qml directory"   "[ -d '$R$CALDIR/qml/.' ]"
for mod in $(sed -n '/^sequence:/,/^branding:/p' "$R$CALDIR/settings.conf" \
             | grep -E '^[[:space:]]+-[[:space:]]' | sed 's/^[[:space:]]*-[[:space:]]*//; s/@.*//' | sort -u); do
    gate "Calamares module '$mod' exists in the package" "[ -d '$R/usr/lib/calamares/modules/$mod' ]"
done
gate "helper scripts are executable" \
    "[ -x '$R/usr/local/bin/simulationos-install' ] && [ -x '$R/usr/local/bin/simos-welcome' ] && [ -x '$R/usr/local/bin/simos-wallpaper' ] && [ -x '$R$CALDIR/scripts/simulationos-verify-target' ]"

# Hyprland's own verifier, run on the configuration a new user receives.
mkdir -p "$R/tmp/hyprcheck/.config" "$R/tmp/hyprcheck/run"
cp -a "$R/etc/skel/.config/hypr" "$R/tmp/hyprcheck/.config/"
chmod 700 "$R/tmp/hyprcheck/run"
HYPR_OUT="$(inroot env HOME=/tmp/hyprcheck XDG_RUNTIME_DIR=/tmp/hyprcheck/run \
            Hyprland --i-am-really-stupid --verify-config 2>&1 | sed -n '/Config parsing result/,$p')"
printf '%s\n' "$HYPR_OUT" | sed 's/^/    /'
gate "Hyprland --verify-config reports 'config ok'" "printf '%s' \"\$HYPR_OUT\" | grep -q 'config ok'"
rm -rf "$R/tmp/hyprcheck"
gate "fastfetch renders the SimOS logo" \
    "inroot env HOME=/etc/skel fastfetch --pipe 2>/dev/null | grep -q '01010011 01101001 01101101 01001111 01010011'"

# ----------------------------------------------------------- run the transform
info "Running simulationos-deloop inside the chroot (as Calamares does)"
# Calamares removes the live account first (removeuser module); mirror that.
chroot "$R" /usr/bin/userdel -r liveuser >/dev/null 2>&1 || true
chroot "$R" "$DELOOP" 2>&1 | sed 's/^/    /'
DELOOP_RC=${PIPESTATUS[0]}
[ "$DELOOP_RC" -eq 0 ] || { red "deloop exited $DELOOP_RC"; exit 1; }
# Idempotence: a second run must change nothing and still succeed.
chroot "$R" "$DELOOP" >/dev/null 2>&1
DELOOP_RC2=$?

info "Building the installed-system initramfs (mkinitcpio -P, as Calamares' initcpio does)"
chroot "$R" /usr/bin/mkinitcpio -P 2>&1 | grep -E 'ERROR|WARNING|Image generation|Initcpio image' | sed 's/^/    /'
MKINIT_RC=${PIPESTATUS[0]}

# ------------------------------------------------------------------ acceptance
printf '\n== installed-system acceptance gates\n'
gate "deloop is idempotent (second run exits 0)" "[ '$DELOOP_RC2' -eq 0 ]"
gate "kernel installed to /boot"              "[ -s '$R/boot/vmlinuz-linux-cachyos' ]"
gate "mkinitcpio -P succeeded"                "[ '$MKINIT_RC' -eq 0 ]"
gate "initramfs generated"                    "[ -s '$R/boot/initramfs-linux-cachyos.img' ]"
gate "initramfs contains no archiso hook"     "! chroot '$R' /usr/bin/lsinitcpio /boot/initramfs-linux-cachyos.img 2>/dev/null | grep -q archiso"
gate "pacman keyring initialised"             "[ -s '$R/etc/pacman.d/gnupg/pubring.gpg' ] || [ -s '$R/etc/pacman.d/gnupg/pubring.kbx' ]"
gate "sudoers configuration valid (visudo -c)" "chroot '$R' /usr/bin/visudo -c >/dev/null 2>&1"
gate "liveuser absent from group files"       "! grep -Eq '(^|[:,])liveuser(,|\$)' '$R/etc/group' '$R/etc/gshadow'"
gate "liveuser removed from /etc/passwd"      "! grep -q '^liveuser:' '$R/etc/passwd'"
gate "/home/liveuser removed"                 "[ ! -d '$R/home/liveuser' ]"
gate "SDDM live autologin removed"            "[ ! -f '$R/etc/sddm.conf.d/20-simulationos-live-autologin.conf' ]"
gate "tty1 autologin drop-in removed"         "[ ! -f '$R/etc/systemd/system/getty@tty1.service.d/autologin.conf' ]"
gate "NOPASSWD sudoers removed"               "[ ! -f '$R/etc/sudoers.d/10-simulationos-live' ]"
gate "password-prompting wheel rule added"    "grep -q '^%wheel ALL=(ALL:ALL) ALL' '$R/etc/sudoers.d/10-simulationos-wheel'"
gate "no active NOPASSWD rule in sudoers"     "! grep -rhsE '^[^#]*NOPASSWD' '$R/etc/sudoers' '$R/etc/sudoers.d/' >/dev/null"
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
gate "desktop skel intact for new users"      "[ -f '$R/etc/skel/.config/hypr/hyprland.lua' ] && [ -f '$R/etc/skel/.config/waybar/config.jsonc' ]"
gate "SimOS wallpapers and logo kept"         "[ -f '$R/usr/share/backgrounds/simulationos/simos-throne.png' ] && [ -f '$R/usr/share/simulationos/fastfetch/logo.txt' ]"
gate "NetworkManager still enabled"           "[ -L '$R/etc/systemd/system/multi-user.target.wants/NetworkManager.service' ]"

printf '\n'
for m in dev sys proc; do umount -R "$R/$m" 2>/dev/null; done
trap - EXIT
rm -rf -- "$WORK"
if [ "$ERRORS" -gt 0 ]; then
    red "DELOOP CONTRACT FAILED: $ERRORS gate(s)"
    exit 1
fi
green "DELOOP CONTRACT PASSED: the de-live transformation is correct"
