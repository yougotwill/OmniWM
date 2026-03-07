const std = @import("std");
const abi = @import("abi_types.zig");
const types = @import("controller_types.zig");

pub fn recordFocus(state: *types.RuntimeState, workspace_id: types.Uuid, handle_id: types.Uuid) !void {
    try state.last_focused_by_workspace.put(workspace_id, handle_id);

    const entry = try state.focus_history_by_workspace.getOrPut(workspace_id);
    if (!entry.found_existing) {
        entry.value_ptr.* = .{};
    }

    var history = entry.value_ptr;
    var index: usize = 0;
    while (index < history.items.len) : (index += 1) {
        if (std.mem.eql(u8, &history.items[index], &handle_id)) {
            _ = history.orderedRemove(index);
            break;
        }
    }
    try history.insert(state.allocator, 0, handle_id);
    if (history.items.len > 32) {
        history.items.len = 32;
    }
}

pub fn previousFocusedWindow(
    state: *const types.RuntimeState,
    workspace_id: types.Uuid,
    excluded: ?types.Uuid,
    isValid: fn (*const types.RuntimeState, types.Uuid, types.Uuid) bool,
) ?types.Uuid {
    const history = state.focus_history_by_workspace.get(workspace_id) orelse return null;
    for (history.items) |candidate| {
        if (excluded) |excluded_id| {
            if (std.mem.eql(u8, &candidate, &excluded_id)) {
                continue;
            }
        }
        if (!isValid(state, workspace_id, candidate)) {
            continue;
        }
        return candidate;
    }
    return null;
}

pub fn mergeSnapshot(state: *types.RuntimeState) !void {
    for (state.workspaces.items) |workspace| {
        if (workspace.last_focused_window_id) |handle_id| {
            try recordFocus(state, workspace.workspace_id, handle_id);
        }
        if (workspace.selected_node_id) |selected_node_id| {
            try state.selected_node_by_workspace.put(workspace.workspace_id, selected_node_id);
        }
    }

    state.focused_window = null;
    for (state.windows.items) |window| {
        if (window.is_focused) {
            state.focused_window = window.handle_id;
            try recordFocus(state, window.workspace_id, window.handle_id);
            break;
        }
    }
}

pub fn exportFocus(
    state: *types.RuntimeState,
    workspace_id: ?types.Uuid,
    selected_node_id: ?types.Uuid,
    focused_window_id: ?types.Uuid,
) !void {
    var focus_export = abi.OmniControllerFocusExport{
        .has_active_monitor_display_id = 0,
        .active_monitor_display_id = 0,
        .has_previous_monitor_display_id = 0,
        .previous_monitor_display_id = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_selected_node_id = 0,
        .selected_node_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_focused_window_id = 0,
        .focused_window_id = .{ .bytes = [_]u8{0} ** 16 },
        .clear_focus = 0,
        .non_managed_focus_active = if (state.non_managed_focus_active) 1 else 0,
        .app_fullscreen_active = if (state.app_fullscreen_active) 1 else 0,
    };
    types.writeOptionalDisplayId(
        &focus_export.has_active_monitor_display_id,
        &focus_export.active_monitor_display_id,
        state.active_monitor,
    );
    types.writeOptionalDisplayId(
        &focus_export.has_previous_monitor_display_id,
        &focus_export.previous_monitor_display_id,
        state.previous_monitor,
    );
    types.writeOptionalUuid(&focus_export.has_workspace_id, &focus_export.workspace_id, workspace_id);
    types.writeOptionalUuid(
        &focus_export.has_selected_node_id,
        &focus_export.selected_node_id,
        selected_node_id,
    );
    types.writeOptionalUuid(
        &focus_export.has_focused_window_id,
        &focus_export.focused_window_id,
        focused_window_id,
    );
    try state.effects.focus_exports.append(state.allocator, focus_export);
}

pub fn exportClearedFocus(
    state: *types.RuntimeState,
    non_managed_focus_active: bool,
    app_fullscreen_active: bool,
) !void {
    state.focused_window = null;
    state.non_managed_focus_active = non_managed_focus_active;
    state.app_fullscreen_active = app_fullscreen_active;

    var focus_export = abi.OmniControllerFocusExport{
        .has_active_monitor_display_id = 0,
        .active_monitor_display_id = 0,
        .has_previous_monitor_display_id = 0,
        .previous_monitor_display_id = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_selected_node_id = 0,
        .selected_node_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_focused_window_id = 0,
        .focused_window_id = .{ .bytes = [_]u8{0} ** 16 },
        .clear_focus = 1,
        .non_managed_focus_active = if (non_managed_focus_active) 1 else 0,
        .app_fullscreen_active = if (app_fullscreen_active) 1 else 0,
    };
    types.writeOptionalDisplayId(
        &focus_export.has_active_monitor_display_id,
        &focus_export.active_monitor_display_id,
        state.active_monitor,
    );
    types.writeOptionalDisplayId(
        &focus_export.has_previous_monitor_display_id,
        &focus_export.previous_monitor_display_id,
        state.previous_monitor,
    );
    try state.effects.focus_exports.append(state.allocator, focus_export);
}
