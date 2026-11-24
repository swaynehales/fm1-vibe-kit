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
        -h|--help)
            echo "Usage: fm1 doctor [--repo <path>]"
            exit 0
            ;;
        *)
            die "unknown option for doctor: $1"
            ;;
    esac
done

FAILURES=0
ok()   { printf '  [ok]   %s\n' "$*"; }
miss() { printf '  [miss] %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
note() { printf '  [info] %s\n' "$*"; }

info "Running read-only preflight checks..."

# 1. Host OS & arch
OS_NAME="$(uname -s)"
ARCH_NAME="$(uname -m)"
if [[ "$OS_NAME" == "Darwin" ]]; then
    ok "macOS ($ARCH_NAME, $(sw_vers -productVersion 2>/dev/null || echo unknown))"
    if [[ "$ARCH_NAME" == "arm64" ]]; then
        if /usr/bin/pgrep oahd >/dev/null 2>&1 || [[ -f /Library/Apple/usr/share/rosetta/rosetta ]]; then
            ok "Rosetta 2 available for linux/amd64 emulation"
        else
            note "Rosetta 2 not detected (OrbStack/Docker Desktop may manage its own emulation)"
        fi
    fi
    if xcode-select -p >/dev/null 2>&1; then
        ok "Xcode Command Line Tools ($(xcode-select -p))"
    else
        miss "Xcode Command Line Tools missing -> run: xcode-select --install"
    fi
else
    note "Host OS is $OS_NAME ($ARCH_NAME); CoreMIDI flashing targets macOS"
fi

# 2. Container & VM runtimes
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        ok "Docker daemon reachable ($(docker version --format '{{.Server.Version}}' 2>/dev/null || echo ok))"
        if docker image inspect "$FM1_DOCKER_IMAGE" >/dev/null 2>&1; then
            ok "Builder image present: $FM1_DOCKER_IMAGE"
        else
            miss "Builder image missing: $FM1_DOCKER_IMAGE -> run: fm1 setup"
        fi
    else
        miss "Docker CLI found, but daemon is not running -> start OrbStack or Docker Desktop"
    fi
else
    miss "Docker CLI missing -> install OrbStack or Docker Desktop"
fi

if command -v tart >/dev/null 2>&1; then
    note "Optional Tart VM CLI available: $(command -v tart)"
fi
if command -v vibe >/dev/null 2>&1; then
    note "Optional Vibe sandbox CLI available: $(command -v vibe)"
fi

# 3. Repo-local Python venv
if [[ -x "$FM1_VENV_DIR/bin/python" ]]; then
    if "$FM1_VENV_DIR/bin/python" -c "import PIL, mido, rtmidi" >/dev/null 2>&1; then
        ok "Local venv ready ($FM1_VENV_DIR)"
        MIDI_PORTS="$("$FM1_VENV_DIR/bin/python" -c "import mido; print(', '.join(mido.get_output_names()) or 'none')" 2>/dev/null || echo "probe-failed")"
        note "MIDI outputs visible: $MIDI_PORTS"
    else
        miss "Local venv missing Pillow/mido/python-rtmidi -> run: fm1 setup"
    fi
else
    miss "Local venv missing ($FM1_VENV_DIR) -> run: fm1 setup"
fi

# 4. Cached JieLi toolchain & AC79 SDK
TC_LINK="$FM1_CACHE_DIR/jieli/toolchain"
TC_STAMP="$FM1_CACHE_DIR/jieli/toolchain.sha256"
if [[ -d "$TC_LINK" && -x "$TC_LINK/common/bin/clang" ]]; then
    if [[ -f "$TC_STAMP" ]] && [[ "$(cat "$TC_STAMP")" == "$JIELI_TOOLCHAIN_SHA256" ]]; then
        ok "JieLi toolchain cached & SHA256 verified ($TC_LINK)"
    elif [[ -f "$TC_STAMP" ]]; then
        miss "JieLi toolchain SHA256 ($(cat "$TC_STAMP")) != pinned ($JIELI_TOOLCHAIN_SHA256) -> run: fm1 setup"
    else
        miss "JieLi toolchain missing SHA256 stamp -> run: fm1 setup"
    fi
else
    miss "JieLi toolchain not cached ($TC_LINK) -> run: fm1 setup"
fi

SDK_DIR="$FM1_CACHE_DIR/fw-AC79_AIoT_SDK"
if [[ -d "$SDK_DIR/.git" ]]; then
    SDK_HEAD="$(git -C "$SDK_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ "$SDK_HEAD" == "$AC79_SDK_COMMIT" ]]; then
        ok "JieLi AC79 SDK cached at pinned commit ($SDK_HEAD)"
    else
        miss "JieLi AC79 SDK HEAD ($SDK_HEAD) != pinned ($AC79_SDK_COMMIT) -> run: fm1 setup"
    fi
else
    miss "JieLi AC79 SDK not cached ($SDK_DIR) -> run: fm1 setup"
fi

# 5. Optional firmware repo check
if RESOLVED_REPO="$(resolve_repo_path "$REPO_ARG" 2>/dev/null)"; then
    if find_repo_tool "$RESOLVED_REPO" "fm1_install.py" >/dev/null 2>&1 || [[ -f "$RESOLVED_REPO/build.sh" ]] || [[ -f "$RESOLVED_REPO/Makefile" ]]; then
        ok "Firmware repo ready: $RESOLVED_REPO"
    else
        miss "Firmware repo missing build.sh/Makefile and fm1_install.py (check submodules): $RESOLVED_REPO -> run: fm1 setup --repo $RESOLVED_REPO"
    fi
elif [[ -n "${REPO_ARG:-${FM1_REPO_DIR:-}}" ]]; then
    miss "Firmware repo directory does not exist: ${REPO_ARG:-${FM1_REPO_DIR:-}}"
else
    note "No --repo / FM1_REPO_DIR specified (pass --repo <path> to validate a firmware checkout)"
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf '\n[fm1] doctor found %d issue(s). Run suggested commands above.\n' "$FAILURES" >&2
    exit 1
fi

printf '\n[fm1] doctor passed: environment is ready.\n'
printf '[fm1] See docs/NEXT-STEPS.md for starter paths, first-build commands, and agent prompts.\n'
