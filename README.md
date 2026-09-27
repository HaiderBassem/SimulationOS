# SimulationOS

An Arch-based Linux distribution built around Hyprland, shipped as a live ISO
with a graphical installer.

SimulationOS is an **archiso profile**: this repository is not an operating
system you run, it is the build recipe that `mkarchiso` turns into

```
out/simulationos-<YYYY.MM.DD>-x86_64.iso
```

> **Status: Alpha.** The profile builds a complete live desktop and installs
> itself. See [Alpha limitations](#alpha-limitations) for what is not done yet,
> and [Verification status](#verification-status) for what has actually been
> tested versus only statically checked.

---

## Architecture

```
Arch Linux                 base distribution, [core] [extra] [multilib]
    |
ArchISO                    profile format, initramfs hooks, ISO assembly
    |
CachyOS repositories       only for what is exclusive to them
    |
linux-cachyos              the kernel SimulationOS ships
    |
SimulationOS live layer    airootfs/ overlay: identity, live user, services
    |
Hyprland                   Wayland session, started by SDDM
    |
Calamares                  graphical installer, SimulationOS configuration
```

Three sources are deliberately kept distinct:

| Layer | Role |
|---|---|
| **ArchISO** | The architectural baseline. Boot modes, `profiledef.sh` semantics, initramfs hooks and the `/etc/skel` mechanism follow upstream exactly. |
| **CachyOS** | A *component supplier*, not a template. Used for `linux-cachyos`, `cachyos-calamares`, `ckbcomp`, `mkinitcpio-openswap` and the keyring/mirrorlist — nothing else. |
| **SimulationOS** | Identity, live session design, desktop configuration and installer configuration. |

Arch repositories are listed **before** `[cachyos]` in `pacman.conf`, so a
package that exists in both comes from Arch. SimulationOS does not adopt the
CachyOS optimised package set.

Full design rationale: [`docs/architecture.md`](docs/architecture.md).

---

## Prerequisites

Building an ISO requires an **Arch Linux x86_64** host running as root:

| Requirement | Why |
|---|---|
| Linux, `x86_64` | `mkarchiso` is Linux-only; a non-x86_64 host would pacstrap the wrong architecture. |
| `archiso` | Provides `mkarchiso`. |
| `cachyos-keyring`, key `F3B607488DB35A47` trusted | `pacstrap` verifies CachyOS package signatures against the **build host** keyring. Signature checking is never disabled. |
| ~20 GB free disk | Work directory plus the ISO. |
| Network access | Package downloads. |

Provision the CachyOS key on the build host (the official CachyOS procedure):

```bash
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key F3B607488DB35A47
sudo pacman -Sy --config ./pacman.conf cachyos-keyring cachyos-mirrorlist
sudo pacman -S archiso
```

`scripts/build-iso.sh` checks every one of these and refuses to start with an
exact remediation message rather than failing halfway through a build.

### Not building on Arch?

You do not need to do anything special. `./build.sh` detects the host and runs
the build inside an x86_64 Arch container automatically:

```bash
./build.sh
```

It prints exactly what it decided before doing any work:

```
==> Host:    Darwin arm64
==> Target:  linux x86_64
==> Builder: container
```

The container is pinned to `--platform linux/amd64`, so an arm64 host can
never silently produce an arm64 ISO. On such a host the builder runs under
emulation: correct, but **much** slower than a native x86_64 machine. Prefer
real x86_64 hardware or a VM for routine builds.

---

## Repository structure

```
SimulationOS/
├── build.sh                      THE build entry point
├── profiledef.sh                 archiso manifest (ISO name, boot modes, permissions)
├── packages.x86_64               everything installed into the ISO
├── pacman.conf                   BUILD HOST repo config (explicit CachyOS Server=)
├── bootstrap_packages.x86_64     minimal set for the bootstrap build mode
│
├── airootfs/                     overlay copied into the ISO root
│   ├── etc/
│   │   ├── os-release, issue, motd, hostname, hosts   identity
│   │   ├── passwd, shadow, group, gshadow             the liveuser account
│   │   ├── pacman.conf                                live/installed repo config
│   │   ├── sddm.conf.d/                               greeter + live autologin
│   │   ├── sudoers.d/, polkit-1/rules.d/              live-only privilege policy
│   │   ├── skel/.config/{hypr,waybar,kitty,mako}/     the desktop, via /etc/skel
│   │   └── systemd/{system,user}/                     explicit service enablement
│   └── usr/
│       ├── local/bin/            simulationos-install, simos-* helpers
│       └── share/
│           ├── applications/     "Install SimulationOS" launcher
│           ├── backgrounds/simulationos/
│           ├── pixmaps/
│           └── simulationos/calamares/   the whole installer configuration
│
├── efiboot/                      systemd-boot entries (UEFI)
├── syslinux/                     syslinux menu (BIOS) + PXE
├── grub/loopback.cfg             boot this ISO from an existing GRUB
│
├── scripts/
│   ├── validate-profile.sh       static consistency checks
│   ├── build-iso.sh              environment checks + mkarchiso + checksum
│   ├── clean-build.sh            remove work/ and out/
│   ├── inspect-iso.sh            L3 artefact inspection
│   ├── test-iso.sh               boot it in QEMU (UEFI or BIOS)
│   └── make-wallpaper.py         regenerate the wallpaper asset
│
├── .github/workflows/
│   ├── validate.yml              L1 static validation (seconds, no container)
│   └── iso.yml                   L2/L3 clean build + artefact inspection
│
└── docs/
    ├── architecture.md           design rationale
    ├── adr/                      15 decision records
    └── research/sources.md       primary-source findings
```

---

## Workflow

### Validate

Runs anywhere, including macOS — it never needs `pacman`:

```bash
./scripts/validate-profile.sh
```

It fails the build on things that would otherwise only surface at boot:
boot entries naming a kernel the profile does not install, Hyprland launching
binaries nobody ships, developer-specific paths, dangling systemd symlinks,
missing Calamares module configs, a `deloop` script that stopped removing the
archiso initramfs hook, shell syntax errors, and more.

### Build

```bash
./build.sh
```

This is the **only** build entry point — developers, CI and releases all use
it, so a local build and a CI build cannot drift. It runs natively on Arch
x86_64 and in a container everywhere else.

```bash
./build.sh --validate    # static checks only
./build.sh --clean       # wipe work/ and out/ first
./build.sh --no-cache    # ignore the local package cache
./build.sh --help
```

Produces, in `out/`:

```
simulationos-<version>-x86_64.iso
simulationos-<version>-x86_64.iso.sha256
build-info.json      commit, archiso version, checksum, duration
build.log
```

### Clean

```bash
./scripts/clean-build.sh            # remove work/ and out/
./scripts/clean-build.sh --keep-iso # remove work/ only
```

### Test in a VM

```bash
./scripts/test-iso.sh                 # UEFI (OVMF)
./scripts/test-iso.sh --bios          # legacy BIOS / syslinux
./scripts/test-iso.sh --install       # attach a blank 30G disk and install
./scripts/test-iso.sh --boot-disk     # boot ONLY that disk, no ISO
```

The last two are the real acceptance test: install to the disk, then boot the
disk with no medium attached.

---

## Boot and installation flow

**Live medium**

```
Firmware → syslinux (BIOS) / systemd-boot (UEFI)
         → linux-cachyos + archiso initramfs
         → SquashFS root (/run/archiso)
         → systemd → graphical.target
         → SDDM → autologin liveuser → Hyprland
```

**Installation**

```
Live session → "Install SimulationOS" → Calamares
  → partition → mount → unpackfs (copy the live SquashFS)
  → users → networkcfg → services-systemd → packages (drop the installer)
  → removeuser (liveuser) → simulationos-deloop (strip live config)
  → initcpiocfg → initcpio (rebuild a NON-archiso initramfs)
  → grubcfg → bootloader (GRUB) → umount
  → reboot into the installed system
```

Because the offline installer copies the live filesystem verbatim, the target
initially inherits every live concession. `simulationos-deloop` removes them:
SDDM autologin, tty autologin, NOPASSWD sudo (replaced by a password-prompting
`%wheel` rule), the permissive polkit rule, the archiso initramfs hook,
archiso-only units, `/home/liveuser` — and it **locks the root account**, which
the live medium leaves passwordless.

---

## Alpha limitations

- **NVIDIA:** no proprietary driver and no `chwd` integration. The previous
  half-wired `chwd`-dependent NVIDIA scripts were removed rather than shipped
  broken. NVIDIA hardware falls back to `nouveau`.
- **Installer model:** offline only. The `unpackfs` module copies the live
  SquashFS; there is no online package selection.
- **Bootloaders:** the installed system always gets GRUB. No systemd-boot,
  rEFInd or Limine choice.
- **No disk encryption flow** has been exercised, though the LUKS-capable
  Calamares modules and `cryptsetup` are present.
- **Secure Boot** is not supported.
- **Locale defaults** to `C.UTF-8` on the live medium; the installer sets the
  real locale for the target.
- **sshd is installed but not enabled** on the live medium, unlike upstream
  archiso. Start it manually after setting a password if you need it.
- The SquashFS is `xz`-compressed, which favours ISO size over boot speed.

---

## Verification status

Everything below was done on a **macOS arm64** workstation, which cannot run
`mkarchiso`, `pacman` or an x86_64 QEMU guest. Nothing here claims a boot that
did not happen.

| Item | Status | Evidence |
|---|---|---|
| Upstream archiso/CachyOS/Calamares research | VERIFIED | primary sources, file+line, in `docs/research/sources.md` |
| Dependency resolution against real repos | VERIFIED | x86_64 Arch container: 144 requested -> **577 resolved**, exactly 6 from `[cachyos]` |
| Profile internal consistency | VERIFIED | `validate-profile.sh` passes |
| Validator actually catches regressions | VERIFIED | 11/11 fault injections caught |
| Shell syntax + shellcheck + YAML/JSON | VERIFIED | clean |
| **ISO builds end to end** | **VERIFIED** | `simulationos-2026.09.27-x86_64.iso`, 2,186,756,096 bytes, sha256 `caf09548…6f77e8`, archiso 90-1, mkarchiso 803 s |
| **`linux-cachyos` is the kernel in the artefact** | **VERIFIED** | ISO contains `arch/boot/x86_64/vmlinuz-linux-cachyos` + `initramfs-linux-cachyos.img` |
| **Both bootloaders present in the artefact** | **VERIFIED** | `boot/syslinux/isolinux.bin` (BIOS) and `EFI/BOOT/BOOTX64.EFI` + `loader/entries/01-simulationos-linux.conf` (UEFI) |
| **Boot menus branded, kernel references correct** | **VERIFIED** | menus extracted *from the ISO*: say SimulationOS, no "Arch Linux install medium", both point at `vmlinuz-linux-cachyos` |
| **Installer source path matches the ISO layout** | **VERIFIED** | `arch/x86_64/airootfs.sfs` present and equals the `unpackfs.conf` source |
| ISO boots (UEFI / BIOS) | NOT TESTED | needs QEMU; see below |
| Hyprland live session | NOT TESTED | requires a boot |
| Calamares run / full install / installed-system boot | NOT TESTED | requires a boot |
| Hardware (real GPUs, Wi-Fi, laptops) | NOT TESTED | no hardware matrix yet |

The build was produced on macOS arm64 through the containerised x86_64 builder,
so it is a genuine x86_64 artefact, but it has **never been booted**. A
structurally correct ISO is a strictly weaker claim than a booting one, and no
claim is made here beyond what the table states.

The first real run should be:

```bash
./scripts/validate-profile.sh && sudo ./scripts/build-iso.sh
./scripts/test-iso.sh --install
./scripts/test-iso.sh --boot-disk
```

---

## Upstream dependencies

| Project | Used for | Licence |
|---|---|---|
| [Arch Linux](https://archlinux.org) | Base system and repositories | various |
| [archiso](https://gitlab.archlinux.org/archlinux/archiso) | ISO build system, profile format | GPL-3.0 |
| [CachyOS](https://cachyos.org) | `linux-cachyos`, `cachyos-calamares`, keyring/mirrorlist | GPL-3.0 and others |
| [Hyprland](https://hypr.land) | Wayland compositor | BSD-3-Clause |
| [Calamares](https://calamares.io) | Installer framework | GPL-3.0 |

SimulationOS packages and configures these projects; it does not claim
authorship of them. `syslinux/splash.png` and the `livecd-sound` accessibility
helper are inherited from archiso and remain under their original terms.

---

## Licence

See [LICENSE](LICENSE).
