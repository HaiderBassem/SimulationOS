# ADR 0010 - /etc/skel is the single source of desktop configuration

**Status:** accepted · 2026-09-28

## Context
The live user's dotfiles and the installed user's dotfiles must not diverge.
An earlier reading suggested archiso never applies `/etc/skel`; reading
`mkarchiso` disproved that.

## Decision
Keep desktop configuration only in `airootfs/etc/skel/.config/`. archiso's
`_make_customize_airootfs` materialises `/home/liveuser` from it with correct
ownership, and Calamares' `users` module copies the same skel for the
installed user.

## Alternatives
- **Ship `airootfs/home/liveuser/`** — duplicates every dotfile and needs
  manual recursive `file_permissions`.
- **A first-login provisioning script** — more machinery, more to fail.

## Consequences
Live and installed desktops are identical by construction. Users who edit
their dotfiles are never overwritten, because skel is only copied at account
creation. The cost: changing a default does not reach existing users — a
migration story is still **open** if we later package the config (see the
"packaged config" item in `docs/research/sources.md`).

## Sources
`mkarchiso:_make_customize_airootfs()`, invoked at line 1852 (after pacstrap).
