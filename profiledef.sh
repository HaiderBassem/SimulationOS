#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="SimulationOS"
file_name="${iso_name}-{iso_version}-x86_64.iso"
iso_label="ARCH_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="SimulationOS <https://github.com/HaiderBassem/SimulationOS>"
iso_application="SimulationOS - Arch-based Rescue and Custom System"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"

install_dir="simulation"

buildmodes=('iso')

bootmodes=(
  'bios.syslinux.mbr'
  'bios.syslinux.eltorito'
  'uefi-ia32.systemd-boot.esp'
  'uefi-x64.systemd-boot.esp'
  'uefi-ia32.systemd-boot.eltorito'
  'uefi-x64.systemd-boot.eltorito'
)

arch="x86_64"

pacman_conf="pacman.conf"

airootfs_image_type="squashfs"

airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')

bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
)

profiles_description="SimulationOS Arch-based custom live ISO for rescue and simulation purposes"

install_dir_disktop="Desktop"

iso_icon="syslinux/splash.png"

additional_packages=(
  "nvim"
  "networkmanager"
  "git"
  "base-devel"
  "linux-headers"
  "btop"
)

kernel_parameters="quite loglevel=3"

run_once_custom_airoots_customize() {
  systemctl enable NetworkManager.service
}

run_once_custom_airoots_finallize() {
  rm -rf "${AIROOTFS}/tmp/*"
}
