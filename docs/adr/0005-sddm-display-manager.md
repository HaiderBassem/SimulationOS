# ADR 0005 - SDDM with an X11 greeter launching a Wayland session

**Status:** provisional · 2026-09-28

## Context
We need autologin on the live medium and a normal greeter on the installed
system. SDDM's Wayland greeter needs a compositor.

## Decision
SDDM with its default `DisplayServer=x11` greeter, launching
`hyprland.desktop` from `/usr/share/wayland-sessions`. Theme `maldives`.

## Alternatives
- **SDDM Wayland greeter** — needs `weston` (`CompositorCommand=weston
  --shell=kiosk`); an extra compositor purely for the login screen.
- **greetd + tuigreet** — lighter, but a text greeter undercuts "polished".
- **No display manager** — rejected: the installed system needs a real login.

## Consequences
Xorg is pulled in as a hard dependency of `sddm` regardless. Revisit when
SDDM's Wayland greeter no longer requires a separate compositor — hence
*provisional*. The previous config specified theme `breeze`, which needs
Plasma and was not installed; only `elarun`, `maldives`, `maya` ship with SDDM.

## Sources
`docs/research/sources.md` § Display manager.
