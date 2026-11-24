#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
CLONE_URL=""
STARTER=""
NO_STARTER=0
SDK_URL_OVERRIDE=""
ALLOW_UNVERIFIED_TOOLCHAIN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a path"
            REPO_ARG="$2"
            shift 2
            ;;
        --clone)
            [[ $# -ge 2 ]] || die "--clone requires a git repository URL"
            CLONE_URL="$2"
            shift 2
            ;;
        --starter)
            [[ $# -ge 2 ]] || die "--starter requires: felucca-bsp, fm1-base, dinghy, or fm1-open"
            STARTER="$2"
            shift 2
            ;;
        --no-starter)
            NO_STARTER=1
            shift
            ;;
        --sdk-url)
            [[ $# -ge 2 ]] || die "--sdk-url requires a URL"
            SDK_URL_OVERRIDE="$2"
            shift 2
            ;;
        --allow-unverified-toolchain)
            ALLOW_UNVERIFIED_TOOLCHAIN=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: fm1 setup [--repo <path>] [--starter <name> | --clone <url> | --no-starter] [--sdk-url <url>] [--allow-unverified-toolchain]

Idempotently provisions the universal Layer 1 FM-1 environment and (by default) clones felucca-bsp:
  1. Repo-local Python venv ($FM1_VENV_DIR)
  2. Verified JieLi Linux toolchain ($FM1_CACHE_DIR/jieli/toolchain)
  3. Pinned JieLi AC79 SDK ($FM1_CACHE_DIR/fw-AC79_AIoT_SDK)
  4. Local linux/amd64 builder image ($FM1_DOCKER_IMAGE)
  5. Starter repo (default: felucca-bsp -> ./workspace/felucca-bsp) or submodules in --repo

Starters (--starter <name>):
  felucca-bsp   Minimal open-source FM-1 BSP (default)
  fm1-base      Middleware on felucca-bsp (host sim, web emu, CoreMIDI tools)
  dinghy        Direct felucca/sloop lineage middleware
  fm1-open      M-VAVE official vendor open firmware
EOF
            exit 0
            ;;
        *)
            die "unknown option for setup: $1"
            ;;
    esac
done

if [[ -n "$CLONE_URL" && -n "$STARTER" ]]; then
    die "--clone and --starter cannot be used together"
fi
if [[ "$NO_STARTER" -eq 1 && ( -n "$CLONE_URL" || -n "$STARTER" ) ]]; then
    die "--no-starter cannot be combined with --starter or --clone"
fi

# Default to felucca-bsp when no --repo, --clone, --starter, or --no-starter is provided
if [[ "$NO_STARTER" -eq 0 && -z "$CLONE_URL" && -z "$STARTER" && -z "$REPO_ARG" && -z "${FM1_REPO_DIR:-}" ]]; then
    STARTER="felucca-bsp"
fi

if [[ -n "$STARTER" ]]; then
    case "$STARTER" in
        felucca-bsp) CLONE_URL="$FELUCCA_BSP_URL" ;;
        fm1-base)    CLONE_URL="$FM1_BASE_URL" ;;
        dinghy)      CLONE_URL="$DINGHY_URL" ;;
        fm1-open)    CLONE_URL="$FM1_OPEN_URL" ;;
        *)           die "unknown --starter '$STARTER' (expected: felucca-bsp, fm1-base, dinghy, or fm1-open)" ;;
    esac
fi

mkdir -p "$FM1_CACHE_DIR/staging" "$FM1_CACHE_DIR/jieli"

# 1. Local Python venv (stamp pinned specs so pins.env bumps trigger upgrade)
info "Ensuring repo-local Python venv ($FM1_VENV_DIR)..."
VENV_STAMP="$FM1_VENV_DIR/.pins.sha256"
WANT_VENV_SHA="$(printf '%s|%s|%s\n' "$PY_PILLOW_SPEC" "$PY_MIDO_SPEC" "$PY_RTMIDI_SPEC" | { shasum -a 256 2>/dev/null || sha256sum; } | awk '{print $1}')"
if [[ ! -x "$FM1_VENV_DIR/bin/python" ]]; then
    python3 -m venv "$FM1_VENV_DIR"
fi
if [[ ! -f "$VENV_STAMP" ]] || [[ "$(cat "$VENV_STAMP")" != "$WANT_VENV_SHA" ]] || ! "$FM1_VENV_DIR/bin/python" -c "import PIL, mido, rtmidi" >/dev/null 2>&1; then
    "$FM1_VENV_DIR/bin/pip" install -q "$PY_PILLOW_SPEC" "$PY_MIDO_SPEC" "$PY_RTMIDI_SPEC"
    printf '%s\n' "$WANT_VENV_SHA" > "$VENV_STAMP"
fi

# 2. JieLi Linux toolchain (staged download + SHA256 verification)
TC_LINK="$FM1_CACHE_DIR/jieli/toolchain"
TC_STAMP="$FM1_CACHE_DIR/jieli/toolchain.sha256"
if [[ ! -x "$TC_LINK/common/bin/clang" ]] || [[ ! -f "$TC_STAMP" ]] || [[ "$(cat "$TC_STAMP")" != "$JIELI_TOOLCHAIN_SHA256" && "$ALLOW_UNVERIFIED_TOOLCHAIN" -eq 0 ]]; then
    TARBALL="$FM1_CACHE_DIR/staging/toolchain.tar.xz"
    if [[ -f "$TARBALL" ]]; then
        ACTUAL_SHA="$(sha256_file "$TARBALL")"
        if [[ "$ACTUAL_SHA" != "$JIELI_TOOLCHAIN_SHA256" ]]; then
            warn "Staged toolchain SHA256 ($ACTUAL_SHA) != pinned ($JIELI_TOOLCHAIN_SHA256); re-downloading..."
            rm -f "$TARBALL"
        fi
    fi
    if [[ ! -f "$TARBALL" ]]; then
        info "Downloading JieLi Linux toolchain..."
        curl -fL --retry 3 -o "$TARBALL.part" "$JIELI_TOOLCHAIN_URL"
        mv "$TARBALL.part" "$TARBALL"
    fi
    ACTUAL_SHA="$(sha256_file "$TARBALL")"
    if [[ "$ACTUAL_SHA" != "$JIELI_TOOLCHAIN_SHA256" ]]; then
        if [[ "$ALLOW_UNVERIFIED_TOOLCHAIN" -eq 1 ]]; then
            warn "Toolchain SHA256 mismatch ($ACTUAL_SHA != $JIELI_TOOLCHAIN_SHA256); continuing due to --allow-unverified-toolchain"
        else
            die "Toolchain SHA256 mismatch ($ACTUAL_SHA != $JIELI_TOOLCHAIN_SHA256). Inspect $TARBALL or pass --allow-unverified-toolchain"
        fi
    fi

    STAGE_EXTRACT="$FM1_CACHE_DIR/staging/jieli-extract"
    rm -rf "$STAGE_EXTRACT"
    mkdir -p "$STAGE_EXTRACT"
    info "Extracting JieLi Linux toolchain..."
    tar -xJf "$TARBALL" -C "$STAGE_EXTRACT"
    EXTRACTED_DIR="$(find "$STAGE_EXTRACT" -maxdepth 1 -type d -name "$JIELI_TOOLCHAIN_DIR_GLOB" | head -n 1)"
    [[ -n "$EXTRACTED_DIR" ]] || die "expected directory matching $JIELI_TOOLCHAIN_DIR_GLOB inside toolchain archive"

    TARGET_DIR="$FM1_CACHE_DIR/jieli/${ACTUAL_SHA:0:12}"
    rm -rf "$TARGET_DIR"
    mv "$EXTRACTED_DIR" "$TARGET_DIR"
    rm -rf "$STAGE_EXTRACT"
    ln -sfn "${ACTUAL_SHA:0:12}" "$TC_LINK"
    printf '%s\n' "$ACTUAL_SHA" > "$TC_STAMP"
    rm -f "$TARBALL"
else
    info "JieLi toolchain already cached and verified."
fi

# 3. JieLi AC79 SDK (staged clone + exact commit SHA verification)
SDK_DIR="$FM1_CACHE_DIR/fw-AC79_AIoT_SDK"
SDK_SOURCE="${SDK_URL_OVERRIDE:-$AC79_SDK_URL}"
NEED_SDK=1
if [[ -d "$SDK_DIR/.git" ]]; then
    if [[ "$(git -C "$SDK_DIR" rev-parse HEAD 2>/dev/null || echo '')" == "$AC79_SDK_COMMIT" ]]; then
        NEED_SDK=0
        info "JieLi AC79 SDK already cached at $AC79_SDK_COMMIT."
    else
        warn "Cached AC79 SDK commit mismatch; re-fetching..."
    fi
fi

if [[ "$NEED_SDK" -eq 1 ]]; then
    STAGE_SDK="$FM1_CACHE_DIR/staging/fw-AC79_AIoT_SDK"
    CLONED=0
    for attempt in 1 2 3; do
        rm -rf "$STAGE_SDK"
        info "Cloning AC79 SDK ($AC79_SDK_TAG, attempt $attempt/3)..."
        if git clone --depth 1 --branch "$AC79_SDK_TAG" "$SDK_SOURCE" "$STAGE_SDK"; then
            CLONED=1
            break
        fi
        sleep 5
    done
    [[ "$CLONED" -eq 1 ]] || die "failed to clone AC79 SDK from $SDK_SOURCE after 3 attempts"

    ACTUAL_COMMIT="$(git -C "$STAGE_SDK" rev-parse HEAD)"
    [[ "$ACTUAL_COMMIT" == "$AC79_SDK_COMMIT" ]] || die "AC79 SDK HEAD ($ACTUAL_COMMIT) != pinned commit ($AC79_SDK_COMMIT)"

    if [[ -e "$SDK_DIR" ]]; then
        rm -rf "${SDK_DIR}.old"
        mv "$SDK_DIR" "${SDK_DIR}.old"
    fi
    mv "$STAGE_SDK" "$SDK_DIR"
    rm -rf "${SDK_DIR}.old"
fi

# 4. Local linux/amd64 builder image (zero JieLi binaries inside image layers)
command -v docker >/dev/null 2>&1 || die "docker CLI not found; install OrbStack or Docker Desktop"
docker info >/dev/null 2>&1 || die "docker daemon not running; start OrbStack or Docker Desktop"
info "Building local builder image ($FM1_DOCKER_IMAGE, linux/amd64)..."
docker build --platform linux/amd64 \
    --build-arg "BASE_IMAGE=$FM1_BASE_IMAGE" \
    -t "$FM1_DOCKER_IMAGE" \
    -f "$KIT_ROOT/container/Dockerfile" \
    "$KIT_ROOT/container"

# 5. Optional starter clone / submodule init
ACTIVE_REPO=""
if [[ -n "$CLONE_URL" ]]; then
    STARTER_NAME="${STARTER:-custom}"
    TARGET_REPO="${REPO_ARG:-${FM1_REPO_DIR:-$FM1_KIT_HOME/workspace/$STARTER_NAME}}"
    mkdir -p "$(dirname "$TARGET_REPO")"
    if [[ ! -e "$TARGET_REPO/.git" ]]; then
        info "Cloning $CLONE_URL into $TARGET_REPO..."
        git clone --recursive "$CLONE_URL" "$TARGET_REPO"
    fi
    ACTIVE_REPO="$(cd "$TARGET_REPO" && pwd)"
elif [[ -n "$REPO_ARG" || -n "${FM1_REPO_DIR:-}" ]]; then
    ACTIVE_REPO="$(resolve_repo_path "$REPO_ARG")"
fi

if [[ -n "$ACTIVE_REPO" ]]; then
    if [[ -e "$ACTIVE_REPO/.git" ]]; then
        info "Ensuring recursive submodules in $ACTIVE_REPO..."
        git -C "$ACTIVE_REPO" submodule update --init --recursive
    else
        die "firmware repo is not a git checkout: $ACTIVE_REPO"
    fi
fi

info "Setup complete."
printf '\nNext steps:\n'
printf '  1. Verify environment:  ./bin/fm1 doctor%s\n' "${ACTIVE_REPO:+ --repo $ACTIVE_REPO}"
if [[ -n "$ACTIVE_REPO" && -f "$ACTIVE_REPO/build.sh" ]]; then
    printf '  2. Test & build:        ./bin/fm1 test --repo %s && ./bin/fm1 build --repo %s\n' "$ACTIVE_REPO" "$ACTIVE_REPO"
    printf '  3. Flash over CoreMIDI: ./bin/fm1 flash --repo %s --dry-run\n' "$ACTIVE_REPO"
elif [[ -n "$ACTIVE_REPO" ]]; then
    printf '  2. Open build shell:    ./bin/fm1 shell --repo %s\n' "$ACTIVE_REPO"
    printf '  3. Or run build cmd:    ./bin/fm1 exec --repo %s -- <cmd>\n' "$ACTIVE_REPO"
else
    printf '  2. Clone a starter:     ./bin/fm1 setup --starter felucca-bsp\n'
fi
printf '  4. Guide & agent prompts: docs/NEXT-STEPS.md\n'
