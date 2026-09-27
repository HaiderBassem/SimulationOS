#!/usr/bin/env bash
#
# build.sh - the single entry point for building SimulationOS.
#
#   ./build.sh
#
# This is the ONE build engine. Local developers, CI and the release pipeline
# all call this same script, so a local build and a CI build cannot drift.
#
# It does not itself know how to build an ISO. It works out *where* the build
# can legally happen and then runs scripts/build-iso.sh there:
#
#   Arch Linux x86_64      -> run natively
#   any other Linux/macOS  -> run inside an x86_64 Arch container
#
# SimulationOS targets x86_64. On an arm64 host the container is forced to
# linux/amd64 so we can never silently emit an arm64 ISO.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${SIMOS_BUILDER_IMAGE:-docker.io/archlinux:latest}"
TARGET_ARCH="x86_64"

CLEAN=0
NO_CACHE=0
VERBOSE=0
FORCE_NATIVE=0
FORCE_CONTAINER=0
VALIDATE_ONLY=0

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

usage() {
    cat <<'EOF'
usage: ./build.sh [options]

  --clean          remove work/ and out/ before building
  --no-cache       do not reuse the host pacman package cache
  --validate       run static validation only, then stop
  --native         force a native build (fails unless Arch x86_64 + root)
  --container      force a containerised build even on Arch
  --verbose        verbose build output
  -h, --help       this message

Environment:
  SIMOS_BUILDER_IMAGE   builder image        (default docker.io/archlinux:latest)
  SIMOS_CONTAINER       podman | docker      (default: whichever is present)
  SIMOS_WORK_DIR        work directory       (default ./work)
  SIMOS_OUT_DIR         output directory     (default ./out)

Output:
  out/simulationos-<version>-x86_64.iso  (+ .sha256, build-info.json, build.log)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --clean)     CLEAN=1 ;;
        --no-cache)  NO_CACHE=1 ;;
        --validate)  VALIDATE_ONLY=1 ;;
        --native)    FORCE_NATIVE=1 ;;
        --container) FORCE_CONTAINER=1 ;;
        --verbose)   VERBOSE=1 ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

# ----------------------------------------------------------------- validation
# Static validation runs on the host: it is pure bash and needs no pacman, so
# there is no reason to spin up a container to be told the profile is broken.
info "Validating profile"
"$REPO/scripts/validate-profile.sh" || die "profile validation failed"
if [ "$VALIDATE_ONLY" -eq 1 ]; then
    green "Validation only (--validate); stopping here."
    exit 0
fi

# ------------------------------------------------------------- where to build
is_native_capable() {
    [ "$HOST_OS" = "Linux" ] || return 1
    [ "$HOST_ARCH" = "$TARGET_ARCH" ] || return 1
    command -v mkarchiso >/dev/null 2>&1 || return 1
    return 0
}

MODE="container"
if [ "$FORCE_NATIVE" -eq 1 ]; then
    MODE="native"
elif [ "$FORCE_CONTAINER" -eq 1 ]; then
    MODE="container"
elif is_native_capable; then
    MODE="native"
fi

printf '\n'
info "Host:    $HOST_OS $HOST_ARCH"
info "Target:  linux $TARGET_ARCH"
info "Builder: $MODE"
printf '\n'

# ---------------------------------------------------------------- clean first
if [ "$CLEAN" -eq 1 ]; then
    "$REPO/scripts/clean-build.sh"
fi

# -------------------------------------------------------------- native build
if [ "$MODE" = "native" ]; then
    is_native_capable || die "--native requested but this host cannot build natively
       (need Linux $TARGET_ARCH with mkarchiso installed; this is $HOST_OS $HOST_ARCH)."
    [ "$(id -u)" -eq 0 ] || die "a native build must run as root. Try: sudo ./build.sh"
    exec "$REPO/scripts/build-iso.sh"
fi

# ----------------------------------------------------------- container build
RUNTIME="${SIMOS_CONTAINER:-}"
if [ -z "$RUNTIME" ]; then
    for c in podman docker; do
        command -v "$c" >/dev/null 2>&1 && { RUNTIME="$c"; break; }
    done
fi
[ -n "$RUNTIME" ] || die "no container runtime found. Install podman or docker,
       or build on an Arch Linux $TARGET_ARCH host and use --native."

"$RUNTIME" info >/dev/null 2>&1 \
    || die "$RUNTIME is installed but its daemon is not responding. Start it and retry."

EMULATED=0
if [ "$HOST_ARCH" != "$TARGET_ARCH" ]; then
    EMULATED=1
    red "NOTE: host is $HOST_ARCH but the target is $TARGET_ARCH."
    red "      The builder runs under emulation, which is CORRECT but SLOW."
    red "      A native x86_64 machine will be dramatically faster."
    printf '\n'
fi

CACHE_ARGS=()
if [ "$NO_CACHE" -eq 0 ]; then
    CACHE_DIR="$REPO/.cache/pacman"
    mkdir -p "$CACHE_DIR"
    CACHE_ARGS=(-v "$CACHE_DIR:/var/cache/pacman/pkg")
    info "Reusing package cache at .cache/pacman (use --no-cache to disable)"
fi

# mkarchiso needs loop devices, mount and squashfs; those require elevated
# container privileges. This is the same model CachyOS uses in its CI.
info "Starting $RUNTIME builder ($IMAGE, platform linux/amd64)"
exec "$RUNTIME" run --rm -i \
    --platform linux/amd64 \
    --privileged \
    -v "$REPO:/simulationos" \
    "${CACHE_ARGS[@]}" \
    -w /simulationos \
    -e "SIMOS_VERBOSE=$VERBOSE" \
    -e "SIMOS_EMULATED=$EMULATED" \
    "$IMAGE" \
    bash -euo pipefail -c '
        printf "\033[36m==>\033[0m builder arch: $(uname -m)\n"
        [ "$(uname -m)" = "x86_64" ] || { echo "ERROR: builder is not x86_64"; exit 1; }

        # pacman >=7 sandboxes downloads with seccomp and an unprivileged
        # user. Under qemu-user emulation that syscall filter fails outright:
        #   error restricting syscalls via seccomp: 22!   (EINVAL)
        # It must be disabled BEFORE the first pacman call, and only for this
        # throwaway builder. Signature verification is untouched and the
        # committed pacman.conf is never modified - validate-profile.sh fails
        # if DisableSandbox ever appears in a committed config.
        if [ "${SIMOS_EMULATED:-0}" = "1" ]; then
            printf "\033[33m==>\033[0m Emulated builder: disabling the pacman sandbox (this container only)\n"
            grep -q "^DisableSandbox" /etc/pacman.conf \
                || sed -i "0,/^\[options\]/s//[options]\nDisableSandbox/" /etc/pacman.conf
            SIMOS_PACMAN_CONF=/tmp/pacman.emulated.conf
            sed "0,/^\[options\]/s//[options]\nDisableSandbox/" \
                /simulationos/pacman.conf > "$SIMOS_PACMAN_CONF"
            export SIMOS_PACMAN_CONF
            # Belt and braces: the conf setting is not always honoured for
            # pacman calls made here, so pass the flag explicitly too.
            PACFLAGS="--disable-sandbox"
        fi
        PACFLAGS="${PACFLAGS:-}"

        printf "\033[36m==>\033[0m Refreshing keyring and installing archiso\n"
        pacman $PACFLAGS -Sy --noconfirm --needed archlinux-keyring >/dev/null
        pacman $PACFLAGS -S  --noconfirm --needed archiso >/dev/null

        printf "\033[36m==>\033[0m Trusting the CachyOS signing key\n"
        pacman-key --init >/dev/null 2>&1 || true
        pacman-key --populate archlinux >/dev/null 2>&1 || true
        pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com >/dev/null 2>&1 \
            || { echo "ERROR: could not fetch the CachyOS signing key"; exit 1; }
        pacman-key --lsign-key F3B607488DB35A47 >/dev/null 2>&1

        # Install the keyring through the profile pacman.conf so there is no
        # hardcoded package-version URL to go stale.
        pacman $PACFLAGS -Sy --noconfirm --needed --config "${SIMOS_PACMAN_CONF:-/simulationos/pacman.conf}" \
            cachyos-keyring cachyos-mirrorlist >/dev/null \
            || { echo "ERROR: could not install cachyos-keyring"; exit 1; }
        pacman-key --populate cachyos >/dev/null 2>&1 || true

        exec /simulationos/scripts/build-iso.sh
    '
