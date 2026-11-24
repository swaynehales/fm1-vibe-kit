#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
FUZZ_SEEDS="8"
HOST_ONLY=0
CONTAINER_ALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a path"
            REPO_ARG="$2"
            shift 2
            ;;
        --fuzz)
            [[ $# -ge 2 ]] || die "--fuzz requires a seed count (e.g. 8)"
            FUZZ_SEEDS="$2"
            shift 2
            ;;
        --host-only)
            HOST_ONLY=1
            shift
            ;;
        --container-all)
            CONTAINER_ALL=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: fm1 test [--repo <path>] [--fuzz <seeds>] [--host-only] [--container-all]

Auto-detects host test & fuzz scripts in the target FM-1 repo (or use 'fm1 exec -- <cmd>' for custom suites).

Options:
  --repo <path>      Path to firmware repository (or set FM1_REPO_DIR)
  --fuzz <seeds>     Number of fuzz seeds to run in container (default: 8)
  --host-only        Run native host tests only (skips Linux ASan/UBSan fuzzing)
  --container-all    Run both host tests and fuzzing inside linux/amd64 container
EOF
            exit 0
            ;;
        *)
            die "unknown option for test: $1"
            ;;
    esac
done

[[ "$FUZZ_SEEDS" =~ ^[0-9]+$ ]] || die "--fuzz expects an integer seed count, got: $FUZZ_SEEDS"
if [[ "$HOST_ONLY" -eq 1 && "$CONTAINER_ALL" -eq 1 ]]; then
    die "--host-only cannot be combined with --container-all"
fi

REPO_DIR="$(require_repo_path "$REPO_ARG")"
HAS_HOST_BUILD=0; [[ -f "$REPO_DIR/tools/build_host.sh" ]] && HAS_HOST_BUILD=1
HAS_RUN_TESTS=0;  [[ -f "$REPO_DIR/tests/run_tests.sh" ]] && HAS_RUN_TESTS=1
HAS_RUN_FUZZ=0;   [[ -f "$REPO_DIR/tests/run_fuzz.sh" ]] && HAS_RUN_FUZZ=1

if [[ "$HAS_RUN_TESTS" -eq 0 && "$HAS_RUN_FUZZ" -eq 0 ]]; then
    die "no tests/run_tests.sh or tests/run_fuzz.sh found in $REPO_DIR; use 'fm1 exec --repo $REPO_DIR -- <your-test-cmd>'"
fi

if [[ "$CONTAINER_ALL" -eq 0 && "$HAS_RUN_TESTS" -eq 1 ]]; then
    info "Running native host test suite in $REPO_DIR..."
    if [[ -d "$FM1_VENV_DIR/bin" ]]; then
        PATH="$FM1_VENV_DIR/bin:$PATH"
    fi
    (
        cd "$REPO_DIR"
        [[ "$HAS_HOST_BUILD" -eq 1 ]] && tools/build_host.sh
        sh tests/run_tests.sh
    )
    if [[ "$HOST_ONLY" -eq 1 || "$HAS_RUN_FUZZ" -eq 0 ]]; then
        [[ "$HAS_RUN_FUZZ" -eq 1 ]] && warn "Skipped tests/run_fuzz.sh (--host-only; macOS sem_init is ENOSYS)"
        info "Host tests passed."
        exit 0
    fi
elif [[ "$HOST_ONLY" -eq 1 ]]; then
    warn "No tests/run_tests.sh found in $REPO_DIR; nothing to run with --host-only"
    exit 0
fi

command -v docker >/dev/null 2>&1 || die "docker CLI not found; install OrbStack or Docker Desktop"
docker info >/dev/null 2>&1 || die "docker daemon not running; start OrbStack or Docker Desktop"
docker image inspect "$FM1_DOCKER_IMAGE" >/dev/null 2>&1 || die "builder image missing ($FM1_DOCKER_IMAGE); run 'fm1 setup'"

if [[ "$CONTAINER_ALL" -eq 1 ]]; then
    info "Running tests + fuzzing (${FUZZ_SEEDS} seeds) in $FM1_DOCKER_IMAGE..."
    docker run --rm --platform linux/amd64 \
        -v "$REPO_DIR:/work" \
        -e FM1_FUZZ_SEEDS="$FUZZ_SEEDS" \
        -w /work \
        "$FM1_DOCKER_IMAGE" \
        bash -c '
            set -euo pipefail
            [[ -f tools/build_host.sh ]] && tools/build_host.sh
            [[ -f tests/run_tests.sh ]] && sh tests/run_tests.sh
            [[ -f tests/run_fuzz.sh ]] && sh tests/run_fuzz.sh "$FM1_FUZZ_SEEDS"
        '
else
    info "Running ASan/UBSan fuzzing (${FUZZ_SEEDS} seeds) in $FM1_DOCKER_IMAGE..."
    docker run --rm --platform linux/amd64 \
        -v "$REPO_DIR:/work" \
        -e FM1_FUZZ_SEEDS="$FUZZ_SEEDS" \
        -w /work \
        "$FM1_DOCKER_IMAGE" \
        bash -c '
            set -euo pipefail
            sh tests/run_fuzz.sh "$FM1_FUZZ_SEEDS"
        '
fi

info "All tests and fuzzing passed."
