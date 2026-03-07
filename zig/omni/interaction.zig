const abi = @import("abi_types.zig");
const geometry = @import("geometry.zig");
const Rect = geometry.Rect;
fn detectResizeEdgesForPoint(point_x: f64, point_y: f64, rect: Rect, threshold: f64) u8 {
    const expanded = Rect{
        .x = rect.x - threshold,
        .y = rect.y - threshold,
        .width = rect.width + threshold * 2.0,
        .height = rect.height + threshold * 2.0,
    };
    if (!geometry.pointInRect(point_x, point_y, expanded)) return 0;
    const inner = Rect{
        .x = rect.x + threshold,
        .y = rect.y + threshold,
        .width = rect.width - threshold * 2.0,
        .height = rect.height - threshold * 2.0,
    };
    if (geometry.pointInRect(point_x, point_y, inner)) return 0;
    const min_x = rect.x;
    const max_x = rect.x + rect.width;
    const min_y = rect.y;
    const max_y = rect.y + rect.height;
    var edges: u8 = 0;
    if (point_x <= min_x + threshold and point_x >= min_x - threshold) {
        edges |= abi.OMNI_NIRI_RESIZE_EDGE_LEFT;
    }
    if (point_x >= max_x - threshold and point_x <= max_x + threshold) {
        edges |= abi.OMNI_NIRI_RESIZE_EDGE_RIGHT;
    }
    if (point_y <= min_y + threshold and point_y >= min_y - threshold) {
        edges |= abi.OMNI_NIRI_RESIZE_EDGE_BOTTOM;
    }
    if (point_y >= max_y - threshold and point_y <= max_y + threshold) {
        edges |= abi.OMNI_NIRI_RESIZE_EDGE_TOP;
    }
    return edges;
}
pub fn omni_niri_hit_test_tiled_impl(
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    point_x: f64,
    point_y: f64,
    out_window_index: [*c]i64,
) i32 {
    if (out_window_index == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_count > 0 and windows == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_window_index[0] = -1;
    for (0..window_count) |i| {
        const w = windows[i];
        const rect = Rect{
            .x = w.frame_x,
            .y = w.frame_y,
            .width = w.frame_width,
            .height = w.frame_height,
        };
        if (geometry.pointInRect(point_x, point_y, rect)) {
            out_window_index[0] = @as(i64, @intCast(i));
            return abi.OMNI_OK;
        }
    }
    return abi.OMNI_OK;
}
pub fn omni_niri_hit_test_resize_impl(
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    point_x: f64,
    point_y: f64,
    threshold: f64,
    out_result: [*c]abi.OmniNiriResizeHitResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_count > 0 and windows == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_result[0] = .{
        .window_index = -1,
        .edges = 0,
    };
    const safe_threshold = @max(0.0, threshold);
    for (0..window_count) |i| {
        const w = windows[i];
        if (w.is_fullscreen != 0) continue;
        const rect = Rect{
            .x = w.frame_x,
            .y = w.frame_y,
            .width = w.frame_width,
            .height = w.frame_height,
        };
        const edges = detectResizeEdgesForPoint(point_x, point_y, rect, safe_threshold);
        if (edges != 0) {
            out_result[0] = .{
                .window_index = @as(i64, @intCast(i)),
                .edges = edges,
            };
            return abi.OMNI_OK;
        }
    }
    return abi.OMNI_OK;
}
pub fn omni_niri_hit_test_move_target_impl(
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    point_x: f64,
    point_y: f64,
    excluding_window_index: i64,
    is_insert_mode: u8,
    out_result: [*c]abi.OmniNiriMoveTargetResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_count > 0 and windows == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_result[0] = .{
        .window_index = -1,
        .insert_position = abi.OMNI_NIRI_INSERT_SWAP,
    };
    for (0..window_count) |i| {
        if (excluding_window_index >= 0 and @as(i64, @intCast(i)) == excluding_window_index) {
            continue;
        }
        const w = windows[i];
        const rect = Rect{
            .x = w.frame_x,
            .y = w.frame_y,
            .width = w.frame_width,
            .height = w.frame_height,
        };
        if (!geometry.pointInRect(point_x, point_y, rect)) continue;
        const insert_position: u8 = if (is_insert_mode != 0)
            if (point_y < rect.y + rect.height / 2.0) abi.OMNI_NIRI_INSERT_BEFORE else abi.OMNI_NIRI_INSERT_AFTER
        else
            abi.OMNI_NIRI_INSERT_SWAP;
        out_result[0] = .{
            .window_index = @as(i64, @intCast(i)),
            .insert_position = insert_position,
        };
        return abi.OMNI_OK;
    }
    return abi.OMNI_OK;
}
pub fn omni_niri_insertion_dropzone_impl(
    input: [*c]const abi.OmniNiriDropzoneInput,
    out_result: [*c]abi.OmniNiriDropzoneResult,
) i32 {
    if (input == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_result[0] = .{
        .frame_x = 0.0,
        .frame_y = 0.0,
        .frame_width = 0.0,
        .frame_height = 0.0,
        .is_valid = 0,
    };
    const in = input[0];
    if (in.post_insertion_count == 0) return abi.OMNI_ERR_INVALID_ARGS;
    if (in.insert_position != abi.OMNI_NIRI_INSERT_BEFORE and in.insert_position != abi.OMNI_NIRI_INSERT_AFTER and in.insert_position != abi.OMNI_NIRI_INSERT_SWAP) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    const column_height = in.column_max_y - in.column_min_y;
    const count_f: f64 = @floatFromInt(in.post_insertion_count);
    const total_gaps = @as(f64, @floatFromInt(in.post_insertion_count - 1)) * in.gap;
    const new_height = @max(0.0, (column_height - total_gaps) / count_f);
    const y = if (in.insert_position == abi.OMNI_NIRI_INSERT_BEFORE)
        blk: {
            const unclamped = in.target_frame_y - in.gap - new_height;
            const max_before_y = @max(in.column_min_y, in.column_max_y - new_height);
            break :blk geometry.clampFloat(unclamped, in.column_min_y, max_before_y);
        }
    else if (in.insert_position == abi.OMNI_NIRI_INSERT_AFTER)
        in.target_frame_y + in.target_frame_height + in.gap
    else
        in.target_frame_y;
    out_result[0] = .{
        .frame_x = in.target_frame_x,
        .frame_y = y,
        .frame_width = in.target_frame_width,
        .frame_height = new_height,
        .is_valid = 1,
    };
    return abi.OMNI_OK;
}
pub fn omni_niri_resize_compute_impl(
    input: [*c]const abi.OmniNiriResizeInput,
    out_result: [*c]abi.OmniNiriResizeResult,
) i32 {
    if (input == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    const in = input[0];
    out_result[0] = .{
        .changed_width = 0,
        .new_column_width = in.original_column_width,
        .changed_weight = 0,
        .new_window_weight = in.original_window_weight,
        .adjust_view_offset = 0,
        .new_view_offset = in.original_view_offset,
    };
    const delta_x = in.current_x - in.start_x;
    const delta_y = in.current_y - in.start_y;
    const has_horizontal = (in.edges & (abi.OMNI_NIRI_RESIZE_EDGE_LEFT | abi.OMNI_NIRI_RESIZE_EDGE_RIGHT)) != 0;
    const has_vertical = (in.edges & (abi.OMNI_NIRI_RESIZE_EDGE_TOP | abi.OMNI_NIRI_RESIZE_EDGE_BOTTOM)) != 0;
    const has_left = (in.edges & abi.OMNI_NIRI_RESIZE_EDGE_LEFT) != 0;
    const has_bottom = (in.edges & abi.OMNI_NIRI_RESIZE_EDGE_BOTTOM) != 0;
    if (has_horizontal) {
        var dx = delta_x;
        if (has_left) dx = -dx;
        const min_width = @min(in.min_column_width, in.max_column_width);
        const max_width = @max(in.min_column_width, in.max_column_width);
        const next_width = geometry.clampFloat(in.original_column_width + dx, min_width, max_width);
        out_result[0].new_column_width = next_width;
        out_result[0].changed_width = @intFromBool(@abs(next_width - in.original_column_width) > 0.0001);
        if (has_left and in.has_original_view_offset != 0) {
            out_result[0].adjust_view_offset = 1;
            out_result[0].new_view_offset = in.original_view_offset + (next_width - in.original_column_width);
        }
    }
    if (has_vertical and in.pixels_per_weight > 0.0) {
        var dy = delta_y;
        if (has_bottom) dy = -dy;
        const weight_delta = dy / in.pixels_per_weight;
        const min_weight = @min(in.min_window_weight, in.max_window_weight);
        const max_weight = @max(in.min_window_weight, in.max_window_weight);
        const next_weight = geometry.clampFloat(in.original_window_weight + weight_delta, min_weight, max_weight);
        out_result[0].new_window_weight = next_weight;
        out_result[0].changed_weight = @intFromBool(@abs(next_weight - in.original_window_weight) > 0.0001);
    }
    return abi.OMNI_OK;
}
