#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REMOVE_IMAGE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            REMOVE_IMAGE=1
            shift
            ;;
        -h|--help)
            echo "Usage: fm1 clean [--all]"
            exit 0
            ;;
        *)
            die "unknown option for clean: $1"
            ;;
    esac
done

RESOLVED_KIT_HOME="$(cd "$FM1_KIT_HOME" 2>/dev/null && pwd || printf '%s' "$FM1_KIT_HOME")"
RESOLVED_HOME="$(cd "$HOME" 2>/dev/null && pwd || printf '%s' "$HOME")"
if [[ -z "$RESOLVED_KIT_HOME" || "$RESOLVED_KIT_HOME" == "/" || "$RESOLVED_KIT_HOME" == "$RESOLVED_HOME" ]]; then
    die "refusing to clean unsafe FM1_KIT_HOME='$FM1_KIT_HOME' (must not be empty, '/', or '\$HOME')"
fi

info "Removing $FM1_CACHE_DIR and $FM1_VENV_DIR..."
rm -rf "$FM1_CACHE_DIR" "$FM1_VENV_DIR"

if [[ "$REMOVE_IMAGE" -eq 1 ]] && command -v docker >/dev/null 2>&1; then
    if docker image inspect "$FM1_DOCKER_IMAGE" >/dev/null 2>&1; then
        info "Removing local Docker image $FM1_DOCKER_IMAGE..."
        docker rmi "$FM1_DOCKER_IMAGE" >/dev/null
    fi
fi

info "Clean complete."
