#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a path"
            REPO_ARG="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            echo "Usage: fm1 exec [--repo <path>] -- <command...>"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -gt 0 ]] || die "usage: fm1 exec [--repo <path>] -- <command...>"

if [[ -n "$REPO_ARG" || -n "${FM1_REPO_DIR:-}" ]]; then
    REPO_DIR="$(require_repo_path "$REPO_ARG")"
else
    REPO_DIR="$(pwd)"
fi
TC_LINK="$FM1_CACHE_DIR/jieli/toolchain"
SDK_DIR="$FM1_CACHE_DIR/fw-AC79_AIoT_SDK"
[[ -x "$TC_LINK/common/bin/clang" ]] || die "JieLi toolchain not cached ($TC_LINK); run 'fm1 setup'"
[[ -d "$SDK_DIR/.git" ]] || die "AC79 SDK not cached ($SDK_DIR); run 'fm1 setup'"
command -v docker >/dev/null 2>&1 || die "docker CLI not found; install OrbStack or Docker Desktop"
docker info >/dev/null 2>&1 || die "docker daemon not running; start OrbStack or Docker Desktop"
docker image inspect "$FM1_DOCKER_IMAGE" >/dev/null 2>&1 || die "builder image missing ($FM1_DOCKER_IMAGE); run 'fm1 setup'"

TC_REAL="$(cd "$TC_LINK" && pwd -P)"
SDK_REAL="$(cd "$SDK_DIR" && pwd -P)"

exec docker run --rm --platform linux/amd64 \
    -v "$REPO_DIR:/work" \
    -v "$TC_REAL:/opt/jieli:ro" \
    -v "$SDK_REAL:/opt/ac79_sdk:ro" \
    -e JIELI_TOOLCHAIN=/opt/jieli \
    -e AC79_SDK=/opt/ac79_sdk \
    -w /work \
    "$FM1_DOCKER_IMAGE" \
    "$@"
