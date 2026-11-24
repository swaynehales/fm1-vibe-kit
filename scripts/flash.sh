#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO_ARG=""
FW_ARG=""
DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a path"
            REPO_ARG="$2"
            shift 2
            ;;
        --fw)
            [[ $# -ge 2 ]] || die "--fw requires a .fwsc path"
            FW_ARG="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: fm1 flash [--repo <path>] [--fw <path>] [--dry-run] [--yes]

Options:
  --repo <path>    Path to firmware repository (or set FM1_REPO_DIR)
  --fw <path>      Path to .fwsc package (auto-detected if omitted)
  --dry-run        Validate package and archive symbols without flashing hardware
  --yes, -y        Pass --yes to fm1_install.py
EOF
            exit 0
            ;;
        *)
            die "unknown option for flash: $1"
            ;;
    esac
done

REPO_DIR="$(require_repo_path "$REPO_ARG")"
INSTALLER="$(find_repo_tool "$REPO_DIR" "fm1_install.py" || true)"
[[ -n "$INSTALLER" ]] || die "fm1_install.py not found in $REPO_DIR/{tools,base/tools,bsp/tools,base/bsp/tools}"
[[ -x "$FM1_VENV_DIR/bin/python" ]] || die "local venv missing ($FM1_VENV_DIR); run 'fm1 setup'"

if [[ -n "$FW_ARG" ]]; then
    FW_PATH="$FW_ARG"
else
    rc=0
    FW_PATH="$(find_single_artifact "$REPO_DIR" "fwsc")" || rc=$?
    if [[ "$rc" -eq 1 ]]; then
        die "no *.fwsc artifact found under $REPO_DIR/{app/build,build}; run 'fm1 build' or pass --fw <path>"
    elif [[ "$rc" -ne 0 ]]; then
        exit "$rc"
    fi
fi
[[ -s "$FW_PATH" ]] || die "firmware package missing or empty: $FW_PATH"

FW_DIR="$(dirname "$FW_PATH")"
BUILD_ID=""
if [[ -z "$FW_ARG" && -f "$FW_DIR/build_id.txt" ]]; then
    BUILD_ID="$(tr -d '[:space:]' < "$FW_DIR/build_id.txt")"
fi

if [[ -n "$BUILD_ID" && "$BUILD_ID" =~ ^[0-9A-Za-z._-]+$ ]]; then
    ELF_PATH="$(find_single_artifact "$REPO_DIR" "elf" || true)"
    if [[ -n "$ELF_PATH" ]]; then
        SYM_DIR="$FM1_CACHE_DIR/symbols/$BUILD_ID"
        mkdir -p "$SYM_DIR"
        cp -f "$ELF_PATH" "$SYM_DIR/fw.elf"
        SYM_SRC="${ELF_PATH%.elf}.sym"
        [[ -f "$SYM_SRC" ]] && cp -f "$SYM_SRC" "$SYM_DIR/fw.sym"
        info "Archived symbols for build $BUILD_ID in $SYM_DIR"
    fi
fi

CMD=("$FM1_VENV_DIR/bin/python" "$INSTALLER" "$FW_PATH")
if [[ "$ASSUME_YES" -eq 1 ]]; then
    CMD+=(--yes)
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] package: $FW_PATH ($(wc -c < "$FW_PATH" | tr -d ' ') B)${BUILD_ID:+, build: $BUILD_ID}"
    info "[dry-run] would run: ${CMD[*]}"
    exit 0
fi

info "Flashing $FW_PATH via macOS CoreMIDI..."
exec "${CMD[@]}"
