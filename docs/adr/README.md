# Architecture Decision Records

One short record per significant decision: context, decision, alternatives,
consequences, sources.

Status values: `accepted` · `provisional` (right for Alpha, revisit later) ·
`open` (needs evidence before implementing) · `superseded`.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-archiso-baseline.md) | archiso is the baseline; do not fork it | accepted |
| [0002](0002-kernel-linux-cachyos.md) | Ship `linux-cachyos`; no custom kernel | accepted |
| [0003](0003-cachyos-as-supplier.md) | CachyOS is a component supplier, not a template | accepted |
| [0004](0004-hyprland-desktop.md) | Hyprland from stable repos; no `-git` | accepted |
| [0005](0005-sddm-display-manager.md) | SDDM, X11 greeter, Wayland session | provisional |
| [0006](0006-networkmanager.md) | NetworkManager alone | accepted |
| [0007](0007-pipewire-audio.md) | PipeWire + WirePlumber, explicitly enabled | accepted |
| [0008](0008-calamares-offline.md) | Calamares, offline unpackfs, own config dir | accepted |
| [0009](0009-grub-for-installed-system.md) | GRUB on the installed system | provisional |
| [0010](0010-skel-as-config-source.md) | `/etc/skel` is the single dotfile source | accepted |
| [0011](0011-filesystem-ext4-default.md) | ext4 default; Btrfs only with a full rollback lifecycle | provisional |
| [0012](0012-no-custom-kernel-yet.md) | No SimulationOS kernel fork | accepted |
| [0013](0013-profiles-as-metapackages.md) | Capability profiles as meta-packages | open |
| [0014](0014-nftables-firewall.md) | nftables default policy | open |
| [0015](0015-single-build-engine.md) | One build engine: `./build.sh` | accepted |
