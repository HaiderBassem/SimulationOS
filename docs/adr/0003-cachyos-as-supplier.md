# ADR 0003 - CachyOS is a component supplier, not a template

**Status:** accepted · 2026-09-28

## Context
CachyOS solves several problems we also have. The temptation is to copy its
ISO profile and repo ordering wholesale.

## Decision
Depend on CachyOS for what is genuinely exclusive to it and nothing else:
`linux-cachyos`, `cachyos-calamares`, `ckbcomp`, `mkinitcpio-openswap`,
`cachyos-keyring`, `cachyos-mirrorlist`. List Arch repositories **before**
`[cachyos]` so a package present in both comes from Arch.

## Alternatives
- **CachyOS ordering ([cachyos] first)** — rejected: pulls the whole optimised
  package set and makes our dependency surface unpredictable.
- **Vendor their files** — rejected: copying code we do not understand is how
  the inherited `chwd`-dependent dead scripts got here in the first place.

## Consequences
Predictable dependency graph, verified: of 577 resolved packages, exactly 6
come from `[cachyos]`. We forgo CachyOS' x86-64-v3/v4 optimised builds; if we
later want them, that is a deliberate, separately measured decision.

## Sources
`docs/research/sources.md` § CachyOS; container resolution run 2026-09-28.
