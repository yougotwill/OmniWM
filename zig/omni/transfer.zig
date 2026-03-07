const std = @import("std");
const abi = @import("abi_types.zig");
const focus = @import("focus.zig");
const types = @import("controller_types.zig");
const routing = @import("routing.zig");

fn effectiveLayout(kind: types.LayoutKind) types.LayoutKind {
    return switch (kind) {
        .default_layout => .niri,
        .niri => .niri,
        .dwindle => .dwindle,
    };
}

fn targetTransferMode(kind: u8, source_layout: types.LayoutKind, target_layout: types.LayoutKind) u8 {
    if (kind == abi.OMNI_CONTROLLER_TRANSFER_MOVE_COLUMN) {
        return switch (effectiveLayout(source_layout)) {
            .niri => switch (effectiveLayout(target_layout)) {
                .niri => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_COLUMN,
                .dwindle => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_BATCH,
                else => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_COLUMN,
            },
            else => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_BATCH,
        };
    }

    return switch (effectiveLayout(source_layout)) {
        .niri => switch (effectiveLayout(target_layout)) {
            .niri => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_WINDOW,
            .dwindle => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_WINDOW,
            else => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_WINDOW,
        },
        .dwindle => switch (effectiveLayout(target_layout)) {
            .niri => abi.OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_NIRI_WINDOW,
            .dwindle => abi.OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_DWINDLE_WINDOW,
            else => abi.OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_DWINDLE_WINDOW,
        },
        else => abi.OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_WINDOW,
    };
}

fn currentWorkspaceForWindow(state: *const types.RuntimeState, handle_id: types.Uuid) ?types.Workspace {
    const window = routing.windowByHandle(state, handle_id) orelse return null;
    return routing.workspaceById(state, window.workspace_id);
}

fn sourceSelectionNodeId(state: *const types.RuntimeState, workspace_id: types.Uuid) ?types.Uuid {
    return state.selected_node_by_workspace.get(workspace_id);
}

fn selectedColumnId(state: *const types.RuntimeState, workspace: types.Workspace) ?types.Uuid {
    const selected_node = workspace.selected_node_id orelse sourceSelectionNodeId(state, workspace.workspace_id);
    if (selected_node) |node_id| {
        for (state.windows.items) |window| {
            if (!std.mem.eql(u8, &window.workspace_id, &workspace.workspace_id)) {
                continue;
            }
            if (window.column_id) |column_id| {
                if (window.node_id) |window_node_id| {
                    if (std.mem.eql(u8, &window_node_id, &node_id)) {
                        return column_id;
                    }
                }
                if (std.mem.eql(u8, &column_id, &node_id)) {
                    return column_id;
                }
            }
        }
    }
    var best_window: ?types.Window = null;
    for (state.windows.items) |window| {
        if (!std.mem.eql(u8, &window.workspace_id, &workspace.workspace_id)) {
            continue;
        }
        if (window.column_id == null) {
            continue;
        }
        if (best_window == null or window.column_index < best_window.?.column_index) {
            best_window = window;
        }
    }
    return if (best_window) |window| window.column_id else null;
}

fn appendTransferWindows(
    state: *const types.RuntimeState,
    workspace_id: types.Uuid,
    maybe_column_id: ?types.Uuid,
    focused_window_id: ?types.Uuid,
    transfer_plan: *abi.OmniControllerTransferPlan,
) i32 {
    var ordered = std.ArrayListUnmanaged(types.Window){};
    defer ordered.deinit(std.heap.page_allocator);

    for (state.windows.items) |window| {
        if (!std.mem.eql(u8, &window.workspace_id, &workspace_id)) {
            continue;
        }
        if (maybe_column_id) |column_id| {
            const window_column_id = window.column_id orelse continue;
            if (!std.mem.eql(u8, &window_column_id, &column_id)) {
                continue;
            }
        } else if (focused_window_id) |handle_id| {
            if (!std.mem.eql(u8, &window.handle_id, &handle_id)) {
                continue;
            }
        }
        ordered.append(std.heap.page_allocator, window) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    std.sort.insertion(types.Window, ordered.items, {}, struct {
        fn lessThan(_: void, lhs: types.Window, rhs: types.Window) bool {
            if (lhs.column_index != rhs.column_index) {
                return lhs.column_index < rhs.column_index;
            }
            if (lhs.row_index != rhs.row_index) {
                return lhs.row_index < rhs.row_index;
            }
            return lhs.order_index < rhs.order_index;
        }
    }.lessThan);

    if (ordered.items.len == 0) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    if (ordered.items.len > abi.OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    transfer_plan.window_count = @intCast(ordered.items.len);
    for (ordered.items, 0..) |window, index| {
        transfer_plan.window_ids[index] = types.rawUuid(window.handle_id);
    }
    return abi.OMNI_OK;
}

fn isWorkspaceWindowValid(
    state: *const types.RuntimeState,
    workspace_id: types.Uuid,
    handle_id: types.Uuid,
) bool {
    const window = routing.windowByHandle(state, handle_id) orelse return false;
    if (!window.is_managed or window.is_hidden) {
        return false;
    }
    return std.mem.eql(u8, &window.workspace_id, &workspace_id);
}

fn planContainsWindow(plan: *const abi.OmniControllerTransferPlan, handle_id: types.Uuid) bool {
    var index: usize = 0;
    while (index < plan.window_count) : (index += 1) {
        if (std.mem.eql(u8, &plan.window_ids[index].bytes, &handle_id)) {
            return true;
        }
    }
    return false;
}

fn firstRemainingWindow(
    state: *const types.RuntimeState,
    workspace_id: types.Uuid,
    plan: *const abi.OmniControllerTransferPlan,
) ?types.Uuid {
    var best_window: ?types.Window = null;
    for (state.windows.items) |window| {
        if (!std.mem.eql(u8, &window.workspace_id, &workspace_id)) {
            continue;
        }
        if (!window.is_managed or window.is_hidden or planContainsWindow(plan, window.handle_id)) {
            continue;
        }
        if (best_window == null or window.order_index < best_window.?.order_index) {
            best_window = window;
        }
    }
    return if (best_window) |window| window.handle_id else null;
}

pub fn pushTransferPlan(
    state: *types.RuntimeState,
    kind: u8,
    source_window_id: ?types.Uuid,
    target_workspace: ?types.Workspace,
    target_workspace_name: []const u8,
    create_if_missing: bool,
    target_monitor_display_id: ?u32,
    follow_focus: bool,
) !i32 {
    const focused_window_id = source_window_id orelse state.focused_window orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    const source_workspace = currentWorkspaceForWindow(state, focused_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    const source_layout = source_workspace.layout_kind;
    const resolved_target_layout = if (target_workspace) |workspace| workspace.layout_kind else source_layout;

    var plan = abi.OmniControllerTransferPlan{
        .kind = kind,
        .mode = targetTransferMode(kind, source_layout, resolved_target_layout),
        .create_target_workspace_if_missing = if (create_if_missing) 1 else 0,
        .follow_focus = if (follow_focus) 1 else 0,
        .window_count = 0,
        .window_ids = [_]abi.OmniUuid128{.{ .bytes = [_]u8{0} ** 16 }} ** abi.OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS,
        .has_source_workspace_id = 0,
        .source_workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .source_workspace_name = source_workspace.name,
        .has_target_workspace_id = 0,
        .target_workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .target_workspace_name = types.encodeName(target_workspace_name),
        .has_target_monitor_display_id = 0,
        .target_monitor_display_id = 0,
        .has_source_fallback_window_id = 0,
        .source_fallback_window_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_target_focus_window_id = 0,
        .target_focus_window_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_source_selection_node_id = 0,
        .source_selection_node_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_target_selection_node_id = 0,
        .target_selection_node_id = .{ .bytes = [_]u8{0} ** 16 },
    };

    types.writeOptionalUuid(
        &plan.has_source_workspace_id,
        &plan.source_workspace_id,
        source_workspace.workspace_id,
    );
    types.writeOptionalDisplayId(
        &plan.has_target_monitor_display_id,
        &plan.target_monitor_display_id,
        target_monitor_display_id,
    );
    if (target_workspace) |workspace| {
        types.writeOptionalUuid(
            &plan.has_target_workspace_id,
            &plan.target_workspace_id,
            workspace.workspace_id,
        );
        plan.target_workspace_name = workspace.name;
    }

    if (kind == abi.OMNI_CONTROLLER_TRANSFER_MOVE_COLUMN) {
        const column_id = selectedColumnId(state, source_workspace) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        const rc = appendTransferWindows(state, source_workspace.workspace_id, column_id, null, &plan);
        if (rc != abi.OMNI_OK) {
            return rc;
        }
        types.writeOptionalUuid(
            &plan.has_source_selection_node_id,
            &plan.source_selection_node_id,
            sourceSelectionNodeId(state, source_workspace.workspace_id),
        );
        if (plan.window_count > 0) {
            const target_focus_window = if (planContainsWindow(&plan, focused_window_id))
                focused_window_id
            else
                types.uuid(plan.window_ids[0]);
            plan.has_target_focus_window_id = 1;
            plan.target_focus_window_id = types.rawUuid(target_focus_window);
            plan.has_target_selection_node_id = 1;
            plan.target_selection_node_id = types.rawUuid(target_focus_window);
        }
    } else {
        const rc = appendTransferWindows(state, source_workspace.workspace_id, null, focused_window_id, &plan);
        if (rc != abi.OMNI_OK) {
            return rc;
        }
        plan.has_target_focus_window_id = 1;
        plan.target_focus_window_id = types.rawUuid(focused_window_id);
        plan.has_target_selection_node_id = 1;
        plan.target_selection_node_id = types.rawUuid(focused_window_id);
    }

    const source_fallback_window =
        focus.previousFocusedWindow(
            state,
            source_workspace.workspace_id,
            focused_window_id,
            isWorkspaceWindowValid,
        ) orelse firstRemainingWindow(state, source_workspace.workspace_id, &plan);
    types.writeOptionalUuid(
        &plan.has_source_fallback_window_id,
        &plan.source_fallback_window_id,
        source_fallback_window,
    );

    if (plan.has_source_selection_node_id == 0) {
        types.writeOptionalUuid(
            &plan.has_source_selection_node_id,
            &plan.source_selection_node_id,
            sourceSelectionNodeId(state, source_workspace.workspace_id),
        );
    }

    try state.effects.transfer_plans.append(state.allocator, plan);
    return abi.OMNI_OK;
}
