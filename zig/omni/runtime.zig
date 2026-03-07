const std = @import("std");
const abi = @import("abi_types.zig");
const layout_context = @import("layout_context.zig");
pub const OmniNiriRuntime = layout_context.OmniNiriLayoutContext;
fn uuidEqual(lhs: abi.OmniUuid128, rhs: abi.OmniUuid128) bool {
    return std.mem.eql(u8, lhs.bytes[0..], rhs.bytes[0..]);
}
fn runtimeWindowToRenderInput(
    window: abi.OmniNiriRuntimeWindowState,
    fullscreen_window_id: ?abi.OmniUuid128,
) abi.OmniNiriWindowInput {
    const is_fixed = window.height_kind == abi.OMNI_NIRI_HEIGHT_KIND_FIXED;
    const fixed_value = @max(16.0, window.height_value);
    const weight = if (is_fixed) 1.0 else @max(0.1, window.height_value);
    const is_fullscreen = if (fullscreen_window_id) |fullscreen_id|
        uuidEqual(fullscreen_id, window.window_id)
    else
        false;
    return .{
        .weight = weight,
        .min_constraint = if (is_fixed) fixed_value else 16.0,
        .max_constraint = if (is_fixed) fixed_value else 0.0,
        .has_max_constraint = if (is_fixed) 1 else 0,
        .is_constraint_fixed = if (is_fixed) 1 else 0,
        .has_fixed_value = if (is_fixed) 1 else 0,
        .fixed_value = if (is_fixed) fixed_value else 0.0,
        .sizing_mode = if (is_fullscreen)
            abi.OMNI_NIRI_SIZING_FULLSCREEN
        else
            abi.OMNI_NIRI_SIZING_NORMAL,
        .render_offset_x = 0.0,
        .render_offset_y = 0.0,
    };
}
pub fn omni_niri_runtime_create_impl() [*c]OmniNiriRuntime {
    return @ptrCast(layout_context.omni_niri_layout_context_create_impl());
}
pub fn omni_niri_runtime_destroy_impl(runtime: [*c]OmniNiriRuntime) void {
    layout_context.omni_niri_layout_context_destroy_impl(@ptrCast(runtime));
}
pub fn omni_niri_runtime_seed_impl(
    runtime: [*c]OmniNiriRuntime,
    request: [*c]const abi.OmniNiriRuntimeSeedRequest,
) i32 {
    if (request == null) return abi.OMNI_ERR_INVALID_ARGS;
    return layout_context.omni_niri_ctx_seed_runtime_state_impl(
        @ptrCast(runtime),
        request[0].columns,
        request[0].column_count,
        request[0].windows,
        request[0].window_count,
    );
}
pub fn omni_niri_runtime_apply_command_impl(
    source_runtime: [*c]OmniNiriRuntime,
    target_runtime: [*c]OmniNiriRuntime,
    request: [*c]const abi.OmniNiriRuntimeCommandRequest,
    out_result: [*c]abi.OmniNiriRuntimeCommandResult,
) i32 {
    if (request == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (source_runtime == null) {
        var invalid_txn = std.mem.zeroes(abi.OmniNiriTxnResult);
        invalid_txn.kind = request[0].txn.kind;
        invalid_txn.error_code = abi.OMNI_ERR_INVALID_ARGS;
        out_result[0] = .{ .txn = invalid_txn };
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    var txn_result = std.mem.zeroes(abi.OmniNiriTxnResult);
    txn_result.kind = request[0].txn.kind;
    const rc = layout_context.omni_niri_ctx_apply_txn_impl(
        @ptrCast(source_runtime),
        @ptrCast(target_runtime),
        &request[0].txn,
        &txn_result,
    );
    if (rc != abi.OMNI_OK) {
        txn_result.error_code = rc;
    } else if (txn_result.structural_animation_active != 0) {
        layout_context.startRuntimeAnimation(
            @ptrCast(&source_runtime[0]),
            layout_context.RUNTIME_ANIMATION_MUTATION,
            request[0].sample_time,
            layout_context.NIRI_MUTATION_ANIMATION_DURATION,
        );
    }
    out_result[0] = .{ .txn = txn_result };
    return rc;
}
pub fn omni_niri_runtime_render_from_state_impl(
    runtime: [*c]OmniNiriRuntime,
    layout: [*c]layout_context.OmniNiriLayoutContext,
    request: [*c]const abi.OmniNiriRuntimeRenderFromStateRequest,
    out_output: [*c]abi.OmniNiriRuntimeRenderOutput,
) i32 {
    if (runtime == null or request == null or out_output == null) return abi.OMNI_ERR_INVALID_ARGS;
    const runtime_ctx: *OmniNiriRuntime = @ptrCast(&runtime[0]);
    const render_ctx: [*c]layout_context.OmniNiriLayoutContext = if (layout != null) layout else @ptrCast(runtime);
    const runtime_column_count = runtime_ctx.runtime_column_count;
    const runtime_window_count = runtime_ctx.runtime_window_count;
    if (runtime_column_count > abi.MAX_WINDOWS or runtime_window_count > abi.MAX_WINDOWS) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    if (request[0].expected_column_count != runtime_column_count or
        request[0].expected_window_count != runtime_window_count)
    {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    if (out_output[0].window_count != runtime_window_count or
        out_output[0].column_count != runtime_column_count)
    {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    if (runtime_window_count > 0 and out_output[0].windows == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (runtime_column_count > 0 and out_output[0].columns == null) return abi.OMNI_ERR_INVALID_ARGS;
    var synthesized_columns: [abi.MAX_WINDOWS]abi.OmniNiriColumnInput = undefined;
    var derived_spans: [abi.MAX_WINDOWS]f64 = undefined;
    var synthesized_windows: [abi.MAX_WINDOWS]abi.OmniNiriWindowInput = undefined;
    const spans_rc = layout_context.deriveRuntimeViewportSpans(
        runtime_ctx,
        request[0].primary_gap,
        request[0].viewport_span,
        &derived_spans,
    );
    if (spans_rc != abi.OMNI_OK) return spans_rc;
    const fullscreen_window_id: ?abi.OmniUuid128 = if (request[0].has_fullscreen_window_id != 0)
        request[0].fullscreen_window_id
    else
        null;
    const view_start = layout_context.runtimeViewportViewStart(
        runtime_ctx,
        request[0].sample_time,
        &derived_spans,
        runtime_column_count,
        request[0].primary_gap,
    );
    for (0..runtime_column_count) |column_idx| {
        const runtime_column = runtime_ctx.runtime_columns[column_idx];
        if (runtime_column.window_start > runtime_window_count or
            runtime_column.window_count > runtime_window_count - runtime_column.window_start)
        {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        const span = derived_spans[column_idx];
        synthesized_columns[column_idx] = .{
            .span = span,
            .render_offset_x = 0.0,
            .render_offset_y = 0.0,
            .is_tabbed = runtime_column.is_tabbed,
            .tab_indicator_width = 0.0,
            .window_start = runtime_column.window_start,
            .window_count = runtime_column.window_count,
        };
    }
    for (0..runtime_window_count) |window_idx| {
        const runtime_window = runtime_ctx.runtime_windows[window_idx];
        if (runtime_window.height_kind != abi.OMNI_NIRI_HEIGHT_KIND_AUTO and
            runtime_window.height_kind != abi.OMNI_NIRI_HEIGHT_KIND_FIXED)
        {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        synthesized_windows[window_idx] = runtimeWindowToRenderInput(
            runtime_window,
            fullscreen_window_id,
        );
    }
    out_output[0].animation_active = 0;
    const rc = layout_context.omni_niri_layout_pass_v3_impl(
        render_ctx,
        if (runtime_column_count > 0) @ptrCast(&synthesized_columns[0]) else null,
        runtime_column_count,
        if (runtime_window_count > 0) @ptrCast(&synthesized_windows[0]) else null,
        runtime_window_count,
        request[0].working_x,
        request[0].working_y,
        request[0].working_width,
        request[0].working_height,
        request[0].view_x,
        request[0].view_y,
        request[0].view_width,
        request[0].view_height,
        request[0].fullscreen_x,
        request[0].fullscreen_y,
        request[0].fullscreen_width,
        request[0].fullscreen_height,
        request[0].primary_gap,
        request[0].secondary_gap,
        view_start,
        request[0].viewport_span,
        request[0].workspace_offset,
        request[0].scale,
        request[0].orientation,
        out_output[0].windows,
        out_output[0].window_count,
        out_output[0].columns,
        out_output[0].column_count,
    );
    if (rc != abi.OMNI_OK) return rc;
    for (0..runtime_window_count) |window_idx| {
        out_output[0].windows[window_idx].window_id = runtime_ctx.runtime_windows[window_idx].window_id;
    }
    out_output[0].animation_active = layout_context.applyRuntimeAnimationToOutputs(
        runtime_ctx,
        request[0].sample_time,
        request[0].orientation,
        request[0].scale,
        out_output[0].windows,
        runtime_window_count,
    );
    return abi.OMNI_OK;
}
pub fn omni_niri_runtime_snapshot_impl(
    runtime: [*c]const OmniNiriRuntime,
    out_export: [*c]abi.OmniNiriRuntimeStateExport,
) i32 {
    return layout_context.omni_niri_ctx_export_runtime_state_impl(
        @ptrCast(runtime),
        out_export,
    );
}
pub fn omni_niri_runtime_start_workspace_switch_animation_impl(
    runtime: [*c]OmniNiriRuntime,
    sample_time: f64,
) i32 {
    return layout_context.omni_niri_ctx_start_workspace_switch_animation_impl(
        @ptrCast(runtime),
        sample_time,
    );
}
pub fn omni_niri_runtime_start_mutation_animation_impl(
    runtime: [*c]OmniNiriRuntime,
    sample_time: f64,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    layout_context.startRuntimeAnimation(
        @ptrCast(&runtime[0]),
        layout_context.RUNTIME_ANIMATION_MUTATION,
        sample_time,
        layout_context.NIRI_MUTATION_ANIMATION_DURATION,
    );
    return abi.OMNI_OK;
}
pub fn omni_niri_runtime_cancel_animation_impl(runtime: [*c]OmniNiriRuntime) i32 {
    return layout_context.omni_niri_ctx_cancel_animation_impl(@ptrCast(runtime));
}
pub fn omni_niri_runtime_animation_active_impl(
    runtime: [*c]OmniNiriRuntime,
    sample_time: f64,
    out_active: [*c]u8,
) i32 {
    return layout_context.omni_niri_ctx_animation_active_impl(
        @ptrCast(runtime),
        sample_time,
        out_active,
    );
}
pub fn omni_niri_runtime_viewport_status_impl(
    runtime: [*c]OmniNiriRuntime,
    sample_time: f64,
    out_status: [*c]abi.OmniNiriRuntimeViewportStatus,
) i32 {
    return layout_context.omni_niri_ctx_viewport_status_impl(
        @ptrCast(runtime),
        sample_time,
        out_status,
    );
}
pub fn omni_niri_runtime_viewport_begin_gesture_impl(
    runtime: [*c]OmniNiriRuntime,
    sample_time: f64,
    is_trackpad: u8,
) i32 {
    return layout_context.omni_niri_ctx_viewport_begin_gesture_impl(
        @ptrCast(runtime),
        sample_time,
        is_trackpad,
    );
}
pub fn omni_niri_runtime_viewport_update_gesture_impl(
    runtime: [*c]OmniNiriRuntime,
    delta_pixels: f64,
    timestamp: f64,
    gap: f64,
    viewport_span: f64,
    out_result: [*c]abi.OmniViewportGestureUpdateResult,
) i32 {
    return layout_context.omni_niri_ctx_viewport_update_gesture_impl(
        @ptrCast(runtime),
        delta_pixels,
        timestamp,
        gap,
        viewport_span,
        out_result,
    );
}
pub fn omni_niri_runtime_viewport_end_gesture_impl(
    runtime: [*c]OmniNiriRuntime,
    gap: f64,
    viewport_span: f64,
    center_mode: u8,
    always_center_single_column: u8,
    sample_time: f64,
    display_refresh_rate: f64,
    reduce_motion: u8,
    out_result: [*c]abi.OmniViewportGestureEndResult,
) i32 {
    return layout_context.omni_niri_ctx_viewport_end_gesture_impl(
        @ptrCast(runtime),
        gap,
        viewport_span,
        center_mode,
        always_center_single_column,
        sample_time,
        display_refresh_rate,
        reduce_motion,
        out_result,
    );
}
pub fn omni_niri_runtime_viewport_transition_to_column_impl(
    runtime: [*c]OmniNiriRuntime,
    requested_index: usize,
    gap: f64,
    viewport_span: f64,
    center_mode: u8,
    always_center_single_column: u8,
    animate: u8,
    scale: f64,
    sample_time: f64,
    display_refresh_rate: f64,
    reduce_motion: u8,
    out_result: [*c]abi.OmniViewportTransitionResult,
) i32 {
    return layout_context.omni_niri_ctx_viewport_transition_to_column_impl(
        @ptrCast(runtime),
        requested_index,
        gap,
        viewport_span,
        center_mode,
        always_center_single_column,
        animate,
        scale,
        sample_time,
        display_refresh_rate,
        reduce_motion,
        out_result,
    );
}
pub fn omni_niri_runtime_viewport_set_offset_impl(
    runtime: [*c]OmniNiriRuntime,
    offset: f64,
) i32 {
    return layout_context.omni_niri_ctx_viewport_set_offset_impl(
        @ptrCast(runtime),
        offset,
    );
}
pub fn omni_niri_runtime_viewport_cancel_impl(
    runtime: [*c]OmniNiriRuntime,
    sample_time: f64,
) i32 {
    return layout_context.omni_niri_ctx_viewport_cancel_impl(
        @ptrCast(runtime),
        sample_time,
    );
}
