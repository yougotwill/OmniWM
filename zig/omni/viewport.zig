const std = @import("std");
const abi = @import("abi_types.zig");
const geometry = @import("geometry.zig");
const gesture_history_limit_seconds: f64 = 0.150;
const gesture_deceleration_rate: f64 = 0.997;
const gesture_working_area_movement: f64 = 1200.0;
const tracker_minimum_velocity_window: f64 = 0.001;
const tracker_velocity_zero_threshold: f64 = 0.001;
fn parseCenterMode(mode: u8) ?u8 {
    return switch (mode) {
        abi.OMNI_CENTER_NEVER, abi.OMNI_CENTER_ALWAYS, abi.OMNI_CENTER_ON_OVERFLOW => mode,
        else => null,
    };
}
fn validateFromIndex(from_container_index: i64, span_count: usize) i32 {
    if (from_container_index < -1) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (from_container_index >= 0 and @as(usize, @intCast(from_container_index)) >= span_count) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    return abi.OMNI_OK;
}
fn containerPositionFromSpans(spans: [*c]const f64, span_count: usize, index: usize, gap: f64) f64 {
    _ = span_count;
    var pos: f64 = 0.0;
    var i: usize = 0;
    while (i < index) : (i += 1) {
        pos += spans[i] + gap;
    }
    return pos;
}
fn totalSpanFromSpans(spans: [*c]const f64, span_count: usize, gap: f64) f64 {
    if (span_count == 0) return 0.0;
    var total: f64 = 0.0;
    for (0..span_count) |i| {
        total += spans[i];
    }
    total += @as(f64, @floatFromInt(span_count - 1)) * gap;
    return total;
}
fn computeCenteredOffsetFromSpans(
    spans: [*c]const f64,
    span_count: usize,
    container_index: usize,
    gap: f64,
    viewport_span: f64,
) f64 {
    if (span_count == 0 or container_index >= span_count) return 0.0;
    const total = totalSpanFromSpans(spans, span_count, gap);
    const pos = containerPositionFromSpans(spans, span_count, container_index, gap);
    if (total <= viewport_span) {
        return -pos - (viewport_span - total) / 2.0;
    }
    const container_size = spans[container_index];
    const centered_offset = -(viewport_span - container_size) / 2.0;
    const max_offset: f64 = 0.0;
    const min_offset = viewport_span - total;
    return geometry.clampFloat(centered_offset, min_offset, max_offset);
}
fn computeFitOffset(
    current_view_pos: f64,
    view_span: f64,
    target_pos: f64,
    target_span: f64,
    gaps: f64,
) f64 {
    if (view_span <= target_span) {
        return 0.0;
    }
    const padding = geometry.clampFloat((view_span - target_span) / 2.0, 0.0, gaps);
    const new_pos = target_pos - padding;
    const new_end_pos = target_pos + target_span + padding;
    if (current_view_pos <= new_pos and new_end_pos <= current_view_pos + view_span) {
        return -(target_pos - current_view_pos);
    }
    const dist_to_start = @abs(current_view_pos - new_pos);
    const dist_to_end = @abs((current_view_pos + view_span) - new_end_pos);
    if (dist_to_start <= dist_to_end) {
        return -padding;
    }
    return -(view_span - padding - target_span);
}
fn considerSnapPoint(
    candidate_view_pos: f64,
    candidate_col_idx: usize,
    projected_view_pos: f64,
    min_view_pos: f64,
    max_view_pos: f64,
    best_is_set: *bool,
    best_view_pos: *f64,
    best_col_idx: *usize,
    best_distance: *f64,
) void {
    const clamped = @min(@max(candidate_view_pos, min_view_pos), max_view_pos);
    const distance = @abs(clamped - projected_view_pos);
    if (!best_is_set.* or distance < best_distance.*) {
        best_is_set.* = true;
        best_view_pos.* = clamped;
        best_col_idx.* = candidate_col_idx;
        best_distance.* = distance;
    }
}
fn computeVisibleOffsetInternal(
    spans: [*c]const f64,
    span_count: usize,
    container_index: usize,
    gap: f64,
    viewport_span: f64,
    current_view_start: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    out_target_offset: [*c]f64,
) i32 {
    if (span_count == 0 or container_index >= span_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    const from_rc = validateFromIndex(from_container_index, span_count);
    if (from_rc != abi.OMNI_OK) return from_rc;
    const parsed_mode = parseCenterMode(center_mode) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const effective_center_mode = if (span_count == 1 and always_center_single_column != 0)
        abi.OMNI_CENTER_ALWAYS
    else
        parsed_mode;
    const target_pos = containerPositionFromSpans(spans, span_count, container_index, gap);
    const target_size = spans[container_index];
    var target_offset: f64 = 0.0;
    switch (effective_center_mode) {
        abi.OMNI_CENTER_ALWAYS => {
            target_offset = computeCenteredOffsetFromSpans(
                spans,
                span_count,
                container_index,
                gap,
                viewport_span,
            );
        },
        abi.OMNI_CENTER_ON_OVERFLOW => {
            if (target_size > viewport_span) {
                target_offset = computeCenteredOffsetFromSpans(
                    spans,
                    span_count,
                    container_index,
                    gap,
                    viewport_span,
                );
            } else if (from_container_index != -1 and from_container_index != @as(i64, @intCast(container_index))) {
                const source_idx = if (from_container_index > @as(i64, @intCast(container_index)))
                    @min(container_index + 1, span_count - 1)
                else
                    if (container_index > 0) container_index - 1 else 0;
                const source_pos = containerPositionFromSpans(spans, span_count, source_idx, gap);
                const source_size = spans[source_idx];
                const total_span_needed: f64 = if (source_pos < target_pos)
                    target_pos - source_pos + target_size + gap * 2.0
                else
                    source_pos - target_pos + source_size + gap * 2.0;
                if (total_span_needed <= viewport_span) {
                    target_offset = computeFitOffset(
                        current_view_start,
                        viewport_span,
                        target_pos,
                        target_size,
                        gap,
                    );
                } else {
                    target_offset = computeCenteredOffsetFromSpans(
                        spans,
                        span_count,
                        container_index,
                        gap,
                        viewport_span,
                    );
                }
            } else {
                target_offset = computeFitOffset(
                    current_view_start,
                    viewport_span,
                    target_pos,
                    target_size,
                    gap,
                );
            }
        },
        abi.OMNI_CENTER_NEVER => {
            target_offset = computeFitOffset(
                current_view_start,
                viewport_span,
                target_pos,
                target_size,
                gap,
            );
        },
        else => return abi.OMNI_ERR_INVALID_ARGS,
    }
    const total = totalSpanFromSpans(spans, span_count, gap);
    const max_offset: f64 = 0.0;
    const min_offset = viewport_span - total;
    if (min_offset < max_offset) {
        target_offset = geometry.clampFloat(target_offset, min_offset, max_offset);
    }
    out_target_offset[0] = target_offset;
    return abi.OMNI_OK;
}
fn findSnapTargetInternal(
    spans: [*c]const f64,
    span_count: usize,
    gap: f64,
    viewport_span: f64,
    projected_view_pos: f64,
    current_view_pos: f64,
    center_mode: u8,
    always_center_single_column: u8,
    out_result: [*c]abi.OmniSnapResult,
) i32 {
    if (span_count == 0) {
        out_result[0] = .{ .view_pos = 0.0, .column_index = 0 };
        return abi.OMNI_OK;
    }
    if (spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    const parsed_mode = parseCenterMode(center_mode) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const effective_center_mode = if (span_count == 1 and always_center_single_column != 0)
        abi.OMNI_CENTER_ALWAYS
    else
        parsed_mode;
    const vw = viewport_span;
    const gaps = gap;
    const total_w = totalSpanFromSpans(spans, span_count, gap);
    const max_view_pos: f64 = 0.0;
    const min_view_pos = vw - total_w;
    var best_is_set = false;
    var best_view_pos: f64 = 0.0;
    var best_col_idx: usize = 0;
    var best_distance: f64 = 0.0;
    if (effective_center_mode == abi.OMNI_CENTER_ALWAYS) {
        for (0..span_count) |idx| {
            const col_x = containerPositionFromSpans(spans, span_count, idx, gap);
            const offset = computeCenteredOffsetFromSpans(spans, span_count, idx, gap, viewport_span);
            const snap_view_pos = col_x + offset;
            considerSnapPoint(
                snap_view_pos,
                idx,
                projected_view_pos,
                min_view_pos,
                max_view_pos,
                &best_is_set,
                &best_view_pos,
                &best_col_idx,
                &best_distance,
            );
        }
    } else {
        var col_x: f64 = 0.0;
        for (0..span_count) |idx| {
            const col_w = spans[idx];
            const padding = geometry.clampFloat((vw - col_w) / 2.0, 0.0, gaps);
            const left_snap = col_x - padding;
            const right_snap = col_x + col_w + padding - vw;
            considerSnapPoint(
                left_snap,
                idx,
                projected_view_pos,
                min_view_pos,
                max_view_pos,
                &best_is_set,
                &best_view_pos,
                &best_col_idx,
                &best_distance,
            );
            if (right_snap != left_snap) {
                considerSnapPoint(
                    right_snap,
                    idx,
                    projected_view_pos,
                    min_view_pos,
                    max_view_pos,
                    &best_is_set,
                    &best_view_pos,
                    &best_col_idx,
                    &best_distance,
                );
            }
            col_x += col_w + gaps;
        }
    }
    if (!best_is_set) {
        out_result[0] = .{ .view_pos = 0.0, .column_index = 0 };
        return abi.OMNI_OK;
    }
    var new_col_idx = best_col_idx;
    if (effective_center_mode != abi.OMNI_CENTER_ALWAYS) {
        const scrolling_right = projected_view_pos >= current_view_pos;
        if (scrolling_right) {
            var idx = new_col_idx + 1;
            while (idx < span_count) : (idx += 1) {
                const col_x = containerPositionFromSpans(spans, span_count, idx, gap);
                const col_w = spans[idx];
                const padding = geometry.clampFloat((vw - col_w) / 2.0, 0.0, gaps);
                if (best_view_pos + vw >= col_x + col_w + padding) {
                    new_col_idx = idx;
                } else {
                    break;
                }
            }
        } else {
            var idx_i: isize = @intCast(new_col_idx);
            while (idx_i > 0) {
                idx_i -= 1;
                const idx: usize = @intCast(idx_i);
                const col_x = containerPositionFromSpans(spans, span_count, idx, gap);
                const col_w = spans[idx];
                const padding = geometry.clampFloat((vw - col_w) / 2.0, 0.0, gaps);
                if (col_x - padding >= best_view_pos) {
                    new_col_idx = idx;
                } else {
                    break;
                }
            }
        }
    }
    out_result[0] = .{ .view_pos = best_view_pos, .column_index = new_col_idx };
    return abi.OMNI_OK;
}
fn gestureHistoryPhysicalIndex(state: *const abi.OmniViewportGestureState, relative_index: usize) usize {
    return (state.history_head + relative_index) % abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP;
}
fn trimGestureHistory(state: *abi.OmniViewportGestureState, current_time: f64) void {
    const cutoff = current_time - gesture_history_limit_seconds;
    while (state.history_count > 0) {
        const idx = state.history_head;
        if (state.history_timestamps[idx] >= cutoff) break;
        state.history_head = (state.history_head + 1) % abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP;
        state.history_count -= 1;
    }
}
fn pushGestureEvent(state: *abi.OmniViewportGestureState, delta: f64, timestamp: f64) void {
    state.tracker_position += delta;
    const write_index: usize = if (state.history_count < abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP) blk: {
        const idx = (state.history_head + state.history_count) % abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP;
        state.history_count += 1;
        break :blk idx;
    } else blk: {
        const idx = state.history_head;
        state.history_head = (state.history_head + 1) % abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP;
        break :blk idx;
    };
    state.history_deltas[write_index] = delta;
    state.history_timestamps[write_index] = timestamp;
    trimGestureHistory(state, timestamp);
}
fn trackerVelocity(state: *const abi.OmniViewportGestureState) f64 {
    if (state.history_count < 2) return 0.0;
    const first_index = state.history_head;
    const last_index = gestureHistoryPhysicalIndex(state, state.history_count - 1);
    const first_time = state.history_timestamps[first_index];
    const last_time = state.history_timestamps[last_index];
    const total_time = last_time - first_time;
    if (total_time <= tracker_minimum_velocity_window) return 0.0;
    var total_delta: f64 = 0.0;
    for (0..state.history_count) |idx| {
        total_delta += state.history_deltas[gestureHistoryPhysicalIndex(state, idx)];
    }
    return total_delta / total_time;
}
fn trackerProjectedEndPosition(state: *const abi.OmniViewportGestureState) f64 {
    const v = trackerVelocity(state);
    if (@abs(v) <= tracker_velocity_zero_threshold) return state.tracker_position;
    const coeff = 1000.0 * @log(gesture_deceleration_rate);
    return state.tracker_position - v / coeff;
}
pub fn omni_viewport_compute_visible_offset_impl(
    spans: [*c]const f64,
    span_count: usize,
    container_index: usize,
    gap: f64,
    viewport_span: f64,
    current_view_start: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    out_target_offset: [*c]f64,
) i32 {
    if (out_target_offset == null) return abi.OMNI_ERR_INVALID_ARGS;
    return computeVisibleOffsetInternal(
        spans,
        span_count,
        container_index,
        gap,
        viewport_span,
        current_view_start,
        center_mode,
        always_center_single_column,
        from_container_index,
        out_target_offset,
    );
}
pub fn omni_viewport_find_snap_target_impl(
    spans: [*c]const f64,
    span_count: usize,
    gap: f64,
    viewport_span: f64,
    projected_view_pos: f64,
    current_view_pos: f64,
    center_mode: u8,
    always_center_single_column: u8,
    out_result: [*c]abi.OmniSnapResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    return findSnapTargetInternal(
        spans,
        span_count,
        gap,
        viewport_span,
        projected_view_pos,
        current_view_pos,
        center_mode,
        always_center_single_column,
        out_result,
    );
}
pub fn omni_viewport_transition_to_column_impl(
    spans: [*c]const f64,
    span_count: usize,
    current_active_index: usize,
    requested_index: usize,
    gap: f64,
    viewport_span: f64,
    current_target_offset: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    scale: f64,
    out_result: [*c]abi.OmniViewportTransitionResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count == 0) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (current_active_index >= span_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (!(scale > 0)) return abi.OMNI_ERR_INVALID_ARGS;
    const clamped_index = @min(requested_index, span_count - 1);
    const old_active_x = containerPositionFromSpans(spans, span_count, current_active_index, gap);
    const new_active_x = containerPositionFromSpans(spans, span_count, clamped_index, gap);
    const offset_delta = old_active_x - new_active_x;
    const adjusted_target_offset = current_target_offset + offset_delta;
    var target_offset: f64 = 0.0;
    const rc = computeVisibleOffsetInternal(
        spans,
        span_count,
        clamped_index,
        gap,
        viewport_span,
        new_active_x + adjusted_target_offset,
        center_mode,
        always_center_single_column,
        from_container_index,
        &target_offset,
    );
    if (rc != abi.OMNI_OK) return rc;
    const snap_delta = target_offset - adjusted_target_offset;
    const pixel = 1.0 / scale;
    out_result[0] = .{
        .resolved_column_index = clamped_index,
        .offset_delta = offset_delta,
        .adjusted_target_offset = adjusted_target_offset,
        .target_offset = target_offset,
        .snap_delta = snap_delta,
        .snap_to_target_immediately = if (@abs(snap_delta) < pixel) 1 else 0,
    };
    return abi.OMNI_OK;
}
pub fn omni_viewport_ensure_visible_impl(
    spans: [*c]const f64,
    span_count: usize,
    active_container_index: usize,
    target_container_index: usize,
    gap: f64,
    viewport_span: f64,
    current_offset: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    epsilon: f64,
    out_result: [*c]abi.OmniViewportEnsureVisibleResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count == 0) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (active_container_index >= span_count or target_container_index >= span_count) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    var target_offset: f64 = 0.0;
    const active_pos = containerPositionFromSpans(spans, span_count, active_container_index, gap);
    const rc = computeVisibleOffsetInternal(
        spans,
        span_count,
        target_container_index,
        gap,
        viewport_span,
        active_pos + current_offset,
        center_mode,
        always_center_single_column,
        from_container_index,
        &target_offset,
    );
    if (rc != abi.OMNI_OK) return rc;
    const offset_delta = target_offset - current_offset;
    const threshold = @abs(epsilon);
    out_result[0] = .{
        .target_offset = target_offset,
        .offset_delta = offset_delta,
        .is_noop = if (@abs(offset_delta) < threshold) 1 else 0,
    };
    return abi.OMNI_OK;
}
pub fn omni_viewport_scroll_step_impl(
    spans: [*c]const f64,
    span_count: usize,
    delta_pixels: f64,
    viewport_span: f64,
    gap: f64,
    current_offset: f64,
    selection_progress: f64,
    change_selection: u8,
    out_result: [*c]abi.OmniViewportScrollResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count > 0 and spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_result[0] = .{
        .applied = 0,
        .new_offset = current_offset,
        .selection_progress = selection_progress,
        .has_selection_steps = 0,
        .selection_steps = 0,
    };
    if (@abs(delta_pixels) <= std.math.floatEps(f64)) return abi.OMNI_OK;
    if (span_count == 0) return abi.OMNI_OK;
    const total_w = totalSpanFromSpans(spans, span_count, gap);
    if (total_w <= 0.0) return abi.OMNI_OK;
    var new_offset = current_offset + delta_pixels;
    const max_offset: f64 = 0.0;
    const min_offset = viewport_span - total_w;
    if (min_offset < max_offset) {
        new_offset = geometry.clampFloat(new_offset, min_offset, max_offset);
    } else {
        new_offset = 0.0;
    }
    out_result[0].applied = 1;
    out_result[0].new_offset = new_offset;
    if (change_selection != 0) {
        const avg_column_width = total_w / @as(f64, @floatFromInt(span_count));
        if (avg_column_width > 0) {
            var next_progress = selection_progress + delta_pixels;
            const steps: i64 = @intFromFloat(@trunc(next_progress / avg_column_width));
            if (steps != 0) {
                next_progress -= @as(f64, @floatFromInt(steps)) * avg_column_width;
                out_result[0].has_selection_steps = 1;
                out_result[0].selection_steps = steps;
            }
            out_result[0].selection_progress = next_progress;
        }
    }
    return abi.OMNI_OK;
}
pub fn omni_viewport_gesture_begin_impl(
    current_view_offset: f64,
    is_trackpad: u8,
    out_state: [*c]abi.OmniViewportGestureState,
) i32 {
    if (out_state == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_state[0] = .{
        .is_trackpad = if (is_trackpad != 0) 1 else 0,
        .history_count = 0,
        .history_head = 0,
        .tracker_position = 0.0,
        .current_view_offset = current_view_offset,
        .stationary_view_offset = current_view_offset,
        .delta_from_tracker = current_view_offset,
        .history_deltas = [_]f64{0.0} ** abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP,
        .history_timestamps = [_]f64{0.0} ** abi.OMNI_VIEWPORT_GESTURE_HISTORY_CAP,
    };
    return abi.OMNI_OK;
}
pub fn omni_viewport_gesture_velocity_impl(
    gesture_state: [*c]const abi.OmniViewportGestureState,
    out_velocity: [*c]f64,
) i32 {
    if (gesture_state == null or out_velocity == null) return abi.OMNI_ERR_INVALID_ARGS;
    const state = gesture_state[0];
    out_velocity[0] = trackerVelocity(&state);
    return abi.OMNI_OK;
}
pub fn omni_viewport_gesture_update_impl(
    gesture_state: [*c]abi.OmniViewportGestureState,
    spans: [*c]const f64,
    span_count: usize,
    active_container_index: usize,
    delta_pixels: f64,
    timestamp: f64,
    gap: f64,
    viewport_span: f64,
    selection_progress: f64,
    out_result: [*c]abi.OmniViewportGestureUpdateResult,
) i32 {
    if (gesture_state == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count > 0 and spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count > 0 and active_container_index >= span_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    var state: *abi.OmniViewportGestureState = @ptrCast(&gesture_state[0]);
    pushGestureEvent(state, delta_pixels, timestamp);
    const norm_factor = if (state.is_trackpad != 0)
        viewport_span / gesture_working_area_movement
    else
        1.0;
    const pos = state.tracker_position * norm_factor;
    const view_offset = pos + state.delta_from_tracker;
    var next_selection_progress = selection_progress;
    var selection_steps: i64 = 0;
    var has_selection_steps: u8 = 0;
    if (span_count == 0) {
        state.current_view_offset = view_offset;
        out_result[0] = .{
            .current_view_offset = view_offset,
            .selection_progress = next_selection_progress,
            .has_selection_steps = 0,
            .selection_steps = 0,
        };
        return abi.OMNI_OK;
    }
    const active_col_x = containerPositionFromSpans(spans, span_count, active_container_index, gap);
    const total_w = totalSpanFromSpans(spans, span_count, gap);
    const leftmost = -active_col_x;
    const rightmost = @max(0.0, total_w - viewport_span) - active_col_x;
    const min_offset = @min(leftmost, rightmost);
    const max_offset = @max(leftmost, rightmost);
    const clamped_offset = geometry.clampFloat(view_offset, min_offset, max_offset);
    state.delta_from_tracker += clamped_offset - view_offset;
    state.current_view_offset = clamped_offset;
    const avg_column_width = total_w / @as(f64, @floatFromInt(span_count));
    if (avg_column_width > 0) {
        next_selection_progress += delta_pixels;
        selection_steps = @intFromFloat(@trunc(next_selection_progress / avg_column_width));
        if (selection_steps != 0) {
            next_selection_progress -= @as(f64, @floatFromInt(selection_steps)) * avg_column_width;
            has_selection_steps = 1;
        }
    }
    out_result[0] = .{
        .current_view_offset = clamped_offset,
        .selection_progress = next_selection_progress,
        .has_selection_steps = has_selection_steps,
        .selection_steps = selection_steps,
    };
    return abi.OMNI_OK;
}
pub fn omni_viewport_gesture_end_impl(
    gesture_state: [*c]const abi.OmniViewportGestureState,
    spans: [*c]const f64,
    span_count: usize,
    active_container_index: usize,
    gap: f64,
    viewport_span: f64,
    center_mode: u8,
    always_center_single_column: u8,
    out_result: [*c]abi.OmniViewportGestureEndResult,
) i32 {
    if (gesture_state == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count > 0 and spans == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count > 0 and active_container_index >= span_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    const state = gesture_state[0];
    const velocity = trackerVelocity(&state);
    const current_offset = state.current_view_offset;
    const norm_factor = if (state.is_trackpad != 0)
        viewport_span / gesture_working_area_movement
    else
        1.0;
    const projected_tracker_pos = trackerProjectedEndPosition(&state) * norm_factor;
    const projected_offset = projected_tracker_pos + state.delta_from_tracker;
    const active_col_x = if (span_count > 0)
        containerPositionFromSpans(spans, span_count, active_container_index, gap)
    else
        0.0;
    const current_view_pos = active_col_x + current_offset;
    const projected_view_pos = active_col_x + projected_offset;
    var snap_result = abi.OmniSnapResult{ .view_pos = 0.0, .column_index = 0 };
    const snap_rc = findSnapTargetInternal(
        spans,
        span_count,
        gap,
        viewport_span,
        projected_view_pos,
        current_view_pos,
        center_mode,
        always_center_single_column,
        &snap_result,
    );
    if (snap_rc != abi.OMNI_OK) return snap_rc;
    const new_col_x = if (span_count > 0)
        containerPositionFromSpans(spans, span_count, snap_result.column_index, gap)
    else
        0.0;
    const offset_delta = active_col_x - new_col_x;
    const target_offset = snap_result.view_pos - new_col_x;
    const total_w = if (span_count > 0) totalSpanFromSpans(spans, span_count, gap) else 0.0;
    const max_offset: f64 = 0.0;
    const min_offset = viewport_span - total_w;
    const clamped_target = @min(@max(target_offset, min_offset), max_offset);
    out_result[0] = .{
        .resolved_column_index = snap_result.column_index,
        .spring_from = current_offset + offset_delta,
        .spring_to = clamped_target,
        .initial_velocity = velocity,
    };
    return abi.OMNI_OK;
}
