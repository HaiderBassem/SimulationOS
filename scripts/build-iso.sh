#!/usr/bin/env bash
#
# build-iso.sh - build the SimulationOS ISO with mkarchiso.
#
# Refuses to run in an environment that cannot produce a correct x86_64 ISO
# rather than emitting a broken or wrong-architecture image.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${SIMOS_WORK_DIR:-$REPO/work}"
OUT="${SIMOS_OUT_DIR:-$REPO/out}"

# CachyOS signing key, per CachyOS' own cachyos-repo.sh.
CACHYOS_KEY="F3B607488DB35A47"
CACHYOS_MIRROR="https://mirror.cachyos.org/repo/x86_64/cachyos"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

# ------------------------------------------------------------------ 1. host
info "Checking build environment"

[ "$(uname -s)" = "Linux" ] || die "mkarchiso only runs on Linux. This host is $(uname -s).
       Build SimulationOS on an Arch Linux x86_64 machine, VM, or container.
       See README.md -> Building for a container recipe."

if [ "$(uname -m)" != "x86_64" ]; then
    die "This host is $(uname -m), but SimulationOS targets x86_64.
       Building here would produce packages for the wrong architecture.
       Use an x86_64 Arch host or an x86_64 container."
fi

[ "$(id -u)" -eq 0 ] || die "mkarchiso must run as root. Try: sudo $0 $*"

command -v pacman    >/dev/null || die "pacman not found: this is not an Arch-based host."
command -v mkarchiso >/dev/null || die "mkarchiso not found. Install it with: pacman -S archiso"

# --------------------------------------------------- 2. CachyOS prerequisites
info "Checking CachyOS repository prerequisites"

if ! pacman -Q cachyos-keyring >/dev/null 2>&1; then
    red "The cachyos-keyring package is not installed on this build host."
    red ""
    red "SimulationOS installs linux-cachyos, cachyos-calamares, ckbcomp and"
    red "mkinitcpio-openswap from the CachyOS repository. pacstrap verifies those"
    red "signatures against the BUILD HOST keyring, so the key must be trusted here."
    red "Package signature verification is never disabled to work around this."
    red ""
    red "Provision it with:"
    red "    pacman-key --recv-keys $CACHYOS_KEY --keyserver keyserver.ubuntu.com"
    red "    pacman-key --lsign-key $CACHYOS_KEY"
    red "    pacman -Sy --config $REPO/pacman.conf cachyos-keyring cachyos-mirrorlist"
    red ""
    red "(Installing through the profile's own pacman.conf avoids a hardcoded"
    red " package-version URL, which goes stale every time CachyOS rebuilds"
    red " the keyring.)"
    exit 1
fi

if ! pacman-key --list-keys "$CACHYOS_KEY" >/dev/null 2>&1; then
    die "cachyos-keyring is installed but key $CACHYOS_KEY is not in the pacman keyring.
       Run: pacman-key --populate cachyos"
fi
green "    CachyOS keyring present and key $CACHYOS_KEY is trusted"

# The profile's pacman.conf pins explicit CachyOS Server= URLs, so no
# /etc/pacman.d/cachyos-mirrorlist is needed on the host. Confirm the repo
# actually resolves before spending an hour on a build.
info "Verifying the CachyOS repository resolves"
if ! pacman -Sp --config "$REPO/pacman.conf" linux-cachyos >/dev/null 2>&1; then
    die "Cannot resolve 'linux-cachyos' through $REPO/pacman.conf.
       Check network access to $CACHYOS_MIRROR and that the [cachyos] section is intact."
fi
green "    linux-cachyos resolves: $(pacman -Sp --config "$REPO/pacman.conf" linux-cachyos 2>/dev/null | head -1)"

# ------------------------------------------------------------ 3. static checks
info "Running profile validation"
if ! "$REPO/scripts/validate-profile.sh"; then
    die "validate-profile.sh failed. Fix the errors above before building."
fi

# ------------------------------------------------------------------ 4. workdir
if [ -d "$WORK" ]; then
    if [ "${SIMOS_REUSE_WORK:-0}" = "1" ]; then
        info "Reusing existing work directory $WORK (SIMOS_REUSE_WORK=1)"
    else
        info "Clearing stale work directory $WORK"
        "$REPO/scripts/clean-build.sh" --keep-iso
    fi
fi
mkdir -p -- "$WORK" "$OUT"

# -------------------------------------------------------------------- 5. build
info "Running mkarchiso (this takes a while and needs ~20 GB free)"
BUILD_LOG="$OUT/build.log"
BUILD_START="$(date -u +%s)"
set -o pipefail
mkarchiso -v -w "$WORK" -o "$OUT" "$REPO" 2>&1 | tee "$BUILD_LOG"
BUILD_END="$(date -u +%s)"

# ------------------------------------------------------------- 6/7. artifact
ISO="$(ls -1t "$OUT"/simulationos-*.iso 2>/dev/null | head -1)"
[ -n "$ISO" ] || die "mkarchiso finished but no ISO was produced in $OUT"

info "Generating SHA256 checksum"
( cd "$OUT" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256" )

info "Writing build-info.json"
# Everything a release engineer needs to answer "which commit produced this
# exact file, with which tools".
cat > "$OUT/build-info.json" <<JSON
{
  "iso": "$(basename "$ISO")",
  "sha256": "$(cut -d" " -f1 < "$ISO.sha256")",
  "size_bytes": $(stat -c%s "$ISO" 2>/dev/null || stat -f%z "$ISO"),
  "iso_version": "$(bash -c 'source "'"$REPO"'/profiledef.sh"; printf %s "$iso_version"')",
  "target_arch": "$(bash -c 'source "'"$REPO"'/profiledef.sh"; printf %s "$arch"')",
  "git_commit": "$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)",
  "git_branch": "$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)",
  "git_dirty": $(test -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" && echo true || echo false),
  "archiso_version": "$(pacman -Q archiso 2>/dev/null | awk '{print $2}' || echo unknown)",
  "pacman_version": "$(pacman -Q pacman 2>/dev/null | awk '{print $2}' || echo unknown)",
  "build_date_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_seconds": $(( BUILD_END - BUILD_START )),
  "builder_host": "$(uname -srm)"
}
JSON
python3 -c "import json;json.load(open('$OUT/build-info.json'))" 2>/dev/null \
    && green "    build-info.json is valid JSON" \
    || red   "    WARNING: build-info.json is not valid JSON"

green ""
green "Build complete"
green "  ISO:      $ISO"
green "  Size:     $(du -h "$ISO" | cut -f1)"
green "  SHA256:   $(cut -d' ' -f1 < "$ISO.sha256")"
green "  Checksum: $ISO.sha256"
green "  Metadata: $OUT/build-info.json"
green "  Log:      $BUILD_LOG"
green ""
green "Boot it with: ./scripts/test-iso.sh \"$ISO\""
