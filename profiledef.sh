#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# SimulationOS archiso profile definition.
#
# Only variables that mkarchiso actually consumes are set here. See
# archiso's docs/README.profile.rst for the authoritative list.
#
# Produces: out/simulationos-<iso_version>-x86_64.iso
#   (mkarchiso builds "${iso_name}-${iso_version}-${arch}.iso")

iso_name="simulationos"
iso_label="SIMOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="SimulationOS <https://github.com/HaiderBassem/SimulationOS>"
iso_application="SimulationOS Live/Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"

# buildmodes is intentionally unset: 'iso' is the implicit default.

# Current archiso boot mode names. The pre-0.90 names
# (bios.syslinux.mbr / bios.syslinux.eltorito / uefi-x64.systemd-boot.esp /
# uefi-ia32.systemd-boot.eltorito / ...) are deprecated shims.
# 'uefi.systemd-boot' already covers x64 *and* mixed-mode IA32 on x86_64,
# and it cannot be combined with 'uefi.grub' (mkarchiso rejects that).
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')

arch="x86_64"
# Overridable so the emulated build container can supply a copy with
# DisableSandbox set (pacman's seccomp sandbox returns EINVAL under qemu-user
# emulation). The committed pacman.conf never disables the sandbox, and
# validate-profile.sh enforces that.
pacman_conf="${SIMOS_PACMAN_CONF:-pacman.conf}"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# A trailing "/" makes mkarchiso apply ownership/mode recursively.
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-simulationos-live"]="0:0:440"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/simulationos-install"]="0:0:755"
  ["/usr/local/bin/simos-screenshot"]="0:0:755"
  ["/usr/local/bin/simos-powermenu"]="0:0:755"
  ["/usr/local/bin/simos-clipboard"]="0:0:755"
  ["/usr/local/bin/simos-session"]="0:0:755"
  ["/usr/local/bin/simos-wallpaper"]="0:0:755"
  ["/usr/local/bin/simos-welcome"]="0:0:755"
  ["/usr/share/simulationos/calamares/scripts/simulationos-deloop"]="0:0:755"
  ["/usr/share/simulationos/calamares/scripts/simulationos-verify-target"]="0:0:755"
)
