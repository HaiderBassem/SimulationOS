#!/usr/bin/env bash
#
# validate-profile.sh - static consistency checks for the SimulationOS profile.
#
# Catches the class of breakage that only shows up hours into a build or, worse,
# at boot: boot entries pointing at a kernel that is not installed, desktop
# configs launching binaries nobody ships, personal paths, dangling symlinks,
# Calamares referring to modules or scripts that do not exist.
#
# Runs anywhere with bash 3.2+ (macOS included) - it never needs pacman.
# Exit status: 0 = clean, 1 = errors found.
#
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

ERRORS=0
WARNINGS=0
CHECKS=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

err()  { ERRORS=$((ERRORS+1));     red    "  ERROR   $*"; }
warn() { WARNINGS=$((WARNINGS+1)); yellow "  WARN    $*"; }
ok()   { CHECKS=$((CHECKS+1)); }
section() { printf '\n== %s\n' "$*"; }

# Packages the profile installs (comments and blanks stripped).
PKGLIST="$(grep -vE '^[[:space:]]*(#|$)' packages.x86_64 2>/dev/null)"
has_pkg() { printf '%s\n' "$PKGLIST" | grep -qx -- "$1"; }

# ---------------------------------------------------------------------------
section "profiledef.sh"
# ---------------------------------------------------------------------------
if [ ! -f profiledef.sh ]; then
    err "profiledef.sh is missing"
else
    bash -n profiledef.sh 2>/dev/null || err "profiledef.sh has a syntax error"
    ok

    # Evaluate declarations only - comments legitimately mention bootmode names.
    PROFILE_CODE="$(sed 's/[[:space:]]*#.*$//' profiledef.sh)"

    # Deprecated / removed archiso boot mode names.
    for bad in bios.syslinux.mbr bios.syslinux.eltorito \
               uefi-x64.systemd-boot.esp uefi-x64.systemd-boot.eltorito \
               uefi-ia32.systemd-boot.esp uefi-ia32.systemd-boot.eltorito \
               uefi-x64.grub.esp uefi-x64.grub.eltorito \
               uefi-ia32.grub.esp uefi-ia32.grub.eltorito; do
        if printf '%s\n' "$PROFILE_CODE" | grep -q "'$bad'"; then
            err "profiledef.sh uses deprecated bootmode '$bad'"
        fi
    done
    ok

    # mkarchiso rejects these two together.
    if printf '%s\n' "$PROFILE_CODE" | grep -q "'uefi.systemd-boot'" \
       && printf '%s\n' "$PROFILE_CODE" | grep -q "'uefi.grub'"; then
        err "bootmodes uefi.systemd-boot and uefi.grub cannot be combined"
    fi
    ok

    # Variables mkarchiso does not consume.
    for fake in iso_icon profiles_description install_dir_disktop kernel_parameters; do
        printf '%s\n' "$PROFILE_CODE" | grep -qE "^[[:space:]]*${fake}=" \
            && err "profiledef.sh sets '$fake', which mkarchiso does not read"
    done
    ok

    # grub/grub.cfg is only consumed by the uefi.grub bootmode.
    if [ -f grub/grub.cfg ] && ! printf '%s\n' "$PROFILE_CODE" | grep -q "'uefi.grub'"; then
        err "grub/grub.cfg exists but 'uefi.grub' is not a bootmode (dead file)"
    fi
    ok

    # file_permissions entries must point at files that exist.
    sed -n 's/^[[:space:]]*\["\([^"]*\)"\].*/\1/p' profiledef.sh | while read -r fp; do
        [ -z "$fp" ] && continue
        if [ ! -e "airootfs${fp}" ] && [ ! -L "airootfs${fp}" ]; then
            red "  ERROR   file_permissions references missing path: airootfs${fp}"
            echo x >>"$REPO/.validate_fperm_fail"
        fi
    done
    if [ -f .validate_fperm_fail ]; then
        ERRORS=$((ERRORS + $(wc -l < .validate_fperm_fail)))
        rm -f .validate_fperm_fail
    fi
    ok

    # mkarchiso copies airootfs WITHOUT preserving modes, so a script is only
    # executable in the ISO if file_permissions says so. A helper missing here
    # ships as 0644 and fails with "permission denied" at runtime.
    while IFS= read -r f; do
        head -1 "$f" | grep -q '^#!' || continue
        grep -qF "[\"${f#airootfs}\"]=\"0:0:755\"" profiledef.sh \
            || err "profiledef.sh file_permissions has no 0:0:755 entry for ${f#airootfs}"
    done < <(find airootfs/usr/local/bin airootfs/usr/share/simulationos/calamares/scripts -type f 2>/dev/null)
    ok
fi

# ---------------------------------------------------------------------------
section "kernel / boot consistency"
# ---------------------------------------------------------------------------
# Derive the kernel pkgbase from the package list, then require that every
# boot entry references exactly that kernel's files.
KPKG=""
for cand in $(printf '%s\n' "$PKGLIST" \
        | grep -E '^linux(-[a-z0-9]+)*$' \
        | grep -vE '^linux-(firmware|api-headers|atm)' \
        | grep -vE -- '-headers$'); do
    KPKG="$cand"
done
if [ -z "$KPKG" ]; then
    err "no kernel package (linux*) found in packages.x86_64"
else
    green "  kernel package: $KPKG"
    VMLINUZ="vmlinuz-${KPKG}"
    INITRAMFS="initramfs-${KPKG}.img"

    BOOTFILES="efiboot/loader/entries/*.conf syslinux/archiso_sys-linux.cfg syslinux/archiso_pxe-linux.cfg grub/loopback.cfg"
    for f in $BOOTFILES; do
        [ -f "$f" ] || continue
        # Any vmlinuz-* reference that is not our kernel is a mismatch.
        bad="$(grep -oE 'vmlinuz-[A-Za-z0-9._-]+' "$f" | grep -v "^${VMLINUZ}$" | sort -u)"
        if [ -n "$bad" ]; then
            err "$f references kernel image(s) [$(echo "$bad" | tr '\n' ' ')] but the profile installs $VMLINUZ"
        fi
        bad="$(grep -oE 'initramfs-[A-Za-z0-9._-]+\.img' "$f" | grep -vE "^initramfs-${KPKG}(-fallback)?\.img$" | sort -u)"
        if [ -n "$bad" ]; then
            err "$f references initramfs [$(echo "$bad" | tr '\n' ' ')] but the profile installs $INITRAMFS"
        fi
    done
    ok

    # Custom mkinitcpio presets are a classic source of kernel-name drift.
    if [ -d airootfs/etc/mkinitcpio.d ]; then
        err "airootfs/etc/mkinitcpio.d exists; upstream archiso removed custom presets (the auto-generated ${KPKG}.preset is correct)"
    fi
    ok

    # systemd-boot default entry must exist.
    if [ -f efiboot/loader/loader.conf ]; then
        DEF="$(sed -n 's/^default[[:space:]]\+//p' efiboot/loader/loader.conf | head -1)"
        if [ -n "$DEF" ] && [ ! -f "efiboot/loader/entries/$DEF" ]; then
            err "loader.conf default entry '$DEF' does not exist in efiboot/loader/entries/"
        fi
    fi
    ok

    # archiso hard requirements.
    has_pkg mkinitcpio         || err "packages.x86_64 is missing mandatory package 'mkinitcpio'"
    has_pkg mkinitcpio-archiso || err "packages.x86_64 is missing mandatory package 'mkinitcpio-archiso'"
    ok

    # Every mkinitcpio hook must have its support package, or mkinitcpio fails
    # late in the build with "file not found: /usr/lib/initcpio/...".
    MKCONF=airootfs/etc/mkinitcpio.conf.d/archiso.conf
    if [ -f "$MKCONF" ]; then
        HOOKS_LINE="$(sed -n 's/^HOOKS=(\(.*\))/\1/p' "$MKCONF")"
        for h in $HOOKS_LINE; do
            case "$h" in
                archiso_pxe_common|archiso_pxe_nfs)
                    has_pkg mkinitcpio-nfs-utils \
                        || err "mkinitcpio hook '$h' needs 'mkinitcpio-nfs-utils' in packages.x86_64" ;;
                archiso_pxe_nbd)
                    has_pkg nbd \
                        || err "mkinitcpio hook '$h' needs 'nbd' in packages.x86_64" ;;
                archiso|archiso_loop_mnt|memdisk)
                    has_pkg mkinitcpio-archiso \
                        || err "mkinitcpio hook '$h' needs 'mkinitcpio-archiso'" ;;
            esac
        done
        # A syslinux PXE config with no PXE hooks is dead configuration.
        if [ -f syslinux/archiso_pxe.cfg ] && ! printf '%s' "$HOOKS_LINE" | grep -q archiso_pxe; then
            err "syslinux/archiso_pxe.cfg exists but no archiso_pxe* mkinitcpio hook is enabled (dead PXE config)"
        fi
    fi
    ok
fi

# ---------------------------------------------------------------------------
section "packages.x86_64"
# ---------------------------------------------------------------------------
DUPES="$(printf '%s\n' "$PKGLIST" | sort | uniq -d)"
[ -n "$DUPES" ] && err "duplicate package entries: $(echo "$DUPES" | tr '\n' ' ')"
ok

# Security posture of the shipped pacman configuration.
for pc in pacman.conf airootfs/etc/pacman.conf; do
    [ -f "$pc" ] || continue
    grep -qE '^[[:space:]]*DisableSandbox' "$pc" \
        && err "$pc sets DisableSandbox; the pacman sandbox must stay on in the committed profile (the emulated builder patches a throwaway copy instead)"
    grep -qE '^[[:space:]]*SigLevel[[:space:]]*=.*Never' "$pc" \
        && err "$pc disables signature verification (SigLevel ... Never)"
    grep -qE '^[[:space:]]*SigLevel[[:space:]]*=[[:space:]]*Required' "$pc" \
        || err "$pc does not set 'SigLevel = Required ...'"
done
ok

# Packages known to have been dropped from the Arch repositories.
for gone in broadcom-wl rofi-wayland libva-mesa-driver ckbcomp-nonfree; do
    has_pkg "$gone" && err "packages.x86_64 lists '$gone', which no longer exists in the Arch repositories"
done
ok

# A graphical profile needs these to reach a desktop at all.
for need in hyprland sddm networkmanager pipewire wireplumber xdg-desktop-portal-hyprland polkit; do
    has_pkg "$need" || err "packages.x86_64 is missing '$need', required for the graphical live session"
done
ok

# ---------------------------------------------------------------------------
section "developer-specific and stale paths"
# ---------------------------------------------------------------------------
SCAN="$(find airootfs syslinux efiboot grub -type f 2>/dev/null)"
for pat in '/mnt/m\.2' '/mnt/[a-z0-9_]*ssd' '/Users/' '/home/[a-z]*/\.config' 'ml4w' 'grimblast' 'auto-cpufreq' 'trash-put'; do
    for f in $SCAN; do
        # Strip comments first: naming a tool in prose is not a dependency.
        if sed -e 's/[[:space:]]*#.*$//' -e 's|[[:space:]]*//.*$||' "$f" 2>/dev/null \
             | grep -qE "$pat"; then
            err "developer-specific reference '$pat' in: $f"
        fi
    done
done
ok

# Stale upstream branding in user-visible boot menus.
HITS="$(grep -rl 'Arch Linux install medium' efiboot syslinux grub 2>/dev/null)"
[ -n "$HITS" ] && err "stale Arch branding in boot menu: $(echo "$HITS" | tr '\n' ' ')"
HITS="$(grep -rl 'CachyOS' airootfs/etc/os-release airootfs/etc/issue airootfs/etc/motd \
        airootfs/etc/simulationos-release efiboot syslinux grub 2>/dev/null)"
[ -n "$HITS" ] && err "CachyOS branding on a SimulationOS identity surface: $(echo "$HITS" | tr '\n' ' ')"
ok

# A black screen on first boot is indistinguishable from a broken session.
if grep -rq 'brightnessctl set 0%' airootfs 2>/dev/null; then
    err "'brightnessctl set 0%' would blank the display on first login"
fi
ok

# ---------------------------------------------------------------------------
section "Hyprland session"
# ---------------------------------------------------------------------------
# Hyprland >= 0.55 is configured in Lua. A leftover hyprland.conf is parsed by
# the legacy loader and greets the user with a wall of config errors.
HYPRDIR=airootfs/etc/skel/.config/hypr
HYPR="$HYPRDIR/hyprland.lua"
[ -f "$HYPRDIR/hyprland.conf" ] \
    && err "$HYPRDIR/hyprland.conf exists: the shipped Hyprland is configured through hyprland.lua (old syntax = config errors at login)"
if [ ! -f "$HYPR" ]; then
    err "$HYPR is missing"
else
    # Legacy hyprlang keywords have no meaning in the Lua config.
    if grep -nE '^[[:space:]]*(exec-once|windowrulev2|windowrule|bind[a-z]*|source|env|monitor)[[:space:]]*=' "$HYPR" >/dev/null; then
        err "$HYPR contains legacy hyprlang syntax (key = value lines)"
    fi

    # Every require()d module must be shipped next to hyprland.lua.
    for mod in $(grep -oE 'require[,(][[:space:]]*"[^"]+"' "$HYPR" | sed 's/.*"\(.*\)"/\1/' | sort -u); do
        [ -f "$HYPRDIR/$(printf '%s' "$mod" | tr . /).lua" ] \
            || err "hyprland.lua requires '$mod' but $HYPRDIR/$mod.lua is not shipped"
    done
    ok

    # Every command started from the config must be a shipped package binary
    # or a script in airootfs/usr/local/bin. Lua locals (terminal, launcher,
    # fileManager) are resolved to their string values first.
    CMDS="$( { grep -oE 'exec_cmd\("[^"]+"' "$HYPR" | sed 's/exec_cmd("//; s/"$//'
               # simos-session is the ordered autostart list: "start <cmd> ..."
               sed -n 's/^start[[:space:]]\+//p' airootfs/usr/local/bin/simos-session 2>/dev/null
               grep -E '^local[[:space:]]+[A-Za-z]+[[:space:]]*=[[:space:]]*"' "$HYPR" \
                   | grep -vE '^local[[:space:]]+mainMod' | sed 's/^[^"]*"//; s/".*//'
             } | awk '{print $1}' | sort -u)"
    for cmd in $CMDS; do
        case "$cmd" in
            dbus-update-activation-environment|systemctl|hyprctl) continue ;;  # dbus/systemd/hyprland
        esac
        if [ -f "airootfs/usr/local/bin/$cmd" ]; then
            [ -x "airootfs/usr/local/bin/$cmd" ] || err "airootfs/usr/local/bin/$cmd is not executable"
            continue
        fi
        prov="$cmd"
        case "$cmd" in
            nm-applet)       prov=network-manager-applet ;;
            blueman-applet)  prov=blueman ;;
            wl-paste)        prov=wl-clipboard ;;
            wpctl)           prov=wireplumber ;;
        esac
        has_pkg "$prov" || err "hyprland.lua runs '$cmd' but package '$prov' is not in packages.x86_64"
    done
    ok

    if command -v luac >/dev/null 2>&1; then
        luac -p "$HYPR" 2>/dev/null || err "Lua syntax error in $HYPR"
        ok
    fi
fi

# hyprpaper >= 0.8 needs a hardware GPU and crashes on software-rendered
# machines; the wallpaper is drawn by swaybg (see simos-wallpaper).
has_pkg hyprpaper && err "packages.x86_64 lists hyprpaper; SimulationOS draws the wallpaper with swaybg"
has_pkg swaybg    || err "packages.x86_64 is missing 'swaybg' (used by simos-wallpaper)"
[ -f "$HYPRDIR/hyprpaper.conf" ] && err "$HYPRDIR/hyprpaper.conf is dead configuration (no hyprpaper is shipped)"
if [ -f "$HYPRDIR/hyprlock.conf" ]; then
    for img in $(sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*\(\/[^[:space:]]*\).*/\1/p' "$HYPRDIR/hyprlock.conf" | sort -u); do
        [ -f "airootfs${img}" ] || err "hyprlock.conf references missing image: $img"
    done
fi
ok

# The session must be started through the ordered startup script.
grep -q 'exec_cmd("simos-session")' "$HYPR" 2>/dev/null \
    || err "hyprland.lua does not start simos-session (unordered autostart races the session environment)"
ok

# Every wallpaper the switcher can select must be shipped.
if [ -f airootfs/usr/local/bin/simos-wallpaper ]; then
    for n in $(sed -n 's/^NAMES=(\(.*\))/\1/p' airootfs/usr/local/bin/simos-wallpaper); do
        [ -f "airootfs/usr/share/backgrounds/simulationos/simos-$n.png" ] \
            || err "simos-wallpaper offers '$n' but simos-$n.png is not shipped"
    done
fi
ok

# The fastfetch logo configured for new users must be shipped.
FF=airootfs/etc/skel/.config/fastfetch/config.jsonc
if [ -f "$FF" ]; then
    LOGO="$(sed -n 's/.*"source":[[:space:]]*"\([^"]*\)".*/\1/p' "$FF" | head -1)"
    [ -n "$LOGO" ] && [ ! -f "airootfs$LOGO" ] && err "fastfetch logo $LOGO is not shipped"
fi
ok

# Waybar must only call helpers that exist.
WB=airootfs/etc/skel/.config/waybar/config.jsonc
if [ -f "$WB" ]; then
    for h in $(grep -oE '"on-click":[[:space:]]*"[^"]+"' "$WB" | sed 's/.*"\([^"]*\)"$/\1/' | awk '{print $1}' | sort -u); do
        [ -x "airootfs/usr/local/bin/$h" ] && continue
        case "$h" in nm-connection-editor|pavucontrol) has_pkg "$h" && continue ;; esac
        [ "$h" = "activate" ] && continue
        err "waybar runs '$h' on click, which is neither a shipped helper nor a known package binary"
    done
fi
ok

# ---------------------------------------------------------------------------
section "display manager / session"
# ---------------------------------------------------------------------------
DM=airootfs/etc/systemd/system/display-manager.service
if [ -L "$DM" ]; then
    TGT="$(readlink "$DM")"
    case "$TGT" in
        */sddm.service) has_pkg sddm || err "display-manager.service points at sddm but sddm is not installed" ;;
        */gdm.service)  has_pkg gdm  || err "display-manager.service points at gdm but gdm is not installed" ;;
        *) warn "display-manager.service points at an unrecognised unit: $TGT" ;;
    esac
else
    err "airootfs/etc/systemd/system/display-manager.service is missing (no display manager will start)"
fi
ok

if [ -L airootfs/etc/systemd/system/default.target ]; then
    case "$(readlink airootfs/etc/systemd/system/default.target)" in
        */graphical.target) ;;
        *) err "default.target does not point at graphical.target" ;;
    esac
else
    err "airootfs/etc/systemd/system/default.target is missing"
fi
ok

# Dangling systemd .wants symlinks inside airootfs must at least name a unit
# path that a shipped package could provide.
find airootfs/etc/systemd -type l 2>/dev/null | while read -r link; do
    tgt="$(readlink "$link")"
    case "$tgt" in
        /usr/lib/systemd/*|/dev/null)
            ;;
        /etc/systemd/system/*)
            # absolute link into our own overlay - the unit must be shipped
            [ -f "airootfs${tgt}" ] || { red "  ERROR   $link -> $tgt (unit not shipped)"; echo x >>"$REPO/.validate_sl_fail"; }
            ;;
        /*)
            red "  ERROR   systemd symlink escapes to an unexpected path: $link -> $tgt"
            echo x >>"$REPO/.validate_sl_fail"
            ;;
        *)
            # relative link - must resolve inside airootfs
            [ -e "$(dirname "$link")/$tgt" ] || { red "  ERROR   dangling systemd symlink $link -> $tgt"; echo x >>"$REPO/.validate_sl_fail"; }
            ;;
    esac
done
if [ -f .validate_sl_fail ]; then
    ERRORS=$((ERRORS + $(wc -l < .validate_sl_fail))); rm -f .validate_sl_fail
fi
ok

# Only one network stack may be enabled.
NMW=airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
NDW=airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
if { [ -e "$NDW" ] || [ -L "$NDW" ]; } && { [ -e "$NMW" ] || [ -L "$NMW" ]; }; then
    err "both systemd-networkd and NetworkManager are enabled"
fi
{ [ -e "$NMW" ] || [ -L "$NMW" ]; } \
    || err "NetworkManager.service is not enabled in the live environment"
ok

# ---------------------------------------------------------------------------
section "Calamares installer"
# ---------------------------------------------------------------------------
CALDIR=airootfs/usr/share/simulationos/calamares
if [ ! -f "$CALDIR/settings.conf" ]; then
    err "$CALDIR/settings.conf is missing"
else
    # Modules that legitimately need no <module>.conf.
    CONFIGLESS="umount"
    MODS="$(sed -n '/^sequence:/,/^branding:/p' "$CALDIR/settings.conf" \
            | grep -E '^[[:space:]]*-[[:space:]]*[a-z]' \
            | sed -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/:[[:space:]]*$//' \
            | grep -vE '^(show|exec)$' | sort -u)"
    for m in $MODS; do
        base="${m%%@*}"
        inst="${m##*@}"
        if [ "$base" != "$m" ]; then
            # instance form module@id -> settings.conf must declare it
            grep -q "id:[[:space:]]*$inst" "$CALDIR/settings.conf" \
                || err "settings.conf uses '$m' but declares no instance with id '$inst'"
            cfg="$(grep -A2 "id:[[:space:]]*$inst" "$CALDIR/settings.conf" | sed -n 's/.*config:[[:space:]]*//p' | head -1)"
            [ -n "$cfg" ] && [ ! -f "$CALDIR/modules/$cfg" ] \
                && err "instance '$inst' references missing config $CALDIR/modules/$cfg"
        else
            if ! printf '%s\n' "$CONFIGLESS" | grep -qx "$base"; then
                [ -f "$CALDIR/modules/$base.conf" ] \
                    || err "Calamares module '$base' has no config at $CALDIR/modules/$base.conf"
            fi
        fi
    done
    ok

    # Branding must resolve.
    BR="$(sed -n 's/^branding:[[:space:]]*//p' "$CALDIR/settings.conf" | head -1)"
    if [ -n "$BR" ]; then
        [ -f "$CALDIR/branding/$BR/branding.desc" ] \
            || err "branding '$BR' has no branding.desc at $CALDIR/branding/$BR/"
        if [ -f "$CALDIR/branding/$BR/branding.desc" ]; then
            sed -n 's/^[[:space:]]*\(productLogo\|productIcon\|productWelcome\|slideshow\):[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\2/p' \
                "$CALDIR/branding/$BR/branding.desc" | while read -r img; do
                [ -z "$img" ] && continue
                [ -f "$CALDIR/branding/$BR/$img" ] || { red "  ERROR   branding asset missing: $img"; echo x >>"$REPO/.validate_br_fail"; }
            done
            if [ -f .validate_br_fail ]; then
                ERRORS=$((ERRORS + $(wc -l < .validate_br_fail))); rm -f .validate_br_fail
            fi
        fi
    fi
    ok

    # Scripts referenced by shellprocess configs must exist and be executable.
    for sp in "$CALDIR"/modules/shellprocess*.conf; do
        [ -f "$sp" ] || continue
        grep -oE '"/usr/share/simulationos[^"]*"' "$sp" | tr -d '"' | while read -r s; do
            [ -x "airootfs$s" ] || { red "  ERROR   $sp references missing/non-executable $s"; echo x >>"$REPO/.validate_sp_fail"; }
        done
    done
    if [ -f .validate_sp_fail ]; then
        ERRORS=$((ERRORS + $(wc -l < .validate_sp_fail))); rm -f .validate_sp_fail
    fi
    ok

    # Calamares refuses to start with -c <dir> unless <dir>/qml exists.
    { [ -e "$CALDIR/qml" ] || [ -L "$CALDIR/qml" ]; } \
        || err "$CALDIR/qml is missing: 'calamares -c' aborts without a qml directory"
    grep -qE '^hide-back-and-next-during-exec:' "$CALDIR/settings.conf" \
        || err "settings.conf lacks 'hide-back-and-next-during-exec' (required by Calamares >= 3.4)"
    ok

    # Order of the exec phase. Each pair is "A must run before B".
    EXEC_SEQ="$(sed -n '/^- exec:/,/^- show:/p' "$CALDIR/settings.conf" \
                | grep -E '^[[:space:]]+-[[:space:]]' | sed 's/^[[:space:]]*-[[:space:]]*//')"
    pos() { printf '%s\n' "$EXEC_SEQ" | grep -nx -- "$1" | head -1 | cut -d: -f1; }
    for pair in \
        'unpackfs:shellprocess@deloop' \
        'removeuser:shellprocess@deloop' \
        'shellprocess@deloop:initcpiocfg' \
        'initcpiocfg:initcpio' \
        'shellprocess@deloop:users' \
        'removeuser:users' \
        'fstab:initcpio' \
        'initcpio:bootloader' \
        'grubcfg:bootloader' \
        'packages:bootloader' \
        'bootloader:shellprocess@verify' \
        'shellprocess@verify:umount'; do
        first="${pair%%:*}"; second="${pair##*:}"
        pa="$(pos "$first")"; pb="$(pos "$second")"
        if [ -z "$pa" ]; then err "settings.conf exec sequence is missing '$first'"; continue; fi
        if [ -z "$pb" ]; then err "settings.conf exec sequence is missing '$second'"; continue; fi
        [ "$pa" -lt "$pb" ] || err "settings.conf: '$first' must run before '$second'"
    done
    for need in displaymanager services-systemd networkcfg machineid localecfg; do
        [ -n "$(pos "$need")" ] || err "settings.conf exec sequence is missing '$need'"
    done
    ok

    # initcpio must build every preset; a literal '*' is passed to mkinitcpio -p.
    grep -qE '^kernel:[[:space:]]*all[[:space:]]*$' "$CALDIR/modules/initcpio.conf" 2>/dev/null \
        || err "initcpio.conf must set 'kernel: all'"
    # Golden path: GRUB, with the ESP at /boot/efi.
    grep -qE '^efiBootLoader:[[:space:]]*"?grub"?' "$CALDIR/modules/bootloader.conf" 2>/dev/null \
        || err "bootloader.conf does not select GRUB"
    for need in grub efibootmgr dosfstools e2fsprogs; do
        has_pkg "$need" || err "packages.x86_64 is missing '$need', required to install the golden path"
    done
    ok

    # The unpackfs source path must match install_dir/arch from profiledef.sh.
    IDIR="$(sed -n 's/^install_dir="\(.*\)"/\1/p' profiledef.sh | head -1)"
    IARCH="$(sed -n 's/^arch="\(.*\)"/\1/p' profiledef.sh | head -1)"
    if [ -f "$CALDIR/modules/unpackfs.conf" ] && [ -n "$IDIR" ] && [ -n "$IARCH" ]; then
        EXPECT="/run/archiso/bootmnt/${IDIR}/${IARCH}/airootfs.sfs"
        grep -q "$EXPECT" "$CALDIR/modules/unpackfs.conf" \
            || err "unpackfs.conf source does not match profiledef (expected $EXPECT)"
    fi
    ok

    # The installer must actually be installable and launchable.
    has_pkg cachyos-calamares || has_pkg calamares \
        || err "no Calamares package in packages.x86_64, but an installer config exists"
    [ -x airootfs/usr/local/bin/simulationos-install ] \
        || err "airootfs/usr/local/bin/simulationos-install is missing or not executable"
    [ -f airootfs/usr/share/applications/simulationos-install.desktop ] \
        || err "installer .desktop launcher is missing"
    if [ -f airootfs/usr/share/applications/simulationos-install.desktop ]; then
        EXEC="$(sed -n 's/^Exec=//p' airootfs/usr/share/applications/simulationos-install.desktop | awk '{print $1}')"
        [ -x "airootfs$EXEC" ] || err ".desktop Exec points at missing $EXEC"
        ICON="$(sed -n 's/^Icon=//p' airootfs/usr/share/applications/simulationos-install.desktop)"
        if [ -n "$ICON" ] && [ "${ICON#/}" = "$ICON" ]; then
            ls airootfs/usr/share/pixmaps/"$ICON".* >/dev/null 2>&1 \
                || warn ".desktop Icon='$ICON' not found in airootfs/usr/share/pixmaps/"
        fi
    fi
    ok

    # The live medium must not leak into the installed system.
    DELOOP="$CALDIR/scripts/simulationos-deloop"
    if [ -f "$DELOOP" ]; then
        for must in 'mkinitcpio.conf.d/archiso.conf' 'live-autologin' '10-simulationos-live' 'passwd --lock root' '/home/liveuser' \
                    '49-simulationos-live-nopasswd.rules' 'vmlinuz-$pkgbase' 'pacman-key --init' 'getty@tty1.service.d/autologin.conf'; do
            grep -q -- "$must" "$DELOOP" \
                || err "simulationos-deloop does not handle '$must'"
        done
    fi
    grep -q 'username:[[:space:]]*liveuser' "$CALDIR/modules/removeuser.conf" 2>/dev/null \
        || err "removeuser.conf does not remove 'liveuser'"
    grep -qE '^[[:space:]]*doAutologin:[[:space:]]*false' "$CALDIR/modules/users.conf" 2>/dev/null \
        || err "users.conf does not set doAutologin: false (live autologin would be inherited)"
    ok
fi

# ---------------------------------------------------------------------------
section "shell scripts"
# ---------------------------------------------------------------------------
SCRIPTS="$(find airootfs/usr/local/bin airootfs/usr/share/simulationos -type f 2>/dev/null; ls scripts/*.sh 2>/dev/null)"
for s in $SCRIPTS; do
    head -1 "$s" | grep -q '^#!' || continue
    if ! bash -n "$s" 2>/dev/null; then
        err "shell syntax error in $s"
    fi
    [ -x "$s" ] || err "$s has a shebang but is not executable"
done
ok

if command -v shellcheck >/dev/null 2>&1; then
    for s in $SCRIPTS; do
        head -1 "$s" | grep -qE '^#!.*(bash|sh)' || continue
        out="$(shellcheck -S error -f gcc "$s" 2>/dev/null)"
        [ -n "$out" ] && err "shellcheck errors in $s:"$'\n'"$out"
    done
    ok
else
    warn "shellcheck not installed; skipping lint"
fi

# ---------------------------------------------------------------------------
section "broken symlinks inside airootfs"
# ---------------------------------------------------------------------------
# Only symlinks that point *within* airootfs can be checked offline; absolute
# links into /usr are resolved on the target at build time.
find airootfs -type l 2>/dev/null | while read -r l; do
    t="$(readlink "$l")"
    case "$t" in
        /*) continue ;;
    esac
    d="$(dirname "$l")"
    [ -e "$d/$t" ] || { red "  ERROR   broken relative symlink: $l -> $t"; echo x >>"$REPO/.validate_bs_fail"; }
done
if [ -f .validate_bs_fail ]; then
    ERRORS=$((ERRORS + $(wc -l < .validate_bs_fail))); rm -f .validate_bs_fail
fi
ok

# ---------------------------------------------------------------------------
printf '\n'
if [ "$ERRORS" -gt 0 ]; then
    red "FAILED: $ERRORS error(s), $WARNINGS warning(s)"
    exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
    yellow "PASSED with $WARNINGS warning(s)"
    exit 0
fi
green "PASSED: profile is internally consistent"
exit 0
