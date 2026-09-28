# ADR 0011 - ext4 is the default filesystem

**Status:** provisional · 2026-09-28

## Context
Btrfs is fashionable for snapshot-based rollback. Snapshots alone are not a
rollback system.

## Decision
Default to ext4. Offer Btrfs, XFS and f2fs in the installer, with Btrfs
subvolumes (`@`, `@home`, `@log`, `@pkg`) pre-configured for anyone choosing it.
Do **not** advertise rollback.

## Alternatives
- **Btrfs by default with snapshots** — rejected for now: a credible rollback
  promise needs snapshot-on-transaction, boot integration, kernel/initramfs
  handling, pruning and tested recovery. We cannot maintain or test that yet,
  and a half-working rollback is worse than none.

## Consequences
Simple, predictable default. Revisit when we can own the whole lifecycle *and*
test it automatically. Promoting this to Btrfs-by-default requires an
automated rollback test in CI first.
