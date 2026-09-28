# ADR 0009 - GRUB on the installed system

**Status:** provisional · 2026-09-28

## Context
The ISO boots via syslinux (BIOS) and systemd-boot (UEFI). The installed
system's bootloader is a separate decision; the inherited installer script
offered five choices, none of them wired up.

## Decision
One bootloader for the installed system: GRUB, via Calamares' `bootloader`
module with `GRUB_DISTRIBUTOR="SimulationOS"`.

## Alternatives
- **systemd-boot** — simpler and faster, but UEFI-only and needs the kernel on
  the ESP, which complicates sizing.
- **Offer a choice (GRUB/systemd-boot/rEFInd/Limine)** — rejected for Alpha:
  each option multiplies the install-test matrix.

## Consequences
One code path covering BIOS and UEFI. Slower boot than systemd-boot. Marked
*provisional*: once the install test is automated, systemd-boot becomes cheap
to evaluate on measured boot-time evidence.
