const std = @import("std");
const abi = @import("abi_types.zig");
const types = @import("controller_types.zig");

pub fn currentMonitorId(state: *const types.RuntimeState) ?u32 {
    if (state.active_monitor) |display_id| {
        return display_id;
    }
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

pub fn monitorForWorkspace(state: *const types.RuntimeState, workspace_id: types.Uuid) ?u32 {
    for (state.workspaces.items) |workspace| {
        if (std.mem.eql(u8, &workspace.workspace_id, &workspace_id)) {
            return workspace.assigned_display_id;
        }
    }
    return null;
}

pub fn activeWorkspaceOnMonitor(state: *const types.RuntimeState, display_id: u32) ?types.Workspace {
    var first_match: ?types.Workspace = null;
    for (state.workspaces.items) |workspace| {
        if (workspace.assigned_display_id != display_id) {
            continue;
        }
        if (first_match == null) {
            first_match = workspace;
        }
        if (workspace.is_visible) {
            return workspace;
        }
    }
    return first_match;
}

pub fn previousWorkspaceOnMonitor(state: *const types.RuntimeState, display_id: u32) ?types.Workspace {
    for (state.workspaces.items) |workspace| {
        if (workspace.assigned_display_id == display_id and workspace.is_previous_visible) {
            return workspace;
        }
    }
    return null;
}

pub fn workspaceByName(state: *const types.RuntimeState, name: []const u8) ?types.Workspace {
    for (state.workspaces.items) |workspace| {
        if (types.nameEquals(workspace.name, name)) {
            return workspace;
        }
    }
    return null;
}

pub fn workspaceById(state: *const types.RuntimeState, workspace_id: types.Uuid) ?types.Workspace {
    for (state.workspaces.items) |workspace| {
        if (std.mem.eql(u8, &workspace.workspace_id, &workspace_id)) {
            return workspace;
        }
    }
    return null;
}

pub fn windowByHandle(state: *const types.RuntimeState, handle_id: types.Uuid) ?types.Window {
    for (state.windows.items) |window| {
        if (std.mem.eql(u8, &window.handle_id, &handle_id)) {
            return window;
        }
    }
    return null;
}

pub fn firstManagedWindowInWorkspace(state: *const types.RuntimeState, workspace_id: types.Uuid) ?types.Window {
    var best_window: ?types.Window = null;
    for (state.windows.items) |window| {
        if (!std.mem.eql(u8, &window.workspace_id, &workspace_id)) {
            continue;
        }
        if (!window.is_managed or window.is_hidden) {
            continue;
        }
        if (best_window == null or window.order_index < best_window.?.order_index) {
            best_window = window;
        }
    }
    return best_window;
}

pub fn nextWorkspaceInOrder(
    state: *const types.RuntimeState,
    display_id: u32,
    current_workspace_id: types.Uuid,
    offset: i32,
    wrap: bool,
) ?types.Workspace {
    var ordered = std.ArrayListUnmanaged(types.Workspace){};
    defer ordered.deinit(std.heap.page_allocator);

    for (state.workspaces.items) |workspace| {
        if (workspace.assigned_display_id == display_id) {
            ordered.append(std.heap.page_allocator, workspace) catch return null;
        }
    }
    if (ordered.items.len == 0) {
        return null;
    }
    std.sort.insertion(types.Workspace, ordered.items, {}, struct {
        fn lessThan(_: void, lhs: types.Workspace, rhs: types.Workspace) bool {
            return types.logicalWorkspaceLessThan(lhs.name, rhs.name);
        }
    }.lessThan);

    var current_index: ?usize = null;
    for (ordered.items, 0..) |workspace, index| {
        if (std.mem.eql(u8, &workspace.workspace_id, &current_workspace_id)) {
            current_index = index;
            break;
        }
    }
    const resolved_current_index = current_index orelse return null;
    const target_index_signed: i64 = @as(i64, @intCast(resolved_current_index)) + offset;
    if (wrap) {
        const len_signed: i64 = @intCast(ordered.items.len);
        const wrapped = @mod(target_index_signed, len_signed);
        return ordered.items[@intCast(wrapped)];
    }
    if (target_index_signed < 0 or target_index_signed >= ordered.items.len) {
        return null;
    }
    return ordered.items[@intCast(target_index_signed)];
}

fn monitorDelta(from: types.Monitor, to: types.Monitor) struct { dx: f64, dy: f64 } {
    const from_center_x = from.frame_x + (from.frame_width / 2.0);
    const from_center_y = from.frame_y + (from.frame_height / 2.0);
    const to_center_x = to.frame_x + (to.frame_width / 2.0);
    const to_center_y = to.frame_y + (to.frame_height / 2.0);
    return .{ .dx = to_center_x - from_center_x, .dy = to_center_y - from_center_y };
}

fn monitorSortLessThan(lhs: types.Monitor, rhs: types.Monitor) bool {
    if (lhs.frame_x != rhs.frame_x) {
        return lhs.frame_x < rhs.frame_x;
    }
    return (lhs.frame_y + lhs.frame_height) > (rhs.frame_y + rhs.frame_height);
}

fn betterDirectionalCandidate(
    current: types.Monitor,
    lhs: types.Monitor,
    rhs: types.Monitor,
    direction: u8,
) bool {
    const lhs_delta = monitorDelta(current, lhs);
    const rhs_delta = monitorDelta(current, rhs);
    const lhs_primary = switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT, abi.OMNI_NIRI_DIRECTION_RIGHT => @abs(lhs_delta.dx),
        abi.OMNI_NIRI_DIRECTION_UP, abi.OMNI_NIRI_DIRECTION_DOWN => @abs(lhs_delta.dy),
        else => @as(f64, 0),
    };
    const rhs_primary = switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT, abi.OMNI_NIRI_DIRECTION_RIGHT => @abs(rhs_delta.dx),
        abi.OMNI_NIRI_DIRECTION_UP, abi.OMNI_NIRI_DIRECTION_DOWN => @abs(rhs_delta.dy),
        else => @as(f64, 0),
    };
    if (lhs_primary != rhs_primary) {
        return lhs_primary < rhs_primary;
    }
    const lhs_secondary = switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT, abi.OMNI_NIRI_DIRECTION_RIGHT => @abs(lhs_delta.dy),
        abi.OMNI_NIRI_DIRECTION_UP, abi.OMNI_NIRI_DIRECTION_DOWN => @abs(lhs_delta.dx),
        else => @as(f64, 0),
    };
    const rhs_secondary = switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT, abi.OMNI_NIRI_DIRECTION_RIGHT => @abs(rhs_delta.dy),
        abi.OMNI_NIRI_DIRECTION_UP, abi.OMNI_NIRI_DIRECTION_DOWN => @abs(rhs_delta.dx),
        else => @as(f64, 0),
    };
    if (lhs_secondary != rhs_secondary) {
        return lhs_secondary < rhs_secondary;
    }
    return monitorSortLessThan(lhs, rhs);
}

pub fn adjacentMonitor(state: *const types.RuntimeState, from_display_id: u32, direction: u8, wrap: bool) ?types.Monitor {
    var current_monitor: ?types.Monitor = null;
    for (state.monitors.items) |monitor| {
        if (monitor.display_id == from_display_id) {
            current_monitor = monitor;
            break;
        }
    }
    const current = current_monitor orelse return null;

    var best_directional: ?types.Monitor = null;
    var best_wrapped: ?types.Monitor = null;
    for (state.monitors.items) |candidate| {
        if (candidate.display_id == from_display_id) {
            continue;
        }
        const delta = monitorDelta(current, candidate);
        const matches_direction = switch (direction) {
            abi.OMNI_NIRI_DIRECTION_LEFT => delta.dx < 0,
            abi.OMNI_NIRI_DIRECTION_RIGHT => delta.dx > 0,
            abi.OMNI_NIRI_DIRECTION_UP => delta.dy > 0,
            abi.OMNI_NIRI_DIRECTION_DOWN => delta.dy < 0,
            else => false,
        };
        if (matches_direction) {
            if (best_directional == null or
                betterDirectionalCandidate(current, candidate, best_directional.?, direction))
            {
                best_directional = candidate;
            }
            continue;
        }
        if (!wrap) {
            continue;
        }
        if (best_wrapped == null or monitorSortLessThan(candidate, best_wrapped.?)) {
            best_wrapped = candidate;
        }
    }
    return best_directional orelse best_wrapped;
}

pub fn previousMonitor(state: *const types.RuntimeState, from_display_id: u32) ?types.Monitor {
    if (state.monitors.items.len < 2) {
        return null;
    }
    var sorted = std.ArrayListUnmanaged(types.Monitor){};
    defer sorted.deinit(std.heap.page_allocator);
    for (state.monitors.items) |monitor| {
        sorted.append(std.heap.page_allocator, monitor) catch return null;
    }
    std.sort.insertion(types.Monitor, sorted.items, {}, struct {
        fn lessThan(_: void, lhs: types.Monitor, rhs: types.Monitor) bool {
            return monitorSortLessThan(lhs, rhs);
        }
    }.lessThan);
    for (sorted.items, 0..) |monitor, index| {
        if (monitor.display_id == from_display_id) {
            const prev_index = if (index == 0) sorted.items.len - 1 else index - 1;
            return sorted.items[prev_index];
        }
    }
    return null;
}

pub fn nextMonitor(state: *const types.RuntimeState, from_display_id: u32) ?types.Monitor {
    if (state.monitors.items.len < 2) {
        return null;
    }
    var sorted = std.ArrayListUnmanaged(types.Monitor){};
    defer sorted.deinit(std.heap.page_allocator);
    for (state.monitors.items) |monitor| {
        sorted.append(std.heap.page_allocator, monitor) catch return null;
    }
    std.sort.insertion(types.Monitor, sorted.items, {}, struct {
        fn lessThan(_: void, lhs: types.Monitor, rhs: types.Monitor) bool {
            return monitorSortLessThan(lhs, rhs);
        }
    }.lessThan);
    for (sorted.items, 0..) |monitor, index| {
        if (monitor.display_id == from_display_id) {
            return sorted.items[(index + 1) % sorted.items.len];
        }
    }
    return null;
}

pub fn pushRoutePlan(
    state: *types.RuntimeState,
    kind: u8,
    source_display_id: ?u32,
    target_display_id: ?u32,
    source_workspace: ?types.Workspace,
    target_workspace: ?types.Workspace,
    target_workspace_name: ?[]const u8,
    create_if_missing: bool,
    animate: bool,
    follow_focus: bool,
) !void {
    var route_plan = abi.OmniControllerRoutePlan{
        .kind = kind,
        .create_target_workspace_if_missing = if (create_if_missing) 1 else 0,
        .animate_workspace_switch = if (animate) 1 else 0,
        .follow_focus = if (follow_focus) 1 else 0,
        .has_source_display_id = 0,
        .source_display_id = 0,
        .has_target_display_id = 0,
        .target_display_id = 0,
        .has_source_workspace_id = 0,
        .source_workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_target_workspace_id = 0,
        .target_workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .source_workspace_name = types.encodeName(""),
        .target_workspace_name = types.encodeName(""),
    };
    types.writeOptionalDisplayId(
        &route_plan.has_source_display_id,
        &route_plan.source_display_id,
        source_display_id,
    );
    types.writeOptionalDisplayId(
        &route_plan.has_target_display_id,
        &route_plan.target_display_id,
        target_display_id,
    );
    if (source_workspace) |workspace| {
        types.writeOptionalUuid(
            &route_plan.has_source_workspace_id,
            &route_plan.source_workspace_id,
            workspace.workspace_id,
        );
        route_plan.source_workspace_name = workspace.name;
    }
    if (target_workspace) |workspace| {
        types.writeOptionalUuid(
            &route_plan.has_target_workspace_id,
            &route_plan.target_workspace_id,
            workspace.workspace_id,
        );
        route_plan.target_workspace_name = workspace.name;
    } else if (target_workspace_name) |name| {
        route_plan.target_workspace_name = types.encodeName(name);
    }
    try state.effects.route_plans.append(state.allocator, route_plan);
}
