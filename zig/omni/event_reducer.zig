const std = @import("std");
const abi = @import("abi_types.zig");
const focus = @import("focus.zig");
const lifecycle = @import("lifecycle.zig");
const refresh = @import("refresh_planner.zig");
const routing = @import("routing.zig");
const types = @import("controller_types.zig");

fn refreshReasonFlags(reason: u8) u32 {
    return switch (reason) {
        abi.OMNI_CONTROLLER_REFRESH_REASON_TIMER => abi.OMNI_CONTROLLER_REFRESH_FULL | abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
        abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CREATED => abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL |
            abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE,
        abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED => abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL,
        abi.OMNI_CONTROLLER_REFRESH_REASON_APP_HIDDEN,
        abi.OMNI_CONTROLLER_REFRESH_REASON_APP_UNHIDDEN,
        abi.OMNI_CONTROLLER_REFRESH_REASON_MONITOR_RECONFIGURED,
        => abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
            abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
        else => abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL,
    };
}

fn shouldSuppressRefresh(state: *const types.RuntimeState, reason: u8) bool {
    if (state.lock_screen_active or state.layout_light_session_active or state.layout_full_enumeration_in_progress) {
        return true;
    }
    return switch (reason) {
        abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED =>
            state.layout_incremental_in_progress or
            state.layout_immediate_in_progress or
            state.layout_animation_active,
        abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CREATED =>
            state.layout_incremental_in_progress or state.layout_immediate_in_progress,
        abi.OMNI_CONTROLLER_REFRESH_REASON_TIMER =>
            state.layout_incremental_in_progress or state.layout_immediate_in_progress,
        else => false,
    };
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

fn fallbackWindowForWorkspace(
    state: *const types.RuntimeState,
    workspace_id: types.Uuid,
    excluded_handle_id: ?types.Uuid,
) ?types.Window {
    if (focus.previousFocusedWindow(state, workspace_id, excluded_handle_id, isWorkspaceWindowValid)) |handle_id| {
        return routing.windowByHandle(state, handle_id);
    }
    return routing.firstManagedWindowInWorkspace(state, workspace_id);
}

fn exportManagedFocusForWindow(state: *types.RuntimeState, window: types.Window) !void {
    const prior_monitor = state.active_monitor;
    state.non_managed_focus_active = false;
    state.app_fullscreen_active = false;
    state.focused_window = window.handle_id;

    if (routing.monitorForWorkspace(state, window.workspace_id)) |target_monitor| {
        if (state.active_monitor) |current_monitor| {
            if (current_monitor != target_monitor) {
                state.previous_monitor = current_monitor;
            }
        }
        state.active_monitor = target_monitor;

        if (routing.workspaceById(state, window.workspace_id)) |workspace| {
            const currently_visible = routing.activeWorkspaceOnMonitor(state, target_monitor);
            if (currently_visible == null or
                !std.mem.eql(u8, &currently_visible.?.workspace_id, &workspace.workspace_id))
            {
                try routing.pushRoutePlan(
                    state,
                    abi.OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE,
                    prior_monitor,
                    target_monitor,
                    if (prior_monitor) |display_id| routing.activeWorkspaceOnMonitor(state, display_id) else null,
                    workspace,
                    null,
                    false,
                    true,
                    true,
                );
            }
        }
    }

    try focus.recordFocus(state, window.workspace_id, window.handle_id);
    if (window.node_id) |node_id| {
        try state.selected_node_by_workspace.put(window.workspace_id, node_id);
    }
    try focus.exportFocus(state, window.workspace_id, window.node_id, window.handle_id);
    try refresh.pushRefreshPlan(
        state,
        abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
            abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT |
            abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
        window.workspace_id,
        state.active_monitor,
    );
}

fn recoverFocusForWorkspace(
    state: *types.RuntimeState,
    workspace_id: types.Uuid,
) !void {
    const fallback_window = fallbackWindowForWorkspace(state, workspace_id, null);
    if (fallback_window) |window| {
        state.non_managed_focus_active = false;
        state.app_fullscreen_active = false;
        state.focused_window = window.handle_id;
        try focus.recordFocus(state, workspace_id, window.handle_id);
        if (window.node_id) |node_id| {
            try state.selected_node_by_workspace.put(workspace_id, node_id);
        }
        try focus.exportFocus(state, workspace_id, window.node_id, window.handle_id);
        return;
    }

    try focus.exportClearedFocus(state, false, false);
    try refresh.pushRefreshPlan(
        state,
        abi.OMNI_CONTROLLER_REFRESH_HIDE_BORDER,
        workspace_id,
        routing.monitorForWorkspace(state, workspace_id),
    );
}

pub fn handleEvent(state: *types.RuntimeState, event: abi.OmniControllerEvent) !i32 {
    switch (event.kind) {
        abi.OMNI_CONTROLLER_EVENT_REFRESH_SESSION => {
            if (!shouldSuppressRefresh(state, event.refresh_reason)) {
                try refresh.pushRefreshPlan(
                    state,
                    refreshReasonFlags(event.refresh_reason),
                    types.optionalUuid(event.has_workspace_id, event.workspace_id),
                    types.optionalDisplayId(event.has_display_id, event.display_id),
                );
            }
        },
        abi.OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED => {
            lifecycle.applySecureInput(state, event.enabled != 0);
            try state.effects.ui_actions.append(state.allocator, .{
                .kind = if (event.enabled != 0)
                    abi.OMNI_CONTROLLER_UI_SHOW_SECURE_INPUT
                else
                    abi.OMNI_CONTROLLER_UI_HIDE_SECURE_INPUT,
            });
        },
        abi.OMNI_CONTROLLER_EVENT_LOCK_SCREEN_CHANGED => {
            lifecycle.applyLockScreen(state, event.enabled != 0);
            if (event.enabled == 0) {
                try refresh.pushRefreshPlan(
                    state,
                    abi.OMNI_CONTROLLER_REFRESH_FULL |
                        abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
                    null,
                    null,
                );
            }
        },
        abi.OMNI_CONTROLLER_EVENT_FOCUS_CHANGED => {
            if (types.optionalUuid(event.has_window_handle_id, event.window_handle_id)) |handle_id| {
                const window = routing.windowByHandle(state, handle_id) orelse {
                    try focus.exportClearedFocus(state, true, false);
                    try refresh.pushRefreshPlan(state, abi.OMNI_CONTROLLER_REFRESH_HIDE_BORDER, null, null);
                    return abi.OMNI_OK;
                };
                try exportManagedFocusForWindow(state, window);
            } else {
                try focus.exportClearedFocus(state, true, false);
                try refresh.pushRefreshPlan(state, abi.OMNI_CONTROLLER_REFRESH_HIDE_BORDER, null, null);
            }
        },
        abi.OMNI_CONTROLLER_EVENT_WINDOW_REMOVED => {
            const removed_handle = types.optionalUuid(event.has_window_handle_id, event.window_handle_id);
            const workspace_id = types.optionalUuid(event.has_workspace_id, event.workspace_id) orelse return abi.OMNI_OK;
            const fallback_window = fallbackWindowForWorkspace(state, workspace_id, removed_handle);

            if (fallback_window) |window| {
                try exportManagedFocusForWindow(state, window);
            } else {
                try focus.exportClearedFocus(state, false, false);
                try refresh.pushRefreshPlan(
                    state,
                    abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
                        abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
                        abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT |
                        abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR |
                        abi.OMNI_CONTROLLER_REFRESH_HIDE_BORDER,
                    workspace_id,
                    routing.monitorForWorkspace(state, workspace_id),
                );
            }
        },
        abi.OMNI_CONTROLLER_EVENT_RECOVER_FOCUS => {
            const workspace_id = types.optionalUuid(event.has_workspace_id, event.workspace_id) orelse return abi.OMNI_OK;
            try recoverFocusForWorkspace(state, workspace_id);
        },
        abi.OMNI_CONTROLLER_EVENT_APP_ACTIVATED => {
            if (state.focused_window) |focused_window_id| {
                try focus.exportFocus(state, null, null, focused_window_id);
            }
        },
        abi.OMNI_CONTROLLER_EVENT_APP_HIDDEN,
        abi.OMNI_CONTROLLER_EVENT_APP_UNHIDDEN,
        abi.OMNI_CONTROLLER_EVENT_MONITOR_RECONFIGURED,
        => {
            try refresh.pushRefreshPlan(
                state,
                abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL |
                    abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
                    abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
                null,
                types.optionalDisplayId(event.has_display_id, event.display_id),
            );
        },
        else => return abi.OMNI_ERR_OUT_OF_RANGE,
    }
    return abi.OMNI_OK;
}

test "secure input event updates state and queues indicator action" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    const rc = try handleEvent(&state, .{
        .kind = abi.OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED,
        .enabled = 1,
        .refresh_reason = 0,
        .has_display_id = 0,
        .display_id = 0,
        .pid = 0,
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expect(state.secure_input_active);
    try std.testing.expectEqual(@as(usize, 1), state.effects.ui_actions.items.len);
    try std.testing.expectEqual(
        abi.OMNI_CONTROLLER_UI_SHOW_SECURE_INPUT,
        state.effects.ui_actions.items[0].kind,
    );
}

test "lock screen unlock queues full refresh and workspace bar update" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();
    state.lock_screen_active = true;

    const rc = try handleEvent(&state, .{
        .kind = abi.OMNI_CONTROLLER_EVENT_LOCK_SCREEN_CHANGED,
        .enabled = 0,
        .refresh_reason = 0,
        .has_display_id = 0,
        .display_id = 0,
        .pid = 0,
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expect(!state.lock_screen_active);
    try std.testing.expectEqual(@as(usize, 1), state.effects.refresh_plans.items.len);
    try std.testing.expectEqual(
        @as(u32, abi.OMNI_CONTROLLER_REFRESH_FULL | abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR),
        state.effects.refresh_plans.items[0].flags,
    );
}

test "monitor reconfigured queues targeted refresh plan" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    const rc = try handleEvent(&state, .{
        .kind = abi.OMNI_CONTROLLER_EVENT_MONITOR_RECONFIGURED,
        .enabled = 0,
        .refresh_reason = 0,
        .has_display_id = 1,
        .display_id = 42,
        .pid = 0,
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.refresh_plans.items.len);

    const plan = state.effects.refresh_plans.items[0];
    try std.testing.expectEqual(
        @as(u32, abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
            abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR),
        plan.flags,
    );
    try std.testing.expectEqual(@as(u8, 1), plan.has_display_id);
    try std.testing.expectEqual(@as(u32, 42), plan.display_id);
}

test "window removed event recovers previous workspace focus in zig" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    const workspace_id: types.Uuid = [_]u8{1} ++ [_]u8{0} ** 15;
    const first_handle: types.Uuid = [_]u8{2} ++ [_]u8{0} ** 15;
    const second_handle: types.Uuid = [_]u8{3} ++ [_]u8{0} ** 15;
    const first_node: types.Uuid = [_]u8{4} ++ [_]u8{0} ** 15;
    const second_node: types.Uuid = [_]u8{5} ++ [_]u8{0} ** 15;

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 7,
        .is_main = true,
        .frame_x = 0,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 0,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("Main"),
    });
    try state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_id,
        .assigned_display_id = 7,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = second_node,
        .last_focused_window_id = second_handle,
    });
    try state.windows.append(std.testing.allocator, .{
        .handle_id = first_handle,
        .pid = 100,
        .window_id = 10,
        .workspace_id = workspace_id,
        .layout_kind = .niri,
        .is_hidden = false,
        .is_focused = false,
        .is_managed = true,
        .node_id = first_node,
        .column_id = first_node,
        .order_index = 0,
        .column_index = 0,
        .row_index = 0,
    });
    state.active_monitor = 7;
    state.focused_window = second_handle;
    try focus.recordFocus(&state, workspace_id, first_handle);
    try focus.recordFocus(&state, workspace_id, second_handle);

    const rc = try handleEvent(&state, .{
        .kind = abi.OMNI_CONTROLLER_EVENT_WINDOW_REMOVED,
        .enabled = 0,
        .refresh_reason = 0,
        .has_display_id = 0,
        .display_id = 0,
        .pid = 100,
        .has_window_handle_id = 1,
        .window_handle_id = types.rawUuid(second_handle),
        .has_workspace_id = 1,
        .workspace_id = types.rawUuid(workspace_id),
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.focus_exports.items.len);
    try std.testing.expectEqual(first_handle, state.effects.focus_exports.items[0].focused_window_id.bytes);
}

test "recover focus event selects first managed window in workspace" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    const workspace_id: types.Uuid = [_]u8{9} ++ [_]u8{0} ** 15;
    const handle_id: types.Uuid = [_]u8{10} ++ [_]u8{0} ** 15;
    const node_id: types.Uuid = [_]u8{11} ++ [_]u8{0} ** 15;

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 3,
        .is_main = true,
        .frame_x = 0,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 0,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("Main"),
    });
    try state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_id,
        .assigned_display_id = 3,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    try state.windows.append(std.testing.allocator, .{
        .handle_id = handle_id,
        .pid = 55,
        .window_id = 44,
        .workspace_id = workspace_id,
        .layout_kind = .niri,
        .is_hidden = false,
        .is_focused = false,
        .is_managed = true,
        .node_id = node_id,
        .column_id = node_id,
        .order_index = 0,
        .column_index = 0,
        .row_index = 0,
    });

    const rc = try handleEvent(&state, .{
        .kind = abi.OMNI_CONTROLLER_EVENT_RECOVER_FOCUS,
        .enabled = 0,
        .refresh_reason = 0,
        .has_display_id = 0,
        .display_id = 0,
        .pid = 0,
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_workspace_id = 1,
        .workspace_id = types.rawUuid(workspace_id),
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.focus_exports.items.len);
    try std.testing.expectEqual(handle_id, state.effects.focus_exports.items[0].focused_window_id.bytes);
    try std.testing.expectEqual(node_id, state.effects.focus_exports.items[0].selected_node_id.bytes);
}
