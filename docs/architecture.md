# SimulationOS architecture

Design decisions and the reasoning behind them. Where a choice differs from
Arch or CachyOS, this document says which behaviour is upstream and which is a
SimulationOS decision.

---

## 1. Layering

```
UPSTREAM ARCHISO BEHAVIOR   the baseline: profile format, boot modes,
                            initramfs hooks, airootfs overlay semantics
CACHYOS-SPECIFIC BEHAVIOR   a component supplier: kernel, installer build,
                            keyring/mirrorlist, two packages Arch lacks
SIMULATIONOS DECISION       identity, live session, desktop, installer config
```

SimulationOS does not fork archiso and does not copy the CachyOS ISO profile.
It is an archiso profile that consumes CachyOS packages.

---

## 2. archiso profile

### Boot modes

**UPSTREAM:** archiso consolidated its boot mode names. `bios.syslinux.mbr` and
`bios.syslinux.eltorito` became `bios.syslinux`; the four
`uefi-{x64,ia32}.systemd-boot.{esp,eltorito}` names became a single
`uefi.systemd-boot`. The old names still exist as shims that emit a
deprecation warning. `mkarchiso` also **rejects** `uefi.systemd-boot` and
`uefi.grub` used together.

**SIMULATIONOS DECISION:**

```bash
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
```

`uefi.systemd-boot` already covers x64 plus mixed-mode IA32 on x86_64, so no
separate IA32 entry is needed.

### `grub/`

**UPSTREAM:** `mkarchiso`'s `_make_bootmodes()` calls
`_make_common_grubenv_and_loopbackcfg` whenever no `*grub*` boot mode is in
use, which installs `grub/loopback.cfg` onto the ISO. `grub/grub.cfg`, by
contrast, is only read by `_make_common_bootmode_grub_cfg`, which only
`_make_bootmode_uefi.grub` calls.

**SIMULATIONOS DECISION:** keep `grub/loopback.cfg` (it lets an existing GRUB
boot this ISO from a file), delete `grub/grub.cfg` (unreachable without a
`uefi.grub` boot mode, which we cannot have alongside systemd-boot).
`validate-profile.sh` enforces this invariant.

### Removed variables

`buildmodes=('iso')` is the implicit default and upstream dropped it from both
its profiles. `iso_icon`, `profiles_description`, `install_dir_disktop` and
`kernel_parameters` are **not** variables `mkarchiso` reads — they were noise.
The validator fails if any reappear.

### Build order matters

`mkarchiso` runs `_make_custom_airootfs` **before** `_make_packages`. The
`airootfs/` overlay is laid down first and pacstrap installs on top of it.
A file we ship at a path a package also owns is therefore only safe when that
path is in the package's `backup` array — otherwise pacstrap aborts with a file
conflict.

Verified backup-array members that SimulationOS overlays safely:

| Path | Owning package | In `backup`? |
|---|---|---|
| `/etc/pacman.conf` | `pacman` | yes |
| `/etc/passwd`, `/etc/group`, `/etc/gshadow` | `filesystem` | yes |
| `/etc/hosts`, `/etc/issue` | `filesystem` | yes |

This is also why SimulationOS **removed** `airootfs/etc/pacman.d/mirrorlist`:
the hand-written CachyOS-forcing mirrorlist both hard-coded mirrors and sat at
a path owned by `pacman-mirrorlist`. The package now provides it and the
inherited `uncomment-mirrors.hook` uncomments it, which is upstream behaviour.

---

## 3. Kernel

**CACHYOS:** `linux-cachyos`'s `PKGBUILD` sets `pkgbase="linux-cachyos"` and
installs the image as `$modulesdir/vmlinuz` with a `pkgbase` marker file. The
standard `mkinitcpio` pacman hook then produces:

```
/boot/vmlinuz-linux-cachyos
/boot/initramfs-linux-cachyos.img
/boot/initramfs-linux-cachyos-fallback.img
/etc/mkinitcpio.d/linux-cachyos.preset
```

**The bug this replaced:** the profile previously had *three* mutually
inconsistent names — `linux-cachyos` installed, boot entries pointing at
`vmlinuz-linux`, and a hand-written `/etc/mkinitcpio.d/linux.preset` naming a
nonexistent `vmlinuz-linux-simos`. Nothing lined up and the ISO could not boot.

**SIMULATIONOS DECISION:** one name, `linux-cachyos`, everywhere: the package
list, the systemd-boot entries, the syslinux entries, the PXE entries and
`loopback.cfg`. The custom preset is deleted — upstream archiso removed its own
`linux.preset` for the same reason ("the default preset is good enough"). The
validator derives the expected filenames from the package list and fails on any
drift.

**Microcode** needs no manual handling: `mkinitcpio`'s `microcode` hook (in
`archiso.conf`) embeds it, and `mkarchiso` detects the embedded case via
`_check_if_initramfs_has_ucode`, copying external ucode images and injecting
them into boot entries only when required.

---

## 4. CachyOS repository integration

Only four things genuinely require CachyOS:

| Package | Why |
|---|---|
| `linux-cachyos` | the kernel SimulationOS is defined by |
| `cachyos-calamares` | Calamares is not in the Arch repositories |
| `ckbcomp`, `mkinitcpio-openswap` | `cachyos-calamares` dependencies, absent from Arch |

Plus `cachyos-keyring` and `cachyos-mirrorlist` so the installed system retains
access.

**SIMULATIONOS DECISION — repository order.** Arch repos are listed *first*:

```
[core] [extra] [multilib] [cachyos]
```

A package present in both comes from Arch. SimulationOS uses CachyOS for what
is exclusive to it, not as a wholesale replacement for the Arch package set.
This is the opposite of CachyOS's own ordering and is intentional: it keeps the
dependency surface predictable.

**SIMULATIONOS DECISION — no developer-specific files.** The build-host
`pacman.conf` declares `[cachyos]` with explicit `Server =` URLs instead of
`Include = /etc/pacman.d/cachyos-mirrorlist`. The previous version required a
file that merely happened to exist on one machine. The *keyring* is still a
genuine host prerequisite, because pacstrap verifies signatures against the
host keyring — so `build-iso.sh` checks for `cachyos-keyring` and for key
`F3B607488DB35A47`, and fails early with the exact provisioning commands.
Signature verification is never disabled. (`DisableSandbox` was also removed
from `pacman.conf`.)

The live system's `/etc/pacman.conf` keeps
`Include = /etc/pacman.d/cachyos-mirrorlist`, which is correct there because
the `cachyos-mirrorlist` package is installed.

---

## 5. The live user

**UPSTREAM:** `mkarchiso`'s `_make_customize_airootfs` runs *after* packages
are installed. For every entry in `airootfs/etc/passwd` with UID 1000–59999 and
a valid home, it creates the home directory if missing, copies `/etc/skel/.`
into it, `chmod 0750`s it and `chown -hR`s it to that user.

That is a real, supported mechanism — `/etc/skel` *is* applied, provided the
account is declared in `airootfs/etc/passwd`.

**SIMULATIONOS DECISION:** put the desktop configuration in
`airootfs/etc/skel/.config/` and let archiso materialise
`/home/liveuser/.config/...` with correct ownership. One source of truth, and
Calamares' `users` module copies the same `/etc/skel` for the installed user —
so the live desktop and the installed desktop are identical by construction,
with no duplicated dotfiles.

Live-only concessions are named so they can be removed deterministically:

| Path | Purpose |
|---|---|
| `/etc/sddm.conf.d/20-simulationos-live-autologin.conf` | autologin liveuser |
| `/etc/sudoers.d/10-simulationos-live` | NOPASSWD sudo |
| `/etc/polkit-1/rules.d/49-simulationos-live-nopasswd.rules` | permissive polkit |
| `/etc/systemd/system/getty@tty1.service.d/autologin.conf` | tty autologin |

Everything with `-live-` in the name is stripped by `simulationos-deloop`.

---

## 6. Graphical session

**SIMULATIONOS DECISION: SDDM, X11 greeter, Wayland session.**

`sddm` hard-depends on `xorg-server` and `xorg-xauth`, so its default
`DisplayServer=x11` greeter works with no extra packages. Its Wayland greeter
would need `weston` (`CompositorCommand=weston --shell=kiosk`), which is not
shipped. The greeter launches `hyprland.desktop` from
`/usr/share/wayland-sessions/`, which the `hyprland` package provides.

The theme is `maldives`, one of the three themes (`elarun`, `maldives`, `maya`)
that ship inside the `sddm` package. The previous config specified `breeze`,
which requires Plasma and was not installed.

Enablement is explicit: `/etc/systemd/system/display-manager.service` is a
symlink to `sddm.service`, and `default.target` points at `graphical.target`.
The inherited `dmcheck` script, which guessed at a display manager and was
never invoked by anything, was deleted.

### Audio enablement

**UPSTREAM:** the `pipewire`, `pipewire-pulse` and `wireplumber` packages ship
user units but **no** `.wants` symlinks, so nothing enables them by file.

**SIMULATIONOS DECISION:** declare enablement explicitly in
`airootfs/etc/systemd/user/`, from the units' actual `[Install]` sections:

| Unit | `[Install]` | Symlink shipped |
|---|---|---|
| `pipewire.socket` | `WantedBy=sockets.target` | `sockets.target.wants/` |
| `pipewire.service` | `WantedBy=default.target` | `default.target.wants/` |
| `pipewire-pulse.socket` | `WantedBy=sockets.target` | `sockets.target.wants/` |
| `pipewire-pulse.service` | `WantedBy=default.target` | `default.target.wants/` |
| `wireplumber.service` | `WantedBy=pipewire.service`, `Alias=pipewire-session-manager.service` | `pipewire.service.wants/` + the alias |

---

## 7. Networking

**UPSTREAM:** archiso's releng profile uses `systemd-networkd` + `iwd` +
`systemd-resolved`, which suits a headless install medium.

**SIMULATIONOS DECISION:** NetworkManager only. A Hyprland desktop wants
`nm-applet` and `nm-connection-editor`, and Calamares' `networkcfg` module
migrates NetworkManager connections into the installed system. Running two
network stacks is a classic source of non-deterministic breakage, so
`systemd-networkd`, its `.network` files, `iwd` and the statically enabled
`wpa_supplicant.service` were all removed. `wpa_supplicant` stays installed
because NetworkManager activates it over D-Bus.

`systemd-resolved` was dropped with it, along with the
`/etc/resolv.conf -> stub-resolv.conf` symlink that depended on it;
NetworkManager manages `/etc/resolv.conf` directly. The validator fails if both
stacks are ever enabled at once.

---

## 8. Hardware

Generic support: `linux-firmware`, `sof-firmware`, `mesa`, `vulkan-radeon`,
`vulkan-intel`, `vulkan-swrast`, `xorg-xwayland`, `bluez`.

**SIMULATIONOS DECISION — no `chwd`, no NVIDIA scripts (Alpha).** The profile
inherited `nvidia-module-loader`, `remove-nvidia` and `removeun`, all of which
call CachyOS's `chwd` hardware-detection tool. `chwd` was never in the package
list and nothing invoked those scripts, so the "NVIDIA support" was inert. The
honest choice for Alpha is removal rather than shipping a half-working
hardware-detection path. NVIDIA hardware falls back to the in-kernel `nouveau`
driver.

`cursor:no_hardware_cursors = true` is set in the Hyprland config because
SimulationOS is expected to be evaluated in a VM, where hardware cursor planes
are frequently broken and the pointer disappears.

---

## 9. Desktop configuration

The inherited Hyprland and Waybar configuration was the author's personal
laptop setup and was replaced wholesale rather than patched. It contained:

- `/mnt/m.2_ssd/Linux/Wallpapers/1354205.jpeg` as the wallpaper
- `~/.scripts/Acer/PredatorSense/rgbkb/rgbkb.service.sh` on autostart
- **`exec-once = brightnessctl set 0%`** — a black screen on first login
- a hardcoded USB audio sink, a hardcoded `SYNA7DB5:00` touchpad, a hardcoded
  `eDP-2` output
- dependencies on `grimblast`, `auto-cpufreq`, `pamixer` and the ML4W dotfile
  framework, none of them shipped
- both `hyprpaper.conf` and `swww` autostart (two wallpaper daemons)
- both `monitor.conf` and `monitors.conf`, plus several config files that were
  shipped but never sourced

**SIMULATIONOS DECISION:** one `hyprland.conf` plus a deliberately empty
`monitors.conf` for per-machine overrides. Every `exec-once` and every keybind
target maps to a package in `packages.x86_64` or to a script in
`airootfs/usr/local/bin/`. Waybar uses **built-in modules only** — no custom
scripts — so a missing helper can never blank the bar. One wallpaper daemon
(`hyprpaper`), one launcher (`wofi`), one terminal (`kitty`), one file manager
(`thunar`), one notification daemon (`mako`), one polkit agent
(`hyprpolkitagent`) and one screen locker (`hyprlock`).

The validator enforces all of this: sourced files must exist, exec targets must
be shipped, the wallpaper must exist, only one wallpaper daemon may autostart,
and `brightnessctl set 0%` is a hard error.

The wallpaper is a real generated asset
(`airootfs/usr/share/backgrounds/simulationos/simulationos-alpha.png`,
1920x1080), reproducible via `scripts/make-wallpaper.py`.

`.bashrc` was also fixed: it aliased `rm` to `trash-put` and `n` to `nvim`
without shipping either, so `rm` was broken in the live session.

Two other inherited defects worth recording: `airootfs/etc/hosts` contained
*only* a hardcoded GitHub IP with no `localhost` entries, and
`airootfs/etc/polkit-1/rules.d/sddm.conf.d/autologin.conf` was an SDDM config
filed inside polkit's rules directory, where SDDM would never read it.

---

## 10. Installer

### Why the configuration is not in `/etc/calamares`

`cachyos-calamares` owns roughly sixty files under `/etc/calamares/modules/`
and declares **no `backup` array**. Because the airootfs overlay is laid down
*before* pacstrap, shipping our own files at those paths would be a hard
pacstrap file conflict and the build would fail.

**SIMULATIONOS DECISION:** ship a self-contained tree at
`/usr/share/simulationos/calamares/` and launch

```
calamares -c /usr/share/simulationos/calamares
```

Calamares' `-c/--config` sets `appDataDir`, and when that is overridden both
`moduleConfigurationCandidates()` and `brandingFileCandidates()` resolve
**only** inside it. So settings, module configs and branding all come from one
SimulationOS-owned directory, with zero chance of silently inheriting CachyOS
defaults and zero file conflicts.

### Installation model

Offline, via `unpackfs`: the live SquashFS at
`/run/archiso/bootmnt/arch/x86_64/airootfs.sfs` (derived from `install_dir`
and `arch` in `profiledef.sh`, and checked by the validator) is copied to the
target. Simple, network-free, and the live desktop is by definition what gets
installed.

Sequence, and why the order is what it is:

```
partition -> mount -> unpackfs -> machineid -> fstab -> locale -> keyboard
-> localecfg -> users -> networkcfg -> hwclock -> services-systemd -> packages
-> removeuser -> shellprocess@deloop -> initcpiocfg -> initcpio
-> grubcfg -> bootloader -> umount
```

- `removeuser` runs after `users`, so the real account exists first.
- **`shellprocess@deloop` must run before `initcpio`.** It deletes
  `/etc/mkinitcpio.conf.d/archiso.conf`; if that drop-in survived, `mkinitcpio`
  would build another *archiso* initramfs and the installed system would not
  boot without the ISO. This ordering is the single most load-bearing detail in
  the installer, and the validator checks that `deloop` still handles it.
- `packages` uses `try_remove` for `cachyos-calamares` and `gparted`, so the
  installed system does not carry its own installer. `try_remove` cannot fail
  the installation.

### Undoing the live medium

`simulationos-deloop` runs inside the target chroot and removes: SDDM
autologin, tty autologin, the NOPASSWD sudoers file (replacing it with a
validated password-prompting `%wheel` rule), the permissive polkit rule, the
archiso initramfs hook, archiso-only units (`livecd-talk`,
`livecd-alsa-unmuter`, `pacman-init`, the gnupg mount), the gpt-auto-generator
mask, the volatile-journal and do-not-suspend drop-ins, and `/home/liveuser`.

It also **locks the root account**. This matters: the live medium ships
`root::` — an empty password — and `unpackfs` copies `/etc/shadow` verbatim, so
without this step every installed system would have a passwordless root.
Calamares is configured with `setRootPassword: false` (a sudo-only model), so
locking root is the correct completion of that design.

The script never deletes the file it is executing from; removing
`/usr/share/simulationos` is a separate command listed after it in
`shellprocess_deloop.conf`.

### Installed-system bootloader

**SIMULATIONOS DECISION: GRUB.** The ISO uses syslinux + systemd-boot; the
installed system uses GRUB. These are separate concerns and conflating them is
a common mistake. GRUB covers BIOS and UEFI with one code path, which is the
right trade for an Alpha. `grubcfg` writes `/etc/default/grub` with
`GRUB_DISTRIBUTOR="SimulationOS"`.

---

## 11. Validation

`scripts/validate-profile.sh` is the guard against regressions. It was itself
verified by fault injection — ten deliberate regressions were introduced into a
scratch copy and every one was caught:

| Injected fault | Caught |
|---|---|
| kernel drift in a boot entry | yes |
| deprecated bootmode reintroduced | yes |
| `broadcom-wl` (removed from Arch) reintroduced | yes |
| personal `/mnt/m.2_ssd` path returns | yes |
| `brightnessctl set 0%` reintroduced | yes |
| Hyprland launches an unshipped binary | yes |
| second wallpaper daemon added | yes |
| `deloop` stops removing the archiso hook | yes |
| `doAutologin: true` in `users.conf` | yes |
| Calamares module config or display manager deleted | yes |

The checks deliberately ignore comment text, so documentation can name a banned
tool without tripping its own rule.
