# ADR 0012 - No SimulationOS kernel fork

**Status:** accepted · 2026-09-28

## Context
Distributions often start patching kernels early. We already consume a tuned
kernel via `linux-cachyos`.

## Decision
No SimulationOS kernel. Consume `linux-cachyos` as a package.

## Before this may be revisited, all of these are required
a measured problem · a benchmark demonstrating the gain · a maintenance owner ·
a security-update plan · kernel CI · a tested fallback kernel.

## Consequences
Zero kernel maintenance burden. **Gap:** there is currently no fallback kernel,
so a bad `linux-cachyos` update has no in-place escape hatch other than the
live ISO. Adding `linux-lts` as a recovery kernel is the next step here and is
tracked as a Phase 3 item.
