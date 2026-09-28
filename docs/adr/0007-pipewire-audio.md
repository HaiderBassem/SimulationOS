# ADR 0007 - PipeWire + WirePlumber, enabled explicitly

**Status:** accepted · 2026-09-28

## Context
The profile shipped no audio stack. Arch's pipewire packages ship user units
but **no** `.wants` symlinks, and Arch does not run `systemctl preset` at
package-install time.

## Decision
PipeWire with `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack` and
WirePlumber, enabled by explicit symlinks under `/etc/systemd/user/` derived
from each unit's real `[Install]` section.

## Alternatives
- **Rely on presets** — rejected: not applied on Arch at install time; audio
  would silently not start.
- **PulseAudio** — rejected: PipeWire is the current desktop default and gives
  JACK and screen-share audio in one stack.

## Consequences
Enablement is visible in the repository rather than implicit. If upstream
changes an `[Install]` section, our symlinks go stale — the validator flags
dangling systemd symlinks.

## Sources
Unit files extracted from the actual packages; see `docs/research/sources.md` § Audio.
