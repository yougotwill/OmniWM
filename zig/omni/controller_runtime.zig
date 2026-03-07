const std = @import("std");
const abi = @import("abi_types.zig");
const actions = @import("actions.zig");
const event_reducer = @import("event_reducer.zig");
const focus = @import("focus.zig");
const refresh = @import("refresh_planner.zig");
const routing = @import("routing.zig");
const types = @import("controller_types.zig");

pub const OmniController = extern struct {
    _opaque: u8 = 0,
};

const RuntimeImpl = struct {
    state: types.RuntimeState,
    config: abi.OmniControllerConfig,
    platform: abi.OmniControllerPlatformVTable,
    started: bool = false,

    fn init(
        allocator: std.mem.Allocator,
        config: abi.OmniControllerConfig,
        platform: abi.OmniControllerPlatformVTable,
    ) RuntimeImpl {
        return .{
            .state = types.RuntimeState.init(allocator),
            .config = config,
            .platform = platform,
            .started = false,
        };
    }

    fn deinit(self: *RuntimeImpl) void {
        self.state.deinit();
    }
};

fn defaultControllerConfig() abi.OmniControllerConfig {
    return .{
        .abi_version = abi.OMNI_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
}

fn defaultControllerPlatform() abi.OmniControllerPlatformVTable {
    return .{
        .userdata = null,
        .capture_snapshot = null,
        .apply_effects = null,
        .report_error = null,
    };
}

fn implFromController(controller: [*c]OmniController) ?*RuntimeImpl {
    if (controller == null) {
        return null;
    }
    return @ptrCast(@alignCast(controller));
}

fn constImplFromController(controller: [*c]const OmniController) ?*const RuntimeImpl {
    if (controller == null) {
        return null;
    }
    return @ptrCast(@alignCast(controller));
}

fn createControllerRuntime(
    config: abi.OmniControllerConfig,
    platform: abi.OmniControllerPlatformVTable,
) [*c]OmniController {
    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = RuntimeImpl.init(std.heap.c_allocator, config, platform);
    return @ptrCast(runtime);
}

fn reportError(impl: *RuntimeImpl, code: i32, message: []const u8) void {
    const reporter = impl.platform.report_error orelse return;
    _ = reporter(impl.platform.userdata, code, types.encodeName(message));
}

fn effectExportFromState(impl: *const RuntimeImpl) abi.OmniControllerEffectExport {
    return .{
        .focus_exports = if (impl.state.effects.focus_exports.items.len == 0)
            null
        else
            impl.state.effects.focus_exports.items.ptr,
        .focus_export_count = impl.state.effects.focus_exports.items.len,
        .route_plans = if (impl.state.effects.route_plans.items.len == 0)
            null
        else
            impl.state.effects.route_plans.items.ptr,
        .route_plan_count = impl.state.effects.route_plans.items.len,
        .transfer_plans = if (impl.state.effects.transfer_plans.items.len == 0)
            null
        else
            impl.state.effects.transfer_plans.items.ptr,
        .transfer_plan_count = impl.state.effects.transfer_plans.items.len,
        .refresh_plans = if (impl.state.effects.refresh_plans.items.len == 0)
            null
        else
            impl.state.effects.refresh_plans.items.ptr,
        .refresh_plan_count = impl.state.effects.refresh_plans.items.len,
        .ui_actions = if (impl.state.effects.ui_actions.items.len == 0)
            null
        else
            impl.state.effects.ui_actions.items.ptr,
        .ui_action_count = impl.state.effects.ui_actions.items.len,
        .layout_actions = if (impl.state.effects.layout_actions.items.len == 0)
            null
        else
            impl.state.effects.layout_actions.items.ptr,
        .layout_action_count = impl.state.effects.layout_actions.items.len,
    };
}

fn hasQueuedEffects(impl: *const RuntimeImpl) bool {
    return impl.state.effects.focus_exports.items.len != 0 or
        impl.state.effects.route_plans.items.len != 0 or
        impl.state.effects.transfer_plans.items.len != 0 or
        impl.state.effects.refresh_plans.items.len != 0 or
        impl.state.effects.ui_actions.items.len != 0 or
        impl.state.effects.layout_actions.items.len != 0;
}

fn flushEffectsToPlatform(impl: *RuntimeImpl) i32 {
    const apply_effects = impl.platform.apply_effects orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!hasQueuedEffects(impl)) {
        return abi.OMNI_OK;
    }
    refresh.normalizeForDispatch(&impl.state);
    var effect_export = effectExportFromState(impl);
    const rc = apply_effects(impl.platform.userdata, &effect_export);
    impl.state.clearEffects();
    if (rc != abi.OMNI_OK) {
        reportError(impl, rc, "controller effects application failed");
        return rc;
    }
    return abi.OMNI_OK;
}

fn seedSnapshotIntoState(
    impl: *RuntimeImpl,
    resolved_snapshot: *const abi.OmniControllerSnapshot,
) i32 {
    impl.state.clearSnapshot();
    impl.state.clearEffects();

    if (resolved_snapshot.monitor_count > 0 and resolved_snapshot.monitors == null) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    if (resolved_snapshot.workspace_count > 0 and resolved_snapshot.workspaces == null) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    if (resolved_snapshot.window_count > 0 and resolved_snapshot.windows == null) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }

    var monitor_index: usize = 0;
    while (monitor_index < resolved_snapshot.monitor_count) : (monitor_index += 1) {
        const raw_monitor = resolved_snapshot.monitors[monitor_index];
        impl.state.monitors.append(impl.state.allocator, .{
            .display_id = raw_monitor.display_id,
            .is_main = raw_monitor.is_main != 0,
            .frame_x = raw_monitor.frame_x,
            .frame_y = raw_monitor.frame_y,
            .frame_width = raw_monitor.frame_width,
            .frame_height = raw_monitor.frame_height,
            .visible_x = raw_monitor.visible_x,
            .visible_y = raw_monitor.visible_y,
            .visible_width = raw_monitor.visible_width,
            .visible_height = raw_monitor.visible_height,
            .name = raw_monitor.name,
        }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    var workspace_index: usize = 0;
    while (workspace_index < resolved_snapshot.workspace_count) : (workspace_index += 1) {
        const raw_workspace = resolved_snapshot.workspaces[workspace_index];
        impl.state.workspaces.append(impl.state.allocator, .{
            .workspace_id = types.uuid(raw_workspace.workspace_id),
            .assigned_display_id = types.optionalDisplayId(
                raw_workspace.has_assigned_display_id,
                raw_workspace.assigned_display_id,
            ),
            .is_visible = raw_workspace.is_visible != 0,
            .is_previous_visible = raw_workspace.is_previous_visible != 0,
            .layout_kind = @enumFromInt(raw_workspace.layout_kind),
            .name = raw_workspace.name,
            .selected_node_id = types.optionalUuid(
                raw_workspace.has_selected_node_id,
                raw_workspace.selected_node_id,
            ),
            .last_focused_window_id = types.optionalUuid(
                raw_workspace.has_last_focused_window_id,
                raw_workspace.last_focused_window_id,
            ),
        }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    var window_index: usize = 0;
    while (window_index < resolved_snapshot.window_count) : (window_index += 1) {
        const raw_window = resolved_snapshot.windows[window_index];
        impl.state.windows.append(impl.state.allocator, .{
            .handle_id = types.uuid(raw_window.handle_id),
            .pid = raw_window.pid,
            .window_id = raw_window.window_id,
            .workspace_id = types.uuid(raw_window.workspace_id),
            .layout_kind = @enumFromInt(raw_window.layout_kind),
            .is_hidden = raw_window.is_hidden != 0,
            .is_focused = raw_window.is_focused != 0,
            .is_managed = raw_window.is_managed != 0,
            .node_id = types.optionalUuid(raw_window.has_node_id, raw_window.node_id),
            .column_id = types.optionalUuid(raw_window.has_column_id, raw_window.column_id),
            .order_index = raw_window.order_index,
            .column_index = raw_window.column_index,
            .row_index = raw_window.row_index,
        }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    impl.state.focused_window = types.optionalUuid(
        resolved_snapshot.has_focused_window_id,
        resolved_snapshot.focused_window_id,
    );
    impl.state.active_monitor = types.optionalDisplayId(
        resolved_snapshot.has_active_monitor_display_id,
        resolved_snapshot.active_monitor_display_id,
    );
    impl.state.previous_monitor = types.optionalDisplayId(
        resolved_snapshot.has_previous_monitor_display_id,
        resolved_snapshot.previous_monitor_display_id,
    );
    impl.state.secure_input_active = resolved_snapshot.secure_input_active != 0;
    impl.state.lock_screen_active = resolved_snapshot.lock_screen_active != 0;
    impl.state.non_managed_focus_active = resolved_snapshot.non_managed_focus_active != 0;
    impl.state.app_fullscreen_active = resolved_snapshot.app_fullscreen_active != 0;
    impl.state.focus_follows_window_to_monitor = resolved_snapshot.focus_follows_window_to_monitor != 0;
    impl.state.move_mouse_to_focused_window = resolved_snapshot.move_mouse_to_focused_window != 0;
    impl.state.layout_light_session_active = resolved_snapshot.layout_light_session_active != 0;
    impl.state.layout_immediate_in_progress = resolved_snapshot.layout_immediate_in_progress != 0;
    impl.state.layout_incremental_in_progress = resolved_snapshot.layout_incremental_in_progress != 0;
    impl.state.layout_full_enumeration_in_progress = resolved_snapshot.layout_full_enumeration_in_progress != 0;
    impl.state.layout_animation_active = resolved_snapshot.layout_animation_active != 0;
    impl.state.layout_has_completed_initial_refresh = resolved_snapshot.layout_has_completed_initial_refresh != 0;

    focus.mergeSnapshot(&impl.state) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

fn refreshSnapshotFromPlatform(impl: *RuntimeImpl) i32 {
    const capture_snapshot = impl.platform.capture_snapshot orelse return abi.OMNI_ERR_INVALID_ARGS;
    var raw_snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
    const capture_rc = capture_snapshot(impl.platform.userdata, &raw_snapshot);
    if (capture_rc != abi.OMNI_OK) {
        reportError(impl, capture_rc, "controller snapshot capture failed");
        return capture_rc;
    }
    const seed_rc = seedSnapshotIntoState(impl, &raw_snapshot);
    if (seed_rc != abi.OMNI_OK) {
        reportError(impl, seed_rc, "controller snapshot import failed");
        return seed_rc;
    }
    return abi.OMNI_OK;
}

fn runTick(impl: *RuntimeImpl, sample_time: f64) i32 {
    _ = sample_time;
    if (impl.state.lock_screen_active) {
        return abi.OMNI_OK;
    }
    return abi.OMNI_OK;
}

pub fn omni_controller_create_impl(
    config: ?*const abi.OmniControllerConfig,
    platform_vtable: ?*const abi.OmniControllerPlatformVTable,
) [*c]OmniController {
    const resolved_platform = platform_vtable orelse return null;
    if (resolved_platform.capture_snapshot == null or resolved_platform.apply_effects == null) {
        return null;
    }
    var resolved_config = defaultControllerConfig();
    if (config) |raw_config| {
        resolved_config = raw_config.*;
    }
    if (resolved_config.abi_version != abi.OMNI_CONTROLLER_ABI_VERSION) {
        return null;
    }
    return createControllerRuntime(resolved_config, resolved_platform.*);
}

pub fn omni_controller_destroy_impl(controller: [*c]OmniController) void {
    const impl = implFromController(controller) orelse return;
    impl.deinit();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_controller_start_impl(controller: [*c]OmniController) i32 {
    const impl = implFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (impl.started) {
        return abi.OMNI_OK;
    }
    impl.started = true;
    const snapshot_rc = refreshSnapshotFromPlatform(impl);
    if (snapshot_rc != abi.OMNI_OK) {
        impl.started = false;
        return snapshot_rc;
    }
    return flushEffectsToPlatform(impl);
}

pub fn omni_controller_stop_impl(controller: [*c]OmniController) i32 {
    const impl = implFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.started = false;
    impl.state.clearEffects();
    return abi.OMNI_OK;
}

pub fn omni_controller_submit_hotkey_impl(
    controller: [*c]OmniController,
    command: ?*const abi.OmniControllerCommand,
) i32 {
    const impl = implFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_command = command orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    const snapshot_rc = refreshSnapshotFromPlatform(impl);
    if (snapshot_rc != abi.OMNI_OK) {
        return snapshot_rc;
    }
    const handle_rc = actions.handleCommand(&impl.state, resolved_command.*) catch abi.OMNI_ERR_OUT_OF_RANGE;
    if (handle_rc != abi.OMNI_OK) {
        reportError(impl, handle_rc, "controller hotkey handling failed");
        impl.state.clearEffects();
        return handle_rc;
    }
    return flushEffectsToPlatform(impl);
}

pub fn omni_controller_submit_os_event_impl(
    controller: [*c]OmniController,
    event: ?*const abi.OmniControllerEvent,
) i32 {
    const impl = implFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_event = event orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    const snapshot_rc = refreshSnapshotFromPlatform(impl);
    if (snapshot_rc != abi.OMNI_OK) {
        return snapshot_rc;
    }
    const handle_rc = event_reducer.handleEvent(&impl.state, resolved_event.*) catch abi.OMNI_ERR_OUT_OF_RANGE;
    if (handle_rc != abi.OMNI_OK) {
        reportError(impl, handle_rc, "controller event handling failed");
        impl.state.clearEffects();
        return handle_rc;
    }
    return flushEffectsToPlatform(impl);
}

pub fn omni_controller_apply_settings_impl(
    controller: [*c]OmniController,
    settings_delta: ?*const abi.OmniControllerSettingsDelta,
) i32 {
    const impl = implFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_delta = settings_delta orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (resolved_delta.has_focus_follows_window_to_monitor != 0) {
        impl.state.focus_follows_window_to_monitor = resolved_delta.focus_follows_window_to_monitor != 0;
    }
    if (resolved_delta.has_move_mouse_to_focused_window != 0) {
        impl.state.move_mouse_to_focused_window = resolved_delta.move_mouse_to_focused_window != 0;
    }
    return abi.OMNI_OK;
}

pub fn omni_controller_tick_impl(
    controller: [*c]OmniController,
    sample_time: f64,
) i32 {
    const impl = implFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }
    const snapshot_rc = refreshSnapshotFromPlatform(impl);
    if (snapshot_rc != abi.OMNI_OK) {
        return snapshot_rc;
    }
    const tick_rc = runTick(impl, sample_time);
    if (tick_rc != abi.OMNI_OK) {
        reportError(impl, tick_rc, "controller tick failed");
        impl.state.clearEffects();
        return tick_rc;
    }
    return flushEffectsToPlatform(impl);
}

pub fn omni_controller_query_ui_state_impl(
    controller: [*c]const OmniController,
    out_state: ?*abi.OmniControllerUiState,
) i32 {
    const impl = constImplFromController(controller) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_state orelse return abi.OMNI_ERR_INVALID_ARGS;
    var result = std.mem.zeroes(abi.OmniControllerUiState);
    types.writeOptionalUuid(&result.has_focused_window_id, &result.focused_window_id, impl.state.focused_window);
    types.writeOptionalDisplayId(
        &result.has_active_monitor_display_id,
        &result.active_monitor_display_id,
        impl.state.active_monitor,
    );
    types.writeOptionalDisplayId(
        &result.has_previous_monitor_display_id,
        &result.previous_monitor_display_id,
        impl.state.previous_monitor,
    );
    result.secure_input_active = if (impl.state.secure_input_active) 1 else 0;
    result.lock_screen_active = if (impl.state.lock_screen_active) 1 else 0;

    var visible_count: usize = 0;
    for (impl.state.workspaces.items) |workspace| {
        if (!workspace.is_visible) {
            continue;
        }
        if (visible_count >= abi.OMNI_CONTROLLER_UI_WORKSPACE_CAP) {
            break;
        }
        result.visible_workspace_ids[visible_count] = types.rawUuid(workspace.workspace_id);
        visible_count += 1;
    }
    result.visible_workspace_count = visible_count;
    resolved_out.* = result;
    return abi.OMNI_OK;
}

test "focus history keeps newest entry first" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    const workspace_id: types.Uuid = [_]u8{1} ++ [_]u8{0} ** 15;
    const first_handle: types.Uuid = [_]u8{2} ++ [_]u8{0} ** 15;
    const second_handle: types.Uuid = [_]u8{3} ++ [_]u8{0} ** 15;

    try focus.recordFocus(&state, workspace_id, first_handle);
    try focus.recordFocus(&state, workspace_id, second_handle);
    try std.testing.expectEqual(second_handle, state.focus_history_by_workspace.get(workspace_id).?.items[0]);
    try std.testing.expectEqual(first_handle, state.focus_history_by_workspace.get(workspace_id).?.items[1]);
}

test "adjacent monitor routing prefers directional candidate" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    try state.monitors.append(std.testing.allocator, .{
        .display_id = 1,
        .is_main = true,
        .frame_x = 0,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 0,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("A"),
    });
    try state.monitors.append(std.testing.allocator, .{
        .display_id = 2,
        .is_main = false,
        .frame_x = 120,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 120,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("B"),
    });
    try state.monitors.append(std.testing.allocator, .{
        .display_id = 3,
        .is_main = false,
        .frame_x = 0,
        .frame_y = 140,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 0,
        .visible_y = 140,
        .visible_width = 100,
        .visible_height = 100,
        .name = types.encodeName("C"),
    });

    const target = routing.adjacentMonitor(&state, 1, abi.OMNI_NIRI_DIRECTION_RIGHT, false).?;
    try std.testing.expectEqual(@as(u32, 2), target.display_id);
}

test "switch workspace command queues route and refresh plans" {
    var impl = RuntimeImpl.init(
        std.testing.allocator,
        defaultControllerConfig(),
        defaultControllerPlatform(),
    );
    defer impl.deinit();

    try impl.state.monitors.append(std.testing.allocator, .{
        .display_id = 1,
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

    const workspace_1: types.Uuid = [_]u8{1} ++ [_]u8{0} ** 15;
    const workspace_2: types.Uuid = [_]u8{2} ++ [_]u8{0} ** 15;
    try impl.state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_1,
        .assigned_display_id = 1,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    try impl.state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_2,
        .assigned_display_id = 1,
        .is_visible = false,
        .is_previous_visible = true,
        .layout_kind = .niri,
        .name = types.encodeName("2"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    impl.state.active_monitor = 1;

    const rc = try actions.handleCommand(&impl.state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX,
        .direction = 0,
        .workspace_index = 1,
        .monitor_direction = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), impl.state.effects.route_plans.items.len);
    try std.testing.expectEqual(@as(usize, 1), impl.state.effects.refresh_plans.items.len);
}

test "focus previous command exports prior focused window" {
    var impl = RuntimeImpl.init(
        std.testing.allocator,
        defaultControllerConfig(),
        defaultControllerPlatform(),
    );
    defer impl.deinit();

    const workspace_id: types.Uuid = [_]u8{1} ++ [_]u8{0} ** 15;
    const first_handle: types.Uuid = [_]u8{2} ++ [_]u8{0} ** 15;
    const second_handle: types.Uuid = [_]u8{3} ++ [_]u8{0} ** 15;
    const first_node: types.Uuid = [_]u8{4} ++ [_]u8{0} ** 15;
    const second_node: types.Uuid = [_]u8{5} ++ [_]u8{0} ** 15;

    try impl.state.monitors.append(std.testing.allocator, .{
        .display_id = 1,
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
    try impl.state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_id,
        .assigned_display_id = 1,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("1"),
        .selected_node_id = second_node,
        .last_focused_window_id = second_handle,
    });
    try impl.state.windows.append(std.testing.allocator, .{
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
    try impl.state.windows.append(std.testing.allocator, .{
        .handle_id = second_handle,
        .pid = 100,
        .window_id = 11,
        .workspace_id = workspace_id,
        .layout_kind = .niri,
        .is_hidden = false,
        .is_focused = true,
        .is_managed = true,
        .node_id = second_node,
        .column_id = second_node,
        .order_index = 1,
        .column_index = 1,
        .row_index = 0,
    });
    impl.state.active_monitor = 1;
    impl.state.focused_window = second_handle;
    try focus.recordFocus(&impl.state, workspace_id, first_handle);
    try focus.recordFocus(&impl.state, workspace_id, second_handle);

    const rc = try actions.handleCommand(&impl.state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_FOCUS_PREVIOUS,
        .direction = 0,
        .workspace_index = 0,
        .monitor_direction = 0,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), impl.state.effects.focus_exports.items.len);

    const focus_export = impl.state.effects.focus_exports.items[0];
    try std.testing.expectEqual(@as(u8, 1), focus_export.has_workspace_id);
    try std.testing.expectEqual(@as(u8, 1), focus_export.has_selected_node_id);
    try std.testing.expectEqual(@as(u8, 1), focus_export.has_focused_window_id);
    try std.testing.expectEqual(first_handle, focus_export.focused_window_id.bytes);
    try std.testing.expectEqual(first_node, focus_export.selected_node_id.bytes);
    try std.testing.expectEqual(@as(usize, 1), impl.state.effects.refresh_plans.items.len);
}

test "workspace command can target explicit workspace id" {
    var impl = RuntimeImpl.init(
        std.testing.allocator,
        defaultControllerConfig(),
        defaultControllerPlatform(),
    );
    defer impl.deinit();

    const workspace_1: types.Uuid = [_]u8{1} ++ [_]u8{0} ** 15;
    const workspace_2: types.Uuid = [_]u8{2} ++ [_]u8{0} ** 15;

    try impl.state.monitors.append(std.testing.allocator, .{
        .display_id = 1,
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
    try impl.state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_1,
        .assigned_display_id = 1,
        .is_visible = true,
        .is_previous_visible = false,
        .layout_kind = .niri,
        .name = types.encodeName("dev"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    try impl.state.workspaces.append(std.testing.allocator, .{
        .workspace_id = workspace_2,
        .assigned_display_id = 1,
        .is_visible = false,
        .is_previous_visible = true,
        .layout_kind = .niri,
        .name = types.encodeName("ops"),
        .selected_node_id = null,
        .last_focused_window_id = null,
    });
    impl.state.active_monitor = 1;

    const rc = try actions.handleCommand(&impl.state, .{
        .kind = abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE,
        .direction = 0,
        .workspace_index = 0,
        .monitor_direction = 0,
        .has_workspace_id = 1,
        .workspace_id = types.rawUuid(workspace_2),
        .has_window_handle_id = 0,
        .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
    });

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), rc);
    try std.testing.expectEqual(@as(usize, 1), impl.state.effects.route_plans.items.len);
    const route_plan = impl.state.effects.route_plans.items[0];
    try std.testing.expectEqual(@as(u8, 1), route_plan.has_target_workspace_id);
    try std.testing.expectEqual(workspace_2, route_plan.target_workspace_id.bytes);
}
