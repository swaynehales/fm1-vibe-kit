#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../pins.env
source "$KIT_ROOT/pins.env"

FM1_KIT_HOME="${FM1_KIT_HOME:-$KIT_ROOT}"
FM1_CACHE_DIR="$FM1_KIT_HOME/.cache"
FM1_VENV_DIR="$FM1_KIT_HOME/.venv"

info() { printf '[fm1] %s\n' "$*"; }
warn() { printf '[fm1] WARN: %s\n' "$*" >&2; }
die()  { printf '[fm1] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_file() {
    local path="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    else
        die "neither shasum nor sha256sum is available"
    fi
}

# Resolve target FM-1 firmware repository path: --repo > $FM1_REPO_DIR > single ./workspace/* checkout
resolve_repo_path() {
    local arg_repo="${1:-}"
    local candidate=""
    if [[ -n "$arg_repo" ]]; then
        candidate="$arg_repo"
    elif [[ -n "${FM1_REPO_DIR:-}" ]]; then
        candidate="$FM1_REPO_DIR"
    elif [[ -d "$FM1_KIT_HOME/workspace" ]]; then
        local ws_dirs=() d
        while IFS= read -r d; do
            ws_dirs+=("$d")
        done < <(find "$FM1_KIT_HOME/workspace" -mindepth 1 -maxdepth 1 -type d | sort)
        if [[ ${#ws_dirs[@]} -eq 1 ]]; then
            candidate="${ws_dirs[0]}"
        else
            return 1
        fi
    else
        return 1
    fi
    if [[ ! -d "$candidate" ]]; then
        die "firmware repo directory does not exist: $candidate"
    fi
    (cd "$candidate" && pwd)
}

require_repo_path() {
    local arg_repo="${1:-}"
    local resolved=""
    if ! resolved="$(resolve_repo_path "$arg_repo")"; then
        die "no firmware repo specified; pass --repo <path>, set FM1_REPO_DIR, or run 'fm1 setup --starter felucca-bsp --repo <path>'"
    fi
    printf '%s\n' "$resolved"
}

# Locate a helper script (e.g. fm1_install.py, fm1_remote.py) across felucca-bsp / fm1-base layouts
find_repo_tool() {
    local repo="$1"
    local tool="$2"
    local rel
    for rel in "tools/$tool" "base/tools/$tool" "bsp/tools/$tool" "base/bsp/tools/$tool"; do
        if [[ -f "$repo/$rel" ]]; then
            printf '%s\n' "$repo/$rel"
            return 0
        fi
    done
    return 1
}

# Locate a single built artifact (*.fwsc or *.elf) in standard build directories
find_single_artifact() {
    local repo="$1"
    local ext="$2"
    local matches=()
    local f
    for dir in "$repo/app/build" "$repo/build"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r f; do
            matches+=("$f")
        done < <(find "$dir" -maxdepth 1 -type f -name "*.$ext" | sort)
    done
    if [[ ${#matches[@]} -eq 1 ]]; then
        printf '%s\n' "${matches[0]}"
        return 0
    elif [[ ${#matches[@]} -eq 0 ]]; then
        return 1
    else
        printf '[fm1] ERROR: multiple *.%s artifacts found; pass explicit path flag (%s)\n' "$ext" "${matches[*]}" >&2
        return 2
    fi
}
