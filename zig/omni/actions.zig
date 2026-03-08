const std = @import("std");
const abi = @import("abi_types.zig");
const focus = @import("focus.zig");
const refresh = @import("refresh_planner.zig");
const routing = @import("routing.zig");
const transfer = @import("transfer.zig");
const types = @import("controller_types.zig");

fn activeWorkspace(state: *const types.RuntimeState) ?types.Workspace {
    const display_id = routing.currentMonitorId(state) orelse return null;
    return routing.activeWorkspaceOnMonitor(state, display_id);
}

fn effectiveLayoutKind(kind: types.LayoutKind) types.LayoutKind {
    return switch (kind) {
        .default_layout, .niri => .niri,
        .dwindle => .dwindle,
    };
}

fn activeWorkspaceLayoutKind(state: *const types.RuntimeState) ?types.LayoutKind {
    const workspace = activeWorkspace(state) orelse return null;
    return effectiveLayoutKind(workspace.layout_kind);
}

fn niriLayoutActive(state: *const types.RuntimeState) bool {
    return if (activeWorkspaceLayoutKind(state)) |kind|
        kind == .niri
    else
        false;
}

fn dwindleLayoutActive(state: *const types.RuntimeState) bool {
    return if (activeWorkspaceLayoutKind(state)) |kind|
        kind == .dwindle
    else
        false;
}

fn workspaceNameFromIndex(index: i64) ?[32]u8 {
    if (index < 0) {
        return null;
    }
    var buffer: [32]u8 = [_]u8{0} ** 32;
    const resolved = std.fmt.bufPrint(&buffer, "{d}", .{index + 1}) catch return null;
    _ = resolved;
    return buffer;
}

fn emitDefaultRefresh(state: *types.RuntimeState, workspace_id: ?types.Uuid, display_id: ?u32) !void {
    try refresh.pushRefreshPlan(
        state,
        abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
            abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT |
            abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
        workspace_id,
        display_id,
    );
}

fn targetWorkspaceForIndex(state: *const types.RuntimeState, index: i64) ?types.Workspace {
    const name_buffer = workspaceNameFromIndex(index) orelse return null;
    const len = std.mem.indexOfScalar(u8, &name_buffer, 0) orelse name_buffer.len;
    return routing.workspaceByName(state, name_buffer[0..len]);
}

fn routeKindForWorkspaceCommand(command_kind: u8) ?u8 {
    return switch (command_kind) {
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX => abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE,
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE => abi.OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE,
        abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE => abi.OMNI_CONTROLLER_ROUTE_SUMMON_WORKSPACE,
        else => null,
    };
}

fn shouldCreateWorkspaceForCommand(command: abi.OmniControllerCommand) bool {
    return command.kind == abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX and
        command.has_workspace_id == 0;
}

fn mainOrFirstMonitorId(state: *const types.RuntimeState) ?u32 {
    if (state.monitors.items.len == 0) {
        return null;
    }
    for (state.monitors.items) |monitor| {
        if (monitor.is_main) {
            return monitor.display_id;
        }
    }
    return state.monitors.items[0].display_id;
}

fn targetMonitorForWorkspaceCommand(
    state: *const types.RuntimeState,
    command_kind: u8,
    current_monitor: u32,
    existing_target: ?types.Workspace,
) ?u32 {
    return switch (command_kind) {
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX => if (existing_target) |workspace|
            routing.monitorForWorkspace(state, workspace.workspace_id)
        else
            mainOrFirstMonitorId(state),
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE => if (existing_target) |workspace|
            routing.monitorForWorkspace(state, workspace.workspace_id)
        else
            null,
        abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE => if (existing_target != null)
            current_monitor
        else
            null,
        else => null,
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

fn emitWorkspaceFocusOrClear(
    state: *types.RuntimeState,
    workspace: ?types.Workspace,
) !void {
    const resolved_workspace = workspace orelse {
        try focus.exportClearedFocus(state, false, false);
        return;
    };

    if (resolved_workspace.last_focused_window_id) |handle_id| {
        if (routing.windowByHandle(state, handle_id)) |window| {
            state.non_managed_focus_active = false;
            state.app_fullscreen_active = false;
            state.focused_window = handle_id;
            try focus.recordFocus(state, resolved_workspace.workspace_id, handle_id);
            if (window.node_id) |node_id| {
                try state.selected_node_by_workspace.put(resolved_workspace.workspace_id, node_id);
            }
            try focus.exportFocus(
                state,
                resolved_workspace.workspace_id,
                window.node_id orelse resolved_workspace.selected_node_id,
                handle_id,
            );
            return;
        }
    }

    if (routing.firstManagedWindowInWorkspace(state, resolved_workspace.workspace_id)) |window| {
        state.non_managed_focus_active = false;
        state.app_fullscreen_active = false;
        state.focused_window = window.handle_id;
        try focus.recordFocus(state, resolved_workspace.workspace_id, window.handle_id);
        if (window.node_id) |node_id| {
            try state.selected_node_by_workspace.put(resolved_workspace.workspace_id, node_id);
        }
        try focus.exportFocus(
            state,
            resolved_workspace.workspace_id,
            window.node_id orelse resolved_workspace.selected_node_id,
            window.handle_id,
        );
        return;
    }

    try focus.exportClearedFocus(state, false, false);
}

fn emitWorkspaceSwitchAnimationIfNeeded(
    state: *types.RuntimeState,
    source_workspace: ?types.Workspace,
    target_workspace: ?types.Workspace,
    target_display_id: ?u32,
) !void {
    const resolved_target_workspace = target_workspace orelse return;
    const resolved_target_display = target_display_id orelse return;
    if (resolved_target_workspace.layout_kind == .dwindle) {
        return;
    }
    if (source_workspace) |resolved_source_workspace| {
        if (std.mem.eql(u8, &resolved_source_workspace.workspace_id, &resolved_target_workspace.workspace_id)) {
            return;
        }
    }

    try refresh.pushRefreshPlan(
        state,
        abi.OMNI_CONTROLLER_REFRESH_STOP_SCROLL_ANIMATION,
        resolved_target_workspace.workspace_id,
        resolved_target_display,
    );
    try refresh.pushRefreshPlan(
        state,
        abi.OMNI_CONTROLLER_REFRESH_START_WORKSPACE_ANIMATION,
        resolved_target_workspace.workspace_id,
        resolved_target_display,
    );
}

fn emitLayoutAction(
    state: *types.RuntimeState,
    kind: u8,
    direction: u8,
    index: i64,
    flag: u8,
) !void {
    try emitLayoutActionWithPayload(state, kind, direction, index, flag, null, null, null);
}

fn emitLayoutActionWithPayload(
    state: *types.RuntimeState,
    kind: u8,
    direction: u8,
    index: i64,
    flag: u8,
    workspace_id: ?types.Uuid,
    window_handle_id: ?types.Uuid,
    secondary_window_handle_id: ?types.Uuid,
) !void {
    var action = abi.OmniControllerLayoutAction{
        .kind = kind,
        .direction = direction,
        .index = index,
        .flag = flag,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_secondary_window_handle_id = 0,
        .secondary_window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    };
    types.writeOptionalUuid(&action.has_workspace_id, &action.workspace_id, workspace_id);
    types.writeOptionalUuid(&action.has_window_handle_id, &action.window_handle_id, window_handle_id);
    types.writeOptionalUuid(
        &action.has_secondary_window_handle_id,
        &action.secondary_window_handle_id,
        secondary_window_handle_id,
    );
    try state.effects.layout_actions.append(state.allocator, action);
}

fn emitFocusCommandRefresh(state: *types.RuntimeState) !void {
    try refresh.pushRefreshPlan(
        state,
        abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
            abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT,
        if (activeWorkspace(state)) |workspace| workspace.workspace_id else null,
        routing.currentMonitorId(state),
    );
}

pub fn handleCommand(state: *types.RuntimeState, command: abi.OmniControllerCommand) !i32 {
    switch (command.kind) {
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_PREVIOUS => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const previous_handle = focus.previousFocusedWindow(
                state,
                current_workspace.workspace_id,
                state.focused_window,
                isWorkspaceWindowValid,
            ) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const previous_window = routing.windowByHandle(state, previous_handle) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const previous_node_id = previous_window.node_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;

            state.focused_window = previous_handle;
            try focus.recordFocus(state, current_workspace.workspace_id, previous_handle);
            try state.selected_node_by_workspace.put(current_workspace.workspace_id, previous_node_id);

            try focus.exportFocus(
                state,
                current_workspace.workspace_id,
                previous_node_id,
                previous_handle,
            );
            try emitDefaultRefresh(state, current_workspace.workspace_id, current_monitor);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_DIRECTION => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_monitor = routing.adjacentMonitor(state, current_monitor, command.direction, false) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_workspace = routing.activeWorkspaceOnMonitor(state, target_monitor.display_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            state.previous_monitor = current_monitor;
            state.active_monitor = target_monitor.display_id;
            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_FOCUS_MONITOR,
                current_monitor,
                target_monitor.display_id,
                activeWorkspace(state),
                target_workspace,
                null,
                false,
                false,
                true,
            );
            try focus.exportFocus(state, target_workspace.workspace_id, target_workspace.selected_node_id, target_workspace.last_focused_window_id);
            try emitDefaultRefresh(state, target_workspace.workspace_id, target_monitor.display_id);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_PREVIOUS,
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_NEXT,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_monitor = if (command.kind == abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_PREVIOUS)
                routing.previousMonitor(state, current_monitor)
            else
                routing.nextMonitor(state, current_monitor) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const resolved_target_monitor = target_monitor orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_workspace = routing.activeWorkspaceOnMonitor(state, resolved_target_monitor.display_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            state.previous_monitor = current_monitor;
            state.active_monitor = resolved_target_monitor.display_id;
            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_FOCUS_MONITOR,
                current_monitor,
                resolved_target_monitor.display_id,
                activeWorkspace(state),
                target_workspace,
                null,
                false,
                false,
                true,
            );
            try focus.exportFocus(state, target_workspace.workspace_id, target_workspace.selected_node_id, target_workspace.last_focused_window_id);
            try emitDefaultRefresh(state, target_workspace.workspace_id, resolved_target_monitor.display_id);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_LAST => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const previous_monitor = state.previous_monitor orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_workspace = routing.activeWorkspaceOnMonitor(state, previous_monitor) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            state.previous_monitor = current_monitor;
            state.active_monitor = previous_monitor;
            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_FOCUS_MONITOR,
                current_monitor,
                previous_monitor,
                activeWorkspace(state),
                target_workspace,
                null,
                false,
                false,
                true,
            );
            try focus.exportFocus(state, target_workspace.workspace_id, target_workspace.selected_node_id, target_workspace.last_focused_window_id);
            try emitDefaultRefresh(state, target_workspace.workspace_id, previous_monitor);
        },
        abi.OMNI_CONTROLLER_COMMAND_SET_ACTIVE_WORKSPACE_ON_MONITOR => {
            const target_workspace = (if (command.has_workspace_id != 0)
                routing.workspaceById(state, command.workspace_id.bytes)
            else
                null) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (command.workspace_index < 0 or command.workspace_index > std.math.maxInt(u32)) {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            const target_display_id: u32 = @intCast(command.workspace_index);
            var monitor_exists = false;
            for (state.monitors.items) |monitor| {
                if (monitor.display_id == target_display_id) {
                    monitor_exists = true;
                    break;
                }
            }
            if (!monitor_exists) {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }

            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE,
                target_display_id,
                target_display_id,
                routing.activeWorkspaceOnMonitor(state, target_display_id),
                target_workspace,
                null,
                false,
                false,
                true,
            );
            try emitDefaultRefresh(state, target_workspace.workspace_id, target_display_id);
        },
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX,
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE,
        abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state);
            var target_name_buffer: [32]u8 = undefined;
            var has_target_name_buffer = false;
            const explicit_target = if (command.has_workspace_id != 0)
                routing.workspaceById(state, command.workspace_id.bytes)
            else
                null;
            if (command.has_workspace_id != 0 and explicit_target == null) {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            if (command.has_workspace_id == 0) {
                target_name_buffer = workspaceNameFromIndex(command.workspace_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                has_target_name_buffer = true;
            }
            const target_name = if (explicit_target) |workspace|
                types.nameSlice(workspace.name)
            else blk: {
                if (!has_target_name_buffer) {
                    return abi.OMNI_ERR_OUT_OF_RANGE;
                }
                const len = std.mem.indexOfScalar(u8, &target_name_buffer, 0) orelse target_name_buffer.len;
                break :blk target_name_buffer[0..len];
            };
            const existing_target = explicit_target orelse routing.workspaceByName(state, target_name);
            const create_if_missing = shouldCreateWorkspaceForCommand(command) and existing_target == null;
            const target_monitor = targetMonitorForWorkspaceCommand(
                state,
                command.kind,
                current_monitor,
                existing_target,
            ) orelse if (create_if_missing)
                current_monitor
            else
                return abi.OMNI_ERR_OUT_OF_RANGE;
            const route_kind = routeKindForWorkspaceCommand(command.kind) orelse return abi.OMNI_ERR_INVALID_ARGS;

            if (target_monitor != current_monitor) {
                state.previous_monitor = current_monitor;
            }

            state.active_monitor = target_monitor;
            try routing.pushRoutePlan(
                state,
                route_kind,
                current_monitor,
                target_monitor,
                current_workspace,
                existing_target,
                target_name,
                create_if_missing,
                true,
                true,
            );
            try emitWorkspaceFocusOrClear(state, existing_target);
            try emitWorkspaceSwitchAnimationIfNeeded(
                state,
                current_workspace,
                existing_target,
                target_monitor,
            );
            try emitDefaultRefresh(
                state,
                if (existing_target) |workspace| workspace.workspace_id else null,
                target_monitor,
            );
        },
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_NEXT,
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_PREVIOUS,
        abi.OMNI_CONTROLLER_COMMAND_WORKSPACE_BACK_AND_FORTH,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_workspace = switch (command.kind) {
                abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_NEXT => routing.nextWorkspaceInOrder(state, current_monitor, current_workspace.workspace_id, 1, true),
                abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_PREVIOUS => routing.nextWorkspaceInOrder(state, current_monitor, current_workspace.workspace_id, -1, true),
                abi.OMNI_CONTROLLER_COMMAND_WORKSPACE_BACK_AND_FORTH => routing.previousWorkspaceOnMonitor(state, current_monitor),
                else => null,
            } orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE,
                current_monitor,
                current_monitor,
                current_workspace,
                target_workspace,
                null,
                false,
                true,
                true,
            );
            try emitWorkspaceFocusOrClear(state, target_workspace);
            try emitWorkspaceSwitchAnimationIfNeeded(
                state,
                current_workspace,
                target_workspace,
                current_monitor,
            );
            try emitDefaultRefresh(state, target_workspace.workspace_id, current_monitor);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_HANDLE => {
            const target_window_id = types.optionalUuid(
                command.has_window_handle_id,
                command.window_handle_id,
            ) orelse return abi.OMNI_ERR_INVALID_ARGS;
            const target_window = routing.windowByHandle(state, target_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (!target_window.is_managed or target_window.is_hidden) {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state);
            const target_workspace = routing.workspaceById(state, target_window.workspace_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_monitor = routing.monitorForWorkspace(state, target_workspace.workspace_id) orelse current_monitor;

            if (target_monitor != current_monitor) {
                state.previous_monitor = current_monitor;
            }
            state.active_monitor = target_monitor;
            state.non_managed_focus_active = false;
            state.app_fullscreen_active = false;
            state.focused_window = target_window_id;
            try focus.recordFocus(state, target_workspace.workspace_id, target_window_id);
            if (target_window.node_id) |node_id| {
                try state.selected_node_by_workspace.put(target_workspace.workspace_id, node_id);
            }

            if (current_workspace == null or
                !std.mem.eql(u8, &current_workspace.?.workspace_id, &target_workspace.workspace_id) or
                target_monitor != current_monitor)
            {
                try routing.pushRoutePlan(
                    state,
                    abi.OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE,
                    current_monitor,
                    target_monitor,
                    current_workspace,
                    target_workspace,
                    null,
                    false,
                    true,
                    true,
                );
                try emitWorkspaceSwitchAnimationIfNeeded(
                    state,
                    current_workspace,
                    target_workspace,
                    target_monitor,
                );
            }

            try focus.exportFocus(
                state,
                target_workspace.workspace_id,
                target_window.node_id orelse target_workspace.selected_node_id,
                target_window_id,
            );
            try emitDefaultRefresh(state, target_workspace.workspace_id, target_monitor);
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_DIRECTION,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_NEXT,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_PREVIOUS,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_monitor = switch (command.kind) {
                abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_DIRECTION => routing.adjacentMonitor(state, current_monitor, command.direction, false),
                abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_NEXT => routing.nextMonitor(state, current_monitor),
                abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_PREVIOUS => routing.previousMonitor(state, current_monitor),
                else => null,
            } orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            state.previous_monitor = current_monitor;
            state.active_monitor = target_monitor.display_id;
            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_MOVE_WORKSPACE_TO_MONITOR,
                current_monitor,
                target_monitor.display_id,
                current_workspace,
                routing.activeWorkspaceOnMonitor(state, target_monitor.display_id),
                null,
                false,
                false,
                true,
            );
            try focus.exportFocus(
                state,
                current_workspace.workspace_id,
                current_workspace.selected_node_id,
                current_workspace.last_focused_window_id,
            );
            try emitDefaultRefresh(state, current_workspace.workspace_id, target_monitor.display_id);
        },
        abi.OMNI_CONTROLLER_COMMAND_SWAP_WORKSPACE_WITH_MONITOR_DIRECTION => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_monitor = routing.adjacentMonitor(state, current_monitor, command.direction, false) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_workspace = routing.activeWorkspaceOnMonitor(state, target_monitor.display_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            try routing.pushRoutePlan(
                state,
                abi.OMNI_CONTROLLER_ROUTE_SWAP_WORKSPACES,
                current_monitor,
                target_monitor.display_id,
                current_workspace,
                target_workspace,
                null,
                false,
                false,
                true,
            );
            try focus.exportFocus(
                state,
                target_workspace.workspace_id,
                target_workspace.selected_node_id,
                target_workspace.last_focused_window_id,
            );
            try emitDefaultRefresh(state, current_workspace.workspace_id, target_monitor.display_id);
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_UP,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_MONITOR_DIRECTION,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_WINDOW_TO_WORKSPACE_ON_MONITOR,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const explicit_source_window = types.optionalUuid(command.has_window_handle_id, command.window_handle_id);
            const explicit_target_workspace = if (command.has_workspace_id != 0)
                routing.workspaceById(state, command.workspace_id.bytes)
            else
                null;
            var target_workspace_name_buf: ?[32]u8 = null;
            var target_workspace: ?types.Workspace = explicit_target_workspace;
            var target_monitor_display_id: ?u32 = null;
            var create_if_missing = false;

            switch (command.kind) {
                abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX => {
                    if (explicit_target_workspace == null) {
                        target_workspace_name_buf = workspaceNameFromIndex(command.workspace_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                        const len = std.mem.indexOfScalar(u8, &target_workspace_name_buf.?, 0) orelse target_workspace_name_buf.?.len;
                        target_workspace = routing.workspaceByName(state, target_workspace_name_buf.?[0..len]);
                        create_if_missing = true;
                    }
                    target_monitor_display_id = if (target_workspace) |workspace|
                        routing.monitorForWorkspace(state, workspace.workspace_id)
                    else
                        current_monitor;
                },
                abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_UP,
                abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN,
                => {
                    const current_ordinal = types.parseWorkspaceOrdinal(current_workspace.name) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    const target_ordinal = if (command.kind == abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN)
                        current_ordinal + 1
                    else if (current_ordinal > 1)
                        current_ordinal - 1
                    else
                        return abi.OMNI_ERR_OUT_OF_RANGE;
                    target_workspace_name_buf = workspaceNameFromIndex(@intCast(target_ordinal - 1)) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    const len = std.mem.indexOfScalar(u8, &target_workspace_name_buf.?, 0) orelse target_workspace_name_buf.?.len;
                    target_workspace = routing.workspaceByName(state, target_workspace_name_buf.?[0..len]);
                    create_if_missing = target_workspace == null;
                    target_monitor_display_id = current_monitor;
                },
                abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_MONITOR_DIRECTION => {
                    const target_monitor = routing.adjacentMonitor(state, current_monitor, command.direction, false) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    target_monitor_display_id = target_monitor.display_id;
                    target_workspace = routing.activeWorkspaceOnMonitor(state, target_monitor.display_id);
                    if (target_workspace) |workspace| {
                        target_workspace_name_buf = undefined;
                        _ = workspace;
                    } else {
                        return abi.OMNI_ERR_OUT_OF_RANGE;
                    }
                },
                abi.OMNI_CONTROLLER_COMMAND_MOVE_WINDOW_TO_WORKSPACE_ON_MONITOR => {
                    const target_monitor = routing.adjacentMonitor(state, current_monitor, command.monitor_direction, false) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    target_monitor_display_id = target_monitor.display_id;
                    target_workspace_name_buf = workspaceNameFromIndex(command.workspace_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    const len = std.mem.indexOfScalar(u8, &target_workspace_name_buf.?, 0) orelse target_workspace_name_buf.?.len;
                    target_workspace = routing.workspaceByName(state, target_workspace_name_buf.?[0..len]);
                    create_if_missing = true;
                },
                else => {},
            }

            const target_name: []const u8 = if (target_workspace) |workspace|
                types.nameSlice(workspace.name)
            else blk: {
                const buffer = target_workspace_name_buf orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const len = std.mem.indexOfScalar(u8, &buffer, 0) orelse buffer.len;
                break :blk buffer[0..len];
            };

            const rc = try transfer.pushTransferPlan(
                state,
                abi.OMNI_CONTROLLER_TRANSFER_MOVE_WINDOW,
                explicit_source_window,
                target_workspace,
                target_name,
                create_if_missing,
                target_monitor_display_id,
                state.focus_follows_window_to_monitor,
            );
            if (rc != abi.OMNI_OK) {
                return rc;
            }
            try emitDefaultRefresh(
                state,
                if (target_workspace) |workspace| workspace.workspace_id else null,
                target_monitor_display_id,
            );
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_WORKSPACE_INDEX,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_UP,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN,
        abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_MONITOR_DIRECTION,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const explicit_target_workspace = if (command.has_workspace_id != 0)
                routing.workspaceById(state, command.workspace_id.bytes)
            else
                null;
            var target_workspace_name_buf: ?[32]u8 = null;
            var target_workspace: ?types.Workspace = explicit_target_workspace;
            var target_monitor_display_id: ?u32 = current_monitor;
            var create_if_missing = false;

            switch (command.kind) {
                abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_WORKSPACE_INDEX => {
                    if (explicit_target_workspace == null) {
                        target_workspace_name_buf = workspaceNameFromIndex(command.workspace_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                        const len = std.mem.indexOfScalar(u8, &target_workspace_name_buf.?, 0) orelse target_workspace_name_buf.?.len;
                        target_workspace = routing.workspaceByName(state, target_workspace_name_buf.?[0..len]);
                        create_if_missing = true;
                    }
                },
                abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_UP,
                abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN,
                => {
                    const current_ordinal = types.parseWorkspaceOrdinal(current_workspace.name) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    const target_ordinal = if (command.kind == abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN)
                        current_ordinal + 1
                    else if (current_ordinal > 1)
                        current_ordinal - 1
                    else
                        return abi.OMNI_ERR_OUT_OF_RANGE;
                    target_workspace_name_buf = workspaceNameFromIndex(@intCast(target_ordinal - 1)) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    const len = std.mem.indexOfScalar(u8, &target_workspace_name_buf.?, 0) orelse target_workspace_name_buf.?.len;
                    target_workspace = routing.workspaceByName(state, target_workspace_name_buf.?[0..len]);
                    create_if_missing = true;
                },
                abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_MONITOR_DIRECTION => {
                    const target_monitor = routing.adjacentMonitor(state, current_monitor, command.direction, false) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    target_monitor_display_id = target_monitor.display_id;
                    target_workspace = routing.activeWorkspaceOnMonitor(state, target_monitor.display_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                },
                else => {},
            }

            const target_name: []const u8 = if (target_workspace) |workspace|
                types.nameSlice(workspace.name)
            else blk: {
                const buffer = target_workspace_name_buf orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const len = std.mem.indexOfScalar(u8, &buffer, 0) orelse buffer.len;
                break :blk buffer[0..len];
            };
            const rc = try transfer.pushTransferPlan(
                state,
                abi.OMNI_CONTROLLER_TRANSFER_MOVE_COLUMN,
                null,
                target_workspace,
                target_name,
                create_if_missing,
                target_monitor_display_id,
                true,
            );
            if (rc != abi.OMNI_OK) {
                return rc;
            }
            try emitDefaultRefresh(
                state,
                if (target_workspace) |workspace| workspace.workspace_id else null,
                target_monitor_display_id,
            );
        },
        abi.OMNI_CONTROLLER_COMMAND_OPEN_WINDOW_FINDER,
        abi.OMNI_CONTROLLER_COMMAND_RAISE_ALL_FLOATING_WINDOWS,
        abi.OMNI_CONTROLLER_COMMAND_OPEN_MENU_ANYWHERE,
        abi.OMNI_CONTROLLER_COMMAND_OPEN_MENU_PALETTE,
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_HIDDEN_BAR,
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_QUAKE_TERMINAL,
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_OVERVIEW,
        => {
            const ui_kind: u8 = switch (command.kind) {
                abi.OMNI_CONTROLLER_COMMAND_OPEN_WINDOW_FINDER => abi.OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER,
                abi.OMNI_CONTROLLER_COMMAND_RAISE_ALL_FLOATING_WINDOWS => abi.OMNI_CONTROLLER_UI_RAISE_ALL_FLOATING_WINDOWS,
                abi.OMNI_CONTROLLER_COMMAND_OPEN_MENU_ANYWHERE => abi.OMNI_CONTROLLER_UI_OPEN_MENU_ANYWHERE,
                abi.OMNI_CONTROLLER_COMMAND_OPEN_MENU_PALETTE => abi.OMNI_CONTROLLER_UI_OPEN_MENU_PALETTE,
                abi.OMNI_CONTROLLER_COMMAND_TOGGLE_HIDDEN_BAR => abi.OMNI_CONTROLLER_UI_TOGGLE_HIDDEN_BAR,
                abi.OMNI_CONTROLLER_COMMAND_TOGGLE_QUAKE_TERMINAL => abi.OMNI_CONTROLLER_UI_TOGGLE_QUAKE_TERMINAL,
                abi.OMNI_CONTROLLER_COMMAND_TOGGLE_OVERVIEW => abi.OMNI_CONTROLLER_UI_TOGGLE_OVERVIEW,
                else => abi.OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER,
            };
            try state.effects.ui_actions.append(state.allocator, .{ .kind = ui_kind });
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION => {
            if (activeWorkspaceLayoutKind(state) == null) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION, command.direction, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_SWAP_DIRECTION => {
            if (activeWorkspaceLayoutKind(state) == null) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_FULLSCREEN, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_NATIVE_FULLSCREEN => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_NATIVE_FULLSCREEN, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_DIRECTION => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_CONSUME_WINDOW_DIRECTION => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_CONSUME_WINDOW_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_EXPEL_WINDOW_DIRECTION => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_EXPEL_WINDOW_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_TABBED => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT, 0, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT, 0, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST, 0, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST, 0, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX, 0, command.workspace_index, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP, 0, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM, 0, 0, 0);
            try emitFocusCommandRefresh(state);
        },
        abi.OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_FORWARD => {
            if (activeWorkspaceLayoutKind(state) == null) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_BACKWARD => {
            if (activeWorkspaceLayoutKind(state) == null) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_FULL_WIDTH => {
            if (!niriLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_BALANCE_SIZES => {
            if (activeWorkspaceLayoutKind(state) == null) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT => {
            if (!dwindleLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT => {
            if (!dwindleLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT => {
            if (!dwindleLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION => {
            if (!dwindleLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(
                state,
                abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION,
                command.direction,
                0,
                command.monitor_direction,
            );
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION => {
            if (!dwindleLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(
                state,
                abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION,
                command.direction,
                0,
                0,
            );
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR => {
            if (!dwindleLayoutActive(state)) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT => {
            if (activeWorkspace(state) == null) return abi.OMNI_OK;
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW => {
            const workspace_id = types.optionalUuid(command.has_workspace_id, command.workspace_id) orelse return abi.OMNI_ERR_INVALID_ARGS;
            const source_window_id = types.optionalUuid(command.has_window_handle_id, command.window_handle_id) orelse return abi.OMNI_ERR_INVALID_ARGS;
            const target_window_id = types.optionalUuid(
                command.has_secondary_window_handle_id,
                command.secondary_window_handle_id,
            ) orelse return abi.OMNI_ERR_INVALID_ARGS;
            const target_workspace = routing.workspaceById(state, workspace_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (effectiveLayoutKind(target_workspace.layout_kind) != .niri) return abi.OMNI_OK;
            const source_window = routing.windowByHandle(state, source_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const target_window = routing.windowByHandle(state, target_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (!source_window.is_managed or source_window.is_hidden or
                !target_window.is_managed or target_window.is_hidden)
            {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            if (!std.mem.eql(u8, &source_window.workspace_id, &workspace_id) or
                !std.mem.eql(u8, &target_window.workspace_id, &workspace_id))
            {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            if (command.monitor_direction != abi.OMNI_NIRI_INSERT_BEFORE and
                command.monitor_direction != abi.OMNI_NIRI_INSERT_AFTER and
                command.monitor_direction != abi.OMNI_NIRI_INSERT_SWAP)
            {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
            try emitLayoutActionWithPayload(
                state,
                abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW,
                0,
                0,
                command.monitor_direction,
                workspace_id,
                source_window_id,
                target_window_id,
            );
            try emitDefaultRefresh(
                state,
                workspace_id,
                routing.monitorForWorkspace(state, workspace_id),
            );
        },
        abi.OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN => {
            const workspace_id = types.optionalUuid(command.has_workspace_id, command.workspace_id) orelse return abi.OMNI_ERR_INVALID_ARGS;
            const source_window_id = types.optionalUuid(command.has_window_handle_id, command.window_handle_id) orelse return abi.OMNI_ERR_INVALID_ARGS;
            const target_workspace = routing.workspaceById(state, workspace_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (effectiveLayoutKind(target_workspace.layout_kind) != .niri) return abi.OMNI_OK;
            const source_window = routing.windowByHandle(state, source_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (!source_window.is_managed or source_window.is_hidden or
                !std.mem.eql(u8, &source_window.workspace_id, &workspace_id))
            {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            try emitLayoutActionWithPayload(
                state,
                abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN,
                0,
                command.workspace_index,
                0,
                workspace_id,
                source_window_id,
                null,
            );
            try emitDefaultRefresh(
                state,
                workspace_id,
                routing.monitorForWorkspace(state, workspace_id),
            );
        },
        else => return abi.OMNI_ERR_OUT_OF_RANGE,
    }
    return abi.OMNI_OK;
}

test "focus layout commands queue immediate refresh plans" {
    const focus_cases = [_]struct {
        kind: u8,
        direction: u8,
        workspace_index: i64,
        expected_layout_kind: u8,
        expected_direction: u8,
        expected_index: i64,
    }{
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION,
            .direction = abi.OMNI_NIRI_DIRECTION_RIGHT,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION,
            .expected_direction = abi.OMNI_NIRI_DIRECTION_RIGHT,
            .expected_index = 0,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT,
            .direction = 0,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT,
            .expected_direction = 0,
            .expected_index = 0,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT,
            .direction = 0,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT,
            .expected_direction = 0,
            .expected_index = 0,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST,
            .direction = 0,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST,
            .expected_direction = 0,
            .expected_index = 0,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST,
            .direction = 0,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST,
            .expected_direction = 0,
            .expected_index = 0,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX,
            .direction = 0,
            .workspace_index = 3,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX,
            .expected_direction = 0,
            .expected_index = 3,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP,
            .direction = 0,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP,
            .expected_direction = 0,
            .expected_index = 0,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM,
            .direction = 0,
            .workspace_index = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM,
            .expected_direction = 0,
            .expected_index = 0,
        },
    };

    for (focus_cases) |case| {
        var state = types.RuntimeState.init(std.testing.allocator);
        defer state.deinit();

        try state.monitors.append(std.testing.allocator, .{
            .display_id = 11,
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
            .workspace_id = [_]u8{1} ** 16,
            .assigned_display_id = 11,
            .is_visible = true,
            .is_previous_visible = false,
            .layout_kind = .niri,
            .name = types.encodeName("1"),
            .selected_node_id = null,
            .last_focused_window_id = null,
        });
        state.active_monitor = 11;

        const rc = try handleCommand(&state, .{
            .kind = case.kind,
            .direction = case.direction,
            .workspace_index = case.workspace_index,
            .monitor_direction = 0,
            .has_workspace_id = 0,
            .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_window_handle_id = 0,
            .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        });

        try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
        try std.testing.expectEqual(@as(usize, 1), state.effects.layout_actions.items.len);
        try std.testing.expectEqual(@as(usize, 1), state.effects.refresh_plans.items.len);
        try std.testing.expectEqual(case.expected_layout_kind, state.effects.layout_actions.items[0].kind);
        try std.testing.expectEqual(case.expected_direction, state.effects.layout_actions.items[0].direction);
        try std.testing.expectEqual(case.expected_index, state.effects.layout_actions.items[0].index);
        try std.testing.expectEqual(
            @as(u32, abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
                abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
                abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT),
            state.effects.refresh_plans.items[0].flags,
        );
        try std.testing.expectEqual(@as(u8, 1), state.effects.refresh_plans.items[0].has_display_id);
        try std.testing.expectEqual(@as(u32, 11), state.effects.refresh_plans.items[0].display_id);
        try std.testing.expectEqual(@as(u8, 1), state.effects.refresh_plans.items[0].has_workspace_id);
    }
}

test "dwindle and layout toggle commands emit layout actions" {
    const layout_cases = [_]struct {
        kind: u8,
        direction: u8,
        flag: u8,
        expected_layout_kind: u8,
        workspace_layout_kind: types.LayoutKind,
    }{
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT,
            .direction = 0,
            .flag = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT,
            .workspace_layout_kind = .dwindle,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT,
            .direction = 0,
            .flag = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT,
            .workspace_layout_kind = .dwindle,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT,
            .direction = 0,
            .flag = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT,
            .workspace_layout_kind = .dwindle,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION,
            .direction = abi.OMNI_NIRI_DIRECTION_RIGHT,
            .flag = 1,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION,
            .workspace_layout_kind = .dwindle,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION,
            .direction = abi.OMNI_NIRI_DIRECTION_LEFT,
            .flag = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION,
            .workspace_layout_kind = .dwindle,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR,
            .direction = 0,
            .flag = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR,
            .workspace_layout_kind = .dwindle,
        },
        .{
            .kind = abi.OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT,
            .direction = 0,
            .flag = 0,
            .expected_layout_kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT,
            .workspace_layout_kind = .niri,
        },
    };

    for (layout_cases) |case| {
        var state = types.RuntimeState.init(std.testing.allocator);
        defer state.deinit();

        try state.monitors.append(std.testing.allocator, .{
            .display_id = 11,
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
            .workspace_id = [_]u8{1} ** 16,
            .assigned_display_id = 11,
            .is_visible = true,
            .is_previous_visible = false,
            .layout_kind = case.workspace_layout_kind,
            .name = types.encodeName("1"),
            .selected_node_id = null,
            .last_focused_window_id = null,
        });
        state.active_monitor = 11;

        const rc = try handleCommand(&state, .{
            .kind = case.kind,
            .direction = case.direction,
            .workspace_index = 0,
            .monitor_direction = case.flag,
            .has_workspace_id = 0,
            .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_window_handle_id = 0,
            .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
        });

        try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
        try std.testing.expectEqual(@as(usize, 1), state.effects.layout_actions.items.len);
        try std.testing.expectEqual(@as(usize, 0), state.effects.refresh_plans.items.len);
        try std.testing.expectEqual(case.expected_layout_kind, state.effects.layout_actions.items[0].kind);
        try std.testing.expectEqual(case.direction, state.effects.layout_actions.items[0].direction);
        try std.testing.expectEqual(case.flag, state.effects.layout_actions.items[0].flag);
    }
}

test "layout-incompatible commands no-op" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 11,
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
        .workspace_id = [_]u8{1} ** 16,
        .assigned_display_id = 11,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .dwindle,
        .name = types.encodeName("1"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    state.active_monitor = 11;

    const niri_rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION,
        .direction = abi.OMNI_NIRI_DIRECTION_RIGHT,
        .workspace_index = 0,
        .monitor_direction = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), niri_rc);
    try std.testing.expectEqual(@as(usize, 0), state.effects.layout_actions.items.len);

    const dwindle_rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT,
        .direction = 0,
        .workspace_index = 0,
        .monitor_direction = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), dwindle_rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.layout_actions.items.len);

    state.effects.clear();
    state.workspaces.items[0].layout_kind = .niri;

    const dwindle_on_niri_rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT,
        .direction = 0,
        .workspace_index = 0,
        .monitor_direction = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), dwindle_on_niri_rc);
    try std.testing.expectEqual(@as(usize, 0), state.effects.layout_actions.items.len);
}

test "overview insert commands emit layout actions with payload" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    const workspace_id = [_]u8{1} ** 16;
    const source_handle = [_]u8{2} ** 16;
    const target_handle = [_]u8{3} ** 16;

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 11,
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
        .assigned_display_id = 11,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    try state.windows.append(std.testing.allocator, .{
        .handle_id = source_handle,
        .pid = 10,
        .window_id = 100,
        .workspace_id = workspace_id,
        .layout_kind = .niri,
        .is_hidden = false,
        .is_focused = false,
        .is_managed = true,
        .node_id = source_handle,
        .column_id = source_handle,
        .order_index = 0,
        .column_index = 0,
        .row_index = 0,
    });
    try state.windows.append(std.testing.allocator, .{
        .handle_id = target_handle,
        .pid = 10,
        .window_id = 101,
        .workspace_id = workspace_id,
        .layout_kind = .niri,
        .is_hidden = false,
        .is_focused = false,
        .is_managed = true,
        .node_id = target_handle,
        .column_id = target_handle,
        .order_index = 1,
        .column_index = 1,
        .row_index = 0,
    });
    state.active_monitor = 11;

    const insert_rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW,
        .direction = 0,
        .workspace_index = 0,
        .monitor_direction = abi.OMNI_NIRI_INSERT_AFTER,
        .has_workspace_id = 1,
        .workspace_id = .{ .bytes = workspace_id },
        .has_window_handle_id = 1,
        .window_handle_id = .{ .bytes = source_handle },
        .has_secondary_window_handle_id = 1,
        .secondary_window_handle_id = .{ .bytes = target_handle },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), insert_rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.layout_actions.items.len);
    try std.testing.expectEqual(abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW, state.effects.layout_actions.items[0].kind);
    try std.testing.expectEqual(@as(u8, 1), state.effects.layout_actions.items[0].has_workspace_id);
    try std.testing.expectEqual(workspace_id, state.effects.layout_actions.items[0].workspace_id.bytes);
    try std.testing.expectEqual(source_handle, state.effects.layout_actions.items[0].window_handle_id.bytes);
    try std.testing.expectEqual(target_handle, state.effects.layout_actions.items[0].secondary_window_handle_id.bytes);
    try std.testing.expectEqual(@as(u8, abi.OMNI_NIRI_INSERT_AFTER), state.effects.layout_actions.items[0].flag);

    state.effects.clear();

    const new_column_rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN,
        .direction = 0,
        .workspace_index = 3,
        .monitor_direction = 0,
        .has_workspace_id = 1,
        .workspace_id = .{ .bytes = workspace_id },
        .has_window_handle_id = 1,
        .window_handle_id = .{ .bytes = source_handle },
        .has_secondary_window_handle_id = 0,
        .secondary_window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), new_column_rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.layout_actions.items.len);
    try std.testing.expectEqual(abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN, state.effects.layout_actions.items[0].kind);
    try std.testing.expectEqual(@as(i64, 3), state.effects.layout_actions.items[0].index);
    try std.testing.expectEqual(source_handle, state.effects.layout_actions.items[0].window_handle_id.bytes);
}

test "focus window handle command exports focus and routes workspace when needed" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 11,
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
    try state.monitors.append(std.testing.allocator, .{
        .display_id = 22,
        .is_main = false,
        .frame_x = 100,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 100,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("Side"),
    });

    const source_workspace_id = [_]u8{1} ** 16;
    const target_workspace_id = [_]u8{2} ** 16;
    const target_handle = [_]u8{9} ** 16;
    const target_node = [_]u8{7} ** 16;

    try state.workspaces.append(std.testing.allocator, .{
        .workspace_id = source_workspace_id,
        .assigned_display_id = 11,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    try state.workspaces.append(std.testing.allocator, .{
        .workspace_id = target_workspace_id,
        .assigned_display_id = 22,
        .is_visible = false,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("2"),
        .selected_node_id = target_node,
        .last_focused_window_id = null,
    });
    try state.windows.append(std.testing.allocator, .{
        .handle_id = target_handle,
        .pid = 12,
        .window_id = 44,
        .workspace_id = target_workspace_id,
        .layout_kind = .niri,
        .is_hidden = false,
        .is_focused = false,
        .is_managed = true,
        .node_id = target_node,
        .column_id = null,
        .order_index = 0,
        .column_index = 0,
        .row_index = 0,
    });
    state.active_monitor = 11;

    const rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_HANDLE,
        .direction = 0,
        .workspace_index = 0,
        .monitor_direction = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 1,
        .window_handle_id = .{ .bytes = target_handle },
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(target_handle, state.focused_window.?);
    try std.testing.expectEqual(@as(u32, 22), state.active_monitor.?);
    try std.testing.expectEqual(@as(usize, 1), state.effects.route_plans.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.effects.focus_exports.items.len);
    try std.testing.expectEqual(@as(usize, 3), state.effects.refresh_plans.items.len);
    try std.testing.expectEqual(target_handle, state.effects.focus_exports.items[0].focused_window_id.bytes);
    try std.testing.expectEqual(target_workspace_id, state.effects.focus_exports.items[0].workspace_id.bytes);
    try std.testing.expectEqual(target_node, state.effects.focus_exports.items[0].selected_node_id.bytes);
}

test "set active workspace on monitor command emits route without focus export" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 11,
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
    try state.monitors.append(std.testing.allocator, .{
        .display_id = 22,
        .is_main = false,
        .frame_x = 100,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 100,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("Side"),
    });

    const current_workspace_id = [_]u8{1} ** 16;
    const target_workspace_id = [_]u8{2} ** 16;

    try state.workspaces.append(std.testing.allocator, .{
        .workspace_id = current_workspace_id,
        .assigned_display_id = 22,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    try state.workspaces.append(std.testing.allocator, .{
        .workspace_id = target_workspace_id,
        .assigned_display_id = 11,
        .is_visible = false,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("2"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });

    const rc = try handleCommand(&state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_SET_ACTIVE_WORKSPACE_ON_MONITOR,
        .direction = 0,
        .workspace_index = 22,
        .monitor_direction = 0,
        .has_workspace_id = 1,
        .workspace_id = .{ .bytes = target_workspace_id },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), state.effects.route_plans.items.len);
    try std.testing.expectEqual(abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE, state.effects.route_plans.items[0].kind);
    try std.testing.expectEqual(@as(u8, 1), state.effects.route_plans.items[0].has_target_display_id);
    try std.testing.expectEqual(@as(u32, 22), state.effects.route_plans.items[0].target_display_id);
    try std.testing.expectEqual(@as(usize, 0), state.effects.focus_exports.items.len);
    try std.testing.expect(state.effects.refresh_plans.items.len > 0);
}
