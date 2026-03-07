const std = @import("std");
const abi = @import("abi_types.zig");
const window_model = @import("window_model.zig");
const workspace_controller = @import("workspace_controller.zig");

pub const OmniWorkspaceRuntime = abi.OmniWorkspaceRuntime;

const RuntimeImpl = struct {
    controller: workspace_controller.WorkspaceController,
    started: bool = false,

    fn init(allocator: std.mem.Allocator) !RuntimeImpl {
        return .{
            .controller = try workspace_controller.WorkspaceController.init(allocator),
        };
    }

    fn deinit(self: *RuntimeImpl) void {
        self.controller.deinit();
        self.* = undefined;
    }
};

fn implFromRuntime(runtime: [*c]OmniWorkspaceRuntime) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

pub fn omni_workspace_runtime_create_impl(
    config: ?*const abi.OmniWorkspaceRuntimeConfig,
) [*c]OmniWorkspaceRuntime {
    var resolved_config = abi.OmniWorkspaceRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION) return null;

    const impl = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    impl.* = RuntimeImpl.init(std.heap.c_allocator) catch {
        std.heap.c_allocator.destroy(impl);
        return null;
    };
    return @ptrCast(impl);
}

pub fn omni_workspace_runtime_destroy_impl(runtime: [*c]OmniWorkspaceRuntime) void {
    const impl = implFromRuntime(runtime) orelse return;
    impl.deinit();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_workspace_runtime_start_impl(runtime: [*c]OmniWorkspaceRuntime) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.started = true;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_stop_impl(runtime: [*c]OmniWorkspaceRuntime) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.started = false;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_import_monitors_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    monitors: [*c]const abi.OmniWorkspaceRuntimeMonitorSnapshot,
    monitor_count: usize,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (monitor_count > 0 and monitors == null) return abi.OMNI_ERR_INVALID_ARGS;

    const slice: []const abi.OmniWorkspaceRuntimeMonitorSnapshot = if (monitor_count == 0)
        &[_]abi.OmniWorkspaceRuntimeMonitorSnapshot{}
    else
        monitors[0..monitor_count];

    impl.controller.importMonitors(slice) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_import_settings_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    settings: ?*const abi.OmniWorkspaceRuntimeSettingsImport,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    const resolved = settings orelse return abi.OMNI_ERR_INVALID_ARGS;

    if (resolved.persistent_name_count > 0 and resolved.persistent_names == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (resolved.monitor_assignment_count > 0 and resolved.monitor_assignments == null) return abi.OMNI_ERR_INVALID_ARGS;

    impl.controller.importSettings(resolved.*) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_export_state_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_export orelse return abi.OMNI_ERR_INVALID_ARGS;

    impl.controller.exportState(resolved_out) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_workspace_id_by_name_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    name: abi.OmniWorkspaceRuntimeName,
    create_if_missing: u8,
    out_has_workspace_id: [*c]u8,
    out_workspace_id: [*c]abi.OmniUuid128,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_has_workspace_id == null or out_workspace_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const result = impl.controller.workspaceIdByName(name, create_if_missing != 0) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    if (result) |workspace_id| {
        out_has_workspace_id[0] = 1;
        out_workspace_id[0] = workspace_id;
    } else {
        out_has_workspace_id[0] = 0;
        out_workspace_id[0] = .{ .bytes = [_]u8{0} ** 16 };
    }
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_set_active_workspace_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
    monitor_display_id: u32,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.controller.setActiveWorkspace(workspace_id, monitor_display_id)) return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_summon_workspace_by_name_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    name: abi.OmniWorkspaceRuntimeName,
    monitor_display_id: u32,
    out_has_workspace_id: [*c]u8,
    out_workspace_id: [*c]abi.OmniUuid128,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_has_workspace_id == null or out_workspace_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const result = impl.controller.summonWorkspaceByName(name, monitor_display_id);
    if (result) |workspace_id| {
        out_has_workspace_id[0] = 1;
        out_workspace_id[0] = workspace_id;
    } else {
        out_has_workspace_id[0] = 0;
        out_workspace_id[0] = .{ .bytes = [_]u8{0} ** 16 };
    }
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_move_workspace_to_monitor_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
    target_monitor_display_id: u32,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const moved = impl.controller.moveWorkspaceToMonitor(workspace_id, target_monitor_display_id) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    if (!moved) return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_swap_workspaces_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    workspace_1_id: abi.OmniUuid128,
    monitor_1_display_id: u32,
    workspace_2_id: abi.OmniUuid128,
    monitor_2_display_id: u32,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.controller.swapWorkspaces(workspace_1_id, monitor_1_display_id, workspace_2_id, monitor_2_display_id)) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_adjacent_monitor_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    from_monitor_display_id: u32,
    direction: u8,
    wrap_around: u8,
    out_has_monitor: [*c]u8,
    out_monitor: [*c]abi.OmniWorkspaceRuntimeMonitorRecord,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_has_monitor == null or out_monitor == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const candidate = impl.controller.adjacentMonitorRecord(from_monitor_display_id, direction, wrap_around != 0);
    if (candidate) |value| {
        out_has_monitor[0] = 1;
        out_monitor[0] = value;
    } else {
        out_has_monitor[0] = 0;
        out_monitor[0] = workspace_controller.WorkspaceController.emptyMonitorRecord();
    }
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_window_upsert_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    request: ?*const abi.OmniWorkspaceRuntimeWindowUpsert,
    out_handle_id: [*c]abi.OmniUuid128,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved = request orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_handle_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const handle = impl.controller.windowUpsert(resolved.*) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    const resolved_handle = handle orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    out_handle_id[0] = resolved_handle;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_window_remove_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    key: abi.OmniWorkspaceRuntimeWindowKey,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    impl.controller.windowRemove(key);
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_window_set_workspace_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    handle_id: abi.OmniUuid128,
    workspace_id: abi.OmniUuid128,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.controller.windowSetWorkspace(handle_id, workspace_id)) return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_window_set_hidden_state_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    handle_id: abi.OmniUuid128,
    has_hidden_state: u8,
    hidden_state: abi.OmniWorkspaceRuntimeWindowHiddenState,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const resolved_state: ?window_model.HiddenState = if (has_hidden_state != 0)
        .{
            .proportional_x = hidden_state.proportional_x,
            .proportional_y = hidden_state.proportional_y,
            .reference_display_id = if (hidden_state.has_reference_display_id != 0) hidden_state.reference_display_id else null,
            .workspace_inactive = hidden_state.workspace_inactive != 0,
        }
    else
        null;

    if (!impl.controller.windowSetHiddenState(handle_id, resolved_state)) return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_window_set_layout_reason_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    handle_id: abi.OmniUuid128,
    layout_reason: u8,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.controller.windowSetLayoutReason(handle_id, layout_reason)) return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_window_remove_missing_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    active_keys: [*c]const abi.OmniWorkspaceRuntimeWindowKey,
    active_key_count: usize,
    required_consecutive_misses: u32,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (active_key_count > 0 and active_keys == null) return abi.OMNI_ERR_INVALID_ARGS;

    const slice: []const abi.OmniWorkspaceRuntimeWindowKey = if (active_key_count == 0)
        &[_]abi.OmniWorkspaceRuntimeWindowKey{}
    else
        active_keys[0..active_key_count];

    impl.controller.windowRemoveMissing(slice, required_consecutive_misses) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}
