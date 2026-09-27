#!/usr/bin/env bash
#
# clean-build.sh - remove SimulationOS build artefacts.
#
# Only ever touches ./work and ./out inside the repository; it refuses to
# delete anything outside it.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${SIMOS_WORK_DIR:-$REPO/work}"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"

KEEP_ISO=0
[ "${1:-}" = "--keep-iso" ] && KEEP_ISO=1

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

# Guard rail: never operate outside the repository, however the env vars are set.
for target in "$WORK" "$OUT"; do
    case "$target" in
        "$REPO"/*) ;;
        *) printf 'refusing to delete %s: outside the repository\n' "$target" >&2; exit 1 ;;
    esac
done

# mkarchiso leaves bind mounts behind if a build was interrupted; unmount them
# before deleting, otherwise the delete can reach into a mounted filesystem.
if [ -d "$WORK" ] && command -v findmnt >/dev/null 2>&1; then
    findmnt -rno TARGET --submounts "$WORK" 2>/dev/null | sort -r | while read -r mp; do
        info "Unmounting leftover mount $mp"
        umount -l -- "$mp" 2>/dev/null || true
    done
fi

if [ -d "$WORK" ]; then
    info "Removing work directory $WORK ($(du -sh "$WORK" 2>/dev/null | cut -f1))"
    rm -rf -- "$WORK"
else
    info "No work directory to remove"
fi

if [ "$KEEP_ISO" -eq 1 ]; then
    info "Keeping $OUT (--keep-iso)"
elif [ -d "$OUT" ]; then
    info "Removing output directory $OUT"
    rm -rf -- "$OUT"
else
    info "No output directory to remove"
fi

info "Clean"
