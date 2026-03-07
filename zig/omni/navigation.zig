const std = @import("std");
const abi = @import("abi_types.zig");
const geometry = @import("geometry.zig");
const SelectedContext = struct {
    column_index: usize,
    row_index: usize,
    window_index: usize,
};
fn parseNiriOrientation(orientation: u8) ?u8 {
    return switch (orientation) {
        abi.OMNI_NIRI_ORIENTATION_HORIZONTAL, abi.OMNI_NIRI_ORIENTATION_VERTICAL => orientation,
        else => null,
    };
}
fn initNavigationResult(out_result: *abi.OmniNiriNavigationResult) void {
    out_result.* = .{
        .has_target = 0,
        .target_window_index = -1,
        .update_source_active_tile = 0,
        .source_column_index = -1,
        .source_active_tile_idx = -1,
        .update_target_active_tile = 0,
        .target_column_index = -1,
        .target_active_tile_idx = -1,
        .refresh_tabbed_visibility_source = 0,
        .refresh_tabbed_visibility_target = 0,
    };
}
fn isValidNiriDirection(direction: u8) bool {
    return switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT,
        abi.OMNI_NIRI_DIRECTION_RIGHT,
        abi.OMNI_NIRI_DIRECTION_UP,
        abi.OMNI_NIRI_DIRECTION_DOWN,
        => true,
        else => false,
    };
}
fn primaryStepForDirection(direction: u8, orientation: u8) ?i64 {
    return switch (orientation) {
        abi.OMNI_NIRI_ORIENTATION_HORIZONTAL => switch (direction) {
            abi.OMNI_NIRI_DIRECTION_RIGHT => 1,
            abi.OMNI_NIRI_DIRECTION_LEFT => -1,
            else => null,
        },
        abi.OMNI_NIRI_ORIENTATION_VERTICAL => switch (direction) {
            abi.OMNI_NIRI_DIRECTION_DOWN => 1,
            abi.OMNI_NIRI_DIRECTION_UP => -1,
            else => null,
        },
        else => null,
    };
}
fn secondaryStepForDirection(direction: u8, orientation: u8) ?i64 {
    return switch (orientation) {
        abi.OMNI_NIRI_ORIENTATION_HORIZONTAL => switch (direction) {
            abi.OMNI_NIRI_DIRECTION_UP => 1,
            abi.OMNI_NIRI_DIRECTION_DOWN => -1,
            else => null,
        },
        abi.OMNI_NIRI_ORIENTATION_VERTICAL => switch (direction) {
            abi.OMNI_NIRI_DIRECTION_RIGHT => 1,
            abi.OMNI_NIRI_DIRECTION_LEFT => -1,
            else => null,
        },
        else => null,
    };
}
fn wrappedColumnIndex(idx: i64, total: usize, infinite_loop: bool) ?usize {
    if (total == 0) return null;
    if (infinite_loop) {
        const modulo = std.math.cast(i64, total) orelse return null;
        const wrapped = @mod(idx, modulo);
        return std.math.cast(usize, wrapped);
    }
    if (idx < 0) return null;
    const casted = std.math.cast(usize, idx) orelse return null;
    if (casted >= total) return null;
    return casted;
}
fn parseSelectedContextRequired(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    column_count: usize,
    window_count: usize,
    request: abi.OmniNiriNavigationRequest,
    out_context: *SelectedContext,
) i32 {
    const column_index = std.math.cast(usize, request.selected_column_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (column_index >= column_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    const selected_column = columns[column_index];
    if (selected_column.window_count == 0) return abi.OMNI_ERR_OUT_OF_RANGE;
    const row_index = std.math.cast(usize, request.selected_row_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (row_index >= selected_column.window_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    const window_index = std.math.cast(usize, request.selected_window_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (window_index >= window_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (!geometry.rangeContains(selected_column.window_start, selected_column.window_count, window_index)) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    if (window_index - selected_column.window_start != row_index) return abi.OMNI_ERR_OUT_OF_RANGE;
    out_context.* = .{
        .column_index = column_index,
        .row_index = row_index,
        .window_index = window_index,
    };
    return abi.OMNI_OK;
}
fn parseSelectedContextOptional(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    column_count: usize,
    window_count: usize,
    request: abi.OmniNiriNavigationRequest,
) ?SelectedContext {
    if (request.selected_column_index < 0 or request.selected_row_index < 0 or request.selected_window_index < 0) {
        return null;
    }
    const column_index = std.math.cast(usize, request.selected_column_index) orelse return null;
    if (column_index >= column_count) return null;
    const selected_column = columns[column_index];
    if (selected_column.window_count == 0) return null;
    const row_index = std.math.cast(usize, request.selected_row_index) orelse return null;
    if (row_index >= selected_column.window_count) return null;
    const window_index = std.math.cast(usize, request.selected_window_index) orelse return null;
    if (window_index >= window_count) return null;
    if (!geometry.rangeContains(selected_column.window_start, selected_column.window_count, window_index)) {
        return null;
    }
    if (window_index - selected_column.window_start != row_index) return null;
    return .{
        .column_index = column_index,
        .row_index = row_index,
        .window_index = window_index,
    };
}
fn setTargetWindow(out_result: *abi.OmniNiriNavigationResult, window_index: usize) i32 {
    const target_window_index = std.math.cast(i64, window_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    out_result.has_target = 1;
    out_result.target_window_index = target_window_index;
    return abi.OMNI_OK;
}
fn setSourceActiveTile(out_result: *abi.OmniNiriNavigationResult, column_index: usize, row_index: usize) i32 {
    out_result.update_source_active_tile = 1;
    out_result.source_column_index = std.math.cast(i64, column_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    out_result.source_active_tile_idx = std.math.cast(i64, row_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}
fn setTargetActiveTile(out_result: *abi.OmniNiriNavigationResult, column_index: usize, row_index: usize) i32 {
    out_result.update_target_active_tile = 1;
    out_result.target_column_index = std.math.cast(i64, column_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    out_result.target_active_tile_idx = std.math.cast(i64, row_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}
fn resolveMoveByColumns(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    column_count: usize,
    selected: SelectedContext,
    step: i64,
    target_row_index: i64,
    infinite_loop: bool,
    out_result: *abi.OmniNiriNavigationResult,
) i32 {
    if (target_row_index < -1) return abi.OMNI_ERR_INVALID_ARGS;
    if (step == 0) {
        return setTargetWindow(out_result, selected.window_index);
    }
    const source_rc = setSourceActiveTile(out_result, selected.column_index, selected.row_index);
    if (source_rc != abi.OMNI_OK) return source_rc;
    if (column_count == 0) return abi.OMNI_OK;
    const source_col_i64 = std.math.cast(i64, selected.column_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    const raw_target_col = std.math.add(i64, source_col_i64, step) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    const target_column_index = wrappedColumnIndex(raw_target_col, column_count, infinite_loop) orelse return abi.OMNI_OK;
    const target_column = columns[target_column_index];
    if (target_column.window_count == 0) return abi.OMNI_OK;
    const target_row: usize = if (target_row_index >= 0)
        if (std.math.cast(usize, target_row_index)) |row_candidate|
            @min(row_candidate, target_column.window_count - 1)
        else
            target_column.window_count - 1
    else
        target_column.active_tile_idx;
    const target_window_index = target_column.window_start + target_row;
    return setTargetWindow(out_result, target_window_index);
}
fn resolveMoveVertical(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    selected: SelectedContext,
    step: i64,
    out_result: *abi.OmniNiriNavigationResult,
) i32 {
    if (step == 0) return abi.OMNI_OK;
    const selected_column = columns[selected.column_index];
    if (selected_column.window_count == 0) return abi.OMNI_OK;
    if (selected_column.is_tabbed != 0) {
        const active_i64 = std.math.cast(i64, selected_column.active_tile_idx) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        const next_i64 = std.math.add(i64, active_i64, step) catch return abi.OMNI_OK;
        if (next_i64 < 0) return abi.OMNI_OK;
        const next_row_index = std.math.cast(usize, next_i64) orelse return abi.OMNI_OK;
        if (next_row_index >= selected_column.window_count) return abi.OMNI_OK;
        const target_window_index = selected_column.window_start + next_row_index;
        const target_rc = setTargetWindow(out_result, target_window_index);
        if (target_rc != abi.OMNI_OK) return target_rc;
        const update_rc = setTargetActiveTile(out_result, selected.column_index, next_row_index);
        if (update_rc != abi.OMNI_OK) return update_rc;
        out_result.refresh_tabbed_visibility_target = 1;
        return abi.OMNI_OK;
    }
    const selected_row_i64 = std.math.cast(i64, selected.row_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    const next_i64 = std.math.add(i64, selected_row_i64, step) catch return abi.OMNI_OK;
    if (next_i64 < 0) return abi.OMNI_OK;
    const next_row_index = std.math.cast(usize, next_i64) orelse return abi.OMNI_OK;
    if (next_row_index >= selected_column.window_count) return abi.OMNI_OK;
    const target_window_index = selected_column.window_start + next_row_index;
    const target_rc = setTargetWindow(out_result, target_window_index);
    if (target_rc != abi.OMNI_OK) return target_rc;
    return setTargetActiveTile(out_result, selected.column_index, next_row_index);
}
fn resolveFocusColumnByIndex(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    target_column_index: usize,
    selected: ?SelectedContext,
    out_result: *abi.OmniNiriNavigationResult,
) i32 {
    if (selected) |ctx| {
        const source_rc = setSourceActiveTile(out_result, ctx.column_index, ctx.row_index);
        if (source_rc != abi.OMNI_OK) return source_rc;
    }
    const target_column = columns[target_column_index];
    if (target_column.window_count == 0) return abi.OMNI_OK;
    const target_row = @min(target_column.active_tile_idx, target_column.window_count - 1);
    const target_window_index = target_column.window_start + target_row;
    return setTargetWindow(out_result, target_window_index);
}
fn resolveFocusWindowInSelectedColumn(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    selected: SelectedContext,
    target_row_index: usize,
    out_result: *abi.OmniNiriNavigationResult,
) i32 {
    const selected_column = columns[selected.column_index];
    if (target_row_index >= selected_column.window_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    const target_window_index = selected_column.window_start + target_row_index;
    const target_rc = setTargetWindow(out_result, target_window_index);
    if (target_rc != abi.OMNI_OK) return target_rc;
    const update_rc = setTargetActiveTile(out_result, selected.column_index, target_row_index);
    if (update_rc != abi.OMNI_OK) return update_rc;
    if (selected_column.is_tabbed != 0) {
        out_result.refresh_tabbed_visibility_target = 1;
    }
    return abi.OMNI_OK;
}
pub fn omni_niri_navigation_resolve_impl(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    column_count: usize,
    windows: [*c]const abi.OmniNiriStateWindowInput,
    window_count: usize,
    request: [*c]const abi.OmniNiriNavigationRequest,
    out_result: [*c]abi.OmniNiriNavigationResult,
) i32 {
    if (request == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (column_count > 0 and columns == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_count > 0 and windows == null) return abi.OMNI_ERR_INVALID_ARGS;
    var resolved_result: abi.OmniNiriNavigationResult = undefined;
    initNavigationResult(&resolved_result);
    const req = request[0];
    const rc: i32 = blk: {
        switch (req.op) {
            abi.OMNI_NIRI_NAV_OP_MOVE_BY_COLUMNS => {
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                break :blk resolveMoveByColumns(
                    columns,
                    column_count,
                    selected,
                    req.step,
                    req.target_row_index,
                    req.infinite_loop != 0,
                    &resolved_result,
                );
            },
            abi.OMNI_NIRI_NAV_OP_MOVE_VERTICAL => {
                const orientation = parseNiriOrientation(req.orientation) orelse break :blk abi.OMNI_ERR_INVALID_ARGS;
                if (!isValidNiriDirection(req.direction)) break :blk abi.OMNI_ERR_INVALID_ARGS;
                const step = secondaryStepForDirection(req.direction, orientation) orelse break :blk abi.OMNI_OK;
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                break :blk resolveMoveVertical(columns, selected, step, &resolved_result);
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_TARGET => {
                const orientation = parseNiriOrientation(req.orientation) orelse break :blk abi.OMNI_ERR_INVALID_ARGS;
                if (!isValidNiriDirection(req.direction)) break :blk abi.OMNI_ERR_INVALID_ARGS;
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                if (primaryStepForDirection(req.direction, orientation)) |step| {
                    break :blk resolveMoveByColumns(
                        columns,
                        column_count,
                        selected,
                        step,
                        -1,
                        req.infinite_loop != 0,
                        &resolved_result,
                    );
                }
                if (secondaryStepForDirection(req.direction, orientation)) |step| {
                    break :blk resolveMoveVertical(columns, selected, step, &resolved_result);
                }
                break :blk abi.OMNI_OK;
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_DOWN_OR_LEFT => {
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                const vertical_step = secondaryStepForDirection(
                    abi.OMNI_NIRI_DIRECTION_DOWN,
                    abi.OMNI_NIRI_ORIENTATION_HORIZONTAL,
                ) orelse break :blk abi.OMNI_ERR_INVALID_ARGS;
                const vertical_rc = resolveMoveVertical(columns, selected, vertical_step, &resolved_result);
                if (vertical_rc != abi.OMNI_OK) break :blk vertical_rc;
                if (resolved_result.has_target != 0) break :blk abi.OMNI_OK;
                break :blk resolveMoveByColumns(
                    columns,
                    column_count,
                    selected,
                    -1,
                    std.math.maxInt(i64),
                    req.infinite_loop != 0,
                    &resolved_result,
                );
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_UP_OR_RIGHT => {
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                const vertical_step = secondaryStepForDirection(
                    abi.OMNI_NIRI_DIRECTION_UP,
                    abi.OMNI_NIRI_ORIENTATION_HORIZONTAL,
                ) orelse break :blk abi.OMNI_ERR_INVALID_ARGS;
                const vertical_rc = resolveMoveVertical(columns, selected, vertical_step, &resolved_result);
                if (vertical_rc != abi.OMNI_OK) break :blk vertical_rc;
                if (resolved_result.has_target != 0) break :blk abi.OMNI_OK;
                break :blk resolveMoveByColumns(
                    columns,
                    column_count,
                    selected,
                    1,
                    -1,
                    req.infinite_loop != 0,
                    &resolved_result,
                );
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_COLUMN_FIRST => {
                if (column_count == 0) break :blk abi.OMNI_OK;
                const selected = parseSelectedContextOptional(columns, column_count, window_count, req);
                break :blk resolveFocusColumnByIndex(columns, 0, selected, &resolved_result);
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_COLUMN_LAST => {
                if (column_count == 0) break :blk abi.OMNI_OK;
                const selected = parseSelectedContextOptional(columns, column_count, window_count, req);
                break :blk resolveFocusColumnByIndex(columns, column_count - 1, selected, &resolved_result);
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_COLUMN_INDEX => {
                if (column_count == 0) break :blk abi.OMNI_OK;
                const target_column_index = std.math.cast(usize, req.target_column_index) orelse break :blk abi.OMNI_ERR_OUT_OF_RANGE;
                if (target_column_index >= column_count) break :blk abi.OMNI_ERR_OUT_OF_RANGE;
                const selected = parseSelectedContextOptional(columns, column_count, window_count, req);
                break :blk resolveFocusColumnByIndex(columns, target_column_index, selected, &resolved_result);
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_WINDOW_INDEX => {
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                const target_row_index = std.math.cast(usize, req.target_window_index) orelse break :blk abi.OMNI_ERR_OUT_OF_RANGE;
                break :blk resolveFocusWindowInSelectedColumn(columns, selected, target_row_index, &resolved_result);
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_WINDOW_TOP => {
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                break :blk resolveFocusWindowInSelectedColumn(columns, selected, 0, &resolved_result);
            },
            abi.OMNI_NIRI_NAV_OP_FOCUS_WINDOW_BOTTOM => {
                var selected: SelectedContext = undefined;
                const selected_rc = parseSelectedContextRequired(
                    columns,
                    column_count,
                    window_count,
                    req,
                    &selected,
                );
                if (selected_rc != abi.OMNI_OK) break :blk selected_rc;
                const selected_column = columns[selected.column_index];
                if (selected_column.window_count == 0) break :blk abi.OMNI_OK;
                break :blk resolveFocusWindowInSelectedColumn(
                    columns,
                    selected,
                    selected_column.window_count - 1,
                    &resolved_result,
                );
            },
            else => break :blk abi.OMNI_ERR_INVALID_ARGS,
        }
    };
    out_result[0] = resolved_result;
    return rc;
}
