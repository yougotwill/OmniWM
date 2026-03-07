#!/usr/bin/env bash
# dev.sh — reliable local build/run flow for Zig + Swift.
#
# Usage:
#   ./dev.sh                    # clean + build Zig + build Swift + run via swift run
#   ./dev.sh --build-only       # clean + build Zig + build Swift (no run)
#   ./dev.sh --app              # clean + package debug unsigned OmniWM.app
#   ./dev.sh --app --run        # clean + package debug unsigned OmniWM.app + open app
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./dev.sh
  ./dev.sh --build-only
  ./dev.sh --app
  ./dev.sh --app --run
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REQUIRED_SYMBOLS=(
    "omni_niri_ctx_apply_txn"
    "omni_niri_ctx_export_delta"
    "omni_border_runtime_create"
    "omni_border_runtime_destroy"
    "omni_border_runtime_apply_config"
    "omni_border_runtime_apply_presentation"
    "omni_border_runtime_submit_snapshot"
    "omni_border_runtime_apply_motion"
    "omni_border_runtime_invalidate_displays"
    "omni_border_runtime_hide"
    "omni_controller_create"
    "omni_controller_destroy"
    "omni_controller_start"
    "omni_controller_stop"
    "omni_controller_submit_hotkey"
    "omni_controller_submit_os_event"
    "omni_controller_apply_settings"
    "omni_controller_tick"
    "omni_controller_query_ui_state"
)

verify_required_symbols() {
    local artifact="$1"
    local label="$2"
    local symbol_names

    symbol_names="$(nm "${artifact}" 2>/dev/null | awk '{ name = $NF; sub(/^_/, "", name); print name }')"
    if [[ -z "${symbol_names}" ]]; then
        echo "error: unable to inspect symbols in ${artifact}" >&2
        exit 1
    fi

    local missing=0
    local symbol
    for symbol in "${REQUIRED_SYMBOLS[@]}"; do
        if ! grep -Fxq "${symbol}" <<< "${symbol_names}"; then
            echo "error: missing required symbol '${symbol}' in ${label} (${artifact})" >&2
            missing=1
        fi
    done

    if [[ "${missing}" -ne 0 ]]; then
        exit 1
    fi

    echo "==> ${label}: required layout and border symbols verified"
}

APP_MODE=false
RUN_FLAG=false
BUILD_ONLY=false

for arg in "$@"; do
    case "${arg}" in
        --app)
            APP_MODE=true
            ;;
        --run)
            RUN_FLAG=true
            ;;
        --build-only)
            BUILD_ONLY=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${APP_MODE}" == "false" && "${RUN_FLAG}" == "true" ]]; then
    echo "--run is only valid with --app (default mode already runs via swift run)." >&2
    usage >&2
    exit 1
fi

if [[ "${APP_MODE}" == "true" && "${BUILD_ONLY}" == "true" ]]; then
    echo "--build-only cannot be combined with --app." >&2
    usage >&2
    exit 1
fi

echo "==> Cleaning SwiftPM and previous artifacts"
rm -rf .build dist/OmniWM.app
swift package clean

if [[ "${APP_MODE}" == "true" ]]; then
    echo "==> Building Zig + Swift and packaging OmniWM.app (debug, unsigned)"
    ./Scripts/package-app.sh debug false

    APP_BIN="dist/OmniWM.app/Contents/MacOS/OmniWM"
    ZIG_LIB=".build/zig/libomni_layout.a"

    if [[ -f "${ZIG_LIB}" ]]; then
        echo "==> Zig archive timestamp:"
        stat -f "%Sm %N" "${ZIG_LIB}"
        verify_required_symbols "${ZIG_LIB}" "Zig archive"
    fi
    if [[ -x "${APP_BIN}" ]]; then
        echo "==> App binary timestamp:"
        stat -f "%Sm %N" "${APP_BIN}"
        verify_required_symbols "${APP_BIN}" "App binary"
    fi

    echo "==> Accessibility reminder:"
    echo "   If hotkeys are inactive, grant Accessibility to OmniWM.app in System Settings."
    echo "   Open directly: open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"

    if [[ "${RUN_FLAG}" == "true" ]]; then
        echo "==> Opening dist/OmniWM.app"
        open dist/OmniWM.app
    else
        echo "==> Built dist/OmniWM.app"
    fi
    exit 0
fi

echo "==> Building Zig static library"
zig build omni-layout --prefix .build

ZIG_LIB=".build/zig/libomni_layout.a"
if [[ -f "${ZIG_LIB}" ]]; then
    verify_required_symbols "${ZIG_LIB}" "Zig archive"
fi

echo "==> Building Swift"
swift build

if [[ "${BUILD_ONLY}" == "true" ]]; then
    echo "==> Build complete (no run)"
else
    echo "==> Running via swift run"
    swift run
fi
