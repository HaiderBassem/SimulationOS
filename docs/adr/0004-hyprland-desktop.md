# ADR 0004 - Hyprland from stable repositories

**Status:** accepted · 2026-09-28

## Context
Hyprland is the SimulationOS desktop. Its ecosystem (portal, polkit agent,
lock, paper) has coupled ABI expectations across releases.

## Decision
Use only official Arch repository packages. No `-git`, no AUR in the base OS.
One component per job: `hyprland`, `hyprpaper`, `hyprlock`,
`hyprpolkitagent`, `waybar`, `wofi`, `kitty`, `thunar`, `mako`.

## Alternatives
- **`hyprland-git`** — rejected: upstream warns about interlocking ABI
  dependencies; a distribution baseline cannot chase that.
- **Ship several launchers/terminals** — rejected: more to test, no user benefit.

## Consequences
We lag upstream Hyprland slightly. In exchange the desktop is reproducible and
every referenced binary is guaranteed present — enforced by the validator,
which fails if `hyprland.conf` launches anything not in `packages.x86_64`.

## Sources
`docs/research/sources.md` § Hyprland. Note `swww` and `rofi-wayland` are not
in the Arch repositories, which is why `hyprpaper` and `wofi` were chosen.
