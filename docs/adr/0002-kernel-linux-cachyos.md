# ADR 0002 - Ship linux-cachyos

**Status:** accepted · 2026-09-28

## Context
SimulationOS' stated identity includes the CachyOS kernel. The repository
already listed `linux-cachyos` but no boot path referenced its actual files.

## Decision
Ship `linux-cachyos` as the only kernel, and derive every filename from its
`pkgbase`: `vmlinuz-linux-cachyos`, `initramfs-linux-cachyos.img`, preset
`linux-cachyos.preset`. Delete the hand-written preset.

## Alternatives
- **Stock `linux`** — simpler, but discards a defining project property.
- **Keep a custom preset** — rejected: presets are keyed to `pkgbase`, so a
  `linux.preset` is orphaned; upstream removed theirs for the same reason.

## Consequences
We depend on the CachyOS repository for the kernel, so a CachyOS outage blocks
builds. No fallback/LTS kernel yet — see ADR 0012.
The validator derives expected filenames from `packages.x86_64` and fails on
any drift, which is how the original three-way mismatch would have been caught.

## Sources
`linux-cachyos/PKGBUILD:177,612,615`. Resolution verified in an x86_64
container: `cachyos/linux-cachyos-7.2.7-1`.
