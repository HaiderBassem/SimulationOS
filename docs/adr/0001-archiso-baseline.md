# ADR 0001 - archiso is the architectural baseline

**Status:** accepted · 2026-09-28

## Context
The repository began as a copy of Arch's `releng` profile and had drifted:
six removed bootmode names, a variable (`iso_icon`) mkarchiso never reads, and
a custom mkinitcpio preset upstream had deleted.

## Decision
Track current archiso exactly. Do not fork it, do not reimplement it, do not
keep deprecated spellings because an old profile used them.

## Alternatives
- **Fork archiso** — rejected: permanent maintenance cost for no benefit yet.
- **Copy the CachyOS ISO profile** — rejected, see ADR 0003.

## Consequences
We inherit archiso's improvements for free, but must re-read its CHANGELOG at
each upgrade. `validate-profile.sh` fails on deprecated bootmodes and on
variables mkarchiso does not consume, so drift is caught mechanically.

## Sources
`docs/research/sources.md` § archiso.
