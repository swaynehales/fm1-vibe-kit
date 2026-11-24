#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
if [[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    echo "Usage: fm1 remote [--repo <path>] <fm1_remote.py args...>"
    exit 0
fi

if [[ $# -ge 2 && "$1" == "--repo" ]]; then
    REPO_ARG="$2"
    shift 2
fi

REPO_DIR="$(require_repo_path "$REPO_ARG")"
REMOTE_PY="$(find_repo_tool "$REPO_DIR" "fm1_remote.py" || true)"
[[ -n "$REMOTE_PY" ]] || die "fm1_remote.py not found in $REPO_DIR/{tools,base/tools,bsp/tools,base/bsp/tools}"
[[ -x "$FM1_VENV_DIR/bin/python" ]] || die "local venv missing ($FM1_VENV_DIR); run 'fm1 setup'"

exec "$FM1_VENV_DIR/bin/python" "$REMOTE_PY" "$@"
