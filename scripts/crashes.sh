#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
ELF_ARG=""
BUILD_ID_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a path"
            REPO_ARG="$2"
            shift 2
            ;;
        --elf)
            [[ $# -ge 2 ]] || die "--elf requires an ELF path"
            ELF_ARG="$2"
            shift 2
            ;;
        --build-id)
            [[ $# -ge 2 ]] || die "--build-id requires a build ID (e.g. 33D943A3)"
            [[ "$2" =~ ^[0-9A-Za-z._-]+$ ]] || die "invalid --build-id format: '$2'"
            BUILD_ID_ARG="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
Usage: fm1 crashes [--repo <path>] [--elf <path>] [--build-id <id>]

Options:
  --repo <path>      Path to firmware repository (or set FM1_REPO_DIR)
  --elf <path>       Explicit firmware ELF path for symbol resolution
  --build-id <id>    Resolve archived ELF for <id> (fails loudly on mismatch)
EOF
            exit 0
            ;;
        *)
            die "unknown option for crashes: $1"
            ;;
    esac
done

REPO_DIR="$(require_repo_path "$REPO_ARG")"
REMOTE_PY="$(find_repo_tool "$REPO_DIR" "fm1_remote.py" || true)"
[[ -n "$REMOTE_PY" ]] || die "fm1_remote.py not found in $REPO_DIR/{tools,base/tools,bsp/tools,base/bsp/tools}"
[[ -x "$FM1_VENV_DIR/bin/python" ]] || die "local venv missing ($FM1_VENV_DIR); run 'fm1 setup'"

ELF_PATH=""
if [[ -n "$ELF_ARG" ]]; then
    [[ -f "$ELF_ARG" ]] || die "specified ELF does not exist: $ELF_ARG"
    ELF_PATH="$ELF_ARG"
elif [[ -n "$BUILD_ID_ARG" ]]; then
    ARCHIVED_ELF="$FM1_CACHE_DIR/symbols/$BUILD_ID_ARG/fw.elf"
    REPO_ELF="$(find_single_artifact "$REPO_DIR" "elf" || true)"
    if [[ -f "$ARCHIVED_ELF" ]]; then
        ELF_PATH="$ARCHIVED_ELF"
    elif [[ -n "$REPO_ELF" && -f "$(dirname "$REPO_ELF")/build_id.txt" ]]; then
        REPO_BUILD="$(tr -d '[:space:]' < "$(dirname "$REPO_ELF")/build_id.txt")"
        if [[ "$REPO_BUILD" == "$BUILD_ID_ARG" ]]; then
            ELF_PATH="$REPO_ELF"
        else
            die "build ID mismatch: requested '$BUILD_ID_ARG', but repo has '$REPO_BUILD' and no archived ELF exists at $ARCHIVED_ELF"
        fi
    else
        die "no archived ELF found for build ID '$BUILD_ID_ARG' at $ARCHIVED_ELF"
    fi
else
    rc=0
    ELF_PATH="$(find_single_artifact "$REPO_DIR" "elf")" || rc=$?
    if [[ "$rc" -eq 1 ]]; then
        die "no *.elf artifact found under $REPO_DIR/{app/build,build} (run 'fm1 build' or pass --elf / --build-id)"
    elif [[ "$rc" -ne 0 ]]; then
        exit "$rc"
    fi
fi

info "Querying FM-1 crash log using ELF: $ELF_PATH"
exec "$FM1_VENV_DIR/bin/python" "$REMOTE_PY" crashes --elf "$ELF_PATH"
