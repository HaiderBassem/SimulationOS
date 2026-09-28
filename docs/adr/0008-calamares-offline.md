# ADR 0008 - Calamares, offline install, SimulationOS-owned config directory

**Status:** accepted · 2026-09-28

## Context
Calamares is not in the Arch repositories; `cachyos-calamares` provides it.
That package owns ~60 files under `/etc/calamares/modules/` and declares no
`backup` array. archiso copies `airootfs/` **before** pacstrap, so shipping
our configs at those paths is a hard file conflict.

## Decision
Ship a self-contained tree at `/usr/share/simulationos/calamares` and launch
`calamares -c /usr/share/simulationos/calamares`. Install offline via
`unpackfs`, then strip live-only configuration with `simulationos-deloop`.

## Alternatives
- **Files in `/etc/calamares`** — breaks the build.
- **Suffixed module configs + `instances:`** — works, but we override nearly
  every module, so it means ~20 oddly named files sitting beside CachyOS'.
- **Fork Calamares** — rejected, large permanent cost.
- **Online `pacstrap` install** — more flexible, needs network and is slower;
  offline matches "the live desktop is what you get".

## Consequences
Verified in Calamares source that `-c` relocates settings, module configs
**and** branding, so CachyOS defaults cannot leak in. The trade-off is that
`unpackfs` copies the live filesystem verbatim, which makes `deloop` a
correctness-critical component — including locking root, which the live medium
leaves passwordless. `deloop` must run before `initcpio`.

## Sources
`docs/research/sources.md` § Calamares.
