# ADR 0015 - One build engine: ./build.sh

**Status:** accepted · 2026-09-28

## Context
The classic distribution failure is a local build that differs from CI, which
differs from the release build.

## Decision
`./build.sh` is the only entry point, for developers, CI and releases. It
chooses *where* to build (native Arch x86_64, or an x86_64 Arch container) and
then runs the same `scripts/build-iso.sh` either way. CI must never implement
its own build procedure.

## Alternatives
- **A separate CI workflow that calls mkarchiso directly** — rejected; this is
  exactly the drift we are avoiding.

## Consequences
An arm64 host builds through emulation rather than silently producing an arm64
ISO. One environment-specific concession was needed and is scoped tightly:
pacman's seccomp sandbox fails with `EINVAL` under qemu-user emulation, so the
**container** patches a throwaway copy of `pacman.conf` with `DisableSandbox`.
The committed `pacman.conf` never sets it, signature verification is never
disabled, and `validate-profile.sh` fails if `DisableSandbox` or
`SigLevel = Never` ever appears in a committed config.
