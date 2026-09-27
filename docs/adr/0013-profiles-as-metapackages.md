# ADR 0013 - Capability profiles as meta-packages

**Status:** open · 2026-09-28

## Context
SimulationOS targets programming, networking and gaming without installing all
three everywhere. The base must stay small.

## Proposed decision
Express profiles as SimulationOS meta-packages
(`simulationos-dev-meta`, `-network-meta`, `-gaming-meta`, `-gaming-apps`),
selected in the installer and installable later, rather than as a shell script
that installs a list of packages.

## Why this is still open
Meta-packages need a SimulationOS **repository**, which needs signing keys,
a keyring package, mirrors and package CI. Until that exists, the installer
can only select from Arch/CachyOS packages directly.

## Evidence needed first
- repository hosting and signing-key custody
- whether `Group` or a meta-package gives better uninstall semantics
- the GPU/32-bit provider-ordering problem for gaming (ADR pending): a naive
  Steam dependency pull can select the wrong vendor's 32-bit Vulkan driver

## Interim
Profiles are **not** implemented. The base desktop is installed as-is. Doing
this badly (a shell script downloading dozens of packages post-install) would
be worse than waiting.
