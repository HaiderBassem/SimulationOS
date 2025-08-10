#!/bin/bash

Main() {
    # Remove current keyring first, to complete initiate it
    sudo rm -rf /etc/pacman.d/gnupg
    # We are using this, because archlinux is signing the keyring often with a newly created keyring
    # This results into a failed installation for the user.
    # Installing archlinux-keyring fails due not being correctly signed
    # Mitigate this by installing the latest archlinux-keyring on the ISO, before starting the installation
    # The issue could also happen, when the installation does rank the mirrors and then a "faulty" mirror gets used
    sudo pacman -Sy --noconfirm archlinux-keyring simulationos-keyring
    # Also populate the keys, before starting the Installer, to avoid above issue
    sudo pacman-key --init
    sudo pacman-key --populate archlinux simulationos
    # Also use timedatectl to sync the time with the hardware clock
    # There has been a bunch of reports, that the keyring was created in the future
    # Syncing appears to fix it
    timedatectl set-ntp true

    local progname="$(basename "$0")"
    local log="/home/liveuser/simulationos-install.log"
    local mode="online"  # TODO: keep this line for now

    local _efi_check_dir="/sys/firmware/efi"
    local _exitcode=2 # by default use grub

    local SYSTEM="SimulationOS"
    local BOOTLOADER=""
    if [ -d "${_efi_check_dir}" ]; then
        _exitcode=$(yad --width 300 --title "Bootloader" \
    --image=gnome-shutdown \
    --button="Grub:2" \
    --button="Systemd-boot(Default):3" \
    --button="Refind:4" \
    --button="AI SDK / Refind:5" \
    --button="Limine:6" \
    --text "Choose Bootloader/Edition:" ; echo $?)
    else
        _exitcode=$(yad --width 300 --title "Bootloader" \
    --image=gnome-shutdown \
    --button="Grub:2" \
    --button="Limine:6" \
    --text "Choose Bootloader/Edition:" ; echo $?)
    fi

    local ISO_VERSION="$(cat /etc/version-tag)"
    echo "USING ISO VERSION: ${ISO_VERSION}"

    if [[ "${_exitcode}" -eq 2 ]]; then
        BOOTLOADER="GRUB"
        echo "USING GRUB!"
        # Remove cachyos calamares packages if they exist (optional)
        sudo pacman -Rns --noconfirm cachyos-calamares-qt6-next-systemd cachyos-calamares-qt6-next-grub cachyos-calamares-qt6-next-refind cachyos-calamares-qt6-next-limine || true
        # Install your calamares grub package or equivalent
        # sudo pacman -Sy simulationos-calamares-grub
    elif [[ "${_exitcode}" -eq 3 ]]; then
        BOOTLOADER="SYSTEMD-BOOT"
        echo "USING SYSTEMD-BOOT!"
        sudo pacman -Rns --noconfirm cachyos-calamares-qt6-next-grub cachyos-calamares-qt6-next-refind cachyos-calamares-qt6-next-limine || true
        # sudo pacman -Sy simulationos-calamares-systemdboot
    elif [[ "${_exitcode}" -eq 4 ]]; then
        BOOTLOADER="REFIND"
        echo "USING REFIND!"
        sudo pacman -Rns --noconfirm cachyos-calamares-qt6-next-grub cachyos-calamares-qt6-next-systemd cachyos-calamares-qt6-next-limine || true
        # sudo pacman -Sy simulationos-calamares-refind
    elif [[ "${_exitcode}" -eq 5 ]]; then
        BOOTLOADER="AI-SDK/Refind"
        echo "USING AI SDK and Refind!"
        sudo pacman -Rns --noconfirm cachyos-calamares-qt6-next-grub cachyos-calamares-qt6-next-systemd cachyos-calamares-qt6-next-refind cachyos-calamares-qt6-next-limine || true
        # sudo pacman -Sy simulationos-calamares-ai
    elif [[ "${_exitcode}" -eq 6 ]]; then
        BOOTLOADER="Limine"
        echo "USING Limine"
        sudo pacman -Rns --noconfirm cachyos-calamares-qt6-next-grub cachyos-calamares-qt6-next-systemd cachyos-calamares-qt6-next-refind || true
        # sudo pacman -Sy simulationos-calamares-limine
    else
        exit
    fi

    # Get Hardware Informations
    inxi -F > $log

    cat <<EOF >> $log
########## $log by $progname
########## Started (UTC): $(date -u "+%x %X")
########## ISO version: $ISO_VERSION
########## System: $SYSTEM
########## Bootloader: $BOOTLOADER
EOF

    sudo cp "/usr/share/calamares/settings_${mode}.conf" /etc/calamares/settings.conf
    sudo -E dbus-launch calamares -D6 >> $log &
}

Main "$@"
