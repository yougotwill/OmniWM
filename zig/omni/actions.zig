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
    try state.effects.layout_actions.append(state.allocator, .{
        .kind = kind,
        .direction = direction,
        .index = index,
        .flag = flag,
    });
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
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX,
        abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE,
        abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE,
        => {
            const current_monitor = routing.currentMonitorId(state) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const current_workspace = activeWorkspace(state);
            var target_name_buffer: ?[32]u8 = null;
            const explicit_target = if (command.has_workspace_id != 0)
                routing.workspaceById(state, command.workspace_id.bytes)
            else
                null;
            if (command.has_workspace_id == 0) {
                target_name_buffer = workspaceNameFromIndex(command.workspace_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            const target_name = if (explicit_target) |workspace|
                types.nameSlice(workspace.name)
            else blk: {
                const name_buffer = target_name_buffer orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const len = std.mem.indexOfScalar(u8, &name_buffer, 0) orelse name_buffer.len;
                break :blk name_buffer[0..len];
            };
            const existing_target = explicit_target orelse routing.workspaceByName(state, target_name);
            const target_monitor = if (existing_target) |workspace|
                routing.monitorForWorkspace(state, workspace.workspace_id)
            else
                current_monitor;

            if (command.kind == abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE and
                existing_target != null and target_monitor == current_monitor)
            {
                return handleCommand(state, .{
                    .kind = abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX,
                    .direction = 0,
                    .workspace_index = command.workspace_index,
                    .monitor_direction = 0,
                    .has_workspace_id = 0,
                    .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
                    .has_window_handle_id = 0,
                    .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
                });
            }

            if (target_monitor) |resolved_target_monitor| {
                if (resolved_target_monitor != current_monitor) {
                    state.previous_monitor = current_monitor;
                }
                state.active_monitor = resolved_target_monitor;
                const route_kind: u8 = switch (command.kind) {
                    abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX => abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE,
                    abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE => abi.OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE,
                    abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE => abi.OMNI_CONTROLLER_ROUTE_SUMMON_WORKSPACE,
                    else => abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE,
                };
                try routing.pushRoutePlan(
                    state,
                    route_kind,
                    current_monitor,
                    resolved_target_monitor,
                    current_workspace,
                    existing_target,
                    target_name,
                    existing_target == null,
                    true,
                    true,
                );
                try emitWorkspaceFocusOrClear(state, existing_target);
                try emitWorkspaceSwitchAnimationIfNeeded(
                    state,
                    current_workspace,
                    existing_target,
                    resolved_target_monitor,
                );
                try emitDefaultRefresh(
                    state,
                    if (existing_target) |workspace| workspace.workspace_id else null,
                    resolved_target_monitor,
                );
            }
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
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_SWAP_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_FULLSCREEN, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_NATIVE_FULLSCREEN => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_NATIVE_FULLSCREEN, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_CONSUME_WINDOW_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_CONSUME_WINDOW_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_EXPEL_WINDOW_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_EXPEL_WINDOW_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_TABBED => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX, 0, command.workspace_index, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_FORWARD => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_BACKWARD => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_FULL_WIDTH => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_BALANCE_SIZES => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION, command.direction, 0, command.monitor_direction);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION, command.direction, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR, 0, 0, 0);
        },
        abi.OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT => {
            try emitLayoutAction(state, abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT, 0, 0, 0);
        },
        else => return abi.OMNI_ERR_OUT_OF_RANGE,
    }
    return abi.OMNI_OK;
}
