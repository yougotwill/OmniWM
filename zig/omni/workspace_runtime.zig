const std = @import("std");
const abi = @import("abi_types.zig");
const window_model = @import("window_model.zig");
const workspace_controller = @import("workspace_controller.zig");

pub const OmniWorkspaceRuntime = abi.OmniWorkspaceRuntime;

const RuntimeImpl = struct {
    controller: workspace_controller.WorkspaceController,
    started: bool = false,
    mutex: std.Thread.Mutex = .{},

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

fn captureStateExport(
    impl: *RuntimeImpl,
    out_export: *abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    impl.controller.exportState(out_export) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
    impl.started = true;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_stop_impl(runtime: [*c]OmniWorkspaceRuntime) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    impl.started = false;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_import_monitors_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    monitors: [*c]const abi.OmniWorkspaceRuntimeMonitorSnapshot,
    monitor_count: usize,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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

    impl.mutex.lock();
    defer impl.mutex.unlock();
    return captureStateExport(impl, resolved_out);
}

pub fn omni_workspace_runtime_query_state_counts_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    out_counts: ?*abi.OmniWorkspaceRuntimeStateCounts,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_counts orelse return abi.OMNI_ERR_INVALID_ARGS;

    impl.mutex.lock();
    defer impl.mutex.unlock();

    var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    const rc = captureStateExport(impl, &state_export);
    if (rc != abi.OMNI_OK) {
        resolved_out.* = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateCounts);
        return rc;
    }

    resolved_out.* = .{
        .monitor_count = state_export.monitor_count,
        .workspace_count = state_export.workspace_count,
        .window_count = state_export.window_count,
    };
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_copy_state_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
    out_monitors: [*c]abi.OmniWorkspaceRuntimeMonitorRecord,
    monitor_capacity: usize,
    out_workspaces: [*c]abi.OmniWorkspaceRuntimeWorkspaceRecord,
    workspace_capacity: usize,
    out_windows: [*c]abi.OmniWorkspaceRuntimeWindowRecord,
    window_capacity: usize,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_export orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (monitor_capacity > 0 and out_monitors == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (workspace_capacity > 0 and out_workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_capacity > 0 and out_windows == null) return abi.OMNI_ERR_INVALID_ARGS;

    impl.mutex.lock();
    defer impl.mutex.unlock();

    var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    const rc = captureStateExport(impl, &state_export);
    if (rc != abi.OMNI_OK) {
        resolved_out.* = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        return rc;
    }

    resolved_out.* = .{
        .monitors = null,
        .monitor_count = state_export.monitor_count,
        .workspaces = null,
        .workspace_count = state_export.workspace_count,
        .windows = null,
        .window_count = state_export.window_count,
        .has_active_monitor_display_id = state_export.has_active_monitor_display_id,
        .active_monitor_display_id = state_export.active_monitor_display_id,
        .has_previous_monitor_display_id = state_export.has_previous_monitor_display_id,
        .previous_monitor_display_id = state_export.previous_monitor_display_id,
    };

    if (state_export.monitor_count > monitor_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (state_export.workspace_count > workspace_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (state_export.window_count > window_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;

    if (state_export.monitor_count > 0) {
        std.mem.copyForwards(
            abi.OmniWorkspaceRuntimeMonitorRecord,
            out_monitors[0..state_export.monitor_count],
            state_export.monitors[0..state_export.monitor_count],
        );
        resolved_out.monitors = out_monitors;
    }
    if (state_export.workspace_count > 0) {
        std.mem.copyForwards(
            abi.OmniWorkspaceRuntimeWorkspaceRecord,
            out_workspaces[0..state_export.workspace_count],
            state_export.workspaces[0..state_export.workspace_count],
        );
        resolved_out.workspaces = out_workspaces;
    }
    if (state_export.window_count > 0) {
        std.mem.copyForwards(
            abi.OmniWorkspaceRuntimeWindowRecord,
            out_windows[0..state_export.window_count],
            state_export.windows[0..state_export.window_count],
        );
        resolved_out.windows = out_windows;
    }

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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (!impl.controller.setActiveWorkspace(workspace_id, monitor_display_id)) return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_switch_workspace_by_name_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    name: abi.OmniWorkspaceRuntimeName,
    out_has_workspace_id: [*c]u8,
    out_workspace_id: [*c]abi.OmniUuid128,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_has_workspace_id == null or out_workspace_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const result = impl.controller.switchWorkspaceByName(name) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    if (result) |workspace_id| {
        out_has_workspace_id[0] = 1;
        out_workspace_id[0] = workspace_id;
    } else {
        out_has_workspace_id[0] = 0;
        out_workspace_id[0] = .{ .bytes = [_]u8{0} ** 16 };
    }
    return abi.OMNI_OK;
}

pub fn omni_workspace_runtime_focus_workspace_anywhere_impl(
    runtime: [*c]OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
    out_has_workspace_id: [*c]u8,
    out_workspace_id: [*c]abi.OmniUuid128,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_has_workspace_id == null or out_workspace_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;

    const result = impl.controller.focusWorkspaceAnywhere(workspace_id);
    if (result) |resolved_workspace_id| {
        out_has_workspace_id[0] = 1;
        out_workspace_id[0] = resolved_workspace_id;
    } else {
        out_has_workspace_id[0] = 0;
        out_workspace_id[0] = .{ .bytes = [_]u8{0} ** 16 };
    }
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
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
    impl.mutex.lock();
    defer impl.mutex.unlock();
    if (!impl.started) return abi.OMNI_ERR_INVALID_ARGS;
    if (active_key_count > 0 and active_keys == null) return abi.OMNI_ERR_INVALID_ARGS;

    const slice: []const abi.OmniWorkspaceRuntimeWindowKey = if (active_key_count == 0)
        &[_]abi.OmniWorkspaceRuntimeWindowKey{}
    else
        active_keys[0..active_key_count];

    impl.controller.windowRemoveMissing(slice, required_consecutive_misses) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

const RuntimeRaceContext = struct {
    runtime: [*c]OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
};

fn upsertRaceWorker(context: *RuntimeRaceContext) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var handle_id: abi.OmniUuid128 = .{ .bytes = [_]u8{0} ** 16 };
        const request = abi.OmniWorkspaceRuntimeWindowUpsert{
            .pid = 91,
            .window_id = @intCast(100 + (i % 4)),
            .workspace_id = context.workspace_id,
            .has_handle_id = 0,
            .handle_id = .{ .bytes = [_]u8{0} ** 16 },
        };
        _ = omni_workspace_runtime_window_upsert_impl(context.runtime, &request, &handle_id);
    }
}

fn exportRaceWorker(context: *RuntimeRaceContext) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        _ = omni_workspace_runtime_export_state_impl(context.runtime, &state_export);
    }
}

fn copyRaceWorker(context: *RuntimeRaceContext) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var counts = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateCounts);
        if (omni_workspace_runtime_query_state_counts_impl(context.runtime, &counts) != abi.OMNI_OK) return;

        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            const monitor_records = std.heap.c_allocator.alloc(
                abi.OmniWorkspaceRuntimeMonitorRecord,
                counts.monitor_count,
            ) catch return;
            defer std.heap.c_allocator.free(monitor_records);

            const workspace_records = std.heap.c_allocator.alloc(
                abi.OmniWorkspaceRuntimeWorkspaceRecord,
                counts.workspace_count,
            ) catch return;
            defer std.heap.c_allocator.free(workspace_records);

            const window_records = std.heap.c_allocator.alloc(
                abi.OmniWorkspaceRuntimeWindowRecord,
                counts.window_count,
            ) catch return;
            defer std.heap.c_allocator.free(window_records);

            var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
            const rc = omni_workspace_runtime_copy_state_impl(
                context.runtime,
                &state_export,
                if (monitor_records.len == 0) null else monitor_records.ptr,
                monitor_records.len,
                if (workspace_records.len == 0) null else workspace_records.ptr,
                workspace_records.len,
                if (window_records.len == 0) null else window_records.ptr,
                window_records.len,
            );
            if (rc == abi.OMNI_OK) break;
            if (rc != abi.OMNI_ERR_OUT_OF_RANGE) return;

            counts.monitor_count = state_export.monitor_count;
            counts.workspace_count = state_export.workspace_count;
            counts.window_count = state_export.window_count;
        }
    }
}

fn removeMissingRaceWorker(context: *RuntimeRaceContext) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const keys = [_]abi.OmniWorkspaceRuntimeWindowKey{
            .{
                .pid = 91,
                .window_id = @intCast(100 + (i % 4)),
            },
        };
        _ = omni_workspace_runtime_window_remove_missing_impl(context.runtime, &keys, keys.len, 1);
    }
}

test "workspace runtime serializes concurrent export and window mutations" {
    var config = abi.OmniWorkspaceRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_workspace_runtime_create_impl(&config);
    defer omni_workspace_runtime_destroy_impl(runtime);

    try std.testing.expect(runtime != null);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), omni_workspace_runtime_start_impl(runtime));

    var initial_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), omni_workspace_runtime_export_state_impl(runtime, &initial_export));
    try std.testing.expect(initial_export.monitor_count >= 1);
    try std.testing.expect(initial_export.workspace_count >= 1);

    const monitor_display_id = initial_export.monitors.?[0].display_id;
    const workspace_id = initial_export.workspaces.?[0].workspace_id;

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_workspace_runtime_set_active_workspace_impl(runtime, workspace_id, monitor_display_id),
    );

    var context = RuntimeRaceContext{
        .runtime = runtime,
        .workspace_id = workspace_id,
    };

    const upsert_thread = try std.Thread.spawn(.{}, upsertRaceWorker, .{&context});
    const export_thread = try std.Thread.spawn(.{}, exportRaceWorker, .{&context});
    const remove_thread = try std.Thread.spawn(.{}, removeMissingRaceWorker, .{&context});

    upsert_thread.join();
    export_thread.join();
    remove_thread.join();

    var final_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), omni_workspace_runtime_export_state_impl(runtime, &final_export));
}

test "workspace runtime copies snapshots safely during concurrent window mutations" {
    var config = abi.OmniWorkspaceRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_workspace_runtime_create_impl(&config);
    defer omni_workspace_runtime_destroy_impl(runtime);

    try std.testing.expect(runtime != null);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), omni_workspace_runtime_start_impl(runtime));

    var initial_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), omni_workspace_runtime_export_state_impl(runtime, &initial_export));
    const monitor_display_id = initial_export.monitors.?[0].display_id;
    const workspace_id = initial_export.workspaces.?[0].workspace_id;

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_workspace_runtime_set_active_workspace_impl(runtime, workspace_id, monitor_display_id),
    );

    var context = RuntimeRaceContext{
        .runtime = runtime,
        .workspace_id = workspace_id,
    };

    const upsert_thread = try std.Thread.spawn(.{}, upsertRaceWorker, .{&context});
    const copy_thread = try std.Thread.spawn(.{}, copyRaceWorker, .{&context});
    const remove_thread = try std.Thread.spawn(.{}, removeMissingRaceWorker, .{&context});

    upsert_thread.join();
    copy_thread.join();
    remove_thread.join();

    var counts = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateCounts);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), omni_workspace_runtime_query_state_counts_impl(runtime, &counts));

    const monitor_records = try std.testing.allocator.alloc(
        abi.OmniWorkspaceRuntimeMonitorRecord,
        counts.monitor_count,
    );
    defer std.testing.allocator.free(monitor_records);

    const workspace_records = try std.testing.allocator.alloc(
        abi.OmniWorkspaceRuntimeWorkspaceRecord,
        counts.workspace_count,
    );
    defer std.testing.allocator.free(workspace_records);

    const window_records = try std.testing.allocator.alloc(
        abi.OmniWorkspaceRuntimeWindowRecord,
        counts.window_count,
    );
    defer std.testing.allocator.free(window_records);

    var copied_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_workspace_runtime_copy_state_impl(
            runtime,
            &copied_export,
            if (monitor_records.len == 0) null else monitor_records.ptr,
            monitor_records.len,
            if (workspace_records.len == 0) null else workspace_records.ptr,
            workspace_records.len,
            if (window_records.len == 0) null else window_records.ptr,
            window_records.len,
        ),
    );
    try std.testing.expectEqual(counts.monitor_count, copied_export.monitor_count);
    try std.testing.expectEqual(counts.workspace_count, copied_export.workspace_count);
    try std.testing.expectEqual(counts.window_count, copied_export.window_count);
}
