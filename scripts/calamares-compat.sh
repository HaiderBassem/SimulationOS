#!/usr/bin/env bash
#
# calamares-compat.sh - make sure the installer can actually start.
#
# cachyos-calamares links against Boost with a full-version soname
# (libboost_python314.so.1.91.0). Boost changes that soname on every release,
# and the CachyOS repository does not always rebuild Calamares the moment Arch
# ships a new Boost. When that happens every Calamares binary and module fails
# to load:
#
#     calamares: error while loading shared libraries:
#         libboost_python314.so.1.91.0: cannot open shared object file
#
# The ISO still builds and boots - the installer just never opens. This script
# runs before mkarchiso and closes that gap:
#
#   1. download the cachyos-calamares and boost-libs packages the build is
#      about to install (pacman verifies their signatures);
#   2. work out which Boost sonames Calamares needs and whether the current
#      boost-libs provides them;
#   3. if not, fetch the matching boost-libs release from the Arch Linux
#      Archive, verify its signature against the Arch keyring, and stage ONLY
#      the missing libraries in
#          airootfs/usr/lib/simulationos/calamares-compat/
#
# That directory is put on LD_LIBRARY_PATH by simulationos-install for the
# installer process alone; it is never in the system library path, and it is
# deleted from the installed system. When CachyOS has rebuilt Calamares the
# script stages nothing and the directory does not exist.
#
# Signature verification is never bypassed. If a needed library cannot be
# obtained and verified, the build FAILS here rather than shipping an ISO
# whose installer cannot run.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACCONF="${SIMOS_PACMAN_CONF:-$REPO/pacman.conf}"
DEST="$REPO/airootfs/usr/lib/simulationos/calamares-compat"
ARCHIVE="https://archive.archlinux.org/packages/b/boost-libs"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

command -v pacman >/dev/null || die "pacman not found: run this inside the Arch builder"
command -v bsdtar >/dev/null || die "bsdtar not found"
command -v curl   >/dev/null || die "curl not found"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/db" "$TMP/cache" "$TMP/cal" "$TMP/boost" "$TMP/old"
# pacman downloads as an unprivileged sandbox user, which must be able to
# reach the cache directory; mktemp -d creates it 0700.
chmod 755 "$TMP" "$TMP/cache"

# Always start from a clean slate: a stale compat directory from an earlier
# build must not survive a Calamares rebuild that made it unnecessary.
rm -rf -- "$DEST"

info "Checking that cachyos-calamares can load against the current Boost"
pacman --config "$PACCONF" --dbpath "$TMP/db" --cachedir "$TMP/cache" \
       -Sywdd --noconfirm cachyos-calamares boost-libs >/dev/null \
    || die "could not download cachyos-calamares/boost-libs through $PACCONF"

CAL_PKG="$(find "$TMP/cache" -name 'cachyos-calamares-*.pkg.tar.*' ! -name '*.sig' | head -1)"
BOOST_PKG="$(find "$TMP/cache" -name 'boost-libs-*.pkg.tar.*' ! -name '*.sig' | head -1)"
[ -n "$CAL_PKG" ] && [ -n "$BOOST_PKG" ] || die "downloaded packages not found in $TMP/cache"

bsdtar -xf "$CAL_PKG" -C "$TMP/cal" usr/bin usr/lib
bsdtar -tf "$BOOST_PKG" | sed -n 's|^usr/lib/||p' > "$TMP/boost.files"

# Sonames are plain strings in an ELF's dynamic string table, so they can be
# listed without binutils (which the minimal builder image does not ship).
boost_needs() { # file... -> unique libboost sonames referenced
    grep -aohE 'libboost_[A-Za-z0-9_]+\.so\.[0-9]+\.[0-9]+\.[0-9]+' "$@" 2>/dev/null | sort -u
}

mapfile -t ELFS < <(find "$TMP/cal/usr/bin/calamares" "$TMP/cal/usr/lib" -type f \( -name '*.so*' -o -name calamares \))
mapfile -t NEEDED < <(boost_needs "${ELFS[@]}")
[ "${#NEEDED[@]}" -gt 0 ] || { green "    cachyos-calamares does not link against Boost; nothing to do"; exit 0; }

MISSING=()
for so in "${NEEDED[@]}"; do
    grep -qxF "$so" "$TMP/boost.files" || MISSING+=("$so")
done

if [ "${#MISSING[@]}" -eq 0 ]; then
    green "    cachyos-calamares matches boost-libs ($(basename "$BOOST_PKG")); no compatibility libraries needed"
    exit 0
fi

# All missing sonames must agree on one Boost version.
WANT="$(printf '%s\n' "${MISSING[@]}" | sed -E 's/.*\.so\.//' | sort -u)"
[ "$(printf '%s\n' "$WANT" | wc -l)" -eq 1 ] || die "Calamares needs Boost libraries from several versions: $WANT"
info "cachyos-calamares was built against Boost $WANT; the repository ships $(basename "$BOOST_PKG")"

# Newest pkgrel of that exact Boost version in the Arch Linux Archive.
OLD_NAME="$(curl -fsSL "$ARCHIVE/" \
    | grep -oE "boost-libs-${WANT//./\\.}-[0-9]+-x86_64\.pkg\.tar\.zst" | sort -uV | tail -1)"
[ -n "$OLD_NAME" ] || die "boost-libs $WANT is not in the Arch Linux Archive ($ARCHIVE/)"

info "Fetching $OLD_NAME from the Arch Linux Archive"
curl -fsSL -o "$TMP/$OLD_NAME"     "$ARCHIVE/$OLD_NAME"
curl -fsSL -o "$TMP/$OLD_NAME.sig" "$ARCHIVE/$OLD_NAME.sig"
pacman-key --verify "$TMP/$OLD_NAME.sig" "$TMP/$OLD_NAME" >/dev/null 2>&1 \
    || die "signature verification FAILED for $OLD_NAME; refusing to ship it"
green "    signature verified against the Arch Linux keyring"
bsdtar -xf "$TMP/$OLD_NAME" -C "$TMP/old" usr/lib

# Stage the missing libraries and, transitively, any old Boost library they
# need in turn (libboost_python pulls in nothing else today, but libboost_graph
# and friends reference each other).
mkdir -p "$DEST"
queue=("${MISSING[@]}")
while [ "${#queue[@]}" -gt 0 ]; do
    so="${queue[0]}"; queue=("${queue[@]:1}")
    [ -e "$DEST/$so" ] && continue
    [ -f "$TMP/old/usr/lib/$so" ] || die "$OLD_NAME does not contain $so"
    install -m755 "$TMP/old/usr/lib/$so" "$DEST/$so"
    while read -r dep; do
        [ -n "$dep" ] || continue
        grep -qxF "$dep" "$TMP/boost.files" && continue
        [ -e "$DEST/$dep" ] || queue+=("$dep")
    done < <(boost_needs "$DEST/$so")
done

cat > "$DEST/README" <<EOF
Boost $WANT libraries for the SimulationOS installer only.

cachyos-calamares ($(basename "$CAL_PKG")) is linked against Boost $WANT, but
this ISO ships $(basename "$BOOST_PKG"). These files come from the
signature-verified Arch Linux Archive package $OLD_NAME and are used through
LD_LIBRARY_PATH by /usr/local/bin/simulationos-install. They are not in the
system library path and are removed from the installed system.

Generated by scripts/calamares-compat.sh.
EOF

green "    staged $(find "$DEST" -name '*.so*' | wc -l) compatibility libraries in ${DEST#"$REPO"/}:"
find "$DEST" -name '*.so*' -printf '        %f\n' | sort
