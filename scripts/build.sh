#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
RELEASE_VER=""
ONE_CORE=0
HOST_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a path"
            REPO_ARG="$2"
            shift 2
            ;;
        --release)
            [[ $# -ge 2 ]] || die "--release requires a version string"
            RELEASE_VER="$2"
            shift 2
            ;;
        --1core)
            ONE_CORE=1
            shift
            ;;
        --host)
            HOST_ONLY=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: fm1 build [--repo <path>] [--release <ver>] [--1core] [--host]

Builds an FM-1 firmware repo using its ./build.sh (or use 'fm1 exec -- <cmd>' for custom layouts).

Options:
  --repo <path>      Path to firmware repository (or set FM1_REPO_DIR)
  --release <ver>    Build release package (passes --release <ver> to ./build.sh)
  --1core            Single-core firmware build (FM1B_CPU2=0 ./build.sh)
  --host             Build native host targets (tools/build_host.sh and/or ./build.sh --host)
EOF
            exit 0
            ;;
        *)
            die "unknown option for build: $1"
            ;;
    esac
done

REPO_DIR="$(require_repo_path "$REPO_ARG")"

if [[ "$HOST_ONLY" -eq 1 ]]; then
    if [[ "$ONE_CORE" -eq 1 || -n "$RELEASE_VER" ]]; then
        die "--host cannot be combined with --1core or --release"
    fi
    info "Building native host targets in $REPO_DIR..."
    if [[ -d "$FM1_VENV_DIR/bin" ]]; then
        PATH="$FM1_VENV_DIR/bin:$PATH"
    fi
    RAN_ANY=0
    if [[ -x "$REPO_DIR/tools/build_host.sh" ]]; then
        (cd "$REPO_DIR" && tools/build_host.sh)
        RAN_ANY=1
    fi
    if [[ -x "$REPO_DIR/build.sh" ]] && grep -q -- '--host' "$REPO_DIR/build.sh" 2>/dev/null; then
        (cd "$REPO_DIR" && ./build.sh --host)
        RAN_ANY=1
    fi
    [[ "$RAN_ANY" -eq 1 ]] || die "no host build script found in $REPO_DIR"
    info "Host build complete."
    exit 0
fi

[[ -f "$REPO_DIR/build.sh" ]] || die "no build.sh in $REPO_DIR; use 'fm1 exec --repo $REPO_DIR -- <your-build-cmd>'"

TC_LINK="$FM1_CACHE_DIR/jieli/toolchain"
SDK_DIR="$FM1_CACHE_DIR/fw-AC79_AIoT_SDK"
[[ -x "$TC_LINK/common/bin/clang" ]] || die "JieLi toolchain not cached ($TC_LINK); run 'fm1 setup'"
[[ -d "$SDK_DIR/.git" ]] || die "AC79 SDK not cached ($SDK_DIR); run 'fm1 setup'"
command -v docker >/dev/null 2>&1 || die "docker CLI not found; install OrbStack or Docker Desktop"
docker info >/dev/null 2>&1 || die "docker daemon not running; start OrbStack or Docker Desktop"
docker image inspect "$FM1_DOCKER_IMAGE" >/dev/null 2>&1 || die "builder image missing ($FM1_DOCKER_IMAGE); run 'fm1 setup'"

TC_REAL="$(cd "$TC_LINK" && pwd -P)"
SDK_REAL="$(cd "$SDK_DIR" && pwd -P)"

CPU2_VAL="1"
if [[ "$ONE_CORE" -eq 1 ]]; then
    CPU2_VAL="0"
fi

info "Building FM-1 firmware in $FM1_DOCKER_IMAGE (FM1B_CPU2=$CPU2_VAL${RELEASE_VER:+, --release $RELEASE_VER})..."
docker run --rm --platform linux/amd64 \
    -v "$REPO_DIR:/work" \
    -v "$TC_REAL:/opt/jieli:ro" \
    -v "$SDK_REAL:/opt/ac79_sdk:ro" \
    -e JIELI_TOOLCHAIN=/opt/jieli \
    -e AC79_SDK=/opt/ac79_sdk \
    -e FM1B_CPU2="$CPU2_VAL" \
    -e FM1_RELEASE_VER="$RELEASE_VER" \
    -w /work \
    "$FM1_DOCKER_IMAGE" \
    bash -c '
        set -euo pipefail
        LOG_FILE="$(mktemp)"
        trap "rm -f \"$LOG_FILE\"" EXIT
        if [[ -n "$FM1_RELEASE_VER" ]]; then
            ./build.sh --release "$FM1_RELEASE_VER" | tee "$LOG_FILE"
        else
            ./build.sh | tee "$LOG_FILE"
        fi

        ELF_PATH=""
        for d in app/build build; do
            [[ -d "$d" ]] || continue
            CAND="$(find "$d" -maxdepth 1 -type f -name "*.elf" | head -n 1 || true)"
            if [[ -n "$CAND" ]]; then
                ELF_PATH="$CAND"
                break
            fi
        done

        if [[ -n "$ELF_PATH" ]]; then
            ELF_DIR="$(dirname "$ELF_PATH")"
            SYM_PATH="${ELF_PATH%.elf}.sym"
            BUILD_ID="$(awk '\''$1 == "build" {print $2; exit}'\'' "$LOG_FILE" || true)"
            if [[ -n "$BUILD_ID" ]]; then
                printf "%s\n" "$BUILD_ID" > "$ELF_DIR/build_id.txt"
            fi
            "$JIELI_TOOLCHAIN/common/bin/objdump" -t "$ELF_PATH" \
                | awk '\''$4 == ".text" || $4 == ".ram_text" {print $1, $NF}'\'' \
                | sort > "$SYM_PATH"
            echo "[fm1] $SYM_PATH: $(wc -l < "$SYM_PATH") symbols"
            echo "[fm1] .pool symbols:"
            "$JIELI_TOOLCHAIN/common/bin/objdump" -t "$ELF_PATH" \
                | awk '\''/\.pool/ && $NF != ".pool" && c < 12 {printf "  %-16s %s\n", $NF, $1; c++}'\''
        fi
    '

info "Firmware build complete."
