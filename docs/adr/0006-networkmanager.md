# ADR 0006 - NetworkManager is the only network stack

**Status:** accepted · 2026-09-28

## Context
Upstream releng uses systemd-networkd + iwd + systemd-resolved, suited to a
headless install medium. The repository had inherited that while also enabling
NetworkManager.

## Decision
NetworkManager alone. `wpa_supplicant` stays installed but is D-Bus-activated,
not statically enabled. systemd-resolved is dropped, so NetworkManager owns
`/etc/resolv.conf`.

## Alternatives
- **networkd + resolved** — better for servers, no desktop GUI story.
- **NetworkManager + systemd-resolved** — viable and adds DNS caching/DNSSEC,
  but is a second moving part; revisit once the base is proven.

## Consequences
One component owns connectivity. Calamares' `networkcfg` migrates live
connections into the installed system, so Wi-Fi joined during installation
keeps working. The validator fails if both stacks are ever enabled at once.
