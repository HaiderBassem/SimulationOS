# SimulationOS research sources

Primary-source findings behind the architecture. Conclusions only — upstream
documentation is not copied here. Every entry records what was checked, where,
and when.

All entries accessed **2026-09-27 / 2026-09-28** unless noted.

---

## archiso

**Source:** `https://gitlab.archlinux.org/archlinux/archiso` — `archiso/mkarchiso`
(2011 lines), `docs/README.profile.rst`, `CHANGELOG.rst`, `configs/releng/`.

| Finding | Evidence |
|---|---|
| Valid boot modes are exactly `bios.syslinux`, `uefi.grub`, `uefi.systemd-boot` | `README.profile.rst`, bootmodes section |
| The six older names are deprecated shims that warn and alias | `mkarchiso:1001-1096` |
| `uefi.systemd-boot` + `uefi.grub` together are **rejected** | `mkarchiso:1050-1052` |
| `uefi.systemd-boot` covers x64 **and** mixed-mode IA32 on x86_64 | `mkarchiso:906-910` |
| `grub/loopback.cfg` is installed when **no** `*grub*` bootmode is set | `mkarchiso:_make_bootmodes()`, lines 473-481 |
| `grub/grub.cfg` is read **only** by `uefi.grub` | `mkarchiso:745` |
| `buildmodes` default is `iso`; upstream removed it from its profiles | `CHANGELOG.rst` "Removed" |
| Upstream removed its custom `/etc/mkinitcpio.d/linux.preset` | `CHANGELOG.rst`: "The default preset is good enough" |
| `broadcom-wl` was removed from Arch; upstream dropped its modprobe drop-in | `CHANGELOG.rst` |
| `airootfs` is copied **before** pacstrap | `mkarchiso:1846` then `:1847` |
| `/etc/skel` **is** copied into every `airootfs/etc/passwd` home with UID 1000-59999, created and `chown -hR`'d | `_make_customize_airootfs()`, runs at `mkarchiso:1852` |
| `file_permissions` with a trailing `/` applies recursively | `README.profile.rst`; `_make_custom_airootfs()` |
| ISO filename is `${iso_name}-${iso_version}-${arch}.iso` | `mkarchiso:1930` |
| Boot-entry placeholders: `%ARCHISO_LABEL% %ARCHISO_UUID% %INSTALL_DIR% %KERNEL_PARAMS% %ARCH%` | `mkarchiso:884-889` |
| Microcode is handled automatically; external ucode images are injected only when not embedded | `_check_if_initramfs_has_ucode()`, `mkarchiso:620-630` |
| SquashFS lands at `<install_dir>/<arch>/airootfs.sfs`; the medium mounts at `/run/archiso/bootmnt` | `mkarchiso:190`; `mkinitcpio-archiso` hook line 168 |
| `mkinitcpio` + `mkinitcpio-archiso` are mandatory packages | `README.profile.rst` |
| `mkarchiso` can run unprivileged via `unshare` (`-N`) when user namespaces exist | `_make_packages()`, `pacstrap -N` branch |

**Decision:** treat archiso as the architectural baseline and do not fork it.

---

## pacman / packaging

| Finding | Evidence |
|---|---|
| `/etc/pacman.conf` is in the `pacman` package's `backup` array | Arch `pacman` PKGBUILD, `backup=(etc/pacman.conf ...)` |
| `/etc/passwd`, `/etc/group`, `/etc/gshadow`, `/etc/hosts`, `/etc/issue` are in `filesystem`'s `backup` array | Arch `filesystem` PKGBUILD |
| Arch ships `system-preset/99-default.preset` = `disable *`, but **no** catch-all user preset | `systemd` package file list |

**Consequence:** an `airootfs` overlay is only safe at a package-owned path if
that path is a backup file. This is why the SimulationOS Calamares config is
*not* in `/etc/calamares`, and why the hand-written mirrorlist was removed.
It is also why pipewire user units are enabled by explicit symlink rather than
by relying on presets.

---

## CachyOS

**Source:** `github.com/CachyOS/{linux-cachyos,cachyos-calamares,CachyOS-Live-ISO,cachyos-repo-add-script}`,
plus the live repository database at `mirror.cachyos.org/repo/x86_64/cachyos/`.

| Finding | Evidence |
|---|---|
| `pkgbase=linux-cachyos`; image installed as `$modulesdir/vmlinuz` with a `pkgbase` marker | `linux-cachyos/PKGBUILD:177,612,615` |
| Therefore the installed files are `vmlinuz-linux-cachyos`, `initramfs-linux-cachyos.img`, preset `linux-cachyos.preset` | standard mkinitcpio hook behaviour |
| `cachyos-calamares` owns ~60 files under `/etc/calamares/modules/` and declares **no** `%BACKUP%` | `cachyos.files` / `cachyos.db` entry for `cachyos-calamares-3.4.2-4` |
| It `provides`/`conflicts` `calamares`; deps include `ckbcomp`, `mkinitcpio-openswap`, `kpmcore`, qt6 stack | `cachyos.db` `%DEPENDS%` |
| `ckbcomp` and `mkinitcpio-openswap` exist **only** in the CachyOS repo | Arch package search returns NONE; present in `cachyos` |
| Repo provisioning is key `F3B607488DB35A47` via keyserver.ubuntu.com, `--lsign-key`, then the keyring package | `cachyos-repo.sh:156-164` |
| `cachyos-calamares` is a full Calamares **fork**, not just configs | repository layout (`src/`, `CMakeLists.txt`) |

**Decision:** use CachyOS as a component supplier only. Do not fork Calamares,
do not adopt the CachyOS ISO profile, do not mirror their repo ordering.

**Verified 2026-09-28** by resolving the whole SimulationOS package set inside a
real `linux/amd64` Arch container: 144 requested → 577 resolved, of which
exactly 6 come from `[cachyos]`.

---

## Calamares

**Source:** `github.com/CachyOS/cachyos-calamares` (the build SimulationOS
installs) — `src/calamares/main.cpp`, `CalamaresApplication.cpp`,
`src/libcalamares/modulesystem/Module.cpp`.

| Finding | Evidence |
|---|---|
| `-c/--config <dir>` calls `Calamares::setAppDataDir(dir)` | `main.cpp:75-95` |
| When appDataDir is overridden, module configs resolve **only** under `<dir>/modules/` | `Module.cpp:50-56` |
| When appDataDir is overridden, branding resolves **only** under `<dir>/branding/` | `CalamaresApplication.cpp: brandingFileCandidates()` |
| Otherwise branding prefers `/etc/calamares/branding/` then `/usr/share/calamares/branding/` | same function |
| `/etc/calamares/settings.conf` is *not* shipped by the package; `/usr/share/calamares/settings{,_offline,_online}.conf` are | `cachyos-calamares` file list |
| Modules available in 3.4.2 include `unpackfs`, `removeuser`, `packages`, `services-systemd`, `initcpiocfg`, `initcpio`, `grubcfg`, `bootloader`, `networkcfg`, `machineid`, `summary` | `usr/lib/calamares/modules/` listing |

**Decision:** ship a self-contained config tree at
`/usr/share/simulationos/calamares` and launch with `-c`. This is the only
approach that is simultaneously conflict-free and immune to silently
inheriting CachyOS defaults.

---

## Hyprland and the Wayland desktop

Package availability confirmed against `archlinux.org/packages` (official repos
only; no AUR, no `-git`).

| Area | Chosen | Note |
|---|---|---|
| compositor | `hyprland` (extra) | ships `/usr/share/wayland-sessions/hyprland.desktop` |
| bar / launcher / term / files | `waybar`, `wofi`, `kitty`, `thunar` + `gvfs` | all extra |
| notifications | `mako` | simplest reliable daemon |
| polkit agent | `hyprpolkitagent` | ships `hyprpolkitagent.service` user unit |
| lock | `hyprlock` | so the power menu's Lock is not a no-op |
| wallpaper | `hyprpaper` only | `swww` is **not** in the Arch repos |
| portals | `xdg-desktop-portal` + `-hyprland` + `-gtk` | |
| screenshots / clipboard | `grim`, `slurp`, `wl-clipboard`, `cliphist` | |

`rofi-wayland` and `libva-mesa-driver` no longer exist as separate packages.

**Decision:** stable repo packages only. Hyprland's ecosystem has coupled ABI
expectations, so `-git` packages are out of scope for a distribution baseline.

---

## Display manager

**Source:** the `sddm` 0.21.0-7 package contents and Arch PKGBUILD.

| Finding | Evidence |
|---|---|
| Default `DisplayServer=x11`; `xorg-server` and `xorg-xauth` are **hard dependencies** | `/usr/lib/sddm/sddm.conf.d/default.conf`; PKGBUILD `depends=` |
| The Wayland greeter needs `weston` (`CompositorCommand=weston --shell=kiosk`) | same default.conf |
| Bundled themes are exactly `elarun`, `maldives`, `maya` | `/usr/share/sddm/themes/` |
| SDDM ships **no** `/etc/sddm.conf` or `/etc/sddm.conf.d/`, so those paths are free | package file list |
| Wayland sessions are read from `/usr/share/wayland-sessions` | default.conf `[Wayland] SessionDir` |

**Decision:** X11 greeter launching a Wayland session; theme `maldives`
(guaranteed present). The previously configured `breeze` needs Plasma.

---

## Audio

`[Install]` sections read from the actual packaged unit files, not from
documentation:

| Unit | `[Install]` |
|---|---|
| `pipewire.socket` | `WantedBy=sockets.target` |
| `pipewire.service` | `WantedBy=default.target`, `Also=pipewire.socket` |
| `pipewire-pulse.socket` | `WantedBy=sockets.target` |
| `pipewire-pulse.service` | `WantedBy=default.target` |
| `wireplumber.service` | `WantedBy=pipewire.service`, `Alias=pipewire-session-manager.service` |

None of these packages ship `.wants` symlinks.

**Decision:** PipeWire + WirePlumber, enabled by explicit symlinks under
`/etc/systemd/user/`. **Rejected:** relying on systemd presets (not applied at
package-install time on Arch) and running PulseAudio alongside PipeWire.

---

## Networking

**Decision:** NetworkManager alone, with `wpa_supplicant` installed but
D-Bus-activated.
**Alternatives considered:** upstream releng's `systemd-networkd` + `iwd` +
`systemd-resolved` — rejected because it targets headless installs, has no
Hyprland-friendly GUI, and Calamares' `networkcfg` module migrates
NetworkManager connections into the installed system.
`systemd-resolved` was dropped with it so only one component owns
`/etc/resolv.conf`.

---

## Still to research (not yet decided)

These are deliberately **not** implemented yet; see `docs/adr/` for status.

- nftables default policy
- filesystem strategy (ext4 vs Btrfs + whether we can own the full snapshot/rollback lifecycle)
- zram sizing, measured rather than copied
- kernel policy beyond `linux-cachyos` (fallback/LTS kernel)
- profile meta-package mechanism (package group vs meta-package)
- SimulationOS package repository, keyring and signing
- GPU driver selection matrix, especially 32-bit Vulkan provider ordering for Steam
