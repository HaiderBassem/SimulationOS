# ADR 0014 - Default nftables policy

**Status:** open · 2026-09-28

## Context
SimulationOS currently ships no firewall. Its exposure is presently low: the
live medium enables no listening network service (sshd is installed but
disabled, unlike upstream archiso).

## Proposed decision
A minimal stateful nftables policy: drop inbound by default; accept
established/related and loopback; allow DHCP/DHCPv6 and essential ICMP/ICMPv6;
leave outbound open.

## Why this is still open
Needs verification against real desktop traffic before being enabled by
default: mDNS/Avahi for printer and cast discovery, KDE Connect, Steam
in-home streaming and local multiplayer, and WireGuard/OpenVPN interfaces all
have inbound expectations. Shipping a policy that silently breaks LAN gaming
is worse than shipping none.

## Evidence needed first
- an inbound-traffic inventory for a normal desktop session
- confirmation that ICMPv6 rules do not break IPv6 SLAAC/PMTUD
- a documented way for a network engineer to extend the ruleset

## Interim
No firewall is enabled, and the attack surface is kept small instead by not
enabling listening services. This is recorded as a **known gap**, not as a
decision that a firewall is unnecessary.
