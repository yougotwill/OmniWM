#!/usr/bin/env bash
# build-zig.sh — compatibility wrapper around `zig build omni-layout`
set -euo pipefail

OUT_LIB=".build/zig/libomni_layout.a"
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
    "omni_input_runtime_create"
    "omni_input_runtime_destroy"
    "omni_input_runtime_start"
    "omni_input_runtime_stop"
    "omni_input_runtime_set_bindings"
    "omni_input_runtime_set_options"
    "omni_input_runtime_submit_event"
    "omni_input_runtime_query_registration_failures"
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

    echo "Verified ${label} exports required runtime symbols."
}

zig build omni-layout --prefix .build
verify_required_symbols "${OUT_LIB}" "Zig archive"

if command -v lipo >/dev/null 2>&1; then
    lipo -info "${OUT_LIB}"
fi

echo "✓ ${OUT_LIB}"
