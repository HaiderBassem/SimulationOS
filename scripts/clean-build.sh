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

# Guard rail. Paths inside the repository are always fine. Paths outside it
# are allowed only when they are explicitly chosen build directories -
# containerised builds put the work directory on a case-sensitive filesystem
# such as /var/tmp - and never when they are a system directory.
for target in "$WORK" "$OUT"; do
    case "$target" in
        "$REPO"/*)
            ;;
        /var/tmp/*|/tmp/*)
            ;;
        ""|/|/usr|/usr/*|/etc|/etc/*|/home|/home/*|/var|/var/*|/opt|/opt/*|/boot|/boot/*)
            printf 'refusing to delete %s: system directory\n' "$target" >&2; exit 1 ;;
        *)
            printf 'refusing to delete %s: outside the repository and not a build directory\n' "$target" >&2
            printf 'set SIMOS_WORK_DIR/SIMOS_OUT_DIR under the repo or /var/tmp\n' >&2
            exit 1 ;;
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

# Build-time staging inside the profile (see scripts/calamares-compat.sh).
COMPAT="$REPO/airootfs/usr/lib/simulationos/calamares-compat"
if [ -d "$COMPAT" ]; then
    info "Removing staged installer compatibility libraries"
    rm -rf -- "$COMPAT"
    rmdir -p --ignore-fail-on-non-empty "$REPO/airootfs/usr/lib/simulationos" 2>/dev/null || true
fi

info "Clean"
