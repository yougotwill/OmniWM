const std = @import("std");
const abi = @import("abi_types.zig");
const border = @import("border.zig");
const controller_runtime = @import("controller_runtime.zig");
const types = @import("controller_types.zig");
const dwindle = @import("dwindle.zig");
const focus_manager = @import("focus_manager.zig");
const mouse_handler = @import("mouse_handler.zig");
const niri_runtime = @import("runtime.zig");
const ax_manager = @import("../platform/ax_manager.zig");
const monitor_discovery = @import("../platform/monitor_discovery.zig");
const skylight = @import("../platform/skylight.zig");
const workspace_runtime = @import("workspace_runtime.zig");
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("unistd.h");
});

pub const OmniWMController = abi.OmniWMController;
pub const OmniWMControllerSnapshot = abi.OmniWMControllerSnapshot;

const Uuid = [16]u8;
const default_layout_gap: f64 = 10.0;
const default_border_width: f64 = 3.0;
const default_niri_max_visible_columns: i64 = 3;
const default_niri_max_windows_per_column: i64 = 3;
const default_niri_width_presets = [_]f64{ 1.0 / 3.0, 0.5, 2.0 / 3.0 };
const default_niri_orientation: u8 = abi.OMNI_NIRI_ORIENTATION_HORIZONTAL;
const enable_runtime_grid_fallback = true;
const default_border_color = abi.OmniBorderColor{
    .red = 0.26,
    .green = 0.72,
    .blue = 1.0,
    .alpha = 0.95,
};

fn defaultWidthPresetBuffer() [abi.OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP]f64 {
    var buffer = [_]f64{0.0} ** abi.OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP;
    for (default_niri_width_presets, 0..) |preset, index| {
        buffer[index] = preset;
    }
    return buffer;
}

const default_single_window_aspect_width: f64 = 4.0;
const default_single_window_aspect_height: f64 = 3.0;
const default_dwindle_split_ratio: f64 = 1.0;
const default_dwindle_split_width_multiplier: f64 = 1.0;
const default_dwindle_resize_step: f64 = 0.1;
const default_dwindle_aspect_tolerance: f64 = 0.1;

const MonitorNiriSettings = struct {
    orientation: u8 = default_niri_orientation,
    center_focused_column: u8 = abi.OMNI_CENTER_NEVER,
    always_center_single_column: bool = true,
    single_window_aspect_width: f64 = default_single_window_aspect_width,
    single_window_aspect_height: f64 = default_single_window_aspect_height,
};

const MonitorDwindleSettings = struct {
    smart_split: bool = true,
    default_split_ratio: f64 = default_dwindle_split_ratio,
    split_width_multiplier: f64 = default_dwindle_split_width_multiplier,
    inner_gap: f64 = default_layout_gap,
    outer_gap_top: f64 = 0.0,
    outer_gap_bottom: f64 = 0.0,
    outer_gap_left: f64 = 0.0,
    outer_gap_right: f64 = 0.0,
    single_window_aspect_width: f64 = default_single_window_aspect_width,
    single_window_aspect_height: f64 = default_single_window_aspect_height,
};

const WorkspaceLayoutSetting = struct {
    name: abi.OmniControllerName,
    layout_kind: types.LayoutKind,
};

const WorkingArea = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

const WorkspaceLayoutRuntime = struct {
    runtime: [*c]niri_runtime.OmniNiriRuntime = null,
    next_column_serial: u64 = 1,

    fn deinit(self: *WorkspaceLayoutRuntime) void {
        if (self.runtime != null) {
            niri_runtime.omni_niri_runtime_destroy_impl(self.runtime);
            self.runtime = null;
        }
    }

    fn generateColumnId(self: *WorkspaceLayoutRuntime, workspace_id: Uuid) abi.OmniUuid128 {
        var bytes = workspace_id;
        std.mem.writeInt(u64, bytes[0..8], self.next_column_serial, .little);
        bytes[8] = 0x6e;
        bytes[9] = 0x69;
        bytes[10] = 0x72;
        bytes[11] = 0x69;
        self.next_column_serial += 1;
        return .{ .bytes = bytes };
    }
};

const WorkspaceDwindleRuntime = struct {
    context: [*c]dwindle.OmniDwindleLayoutContext = null,

    fn deinit(self: *WorkspaceDwindleRuntime) void {
        if (self.context != null) {
            dwindle.omni_dwindle_layout_context_destroy_impl(self.context);
            self.context = null;
        }
    }
};

const WorkspaceSelectionState = struct {
    selected_node_id: ?Uuid = null,
    selected_column_id: ?Uuid = null,
    focused_window_id: ?Uuid = null,
    actionable_window_id: ?Uuid = null,
    managed_fullscreen_window_id: ?Uuid = null,
};

const WorkspaceRuntimeContext = struct {
    workspace_id: abi.OmniUuid128,
    layout_runtime: *WorkspaceLayoutRuntime,
    runtime_export: abi.OmniNiriRuntimeStateExport,
    selection: WorkspaceSelectionState,
};
const WorkspaceRuntimeContextResolution = struct {
    rc: i32 = abi.OMNI_OK,
    context: ?WorkspaceRuntimeContext = null,
};

const SnapshotImpl = struct {
    allocator: std.mem.Allocator,
    controller_snapshot: abi.OmniControllerSnapshot = std.mem.zeroes(abi.OmniControllerSnapshot),
    workspace_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport),
    counts: abi.OmniWMControllerSnapshotCounts = std.mem.zeroes(abi.OmniWMControllerSnapshotCounts),
    ui_state: abi.OmniControllerUiState = std.mem.zeroes(abi.OmniControllerUiState),
    controller_monitor_snapshots: []abi.OmniControllerMonitorSnapshot = &.{},
    controller_workspace_snapshots: []abi.OmniControllerWorkspaceSnapshot = &.{},
    controller_window_snapshots: []abi.OmniControllerWindowSnapshot = &.{},
    monitor_records: []abi.OmniWorkspaceRuntimeMonitorRecord = &.{},
    workspace_records: []abi.OmniWorkspaceRuntimeWorkspaceRecord = &.{},
    window_records: []abi.OmniWorkspaceRuntimeWindowRecord = &.{},
    changed_workspace_ids: []abi.OmniUuid128 = &.{},

    fn init(allocator: std.mem.Allocator) SnapshotImpl {
        return .{
            .allocator = allocator,
        };
    }

    fn deinit(self: *SnapshotImpl) void {
        if (self.controller_monitor_snapshots.len > 0) self.allocator.free(self.controller_monitor_snapshots);
        if (self.controller_workspace_snapshots.len > 0) self.allocator.free(self.controller_workspace_snapshots);
        if (self.controller_window_snapshots.len > 0) self.allocator.free(self.controller_window_snapshots);
        if (self.monitor_records.len > 0) self.allocator.free(self.monitor_records);
        if (self.workspace_records.len > 0) self.allocator.free(self.workspace_records);
        if (self.window_records.len > 0) self.allocator.free(self.window_records);
        if (self.changed_workspace_ids.len > 0) self.allocator.free(self.changed_workspace_ids);
        self.* = undefined;
    }
};

const OwnedWorkspaceState = struct {
    allocator: std.mem.Allocator,
    state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport),
    monitors: []abi.OmniWorkspaceRuntimeMonitorRecord = &.{},
    workspaces: []abi.OmniWorkspaceRuntimeWorkspaceRecord = &.{},
    windows: []abi.OmniWorkspaceRuntimeWindowRecord = &.{},

    fn init(allocator: std.mem.Allocator) OwnedWorkspaceState {
        return .{
            .allocator = allocator,
        };
    }

    fn deinit(self: *OwnedWorkspaceState) void {
        if (self.monitors.len > 0) self.allocator.free(self.monitors);
        if (self.workspaces.len > 0) self.allocator.free(self.workspaces);
        if (self.windows.len > 0) self.allocator.free(self.windows);
        self.* = undefined;
    }
};

const WindowInventoryOperation = struct {
    request: abi.OmniWorkspaceRuntimeWindowUpsert,
    layout_reason: u8,
};

const RuntimeImpl = struct {
    allocator: std.mem.Allocator,
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    host: abi.OmniWMControllerHostVTable,
    controller: [*c]controller_runtime.OmniController = null,
    ax_runtime: [*c]ax_manager.OmniAXRuntime = null,
    border_runtime: [*c]border.OmniBorderRuntime = null,
    last_border_runtime_create_status: ?border.BorderRuntimeCreateStatus = null,
    started: bool = false,
    mutex: std.Thread.Mutex = .{},
    tick_timer: c.CFRunLoopTimerRef = null,

    monitor_snapshots: std.ArrayListUnmanaged(abi.OmniControllerMonitorSnapshot) = .{},
    workspace_snapshots: std.ArrayListUnmanaged(abi.OmniControllerWorkspaceSnapshot) = .{},
    workspace_projection_snapshots: std.ArrayListUnmanaged(abi.OmniControllerWorkspaceProjectionRecord) = .{},
    window_snapshots: std.ArrayListUnmanaged(abi.OmniControllerWindowSnapshot) = .{},
    monitor_records: std.ArrayListUnmanaged(abi.OmniMonitorRecord) = .{},
    display_infos: std.ArrayListUnmanaged(abi.OmniBorderDisplayInfo) = .{},
    visible_windows: std.ArrayListUnmanaged(abi.OmniSkyLightWindowInfo) = .{},
    active_window_keys: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeWindowKey) = .{},
    frame_requests: std.ArrayListUnmanaged(abi.OmniAXFrameRequest) = .{},

    workspace_layout_runtimes: std.AutoHashMap(Uuid, WorkspaceLayoutRuntime),
    workspace_dwindle_runtimes: std.AutoHashMap(Uuid, WorkspaceDwindleRuntime),
    projection_generation_by_workspace: std.AutoHashMap(Uuid, u64),
    dirty_projection_workspaces: std.AutoHashMap(Uuid, void),
    projection_generation_tracking_failed: bool = false,
    invalidate_all_projection_workspaces_pending: bool = true,
    selected_node_by_workspace: std.AutoHashMap(Uuid, Uuid),
    last_focused_by_workspace: std.AutoHashMap(Uuid, Uuid),
    managed_fullscreen_by_workspace: std.AutoHashMap(Uuid, Uuid),
    tracked_ax_pids: std.AutoHashMap(i32, void),

    focused_window: ?Uuid = null,
    active_monitor_override: ?u32 = null,
    previous_monitor_override: ?u32 = null,

    secure_input_active: bool = false,
    lock_screen_active: bool = false,
    non_managed_focus_active: bool = false,
    app_fullscreen_active: bool = false,
    focus_follows_mouse: bool = false,
    focus_follows_window_to_monitor: bool = false,
    move_mouse_to_focused_window: bool = false,
    layout_gap: f64 = default_layout_gap,
    outer_gap_left: f64 = 0,
    outer_gap_right: f64 = 0,
    outer_gap_top: f64 = 0,
    outer_gap_bottom: f64 = 0,
    niri_max_visible_columns: i64 = default_niri_max_visible_columns,
    niri_max_windows_per_column: i64 = default_niri_max_windows_per_column,
    niri_infinite_loop: bool = false,
    niri_width_preset_count: usize = default_niri_width_presets.len,
    niri_width_presets: [abi.OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP]f64 = defaultWidthPresetBuffer(),
    layout_light_session_active: bool = false,
    layout_immediate_in_progress: bool = false,
    layout_incremental_in_progress: bool = false,
    layout_full_enumeration_in_progress: bool = false,
    layout_animation_active: bool = false,
    layout_has_completed_initial_refresh: bool = false,
    layout_animation_deadline: ?f64 = null,
    runtime_layout_render_failed: bool = false,
    logged_border_suppression_for_runtime_failure: bool = false,
    last_tick_sample_time: f64 = 0,
    border_enabled: bool = false,
    border_width: f64 = default_border_width,
    border_color: abi.OmniBorderColor = default_border_color,
    mouse_input_handler: mouse_handler.MouseHandler = mouse_handler.MouseHandler.init(.{}),
    monitor_niri_settings_by_display: std.AutoHashMap(u32, MonitorNiriSettings),
    monitor_dwindle_settings_by_display: std.AutoHashMap(u32, MonitorDwindleSettings),
    workspace_layout_settings: std.ArrayListUnmanaged(WorkspaceLayoutSetting) = .{},
    default_layout_kind: types.LayoutKind = .niri,
    dwindle_move_to_root_stable: bool = true,

    fn init(
        allocator: std.mem.Allocator,
        workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
        host: abi.OmniWMControllerHostVTable,
    ) RuntimeImpl {
        return .{
            .allocator = allocator,
            .workspace_runtime_owner = workspace_runtime_owner,
            .host = host,
            .workspace_layout_runtimes = std.AutoHashMap(Uuid, WorkspaceLayoutRuntime).init(allocator),
            .workspace_dwindle_runtimes = std.AutoHashMap(Uuid, WorkspaceDwindleRuntime).init(allocator),
            .projection_generation_by_workspace = std.AutoHashMap(Uuid, u64).init(allocator),
            .dirty_projection_workspaces = std.AutoHashMap(Uuid, void).init(allocator),
            .selected_node_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
            .last_focused_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
            .managed_fullscreen_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
            .tracked_ax_pids = std.AutoHashMap(i32, void).init(allocator),
            .monitor_niri_settings_by_display = std.AutoHashMap(u32, MonitorNiriSettings).init(allocator),
            .monitor_dwindle_settings_by_display = std.AutoHashMap(u32, MonitorDwindleSettings).init(allocator),
            .workspace_layout_settings = .{},
            .default_layout_kind = .niri,
            .dwindle_move_to_root_stable = true,
        };
    }

    fn deinit(self: *RuntimeImpl) void {
        if (self.controller != null) {
            _ = controller_runtime.omni_controller_stop_impl(self.controller);
            controller_runtime.omni_controller_destroy_impl(self.controller);
            self.controller = null;
        }
        self.destroyAuxRuntimes();

        self.monitor_snapshots.deinit(self.allocator);
        self.workspace_snapshots.deinit(self.allocator);
        self.workspace_projection_snapshots.deinit(self.allocator);
        self.window_snapshots.deinit(self.allocator);
        self.monitor_records.deinit(self.allocator);
        self.display_infos.deinit(self.allocator);
        self.visible_windows.deinit(self.allocator);
        self.active_window_keys.deinit(self.allocator);
        self.frame_requests.deinit(self.allocator);
        var runtime_it = self.workspace_layout_runtimes.valueIterator();
        while (runtime_it.next()) |entry| {
            entry.deinit();
        }
        self.workspace_layout_runtimes.deinit();
        var dwindle_runtime_it = self.workspace_dwindle_runtimes.valueIterator();
        while (dwindle_runtime_it.next()) |entry| {
            entry.deinit();
        }
        self.workspace_dwindle_runtimes.deinit();
        self.projection_generation_by_workspace.deinit();
        self.dirty_projection_workspaces.deinit();
        self.selected_node_by_workspace.deinit();
        self.last_focused_by_workspace.deinit();
        self.managed_fullscreen_by_workspace.deinit();
        self.tracked_ax_pids.deinit();
        self.monitor_niri_settings_by_display.deinit();
        self.monitor_dwindle_settings_by_display.deinit();
        self.workspace_layout_settings.deinit(self.allocator);
        self.* = undefined;
    }

    fn createController(self: *RuntimeImpl) bool {
        var config = abi.OmniControllerConfig{
            .abi_version = abi.OMNI_CONTROLLER_ABI_VERSION,
            .reserved = 0,
        };
        var platform = abi.OmniControllerPlatformVTable{
            .userdata = @ptrCast(self),
            .capture_snapshot = captureSnapshotBridge,
            .apply_effects = applyEffectsBridge,
            .report_error = reportErrorBridge,
        };

        self.controller = controller_runtime.omni_controller_create_impl(&config, &platform);
        if (self.controller == null) return false;
        self.createAuxRuntimes();
        return true;
    }

    fn ensureBorderRuntime(self: *RuntimeImpl) void {
        if (self.border_runtime != null) return;

        self.border_runtime = border.omni_border_runtime_create_impl();
        if (self.border_runtime != null) {
            self.last_border_runtime_create_status = null;
            return;
        }

        const status = border.omni_border_runtime_last_create_status_impl();
        if (self.last_border_runtime_create_status) |last_status| {
            if (last_status == status) return;
        }
        self.last_border_runtime_create_status = status;

        switch (status) {
            .success => {},
            .connection_unavailable => std.log.warn(
                "border runtime unavailable: SkyLight connection not ready; will retry",
                .{},
            ),
            .missing_move_primitive => std.log.warn(
                "border runtime unavailable: missing SkyLight window move primitive",
                .{},
            ),
            .missing_skylight => std.log.warn(
                "border runtime unavailable: SkyLight symbols not loaded",
                .{},
            ),
            .missing_symbol => std.log.warn(
                "border runtime unavailable: required border symbol missing",
                .{},
            ),
            .out_of_memory => std.log.warn(
                "border runtime unavailable: out of memory during creation",
                .{},
            ),
        }
    }

    fn createAuxRuntimes(self: *RuntimeImpl) void {
        self.ensureBorderRuntime();
    }

    fn destroyAuxRuntimes(self: *RuntimeImpl) void {
        if (self.border_runtime != null) {
            _ = border.omni_border_runtime_hide_impl(self.border_runtime);
            border.omni_border_runtime_destroy_impl(self.border_runtime);
            self.border_runtime = null;
        }
    }

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
        const snapshot_rc = self.captureSnapshotForController(&snapshot, "start");
        if (snapshot_rc != abi.OMNI_OK) return snapshot_rc;
        const rc = controller_runtime.omni_controller_start_with_snapshot_impl(self.controller, &snapshot);
        if (rc == abi.OMNI_OK) {
            self.started = true;
            self.last_tick_sample_time = currentSampleTime();
            self.invalidate_all_projection_workspaces_pending = true;
            self.ensureBorderRuntime();
            if (!self.lock_screen_active) {
                _ = self.synchronizeRuntimeStateAndLayout();
            } else if (self.border_runtime != null) {
                _ = border.omni_border_runtime_hide_impl(self.border_runtime);
            }
            self.updateTickTimerLocked();
        }
        return rc;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_OK;
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        const rc = controller_runtime.omni_controller_stop_impl(self.controller);
        self.started = false;
        self.layout_light_session_active = false;
        self.layout_immediate_in_progress = false;
        self.layout_incremental_in_progress = false;
        self.layout_full_enumeration_in_progress = false;
        self.layout_animation_active = false;
        self.layout_animation_deadline = null;
        self.disarmTickTimerLocked();
        if (self.border_runtime != null) {
            _ = border.omni_border_runtime_hide_impl(self.border_runtime);
        }
        return rc;
    }

    fn flush(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_ERR_INVALID_ARGS;
        return self.synchronizeRuntimeStateAndLayout();
    }

    fn submitHotkey(self: *RuntimeImpl, command: *const abi.OmniControllerCommand) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
        const snapshot_rc = self.captureSnapshotForController(&snapshot, "hotkey");
        if (snapshot_rc != abi.OMNI_OK) return snapshot_rc;
        return controller_runtime.omni_controller_submit_hotkey_with_snapshot_impl(
            self.controller,
            command,
            &snapshot,
        );
    }

    fn submitEvent(self: *RuntimeImpl, event: *const abi.OmniControllerEvent) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        self.mergeEventSnapshotHints(event.*);
        var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
        const snapshot_rc = self.captureSnapshotForController(&snapshot, "event");
        if (snapshot_rc != abi.OMNI_OK) return snapshot_rc;
        return controller_runtime.omni_controller_submit_os_event_with_snapshot_impl(
            self.controller,
            event,
            &snapshot,
        );
    }

    fn setAXRuntime(self: *RuntimeImpl, runtime: [*c]ax_manager.OmniAXRuntime) i32 {
        self.ax_runtime = runtime;
        if (runtime == null) {
            self.tracked_ax_pids.clearRetainingCapacity();
        }
        return abi.OMNI_OK;
    }

    fn submitInputEffectBatch(self: *RuntimeImpl, effects: *const abi.OmniInputEffectExport) i32 {
        if (effects.effect_count > 0 and effects.effects == null) return abi.OMNI_ERR_INVALID_ARGS;

        var first_error: i32 = abi.OMNI_OK;
        for (0..effects.effect_count) |index| {
            const effect = effects.effects[index];
            defer releaseInputEventRefIfNeeded(effect.event);
            if (effect.kind != abi.OMNI_INPUT_EFFECT_DISPATCH_EVENT) continue;
            const rc = self.submitInputEvent(effect.event);
            if (first_error == abi.OMNI_OK and rc != abi.OMNI_OK) {
                first_error = rc;
            }
        }
        return first_error;
    }

    fn submitInputEvent(self: *RuntimeImpl, event: abi.OmniInputEvent) i32 {
        const now_sample = currentSampleTime();
        const action = self.mouse_input_handler.handleInputEvent(event, sampleTimeToMillis(now_sample));

        switch (action) {
            .focus_follows_mouse => {
                if (!self.focus_follows_mouse) return abi.OMNI_OK;
                return self.focusWindowUnderPoint(event.location_x, event.location_y);
            },
            else => return abi.OMNI_OK,
        }
    }

    fn focusWindowUnderPoint(self: *RuntimeImpl, x: f64, y: f64) i32 {
        if (self.visible_windows.items.len == 0) return abi.OMNI_OK;

        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        const export_rc = self.copyWorkspaceState(&state);
        if (export_rc != abi.OMNI_OK) return export_rc;
        const state_export = state.state_export;

        for (self.visible_windows.items) |window| {
            if (!pointInRect(x, y, window.frame)) continue;
            const handle_id = self.resolveManagedHandleForWindowId(state_export, window.pid, window.id) orelse continue;
            if (self.focused_window) |focused| {
                if (std.mem.eql(u8, focused[0..], handle_id[0..])) return abi.OMNI_OK;
            }
            return self.focusWindowByHandle(handle_id);
        }

        return abi.OMNI_OK;
    }

    fn handleFocusedWindowChanged(self: *RuntimeImpl, pid: i32) i32 {
        if (pid <= 0) return abi.OMNI_ERR_INVALID_ARGS;

        var event = std.mem.zeroes(abi.OmniControllerEvent);
        event.kind = abi.OMNI_CONTROLLER_EVENT_FOCUS_CHANGED;
        event.refresh_reason = abi.OMNI_CONTROLLER_REFRESH_REASON_TIMER;
        event.pid = pid;

        const runtime = self.ax_runtime orelse return self.submitEvent(&event);

        var has_window_id: u8 = 0;
        var window_id: u32 = 0;
        const focused_rc = ax_manager.omni_ax_runtime_get_focused_window_id_impl(
            runtime,
            pid,
            &has_window_id,
            &window_id,
        );
        const sync_rc = self.synchronizeRuntimeState();
        if (sync_rc != abi.OMNI_OK and sync_rc != abi.OMNI_ERR_PLATFORM) {
            return sync_rc;
        }

        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        const export_rc = self.copyWorkspaceState(&state);
        if (export_rc != abi.OMNI_OK) return export_rc;
        const state_export = state.state_export;

        if (focused_rc == abi.OMNI_OK and has_window_id != 0) {
            if (self.resolveManagedHandleForWindowId(state_export, pid, window_id)) |handle_id| {
                event.has_window_handle_id = 1;
                event.window_handle_id = .{ .bytes = handle_id };
            }
        }

        var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
        const snapshot_rc = self.captureSnapshotFromWorkspaceState(state_export, &snapshot);
        if (snapshot_rc != abi.OMNI_OK) return snapshot_rc;
        return controller_runtime.omni_controller_submit_os_event_with_snapshot_impl(
            self.controller,
            &event,
            &snapshot,
        );
    }

    fn applySettings(self: *RuntimeImpl, delta: *const abi.OmniControllerSettingsDelta) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (delta.struct_size != @sizeOf(abi.OmniControllerSettingsDelta)) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (delta.monitor_niri_settings_count > 0 and delta.monitor_niri_settings == null) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (delta.monitor_dwindle_settings_count > 0 and delta.monitor_dwindle_settings == null) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (delta.workspace_layout_settings_count > 0 and delta.workspace_layout_settings == null) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (delta.has_focus_follows_mouse != 0) {
            self.focus_follows_mouse = delta.focus_follows_mouse != 0;
        }
        if (delta.has_focus_follows_window_to_monitor != 0) {
            self.focus_follows_window_to_monitor = delta.focus_follows_window_to_monitor != 0;
        }
        if (delta.has_move_mouse_to_focused_window != 0) {
            self.move_mouse_to_focused_window = delta.move_mouse_to_focused_window != 0;
        }
        if (delta.has_layout_gap != 0) {
            self.layout_gap = std.math.clamp(delta.layout_gap, 0.0, 64.0);
        }
        if (delta.has_outer_gap_left != 0) {
            self.outer_gap_left = std.math.clamp(delta.outer_gap_left, 0.0, 64.0);
        }
        if (delta.has_outer_gap_right != 0) {
            self.outer_gap_right = std.math.clamp(delta.outer_gap_right, 0.0, 64.0);
        }
        if (delta.has_outer_gap_top != 0) {
            self.outer_gap_top = std.math.clamp(delta.outer_gap_top, 0.0, 64.0);
        }
        if (delta.has_outer_gap_bottom != 0) {
            self.outer_gap_bottom = std.math.clamp(delta.outer_gap_bottom, 0.0, 64.0);
        }
        if (delta.has_niri_max_visible_columns != 0) {
            self.niri_max_visible_columns = std.math.clamp(delta.niri_max_visible_columns, 1, 16);
        }
        if (delta.has_niri_max_windows_per_column != 0) {
            self.niri_max_windows_per_column = std.math.clamp(delta.niri_max_windows_per_column, 1, 16);
        }
        if (delta.has_niri_infinite_loop != 0) {
            self.niri_infinite_loop = delta.niri_infinite_loop != 0;
        }
        if (delta.has_niri_width_presets != 0) {
            var next_count = @min(
                delta.niri_width_preset_count,
                @as(usize, abi.OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP),
            );
            if (next_count == 0) next_count = default_niri_width_presets.len;
            self.niri_width_preset_count = next_count;
            for (0..next_count) |index| {
                const candidate = if (index < delta.niri_width_preset_count)
                    delta.niri_width_presets[index]
                else
                    default_niri_width_presets[@min(index, default_niri_width_presets.len - 1)];
                self.niri_width_presets[index] = std.math.clamp(candidate, 0.05, 1.0);
            }
        }
        if (delta.has_border_enabled != 0) {
            self.border_enabled = delta.border_enabled != 0;
        }
        if (delta.has_border_width != 0) {
            self.border_width = std.math.clamp(delta.border_width, 0.0, 32.0);
        }
        if (delta.has_border_color != 0) {
            self.border_color = sanitizeBorderColor(delta.border_color);
        }
        if (delta.has_default_layout_kind != 0) {
            self.default_layout_kind = self.effectiveLayoutKind(normalizeLayoutKind(delta.default_layout_kind));
        }
        if (delta.has_dwindle_move_to_root_stable != 0) {
            self.dwindle_move_to_root_stable = delta.dwindle_move_to_root_stable != 0;
        }
        self.monitor_niri_settings_by_display.clearRetainingCapacity();
        for (0..delta.monitor_niri_settings_count) |index| {
            const raw = delta.monitor_niri_settings[index];
            self.monitor_niri_settings_by_display.put(raw.display_id, .{
                .orientation = normalizeOrientation(raw.orientation),
                .center_focused_column = normalizeCenterMode(raw.center_focused_column),
                .always_center_single_column = raw.always_center_single_column != 0,
                .single_window_aspect_width = sanitizeAspectComponent(raw.single_window_aspect_width, default_single_window_aspect_width),
                .single_window_aspect_height = sanitizeAspectComponent(raw.single_window_aspect_height, default_single_window_aspect_height),
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        self.monitor_dwindle_settings_by_display.clearRetainingCapacity();
        for (0..delta.monitor_dwindle_settings_count) |index| {
            const raw = delta.monitor_dwindle_settings[index];
            self.monitor_dwindle_settings_by_display.put(raw.display_id, .{
                .smart_split = raw.smart_split != 0,
                .default_split_ratio = std.math.clamp(raw.default_split_ratio, 0.1, 1.9),
                .split_width_multiplier = std.math.clamp(raw.split_width_multiplier, 0.1, 4.0),
                .inner_gap = std.math.clamp(raw.inner_gap, 0.0, 64.0),
                .outer_gap_top = std.math.clamp(raw.outer_gap_top, 0.0, 64.0),
                .outer_gap_bottom = std.math.clamp(raw.outer_gap_bottom, 0.0, 64.0),
                .outer_gap_left = std.math.clamp(raw.outer_gap_left, 0.0, 64.0),
                .outer_gap_right = std.math.clamp(raw.outer_gap_right, 0.0, 64.0),
                .single_window_aspect_width = sanitizeAspectComponent(raw.single_window_aspect_width, default_single_window_aspect_width),
                .single_window_aspect_height = sanitizeAspectComponent(raw.single_window_aspect_height, default_single_window_aspect_height),
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        self.workspace_layout_settings.clearRetainingCapacity();
        self.workspace_layout_settings.ensureTotalCapacity(self.allocator, delta.workspace_layout_settings_count) catch {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };
        for (0..delta.workspace_layout_settings_count) |index| {
            const raw = delta.workspace_layout_settings[index];
            self.workspace_layout_settings.appendAssumeCapacity(.{
                .name = raw.name,
                .layout_kind = normalizeLayoutKind(raw.layout_kind),
            });
        }
        return controller_runtime.omni_controller_apply_settings_impl(self.controller, delta);
    }

    fn tick(self: *RuntimeImpl, sample_time: f64) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
        const snapshot_rc = self.captureSnapshotForController(&snapshot, "tick");
        if (snapshot_rc != abi.OMNI_OK) return snapshot_rc;
        const rc = controller_runtime.omni_controller_tick_with_snapshot_impl(
            self.controller,
            sample_time,
            &snapshot,
        );
        if (rc != abi.OMNI_OK) return rc;

        self.last_tick_sample_time = if (sample_time > 0) sample_time else currentSampleTime();

        if (self.layout_animation_deadline) |deadline| {
            if (self.last_tick_sample_time >= deadline) {
                self.layout_animation_active = false;
                self.layout_animation_deadline = null;
            }
        }

        const sync_rc = self.synchronizeRuntimeStateAndLayout();
        if (sync_rc != abi.OMNI_OK and sync_rc != abi.OMNI_ERR_PLATFORM) {
            return sync_rc;
        }
        self.updateTickTimerLocked();
        return sync_rc;
    }

    fn createFrozenSnapshot(self: *RuntimeImpl) ?*SnapshotImpl {
        if (!self.started) return null;

        const snapshot = std.heap.c_allocator.create(SnapshotImpl) catch return null;
        snapshot.* = SnapshotImpl.init(std.heap.c_allocator);
        errdefer {
            snapshot.deinit();
            std.heap.c_allocator.destroy(snapshot);
        }

        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        if (self.copyWorkspaceState(&state) != abi.OMNI_OK) {
            return null;
        }
        const state_export = state.state_export;
        var controller_snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
        if (self.captureSnapshotFromWorkspaceState(state_export, &controller_snapshot) != abi.OMNI_OK) {
            return null;
        }
        if (self.copyControllerStateIntoSnapshot(controller_snapshot, snapshot) != abi.OMNI_OK) {
            return null;
        }
        if (self.copyWorkspaceStateIntoSnapshot(state_export, snapshot) != abi.OMNI_OK) {
            return null;
        }
        if (self.queryUiState(&snapshot.ui_state) != abi.OMNI_OK) {
            return null;
        }
        if (self.drainChangedWorkspacesIntoSnapshot(snapshot) != abi.OMNI_OK) {
            return null;
        }
        return snapshot;
    }

    fn copyControllerStateIntoSnapshot(
        _: *RuntimeImpl,
        controller_snapshot: abi.OmniControllerSnapshot,
        snapshot: *SnapshotImpl,
    ) i32 {
        if (controller_snapshot.monitor_count > 0 and controller_snapshot.monitors == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (controller_snapshot.workspace_count > 0 and controller_snapshot.workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (controller_snapshot.window_count > 0 and controller_snapshot.windows == null) return abi.OMNI_ERR_INVALID_ARGS;

        snapshot.controller_monitor_snapshots = snapshot.allocator.alloc(
            abi.OmniControllerMonitorSnapshot,
            controller_snapshot.monitor_count,
        ) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        snapshot.controller_workspace_snapshots = snapshot.allocator.alloc(
            abi.OmniControllerWorkspaceSnapshot,
            controller_snapshot.workspace_count,
        ) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        snapshot.controller_window_snapshots = snapshot.allocator.alloc(
            abi.OmniControllerWindowSnapshot,
            controller_snapshot.window_count,
        ) catch return abi.OMNI_ERR_OUT_OF_RANGE;

        if (controller_snapshot.monitor_count > 0) {
            std.mem.copyForwards(
                abi.OmniControllerMonitorSnapshot,
                snapshot.controller_monitor_snapshots,
                controller_snapshot.monitors[0..controller_snapshot.monitor_count],
            );
        }
        if (controller_snapshot.workspace_count > 0) {
            std.mem.copyForwards(
                abi.OmniControllerWorkspaceSnapshot,
                snapshot.controller_workspace_snapshots,
                controller_snapshot.workspaces[0..controller_snapshot.workspace_count],
            );
        }
        if (controller_snapshot.window_count > 0) {
            std.mem.copyForwards(
                abi.OmniControllerWindowSnapshot,
                snapshot.controller_window_snapshots,
                controller_snapshot.windows[0..controller_snapshot.window_count],
            );
        }

        snapshot.controller_snapshot = controller_snapshot;
        snapshot.controller_snapshot.monitors = if (snapshot.controller_monitor_snapshots.len == 0)
            null
        else
            snapshot.controller_monitor_snapshots.ptr;
        snapshot.controller_snapshot.workspaces = if (snapshot.controller_workspace_snapshots.len == 0)
            null
        else
            snapshot.controller_workspace_snapshots.ptr;
        snapshot.controller_snapshot.windows = if (snapshot.controller_window_snapshots.len == 0)
            null
        else
            snapshot.controller_window_snapshots.ptr;
        return abi.OMNI_OK;
    }

    fn copyWorkspaceStateIntoSnapshot(
        _: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        snapshot: *SnapshotImpl,
    ) i32 {
        if (state_export.monitor_count > 0 and state_export.monitors == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (state_export.workspace_count > 0 and state_export.workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (state_export.window_count > 0 and state_export.windows == null) return abi.OMNI_ERR_INVALID_ARGS;

        snapshot.monitor_records = snapshot.allocator.alloc(
            abi.OmniWorkspaceRuntimeMonitorRecord,
            state_export.monitor_count,
        ) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        snapshot.workspace_records = snapshot.allocator.alloc(
            abi.OmniWorkspaceRuntimeWorkspaceRecord,
            state_export.workspace_count,
        ) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        snapshot.window_records = snapshot.allocator.alloc(
            abi.OmniWorkspaceRuntimeWindowRecord,
            state_export.window_count,
        ) catch return abi.OMNI_ERR_OUT_OF_RANGE;

        if (state_export.monitor_count > 0) {
            std.mem.copyForwards(
                abi.OmniWorkspaceRuntimeMonitorRecord,
                snapshot.monitor_records,
                state_export.monitors[0..state_export.monitor_count],
            );
        }
        if (state_export.workspace_count > 0) {
            std.mem.copyForwards(
                abi.OmniWorkspaceRuntimeWorkspaceRecord,
                snapshot.workspace_records,
                state_export.workspaces[0..state_export.workspace_count],
            );
        }
        if (state_export.window_count > 0) {
            std.mem.copyForwards(
                abi.OmniWorkspaceRuntimeWindowRecord,
                snapshot.window_records,
                state_export.windows[0..state_export.window_count],
            );
        }

        snapshot.workspace_export = .{
            .monitors = if (snapshot.monitor_records.len == 0) null else snapshot.monitor_records.ptr,
            .monitor_count = snapshot.monitor_records.len,
            .workspaces = if (snapshot.workspace_records.len == 0) null else snapshot.workspace_records.ptr,
            .workspace_count = snapshot.workspace_records.len,
            .windows = if (snapshot.window_records.len == 0) null else snapshot.window_records.ptr,
            .window_count = snapshot.window_records.len,
            .has_active_monitor_display_id = state_export.has_active_monitor_display_id,
            .active_monitor_display_id = state_export.active_monitor_display_id,
            .has_previous_monitor_display_id = state_export.has_previous_monitor_display_id,
            .previous_monitor_display_id = state_export.previous_monitor_display_id,
        };
        snapshot.counts.monitor_count = snapshot.monitor_records.len;
        snapshot.counts.workspace_count = snapshot.workspace_records.len;
        snapshot.counts.window_count = snapshot.window_records.len;
        return abi.OMNI_OK;
    }

    fn drainChangedWorkspacesIntoSnapshot(self: *RuntimeImpl, snapshot: *SnapshotImpl) i32 {
        snapshot.counts.invalidate_all_workspace_projections = 0;

        if (self.invalidate_all_projection_workspaces_pending) {
            self.dirty_projection_workspaces.clearRetainingCapacity();
            self.invalidate_all_projection_workspaces_pending = false;
            snapshot.counts.changed_workspace_count = 0;
            snapshot.counts.invalidate_all_workspace_projections = 1;
            return abi.OMNI_OK;
        }

        const changed_count = self.dirty_projection_workspaces.count();
        snapshot.changed_workspace_ids = snapshot.allocator.alloc(abi.OmniUuid128, changed_count) catch {
            self.dirty_projection_workspaces.clearRetainingCapacity();
            snapshot.counts.changed_workspace_count = 0;
            snapshot.counts.invalidate_all_workspace_projections = 1;
            return abi.OMNI_OK;
        };

        var index: usize = 0;
        var it = self.dirty_projection_workspaces.keyIterator();
        while (it.next()) |workspace_id_ptr| {
            snapshot.changed_workspace_ids[index] = .{ .bytes = workspace_id_ptr.* };
            index += 1;
        }
        self.dirty_projection_workspaces.clearRetainingCapacity();
        snapshot.counts.changed_workspace_count = index;
        return abi.OMNI_OK;
    }

    fn queryUiState(self: *const RuntimeImpl, out_state: *abi.OmniControllerUiState) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        return controller_runtime.omni_controller_query_ui_state_impl(self.controller, out_state);
    }

    fn exportWorkspaceState(self: *RuntimeImpl, out_export: *abi.OmniWorkspaceRuntimeStateExport) i32 {
        return workspace_runtime.omni_workspace_runtime_export_state_impl(self.workspace_runtime_owner, out_export);
    }

    fn copyWorkspaceState(self: *RuntimeImpl, out_state: *OwnedWorkspaceState) i32 {
        out_state.* = OwnedWorkspaceState.init(self.allocator);

        var counts = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateCounts);
        const counts_rc = workspace_runtime.omni_workspace_runtime_query_state_counts_impl(
            self.workspace_runtime_owner,
            &counts,
        );
        if (counts_rc != abi.OMNI_OK) return counts_rc;

        var attempt: usize = 0;
        while (attempt < 4) : (attempt += 1) {
            const monitor_records = self.allocator.alloc(
                abi.OmniWorkspaceRuntimeMonitorRecord,
                counts.monitor_count,
            ) catch return abi.OMNI_ERR_OUT_OF_RANGE;

            const workspace_records = self.allocator.alloc(
                abi.OmniWorkspaceRuntimeWorkspaceRecord,
                counts.workspace_count,
            ) catch {
                if (monitor_records.len > 0) self.allocator.free(monitor_records);
                return abi.OMNI_ERR_OUT_OF_RANGE;
            };

            const window_records = self.allocator.alloc(
                abi.OmniWorkspaceRuntimeWindowRecord,
                counts.window_count,
            ) catch {
                if (workspace_records.len > 0) self.allocator.free(workspace_records);
                if (monitor_records.len > 0) self.allocator.free(monitor_records);
                return abi.OMNI_ERR_OUT_OF_RANGE;
            };

            var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
            const rc = workspace_runtime.omni_workspace_runtime_copy_state_impl(
                self.workspace_runtime_owner,
                &state_export,
                if (monitor_records.len == 0) null else monitor_records.ptr,
                monitor_records.len,
                if (workspace_records.len == 0) null else workspace_records.ptr,
                workspace_records.len,
                if (window_records.len == 0) null else window_records.ptr,
                window_records.len,
            );
            if (rc == abi.OMNI_OK) {
                out_state.monitors = monitor_records;
                out_state.workspaces = workspace_records;
                out_state.windows = window_records;
                out_state.state_export = state_export;
                return abi.OMNI_OK;
            }
            if (window_records.len > 0) self.allocator.free(window_records);
            if (workspace_records.len > 0) self.allocator.free(workspace_records);
            if (monitor_records.len > 0) self.allocator.free(monitor_records);
            if (rc != abi.OMNI_ERR_OUT_OF_RANGE) return rc;

            if (state_export.monitor_count > counts.monitor_count) {
                counts.monitor_count = state_export.monitor_count;
            }
            if (state_export.workspace_count > counts.workspace_count) {
                counts.workspace_count = state_export.workspace_count;
            }
            if (state_export.window_count > counts.window_count) {
                counts.window_count = state_export.window_count;
            }
        }

        return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    fn populateWorkspaceProjectionSnapshots(self: *RuntimeImpl) i32 {
        if (self.projection_generation_tracking_failed) return abi.OMNI_ERR_OUT_OF_RANGE;

        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        const export_rc = self.copyWorkspaceState(&state);
        if (export_rc != abi.OMNI_OK) return export_rc;
        const state_export = state.state_export;
        if (state_export.workspace_count > 0 and state_export.workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.workspace_projection_snapshots.clearRetainingCapacity();
        self.workspace_projection_snapshots.ensureTotalCapacity(self.allocator, state_export.workspace_count) catch {
            self.projection_generation_tracking_failed = true;
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };

        var stale_workspace_ids = std.ArrayListUnmanaged(Uuid){};
        defer stale_workspace_ids.deinit(self.allocator);
        var generation_it = self.projection_generation_by_workspace.keyIterator();
        while (generation_it.next()) |workspace_id_ptr| {
            if (workspaceRecordById(state_export, workspace_id_ptr.*) != null) continue;
            stale_workspace_ids.append(self.allocator, workspace_id_ptr.*) catch {
                self.projection_generation_tracking_failed = true;
                return abi.OMNI_ERR_OUT_OF_RANGE;
            };
        }
        for (stale_workspace_ids.items) |workspace_id| {
            _ = self.projection_generation_by_workspace.remove(workspace_id);
        }

        if (state_export.workspace_count == 0) return abi.OMNI_OK;
        for (state_export.workspaces[0..state_export.workspace_count]) |workspace| {
            self.workspace_projection_snapshots.appendAssumeCapacity(.{
                .workspace_id = workspace.workspace_id,
                .layout_generation = self.projectionGenerationForWorkspace(workspace.workspace_id.bytes),
            });
        }
        return abi.OMNI_OK;
    }

    fn queryWorkspaceProjectionCounts(
        self: *RuntimeImpl,
        out_counts: *abi.OmniControllerWorkspaceProjectionCounts,
    ) i32 {
        const rc = self.populateWorkspaceProjectionSnapshots();
        if (rc != abi.OMNI_OK) return rc;
        out_counts.* = .{
            .workspace_count = self.workspace_projection_snapshots.items.len,
        };
        return abi.OMNI_OK;
    }

    fn copyWorkspaceProjections(
        self: *RuntimeImpl,
        out_records: [*]abi.OmniControllerWorkspaceProjectionRecord,
        record_capacity: usize,
        out_record_count: *usize,
    ) i32 {
        const rc = self.populateWorkspaceProjectionSnapshots();
        if (rc != abi.OMNI_OK) return rc;
        const records = self.workspace_projection_snapshots.items;
        if (records.len > record_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
        if (records.len > 0) {
            std.mem.copyForwards(abi.OmniControllerWorkspaceProjectionRecord, out_records[0..records.len], records);
        }
        out_record_count.* = records.len;
        return abi.OMNI_OK;
    }

    fn queryWorkspaceLayoutSettingsCount(
        self: *const RuntimeImpl,
        out_setting_count: *usize,
    ) i32 {
        out_setting_count.* = self.workspace_layout_settings.items.len;
        return abi.OMNI_OK;
    }

    fn copyWorkspaceLayoutSettings(
        self: *const RuntimeImpl,
        out_settings: [*]abi.OmniControllerWorkspaceLayoutSetting,
        setting_capacity: usize,
        out_setting_count: *usize,
    ) i32 {
        const settings = self.workspace_layout_settings.items;
        if (settings.len > setting_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;

        for (settings, 0..) |setting, index| {
            out_settings[index] = .{
                .name = setting.name,
                .layout_kind = switch (setting.layout_kind) {
                    .default_layout => abi.OMNI_CONTROLLER_LAYOUT_DEFAULT,
                    .niri => abi.OMNI_CONTROLLER_LAYOUT_NIRI,
                    .dwindle => abi.OMNI_CONTROLLER_LAYOUT_DWINDLE,
                },
            };
        }
        out_setting_count.* = settings.len;
        return abi.OMNI_OK;
    }

    fn seedLockStateForStart(self: *RuntimeImpl, locked: bool) void {
        self.lock_screen_active = locked;
    }

    fn captureSnapshotForController(
        self: *RuntimeImpl,
        out_snapshot: *abi.OmniControllerSnapshot,
        phase: []const u8,
    ) i32 {
        const sync_rc = self.synchronizeRuntimeState();
        if (sync_rc != abi.OMNI_OK and sync_rc != abi.OMNI_ERR_PLATFORM) {
            var buffer: [64]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, "{s} snapshot pre-sync failed", .{phase}) catch
                return self.reportPhaseError(sync_rc, "controller snapshot pre-sync failed");
            return self.reportPhaseError(sync_rc, message);
        }
        var workspace_state = OwnedWorkspaceState.init(self.allocator);
        defer workspace_state.deinit();

        const export_rc = self.copyWorkspaceState(&workspace_state);
        if (export_rc != abi.OMNI_OK) {
            var buffer: [64]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, "{s} workspace export failed", .{phase}) catch
                return self.reportPhaseError(export_rc, "controller workspace export failed");
            return self.reportPhaseError(export_rc, message);
        }
        const capture_rc = self.captureSnapshotFromWorkspaceState(workspace_state.state_export, out_snapshot);
        if (capture_rc != abi.OMNI_OK) {
            var buffer: [64]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, "{s} snapshot capture failed", .{phase}) catch
                return self.reportPhaseError(capture_rc, "controller snapshot capture failed");
            return self.reportPhaseError(capture_rc, message);
        }
        return abi.OMNI_OK;
    }

    fn ensureWorkspaceLayoutRuntime(self: *RuntimeImpl, workspace_id: Uuid) !*WorkspaceLayoutRuntime {
        if (self.workspace_layout_runtimes.getPtr(workspace_id)) |entry| {
            return entry;
        }

        const runtime_owner = niri_runtime.omni_niri_runtime_create_impl();
        if (runtime_owner == null) {
            return error.OutOfMemory;
        }
        errdefer niri_runtime.omni_niri_runtime_destroy_impl(runtime_owner);

        try self.workspace_layout_runtimes.put(workspace_id, .{
            .runtime = runtime_owner,
        });
        return self.workspace_layout_runtimes.getPtr(workspace_id).?;
    }

    fn ensureWorkspaceDwindleRuntime(self: *RuntimeImpl, workspace_id: Uuid) !*WorkspaceDwindleRuntime {
        if (self.workspace_dwindle_runtimes.getPtr(workspace_id)) |entry| {
            return entry;
        }

        const context = dwindle.omni_dwindle_layout_context_create_impl();
        if (context == null) {
            return error.OutOfMemory;
        }
        errdefer dwindle.omni_dwindle_layout_context_destroy_impl(context);

        try self.workspace_dwindle_runtimes.put(workspace_id, .{
            .context = context,
        });
        return self.workspace_dwindle_runtimes.getPtr(workspace_id).?;
    }

    fn removeWorkspaceLayoutRuntime(self: *RuntimeImpl, workspace_id: Uuid, clear_cached_state: bool) void {
        if (self.workspace_layout_runtimes.fetchRemove(workspace_id)) |entry| {
            var value = entry.value;
            value.deinit();
        }
        if (clear_cached_state) {
            _ = self.managed_fullscreen_by_workspace.remove(workspace_id);
            self.clearWorkspaceSelectionCache(workspace_id);
            _ = self.projection_generation_by_workspace.remove(workspace_id);
            _ = self.dirty_projection_workspaces.remove(workspace_id);
        } else {
            _ = self.managed_fullscreen_by_workspace.remove(workspace_id);
            _ = self.selected_node_by_workspace.remove(workspace_id);
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
    }

    fn removeWorkspaceDwindleRuntime(self: *RuntimeImpl, workspace_id: Uuid, clear_cached_state: bool) void {
        if (self.workspace_dwindle_runtimes.fetchRemove(workspace_id)) |entry| {
            var value = entry.value;
            value.deinit();
        }
        if (clear_cached_state) {
            _ = self.managed_fullscreen_by_workspace.remove(workspace_id);
            self.clearWorkspaceSelectionCache(workspace_id);
            _ = self.projection_generation_by_workspace.remove(workspace_id);
            _ = self.dirty_projection_workspaces.remove(workspace_id);
        } else {
            _ = self.managed_fullscreen_by_workspace.remove(workspace_id);
            _ = self.selected_node_by_workspace.remove(workspace_id);
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
    }

    fn clearWorkspaceSelectionCache(self: *RuntimeImpl, workspace_id: Uuid) void {
        const removed_selected = self.selected_node_by_workspace.remove(workspace_id);
        const removed_focused = self.last_focused_by_workspace.remove(workspace_id);
        if (removed_selected or removed_focused) {
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
    }

    fn bumpWorkspaceProjectionGeneration(self: *RuntimeImpl, workspace_id: Uuid) void {
        self.markWorkspaceProjectionDirty(workspace_id);
        const next_generation = (self.projection_generation_by_workspace.get(workspace_id) orelse 0) +% 1;
        self.projection_generation_by_workspace.put(workspace_id, next_generation) catch {
            self.projection_generation_tracking_failed = true;
        };
    }

    fn markWorkspaceProjectionDirty(self: *RuntimeImpl, workspace_id: Uuid) void {
        if (self.invalidate_all_projection_workspaces_pending) return;
        self.dirty_projection_workspaces.put(workspace_id, {}) catch {
            self.dirty_projection_workspaces.clearRetainingCapacity();
            self.invalidate_all_projection_workspaces_pending = true;
        };
    }

    fn projectionGenerationForWorkspace(self: *RuntimeImpl, workspace_id: Uuid) u64 {
        return self.projection_generation_by_workspace.get(workspace_id) orelse 0;
    }

    fn setSelectedNode(self: *RuntimeImpl, workspace_id: Uuid, node_id: Uuid) void {
        const current = self.selected_node_by_workspace.get(workspace_id);
        if (current != null and std.mem.eql(u8, current.?[0..], node_id[0..])) return;
        self.selected_node_by_workspace.put(workspace_id, node_id) catch {
            self.projection_generation_tracking_failed = true;
            return;
        };
        self.bumpWorkspaceProjectionGeneration(workspace_id);
    }

    fn setLastFocusedWindow(self: *RuntimeImpl, workspace_id: Uuid, window_id: Uuid) void {
        const current = self.last_focused_by_workspace.get(workspace_id);
        if (current != null and std.mem.eql(u8, current.?[0..], window_id[0..])) return;
        self.last_focused_by_workspace.put(workspace_id, window_id) catch {
            self.projection_generation_tracking_failed = true;
            return;
        };
        self.bumpWorkspaceProjectionGeneration(workspace_id);
    }

    fn clearLastFocusedWindow(self: *RuntimeImpl, workspace_id: Uuid) void {
        if (self.last_focused_by_workspace.remove(workspace_id)) {
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
    }

    fn setManagedFullscreenWindow(self: *RuntimeImpl, workspace_id: Uuid, window_id: Uuid) void {
        const current = self.managed_fullscreen_by_workspace.get(workspace_id);
        if (current != null and std.mem.eql(u8, current.?[0..], window_id[0..])) return;
        self.managed_fullscreen_by_workspace.put(workspace_id, window_id) catch {
            self.projection_generation_tracking_failed = true;
            return;
        };
        self.bumpWorkspaceProjectionGeneration(workspace_id);
    }

    fn clearManagedFullscreenWindow(self: *RuntimeImpl, workspace_id: Uuid) void {
        if (self.managed_fullscreen_by_workspace.remove(workspace_id)) {
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
    }

    fn snapshotWorkspaceLayoutRuntime(
        self: *RuntimeImpl,
        workspace_id: Uuid,
        out_export: *abi.OmniNiriRuntimeStateExport,
    ) i32 {
        const entry = self.workspace_layout_runtimes.getPtr(workspace_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        return niri_runtime.omni_niri_runtime_snapshot_impl(entry.runtime, out_export);
    }

    fn snapshotWorkspaceLayoutRuntimeRecovering(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
        out_export: *abi.OmniNiriRuntimeStateExport,
    ) i32 {
        var snapshot_rc = self.snapshotWorkspaceLayoutRuntime(workspace_id, out_export);
        if (snapshot_rc == abi.OMNI_OK and runtimeExportIsCoherent(out_export.*)) {
            return abi.OMNI_OK;
        }

        const reseed_rc = self.syncWorkspaceLayoutRuntimeForWorkspace(state_export, workspace_id);
        if (reseed_rc != abi.OMNI_OK) return reseed_rc;

        snapshot_rc = self.snapshotWorkspaceLayoutRuntime(workspace_id, out_export);
        if (snapshot_rc != abi.OMNI_OK) return snapshot_rc;
        if (!runtimeExportIsCoherent(out_export.*)) return abi.OMNI_ERR_OUT_OF_RANGE;
        return abi.OMNI_OK;
    }

    fn buildWorkspaceSelectionState(
        self: *RuntimeImpl,
        workspace_id: Uuid,
        runtime_export: abi.OmniNiriRuntimeStateExport,
        prefer_first_window: bool,
    ) WorkspaceSelectionState {
        var state = WorkspaceSelectionState{};

        if (self.managed_fullscreen_by_workspace.get(workspace_id)) |fullscreen_window_id| {
            if (findRuntimeWindowIndex(runtime_export, fullscreen_window_id) != null) {
                state.managed_fullscreen_window_id = fullscreen_window_id;
            } else {
                self.clearManagedFullscreenWindow(workspace_id);
            }
        }

        if (self.focused_window) |focused_window_id| {
            if (findRuntimeWindowIndex(runtime_export, focused_window_id)) |focused_index| {
                state.focused_window_id = focused_window_id;
                const runtime_window = runtime_export.windows[focused_index];
                state.selected_column_id = runtime_window.column_id.bytes;
            }
        }

        if (self.selected_node_by_workspace.get(workspace_id)) |selected_node_id| {
            if (findRuntimeWindowIndex(runtime_export, selected_node_id)) |selected_window_index| {
                state.selected_node_id = selected_node_id;
                if (state.focused_window_id == null) {
                    state.focused_window_id = selected_node_id;
                }
                const runtime_window = runtime_export.windows[selected_window_index];
                state.selected_column_id = runtime_window.column_id.bytes;
            } else if (findRuntimeColumnIndex(runtime_export, selected_node_id)) |_| {
                state.selected_node_id = selected_node_id;
                state.selected_column_id = selected_node_id;
            } else {
                self.clearWorkspaceSelectionCache(workspace_id);
            }
        }

        if (state.selected_node_id == null) {
            if (state.focused_window_id) |focused_window_id| {
                state.selected_node_id = focused_window_id;
            } else if (self.last_focused_by_workspace.get(workspace_id)) |last_focused_id| {
                if (findRuntimeWindowIndex(runtime_export, last_focused_id)) |last_focused_index| {
                    state.selected_node_id = last_focused_id;
                    state.focused_window_id = last_focused_id;
                    const runtime_window = runtime_export.windows[last_focused_index];
                    state.selected_column_id = runtime_window.column_id.bytes;
                } else {
                    self.clearLastFocusedWindow(workspace_id);
                }
            }
        }

        if (state.selected_column_id == null) {
            if (state.focused_window_id) |focused_window_id| {
                if (findRuntimeWindowIndex(runtime_export, focused_window_id)) |focused_index| {
                    state.selected_column_id = runtime_export.windows[focused_index].column_id.bytes;
                }
            }
        }

        if (state.selected_node_id) |selected_node_id| {
            if (findRuntimeWindowIndex(runtime_export, selected_node_id)) |_| {
                state.actionable_window_id = selected_node_id;
            } else if (findRuntimeColumnIndex(runtime_export, selected_node_id)) |selected_column_index| {
                if (selectedColumnActionableWindow(runtime_export, selected_column_index)) |window_id| {
                    state.actionable_window_id = window_id.bytes;
                    state.selected_column_id = selected_node_id;
                }
            }
        }

        if (state.actionable_window_id == null and state.focused_window_id != null) {
            state.actionable_window_id = state.focused_window_id;
        }

        if (prefer_first_window and state.selected_node_id == null and runtime_export.window_count > 0 and runtime_export.windows != null) {
            const first_window_id = runtime_export.windows[0].window_id.bytes;
            state.selected_node_id = first_window_id;
            state.focused_window_id = state.focused_window_id orelse first_window_id;
            state.actionable_window_id = state.actionable_window_id orelse first_window_id;
            state.selected_column_id = runtime_export.windows[0].column_id.bytes;
        }

        if (state.selected_node_id == null and runtime_export.column_count == 1 and runtime_export.columns != null) {
            const column = runtime_export.columns[0];
            if (column.window_count == 0) {
                state.selected_node_id = column.column_id.bytes;
                state.selected_column_id = column.column_id.bytes;
            }
        }

        return state;
    }

    fn dwindleSettingsForDisplay(self: *const RuntimeImpl, display_id: u32) MonitorDwindleSettings {
        return self.monitor_dwindle_settings_by_display.get(display_id) orelse .{
            .smart_split = true,
            .default_split_ratio = default_dwindle_split_ratio,
            .split_width_multiplier = default_dwindle_split_width_multiplier,
            .inner_gap = self.layout_gap,
            .outer_gap_top = self.outer_gap_top,
            .outer_gap_bottom = self.outer_gap_bottom,
            .outer_gap_left = self.outer_gap_left,
            .outer_gap_right = self.outer_gap_right,
            .single_window_aspect_width = default_single_window_aspect_width,
            .single_window_aspect_height = default_single_window_aspect_height,
        };
    }

    fn dwindleSettingsForWorkspace(
        self: *const RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
    ) MonitorDwindleSettings {
        if (monitorForWorkspace(state_export, workspace_id)) |monitor| {
            return self.dwindleSettingsForDisplay(monitor.display_id);
        }
        return self.dwindleSettingsForDisplay(0);
    }

    fn dwindleRuntimeSettings(raw: MonitorDwindleSettings) abi.OmniDwindleRuntimeSettings {
        return .{
            .smart_split = if (raw.smart_split) 1 else 0,
            .default_split_ratio = raw.default_split_ratio,
            .split_width_multiplier = raw.split_width_multiplier,
            .inner_gap = raw.inner_gap,
        };
    }

    fn applyDwindleOp(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
        request: *abi.OmniDwindleOpRequest,
        out_result: *abi.OmniDwindleOpResult,
        removed_window_ids: []abi.OmniUuid128,
    ) i32 {
        const runtime = self.ensureWorkspaceDwindleRuntime(workspace_id) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        request.runtime_settings = dwindleRuntimeSettings(self.dwindleSettingsForWorkspace(state_export, workspace_id));
        return dwindle.omni_dwindle_ctx_apply_op_impl(
            runtime.context,
            request,
            out_result,
            if (removed_window_ids.len == 0) null else removed_window_ids.ptr,
            removed_window_ids.len,
        );
    }

    fn updateDwindleSelectionStateFromResult(
        self: *RuntimeImpl,
        workspace_id: Uuid,
        result: abi.OmniDwindleOpResult,
    ) void {
        if (result.has_selected_window_id != 0) {
            self.setSelectedNode(workspace_id, result.selected_window_id.bytes);
        } else if (self.selected_node_by_workspace.remove(workspace_id)) {
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
        if (result.has_focused_window_id != 0) {
            self.setLastFocusedWindow(workspace_id, result.focused_window_id.bytes);
        } else {
            self.clearLastFocusedWindow(workspace_id);
        }
    }

    fn syncManagedFullscreenFromDwindleRuntime(
        self: *RuntimeImpl,
        workspace_id: Uuid,
    ) void {
        const runtime = self.workspace_dwindle_runtimes.getPtr(workspace_id) orelse {
            self.clearManagedFullscreenWindow(workspace_id);
            return;
        };
        const ctx: *const dwindle.OmniDwindleLayoutContext = @ptrCast(@alignCast(runtime.context));
        for (0..ctx.node_count) |node_index| {
            const node = ctx.nodes[node_index];
            if (node.kind != abi.OMNI_DWINDLE_NODE_LEAF or node.has_window_id == 0) continue;
            if (node.is_fullscreen != 0) {
                self.setManagedFullscreenWindow(workspace_id, node.window_id.bytes);
                return;
            }
        }
        self.clearManagedFullscreenWindow(workspace_id);
    }

    fn syncWorkspaceDwindleRuntimeForWorkspace(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
    ) i32 {
        _ = self.ensureWorkspaceDwindleRuntime(workspace_id) catch return abi.OMNI_ERR_OUT_OF_RANGE;

        var managed_window_ids = [_]abi.OmniUuid128{zeroUuid()} ** abi.MAX_WINDOWS;
        var managed_count: usize = 0;
        if (state_export.window_count > 0 and state_export.windows != null) {
            for (state_export.windows[0..state_export.window_count]) |window| {
                if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id[0..])) continue;
                if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
                if (managed_count >= abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
                managed_window_ids[managed_count] = window.handle_id;
                managed_count += 1;
            }
        }

        var request = abi.OmniDwindleOpRequest{
            .op = abi.OMNI_DWINDLE_OP_SYNC_WINDOWS,
            .payload = undefined,
            .runtime_settings = undefined,
        };
        request.payload.sync_windows = .{
            .window_ids = if (managed_count == 0) null else &managed_window_ids[0],
            .window_count = managed_count,
        };
        var result = std.mem.zeroes(abi.OmniDwindleOpResult);
        var removed_window_ids = [_]abi.OmniUuid128{zeroUuid()} ** abi.MAX_WINDOWS;
        const rc = self.applyDwindleOp(
            state_export,
            workspace_id,
            &request,
            &result,
            removed_window_ids[0..],
        );
        if (rc != abi.OMNI_OK) return rc;

        if (managed_count == 0) {
            if (self.selected_node_by_workspace.remove(workspace_id)) {
                self.bumpWorkspaceProjectionGeneration(workspace_id);
            }
            self.clearLastFocusedWindow(workspace_id);
        } else {
            self.updateDwindleSelectionStateFromResult(workspace_id, result);
        }
        self.syncManagedFullscreenFromDwindleRuntime(workspace_id);
        self.bumpWorkspaceProjectionGeneration(workspace_id);
        return abi.OMNI_OK;
    }

    fn syncWorkspaceLayoutRuntimes(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) i32 {
        var stale_workspace_ids = std.ArrayListUnmanaged(Uuid){};
        defer stale_workspace_ids.deinit(self.allocator);

        var workspace_it = self.workspace_layout_runtimes.keyIterator();
        while (workspace_it.next()) |workspace_id_ptr| {
            if (workspaceRecordById(state_export, workspace_id_ptr.*) != null) continue;
            stale_workspace_ids.append(self.allocator, workspace_id_ptr.*) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        for (stale_workspace_ids.items) |workspace_id| {
            self.removeWorkspaceLayoutRuntime(workspace_id, true);
        }

        stale_workspace_ids.clearRetainingCapacity();
        var dwindle_workspace_it = self.workspace_dwindle_runtimes.keyIterator();
        while (dwindle_workspace_it.next()) |workspace_id_ptr| {
            if (workspaceRecordById(state_export, workspace_id_ptr.*) != null) continue;
            stale_workspace_ids.append(self.allocator, workspace_id_ptr.*) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        for (stale_workspace_ids.items) |workspace_id| {
            self.removeWorkspaceDwindleRuntime(workspace_id, true);
        }

        if (state_export.workspace_count == 0 or state_export.workspaces == null) {
            return abi.OMNI_OK;
        }

        for (state_export.workspaces[0..state_export.workspace_count]) |workspace| {
            switch (self.layoutKindForWorkspaceRecord(workspace)) {
                .niri => {
                    self.removeWorkspaceDwindleRuntime(workspace.workspace_id.bytes, false);
                    const sync_rc = self.syncWorkspaceLayoutRuntimeForWorkspace(state_export, workspace.workspace_id.bytes);
                    if (sync_rc != abi.OMNI_OK) return sync_rc;
                },
                .dwindle => {
                    self.removeWorkspaceLayoutRuntime(workspace.workspace_id.bytes, false);
                    const sync_rc = self.syncWorkspaceDwindleRuntimeForWorkspace(state_export, workspace.workspace_id.bytes);
                    if (sync_rc != abi.OMNI_OK) return sync_rc;
                },
                .default_layout => unreachable,
            }
        }

        if (self.focused_window) |focused_window_id| {
            if (!managedWindowExists(state_export, focused_window_id)) {
                self.focused_window = null;
            }
        }

        return abi.OMNI_OK;
    }

    fn syncWorkspaceLayoutRuntimeForWorkspace(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
    ) i32 {
        const entry = self.ensureWorkspaceLayoutRuntime(workspace_id) catch return abi.OMNI_ERR_OUT_OF_RANGE;

        var previous_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
        const previous_rc = niri_runtime.omni_niri_runtime_snapshot_impl(entry.runtime, &previous_export);
        const has_previous = previous_rc == abi.OMNI_OK and runtimeExportIsCoherent(previous_export);

        var managed_windows = [_]abi.OmniWorkspaceRuntimeWindowRecord{undefined} ** abi.MAX_WINDOWS;
        var managed_count: usize = 0;
        if (state_export.window_count > 0 and state_export.windows != null) {
            for (state_export.windows[0..state_export.window_count]) |window| {
                if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id[0..])) continue;
                if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
                if (managed_count >= abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
                managed_windows[managed_count] = window;
                managed_count += 1;
            }
        }

        var included = [_]bool{false} ** abi.MAX_WINDOWS;
        var next_columns = [_]abi.OmniNiriRuntimeColumnState{undefined} ** abi.MAX_WINDOWS;
        var next_windows = [_]abi.OmniNiriRuntimeWindowState{undefined} ** abi.MAX_WINDOWS;
        var next_column_count: usize = 0;
        var next_window_count: usize = 0;
        var placeholder_column: ?abi.OmniNiriRuntimeColumnState = null;

        if (has_previous and previous_export.column_count > 0 and previous_export.columns != null) {
            for (0..previous_export.column_count) |column_index| {
                const previous_column = previous_export.columns[column_index];
                const window_start = previous_column.window_start;
                const count = previous_column.window_count;
                if (window_start > previous_export.window_count or count > previous_export.window_count - window_start) continue;

                const next_start = next_window_count;
                var kept_count: usize = 0;
                for (window_start..window_start + count) |window_index| {
                    const previous_window = previous_export.windows[window_index];
                    const current_index = managedWindowIndex(&managed_windows, managed_count, previous_window.window_id.bytes) orelse continue;
                    if (included[current_index]) continue;
                    included[current_index] = true;
                    next_windows[next_window_count] = previous_window;
                    next_windows[next_window_count].column_id = previous_column.column_id;
                    next_windows[next_window_count].column_index = next_column_count;
                    next_window_count += 1;
                    kept_count += 1;
                }

                if (kept_count == 0) {
                    if (placeholder_column == null) {
                        placeholder_column = defaultRuntimeColumnState(previous_column.column_id);
                    }
                    continue;
                }

                if (next_column_count >= abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
                next_columns[next_column_count] = previous_column;
                next_columns[next_column_count].window_start = next_start;
                next_columns[next_column_count].window_count = kept_count;
                next_columns[next_column_count].active_tile_idx = clampActiveTile(previous_column.active_tile_idx, kept_count);
                next_column_count += 1;
            }
        }

        for (0..managed_count) |managed_index| {
            if (included[managed_index]) continue;
            const column_id = if (next_column_count == 0 and placeholder_column != null)
                placeholder_column.?.column_id
            else
                entry.generateColumnId(workspace_id);
            if (next_column_count >= abi.MAX_WINDOWS or next_window_count >= abi.MAX_WINDOWS) {
                return abi.OMNI_ERR_OUT_OF_RANGE;
            }
            next_columns[next_column_count] = defaultRuntimeColumnState(column_id);
            next_columns[next_column_count].window_start = next_window_count;
            next_columns[next_column_count].window_count = 1;
            next_columns[next_column_count].active_tile_idx = 0;
            next_windows[next_window_count] = defaultRuntimeWindowState(managed_windows[managed_index].handle_id, column_id, next_column_count);
            next_window_count += 1;
            next_column_count += 1;
            placeholder_column = null;
        }

        if (next_column_count == 0) {
            const column_id = if (placeholder_column) |column|
                column.column_id
            else
                entry.generateColumnId(workspace_id);
            next_columns[0] = defaultRuntimeColumnState(column_id);
            next_column_count = 1;
        }

        normalizeRuntimeSeedState(next_columns[0..next_column_count], next_windows[0..next_window_count]);

        const selection = buildWorkspaceSelectionStateForSeed(self, workspace_id, next_columns[0..next_column_count], next_windows[0..next_window_count]);
        if (selection.selected_node_id) |selected_node_id| {
            self.setSelectedNode(workspace_id, selected_node_id);
        } else {
            self.clearWorkspaceSelectionCache(workspace_id);
        }
        if (selection.focused_window_id) |focused_window_id| {
            self.setLastFocusedWindow(workspace_id, focused_window_id);
        } else if (managed_count == 0) {
            self.clearLastFocusedWindow(workspace_id);
        }

        if (has_previous and runtimeStateEqualsExport(
            previous_export,
            next_columns[0..next_column_count],
            next_windows[0..next_window_count],
        )) {
            return abi.OMNI_OK;
        }

        var seed_request = abi.OmniNiriRuntimeSeedRequest{
            .columns = if (next_column_count == 0) null else &next_columns[0],
            .column_count = next_column_count,
            .windows = if (next_window_count == 0) null else &next_windows[0],
            .window_count = next_window_count,
        };
        const seed_rc = niri_runtime.omni_niri_runtime_seed_impl(entry.runtime, &seed_request);
        if (seed_rc == abi.OMNI_OK) {
            self.bumpWorkspaceProjectionGeneration(workspace_id);
        }
        return seed_rc;
    }

    fn captureSnapshot(self: *RuntimeImpl, out_snapshot: *abi.OmniControllerSnapshot) i32 {
        return self.captureSnapshotForController(out_snapshot, "snapshot");
    }

    fn captureSnapshotFromWorkspaceState(
        self: *RuntimeImpl,
        workspace_export: abi.OmniWorkspaceRuntimeStateExport,
        out_snapshot: *abi.OmniControllerSnapshot,
    ) i32 {
        self.monitor_snapshots.clearRetainingCapacity();
        self.workspace_snapshots.clearRetainingCapacity();
        self.window_snapshots.clearRetainingCapacity();

        const monitor_count = workspace_export.monitor_count;
        const workspace_count = workspace_export.workspace_count;
        const window_count = workspace_export.window_count;

        self.monitor_snapshots.ensureTotalCapacity(self.allocator, monitor_count) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        self.workspace_snapshots.ensureTotalCapacity(self.allocator, workspace_count) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        self.window_snapshots.ensureTotalCapacity(self.allocator, window_count) catch return abi.OMNI_ERR_OUT_OF_RANGE;

        if (monitor_count > 0 and workspace_export.monitors == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (workspace_count > 0 and workspace_export.workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (window_count > 0 and workspace_export.windows == null) return abi.OMNI_ERR_INVALID_ARGS;

        var runtime_exports = std.AutoHashMap(Uuid, abi.OmniNiriRuntimeStateExport).init(self.allocator);
        defer runtime_exports.deinit();

        for (0..monitor_count) |index| {
            const monitor = workspace_export.monitors[index];
            self.monitor_snapshots.appendAssumeCapacity(.{
                .display_id = monitor.display_id,
                .is_main = monitor.is_main,
                .frame_x = monitor.frame_x,
                .frame_y = monitor.frame_y,
                .frame_width = monitor.frame_width,
                .frame_height = monitor.frame_height,
                .visible_x = monitor.visible_x,
                .visible_y = monitor.visible_y,
                .visible_width = monitor.visible_width,
                .visible_height = monitor.visible_height,
                .name = controllerNameFromWorkspaceName(monitor.name),
            });
        }

        for (0..workspace_count) |index| {
            const workspace = workspace_export.workspaces[index];
            const workspace_id = workspace.workspace_id.bytes;
            const last_focused = self.last_focused_by_workspace.get(workspace_id);
            const workspace_layout_kind = self.layoutKindForWorkspaceRecord(workspace);
            var selection = WorkspaceSelectionState{};

            if (workspace_layout_kind == .niri) {
                var runtime_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
                const runtime_rc = self.snapshotWorkspaceLayoutRuntimeRecovering(workspace_export, workspace_id, &runtime_export);
                if (runtime_rc == abi.OMNI_OK) {
                    runtime_exports.put(workspace_id, runtime_export) catch return abi.OMNI_ERR_OUT_OF_RANGE;
                    selection = self.buildWorkspaceSelectionState(workspace_id, runtime_export, false);
                }
            } else {
                if (self.selected_node_by_workspace.get(workspace_id)) |selected_node_id| {
                    selection.selected_node_id = selected_node_id;
                    selection.actionable_window_id = selected_node_id;
                }
                if (last_focused) |last_focused_id| {
                    selection.focused_window_id = last_focused_id;
                    selection.actionable_window_id = selection.actionable_window_id orelse last_focused_id;
                    if (selection.selected_node_id == null) {
                        selection.selected_node_id = last_focused_id;
                    }
                }
            }

            self.workspace_snapshots.appendAssumeCapacity(.{
                .workspace_id = workspace.workspace_id,
                .has_assigned_display_id = workspace.has_assigned_display_id,
                .assigned_display_id = workspace.assigned_display_id,
                .is_visible = workspace.is_visible,
                .is_previous_visible = workspace.is_previous_visible,
                .layout_kind = @intFromEnum(workspace_layout_kind),
                .name = controllerNameFromWorkspaceName(workspace.name),
                .has_selected_node_id = if (selection.selected_node_id == null) 0 else 1,
                .selected_node_id = if (selection.selected_node_id) |value| .{ .bytes = value } else .{ .bytes = [_]u8{0} ** 16 },
                .has_last_focused_window_id = if (last_focused == null) 0 else 1,
                .last_focused_window_id = if (last_focused) |value| .{ .bytes = value } else .{ .bytes = [_]u8{0} ** 16 },
            });
        }

        for (0..window_count) |index| {
            const window = workspace_export.windows[index];
            const is_focused = if (self.focused_window) |focused|
                std.mem.eql(u8, focused[0..], window.handle_id.bytes[0..])
            else
                false;
            const workspace_layout_kind = self.layoutKindForWorkspaceId(workspace_export, window.workspace_id.bytes) orelse .niri;

            var has_node_id: u8 = 0;
            var node_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
            var has_column_id: u8 = 0;
            var column_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
            var order_index: usize = index;
            var column_index: usize = index;
            var row_index: usize = 0;

            if (window.layout_reason == abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD and workspace_layout_kind == .niri) {
                if (runtime_exports.get(window.workspace_id.bytes)) |runtime_export| {
                    if (runtimeWindowSnapshot(runtime_export, window.handle_id.bytes)) |snapshot| {
                        has_node_id = 1;
                        node_id = .{ .bytes = window.handle_id.bytes };
                        has_column_id = 1;
                        column_id = snapshot.column_id;
                        order_index = snapshot.order_index;
                        column_index = snapshot.column_index;
                        row_index = snapshot.row_index;
                    }
                }
            } else if (window.layout_reason == abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD and workspace_layout_kind == .dwindle) {
                if (self.workspace_dwindle_runtimes.getPtr(window.workspace_id.bytes)) |runtime| {
                    const ctx: *const dwindle.OmniDwindleLayoutContext = @ptrCast(@alignCast(runtime.context));
                    if (findDwindleWindowSnapshot(ctx, window.handle_id.bytes)) |snapshot| {
                        has_node_id = 1;
                        node_id = .{ .bytes = snapshot.node_id };
                        order_index = snapshot.order_index;
                        column_index = snapshot.order_index;
                        row_index = 0;
                    }
                }
            }

            self.window_snapshots.appendAssumeCapacity(.{
                .handle_id = window.handle_id,
                .pid = window.pid,
                .window_id = window.window_id,
                .workspace_id = window.workspace_id,
                .layout_kind = if (window.layout_reason == abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD)
                    @intFromEnum(workspace_layout_kind)
                else
                    abi.OMNI_CONTROLLER_LAYOUT_DEFAULT,
                .is_hidden = if (window.has_hidden_state != 0) 1 else 0,
                .is_focused = if (is_focused) 1 else 0,
                .is_managed = if (window.layout_reason == abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) 1 else 0,
                .has_node_id = has_node_id,
                .node_id = node_id,
                .has_column_id = has_column_id,
                .column_id = column_id,
                .order_index = @intCast(order_index),
                .column_index = @intCast(column_index),
                .row_index = @intCast(row_index),
            });
        }

        const active_monitor = self.active_monitor_override orelse optionalDisplayId(
            workspace_export.has_active_monitor_display_id,
            workspace_export.active_monitor_display_id,
        );
        const previous_monitor = self.previous_monitor_override orelse optionalDisplayId(
            workspace_export.has_previous_monitor_display_id,
            workspace_export.previous_monitor_display_id,
        );

        out_snapshot.* = .{
            .monitors = if (self.monitor_snapshots.items.len == 0) null else self.monitor_snapshots.items.ptr,
            .monitor_count = self.monitor_snapshots.items.len,
            .workspaces = if (self.workspace_snapshots.items.len == 0) null else self.workspace_snapshots.items.ptr,
            .workspace_count = self.workspace_snapshots.items.len,
            .windows = if (self.window_snapshots.items.len == 0) null else self.window_snapshots.items.ptr,
            .window_count = self.window_snapshots.items.len,
            .has_focused_window_id = if (self.focused_window == null) 0 else 1,
            .focused_window_id = if (self.focused_window) |focused| .{ .bytes = focused } else .{ .bytes = [_]u8{0} ** 16 },
            .has_active_monitor_display_id = if (active_monitor == null) 0 else 1,
            .active_monitor_display_id = active_monitor orelse 0,
            .has_previous_monitor_display_id = if (previous_monitor == null) 0 else 1,
            .previous_monitor_display_id = previous_monitor orelse 0,
            .secure_input_active = if (self.secure_input_active) 1 else 0,
            .lock_screen_active = if (self.lock_screen_active) 1 else 0,
            .non_managed_focus_active = if (self.non_managed_focus_active) 1 else 0,
            .app_fullscreen_active = if (self.app_fullscreen_active) 1 else 0,
            .focus_follows_window_to_monitor = if (self.focus_follows_window_to_monitor) 1 else 0,
            .move_mouse_to_focused_window = if (self.move_mouse_to_focused_window) 1 else 0,
            .layout_light_session_active = if (self.layout_light_session_active) 1 else 0,
            .layout_immediate_in_progress = if (self.layout_immediate_in_progress) 1 else 0,
            .layout_incremental_in_progress = if (self.layout_incremental_in_progress) 1 else 0,
            .layout_full_enumeration_in_progress = if (self.layout_full_enumeration_in_progress) 1 else 0,
            .layout_animation_active = if (self.layout_animation_active) 1 else 0,
            .layout_has_completed_initial_refresh = if (self.layout_has_completed_initial_refresh) 1 else 0,
        };
        return abi.OMNI_OK;
    }

    fn applyEffects(self: *RuntimeImpl, effect_export: *const abi.OmniControllerEffectExport) i32 {
        const effects = effect_export.*;

        const route_rc = self.applyRoutePlans(effects);
        if (route_rc != abi.OMNI_OK) return route_rc;

        const transfer_rc = self.applyTransferPlans(effects);
        if (transfer_rc != abi.OMNI_OK) return transfer_rc;

        const layout_rc = self.applyLayoutActions(effects);
        if (layout_rc != abi.OMNI_OK and layout_rc != abi.OMNI_ERR_PLATFORM) return layout_rc;

        self.absorbFocusEffects(effects);
        const focus_rc = self.applyFocusEffects(effects);
        if (focus_rc != abi.OMNI_OK and focus_rc != abi.OMNI_ERR_PLATFORM) return focus_rc;

        const refresh_rc = self.applyRefreshPlans(effects);
        if (refresh_rc != abi.OMNI_OK) return refresh_rc;

        if (self.host.apply_effects) |callback| {
            var ui_only = abi.OmniControllerEffectExport{
                .focus_exports = null,
                .focus_export_count = 0,
                .route_plans = null,
                .route_plan_count = 0,
                .transfer_plans = null,
                .transfer_plan_count = 0,
                .refresh_plans = null,
                .refresh_plan_count = 0,
                .ui_actions = effects.ui_actions,
                .ui_action_count = effects.ui_action_count,
                .layout_actions = null,
                .layout_action_count = 0,
            };
            const callback_rc = callback(self.host.userdata, &ui_only);
            if (callback_rc != abi.OMNI_OK) return callback_rc;
        }
        return abi.OMNI_OK;
    }

    fn reportError(self: *RuntimeImpl, code: i32, message: abi.OmniControllerName) void {
        if (self.host.report_error) |callback| {
            _ = callback(self.host.userdata, code, message);
        }
    }

    fn reportPhaseError(self: *RuntimeImpl, code: i32, message: []const u8) i32 {
        self.reportError(code, types.encodeName(message));
        return code;
    }

    fn noteRuntimeLayoutFailure(self: *RuntimeImpl, stage: []const u8, code: i32) void {
        if (!self.runtime_layout_render_failed) {
            std.log.warn("runtime layout render failed stage={s} code={d}", .{ stage, code });
        }
        self.runtime_layout_render_failed = true;
        self.logged_border_suppression_for_runtime_failure = false;
    }

    fn absorbFocusEffects(self: *RuntimeImpl, effect_export: abi.OmniControllerEffectExport) void {
        if (effect_export.focus_export_count == 0 or effect_export.focus_exports == null) return;

        for (effect_export.focus_exports[0..effect_export.focus_export_count]) |focus_export| {
            if (focus_export.has_previous_monitor_display_id != 0) {
                self.previous_monitor_override = focus_export.previous_monitor_display_id;
            }
            if (focus_export.has_active_monitor_display_id != 0) {
                self.active_monitor_override = focus_export.active_monitor_display_id;
            }

            self.non_managed_focus_active = focus_export.non_managed_focus_active != 0;
            self.app_fullscreen_active = focus_export.app_fullscreen_active != 0;

            if (focus_export.clear_focus != 0) {
                self.focused_window = null;
            }
            if (focus_export.has_focused_window_id != 0) {
                self.focused_window = focus_export.focused_window_id.bytes;
            }

            if (focus_export.has_workspace_id != 0) {
                const workspace_id = focus_export.workspace_id.bytes;
                if (focus_export.has_selected_node_id != 0) {
                    self.setSelectedNode(workspace_id, focus_export.selected_node_id.bytes);
                }
                if (focus_export.has_focused_window_id != 0) {
                    self.setLastFocusedWindow(workspace_id, focus_export.focused_window_id.bytes);
                }
            }
        }
    }

    fn mergeEventSnapshotHints(self: *RuntimeImpl, event: abi.OmniControllerEvent) void {
        switch (event.kind) {
            abi.OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED => {
                self.secure_input_active = event.enabled != 0;
            },
            abi.OMNI_CONTROLLER_EVENT_LOCK_SCREEN_CHANGED => {
                self.lock_screen_active = event.enabled != 0;
            },
            abi.OMNI_CONTROLLER_EVENT_FOCUS_CHANGED => {
                if (event.has_window_handle_id != 0) {
                    self.focused_window = event.window_handle_id.bytes;
                } else {
                    self.focused_window = null;
                }
            },
            abi.OMNI_CONTROLLER_EVENT_WINDOW_REMOVED => {
                if (event.has_window_handle_id == 0 or self.focused_window == null) return;
                if (std.mem.eql(u8, self.focused_window.?[0..], event.window_handle_id.bytes[0..])) {
                    self.focused_window = null;
                }
            },
            else => {},
        }
    }

    fn applyRoutePlans(self: *RuntimeImpl, effects: abi.OmniControllerEffectExport) i32 {
        if (effects.route_plan_count == 0) return abi.OMNI_OK;
        if (effects.route_plans == null) return abi.OMNI_ERR_INVALID_ARGS;
        for (effects.route_plans[0..effects.route_plan_count]) |plan| {
            const rc = self.applySingleRoutePlan(plan);
            if (rc != abi.OMNI_OK) return rc;
        }
        return abi.OMNI_OK;
    }

    fn applySingleRoutePlan(self: *RuntimeImpl, plan: abi.OmniControllerRoutePlan) i32 {
        const target_display_id: ?u32 = if (plan.has_target_display_id != 0) plan.target_display_id else null;
        const source_display_id: ?u32 = if (plan.has_source_display_id != 0) plan.source_display_id else null;
        var target_workspace_id = self.resolveWorkspaceId(
            plan.has_target_workspace_id,
            plan.target_workspace_id,
            plan.target_workspace_name,
            plan.create_target_workspace_if_missing != 0,
        );
        const source_workspace_id: ?abi.OmniUuid128 = if (plan.has_source_workspace_id != 0)
            plan.source_workspace_id
        else
            null;

        switch (plan.kind) {
            abi.OMNI_CONTROLLER_ROUTE_FOCUS_MONITOR,
            abi.OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE,
            => {
                const resolved_display = target_display_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const target_name = workspaceNameFromControllerName(plan.target_workspace_name);
                if (target_name.length > 0) {
                    var has_workspace_id: u8 = 0;
                    var resolved_workspace_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
                    const rc = workspace_runtime.omni_workspace_runtime_switch_workspace_by_name_impl(
                        self.workspace_runtime_owner,
                        target_name,
                        &has_workspace_id,
                        &resolved_workspace_id,
                    );
                    if (rc != abi.OMNI_OK) return rc;
                    return abi.OMNI_OK;
                }
                if (target_workspace_id == null) {
                    target_workspace_id = self.activeWorkspaceIdForDisplay(resolved_display);
                }
                const resolved_workspace = target_workspace_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                return workspace_runtime.omni_workspace_runtime_set_active_workspace_impl(
                    self.workspace_runtime_owner,
                    resolved_workspace,
                    resolved_display,
                );
            },
            abi.OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE => {
                const resolved_workspace = target_workspace_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                var has_workspace_id: u8 = 0;
                var resolved_workspace_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
                const rc = workspace_runtime.omni_workspace_runtime_focus_workspace_anywhere_impl(
                    self.workspace_runtime_owner,
                    resolved_workspace,
                    &has_workspace_id,
                    &resolved_workspace_id,
                );
                if (rc != abi.OMNI_OK) return rc;
                return abi.OMNI_OK;
            },
            abi.OMNI_CONTROLLER_ROUTE_SUMMON_WORKSPACE => {
                const resolved_display = target_display_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                var target_name = workspaceNameFromControllerName(plan.target_workspace_name);
                if (target_name.length == 0) {
                    const resolved_workspace = target_workspace_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
                    const export_rc = self.exportWorkspaceState(&state_export);
                    if (export_rc != abi.OMNI_OK) return export_rc;
                    const workspace = workspaceRecordById(state_export, resolved_workspace.bytes) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                    target_name = workspace.name;
                }

                var has_workspace_id: u8 = 0;
                var resolved_workspace_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
                const rc = workspace_runtime.omni_workspace_runtime_summon_workspace_by_name_impl(
                    self.workspace_runtime_owner,
                    target_name,
                    resolved_display,
                    &has_workspace_id,
                    &resolved_workspace_id,
                );
                if (rc != abi.OMNI_OK) return rc;
                return abi.OMNI_OK;
            },
            abi.OMNI_CONTROLLER_ROUTE_MOVE_WORKSPACE_TO_MONITOR => {
                const resolved_workspace = source_workspace_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const resolved_display = target_display_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                return workspace_runtime.omni_workspace_runtime_move_workspace_to_monitor_impl(
                    self.workspace_runtime_owner,
                    resolved_workspace,
                    resolved_display,
                );
            },
            abi.OMNI_CONTROLLER_ROUTE_SWAP_WORKSPACES => {
                const resolved_source_workspace = source_workspace_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const resolved_target_workspace = target_workspace_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const resolved_source_display = source_display_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                const resolved_target_display = target_display_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                return workspace_runtime.omni_workspace_runtime_swap_workspaces_impl(
                    self.workspace_runtime_owner,
                    resolved_source_workspace,
                    resolved_source_display,
                    resolved_target_workspace,
                    resolved_target_display,
                );
            },
            else => return abi.OMNI_OK,
        }
    }

    fn applyTransferPlans(self: *RuntimeImpl, effects: abi.OmniControllerEffectExport) i32 {
        if (effects.transfer_plan_count == 0) return abi.OMNI_OK;
        if (effects.transfer_plans == null) return abi.OMNI_ERR_INVALID_ARGS;
        for (effects.transfer_plans[0..effects.transfer_plan_count]) |plan| {
            const rc = self.applySingleTransferPlan(plan);
            if (rc != abi.OMNI_OK) return rc;
        }
        return abi.OMNI_OK;
    }

    fn applyLayoutActions(self: *RuntimeImpl, effects: abi.OmniControllerEffectExport) i32 {
        if (effects.layout_action_count == 0) return abi.OMNI_OK;
        if (effects.layout_actions == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.layout_incremental_in_progress = true;
        self.layout_has_completed_initial_refresh = true;
        var soft_focus_platform_failure = false;

        for (effects.layout_actions[0..effects.layout_action_count]) |action| {
            const rc = self.applySingleLayoutAction(action);
            if (rc == abi.OMNI_ERR_PLATFORM and isFocusLayoutAction(action.kind)) {
                soft_focus_platform_failure = true;
                continue;
            }
            if (rc != abi.OMNI_OK) return rc;
        }

        return if (soft_focus_platform_failure) abi.OMNI_ERR_PLATFORM else abi.OMNI_OK;
    }

    fn applySingleLayoutAction(self: *RuntimeImpl, action: abi.OmniControllerLayoutAction) i32 {
        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        const export_rc = self.copyWorkspaceState(&state);
        if (export_rc != abi.OMNI_OK) return export_rc;
        const state_export = state.state_export;

        const sync_rc = self.syncWorkspaceLayoutRuntimes(state_export);
        if (sync_rc != abi.OMNI_OK) return sync_rc;

        const active_layout_kind = self.activeLayoutKindForLayoutAction(state_export, action);

        switch (action.kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM,
            => {
                if (active_layout_kind == .dwindle and action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION) {
                    return self.applyDwindleLayoutAction(state_export, action);
                }
                return self.applyNiriNavigationAction(state_export, action);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CONSUME_WINDOW_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_EXPEL_WINDOW_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN,
            => {
                if (active_layout_kind == .dwindle) {
                    return self.applyDwindleLayoutAction(state_export, action);
                }
                return if (action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW or
                    action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN)
                    self.applyNiriOverviewInsertAction(state_export, action)
                else
                    self.applyNiriMutationAction(state_export, action);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_FULLSCREEN => {
                if (active_layout_kind == .dwindle) {
                    return self.applyDwindleLayoutAction(state_export, action);
                }
                return self.toggleManagedFullscreen(state_export);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_NATIVE_FULLSCREEN => {
                return self.toggleNativeFullscreen(state_export);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR,
            => {
                return self.applyDwindleLayoutAction(state_export, action);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT => {
                return self.toggleWorkspaceLayout(state_export, action);
            },
            else => {
                self.markLayoutAnimationStarted(0.20);
                return abi.OMNI_OK;
            },
        }
    }

    fn applyFocusEffects(self: *RuntimeImpl, effects: abi.OmniControllerEffectExport) i32 {
        if (effects.focus_export_count == 0) return abi.OMNI_OK;
        if (effects.focus_exports == null) return abi.OMNI_ERR_INVALID_ARGS;
        var soft_focus_platform_failure = false;

        for (effects.focus_exports[0..effects.focus_export_count]) |focus_export| {
            if (focus_export.has_workspace_id != 0 and focus_export.has_active_monitor_display_id != 0) {
                const workspace_rc = workspace_runtime.omni_workspace_runtime_set_active_workspace_impl(
                    self.workspace_runtime_owner,
                    focus_export.workspace_id,
                    focus_export.active_monitor_display_id,
                );
                if (workspace_rc != abi.OMNI_OK and workspace_rc != abi.OMNI_ERR_OUT_OF_RANGE) {
                    return workspace_rc;
                }
            }

            if (focus_export.has_focused_window_id == 0) continue;
            const focus_rc = self.focusWindowByHandle(focus_export.focused_window_id.bytes);
            if (focus_rc == abi.OMNI_ERR_PLATFORM) {
                soft_focus_platform_failure = true;
                continue;
            }
            if (focus_rc != abi.OMNI_OK and focus_rc != abi.OMNI_ERR_OUT_OF_RANGE) {
                return focus_rc;
            }
        }

        return if (soft_focus_platform_failure) abi.OMNI_ERR_PLATFORM else abi.OMNI_OK;
    }

    fn applyRefreshPlans(self: *RuntimeImpl, effects: abi.OmniControllerEffectExport) i32 {
        if (effects.refresh_plan_count == 0) return abi.OMNI_OK;
        if (effects.refresh_plans == null) return abi.OMNI_ERR_INVALID_ARGS;

        for (effects.refresh_plans[0..effects.refresh_plan_count]) |plan| {
            self.applySingleRefreshPlan(plan);
        }
        const runtime_rc = self.synchronizeRuntimeStateAndLayout();
        if (runtime_rc != abi.OMNI_OK) {
            return self.reportPhaseError(runtime_rc, "refresh/layout synchronization failed");
        }
        self.layout_has_completed_initial_refresh = true;
        return abi.OMNI_OK;
    }

    fn applySingleRefreshPlan(self: *RuntimeImpl, plan: abi.OmniControllerRefreshPlan) void {
        if (plan.flags & abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE != 0) {
            self.layout_immediate_in_progress = true;
            self.layout_incremental_in_progress = false;
            self.layout_full_enumeration_in_progress = false;
        } else if (plan.flags & abi.OMNI_CONTROLLER_REFRESH_FULL != 0) {
            self.layout_immediate_in_progress = false;
            self.layout_incremental_in_progress = false;
            self.layout_full_enumeration_in_progress = true;
        } else if (plan.flags & (abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL | abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT) != 0) {
            self.layout_immediate_in_progress = false;
            self.layout_incremental_in_progress = true;
            self.layout_full_enumeration_in_progress = false;
        }

        if (plan.flags & abi.OMNI_CONTROLLER_REFRESH_START_WORKSPACE_ANIMATION != 0) {
            self.markLayoutAnimationStarted(0.30);
        }
        if (plan.flags & abi.OMNI_CONTROLLER_REFRESH_STOP_SCROLL_ANIMATION != 0) {
            self.layout_animation_active = false;
            self.layout_animation_deadline = null;
        }
    }

    fn synchronizeRuntimeStateAndLayout(self: *RuntimeImpl) i32 {
        defer {
            self.layout_immediate_in_progress = false;
            self.layout_incremental_in_progress = false;
            self.layout_full_enumeration_in_progress = false;
            self.updateTickTimerLocked();
        }

        const sync_rc = self.synchronizeRuntimeState();
        if (sync_rc != abi.OMNI_OK and sync_rc != abi.OMNI_ERR_PLATFORM) {
            return sync_rc;
        }

        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        const export_rc = self.copyWorkspaceState(&state);
        if (export_rc != abi.OMNI_OK) return export_rc;
        const state_export = state.state_export;

        if (self.lock_screen_active) {
            if (self.border_runtime != null) {
                _ = border.omni_border_runtime_hide_impl(self.border_runtime);
            }
            return abi.OMNI_OK;
        }

        const layout_rc = self.applyManagedLayout(state_export);
        if (layout_rc != abi.OMNI_OK and layout_rc != abi.OMNI_ERR_PLATFORM) {
            return layout_rc;
        }

        const border_rc = self.updateBorderPresentation(state_export);
        if (border_rc != abi.OMNI_OK and border_rc != abi.OMNI_ERR_PLATFORM) {
            return border_rc;
        }

        return abi.OMNI_OK;
    }

    fn synchronizeRuntimeState(self: *RuntimeImpl) i32 {
        const monitor_rc = self.importMonitorTopology();
        if (monitor_rc != abi.OMNI_OK and monitor_rc != abi.OMNI_ERR_PLATFORM) {
            return monitor_rc;
        }

        if (self.lock_screen_active) {
            self.focused_window = null;
            return abi.OMNI_OK;
        }

        var state = OwnedWorkspaceState.init(self.allocator);
        defer state.deinit();

        const export_rc = self.copyWorkspaceState(&state);
        if (export_rc != abi.OMNI_OK) return export_rc;

        const windows_rc = self.syncWindowInventoryFromSystem(state.state_export);
        if (windows_rc != abi.OMNI_OK and windows_rc != abi.OMNI_ERR_PLATFORM) {
            return windows_rc;
        }

        var refreshed_state = OwnedWorkspaceState.init(self.allocator);
        defer refreshed_state.deinit();

        const refreshed_rc = self.copyWorkspaceState(&refreshed_state);
        if (refreshed_rc == abi.OMNI_OK) {
            self.reconcileFocusedWindow(refreshed_state.state_export);
            const runtime_rc = self.syncWorkspaceLayoutRuntimes(refreshed_state.state_export);
            if (runtime_rc != abi.OMNI_OK) return runtime_rc;
        }

        return abi.OMNI_OK;
    }

    fn importMonitorTopology(self: *RuntimeImpl) i32 {
        var required: usize = 0;
        const probe_rc = monitor_discovery.omni_monitor_query_current_impl(null, 0, &required);
        if (probe_rc != abi.OMNI_OK) return probe_rc;

        self.monitor_records.clearRetainingCapacity();
        self.display_infos.clearRetainingCapacity();
        if (required == 0) return abi.OMNI_OK;

        self.monitor_records.ensureTotalCapacity(self.allocator, required) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        self.monitor_records.items.len = required;

        var written: usize = 0;
        const query_rc = monitor_discovery.omni_monitor_query_current_impl(
            self.monitor_records.items.ptr,
            self.monitor_records.items.len,
            &written,
        );
        if (query_rc != abi.OMNI_OK) return query_rc;
        if (written < self.monitor_records.items.len) {
            self.monitor_records.items.len = written;
        }

        if (self.monitor_records.items.len == 0) return abi.OMNI_OK;

        var snapshots = self.allocator.alloc(abi.OmniWorkspaceRuntimeMonitorSnapshot, self.monitor_records.items.len) catch {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };
        defer self.allocator.free(snapshots);

        self.display_infos.ensureTotalCapacity(self.allocator, self.monitor_records.items.len) catch {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };

        for (self.monitor_records.items, 0..) |monitor, idx| {
            snapshots[idx] = .{
                .display_id = monitor.display_id,
                .is_main = monitor.is_main,
                .frame_x = monitor.frame_x,
                .frame_y = monitor.frame_y,
                .frame_width = monitor.frame_width,
                .frame_height = monitor.frame_height,
                .visible_x = monitor.visible_x,
                .visible_y = monitor.visible_y,
                .visible_width = monitor.visible_width,
                .visible_height = monitor.visible_height,
                .name = monitor.name,
            };
            self.display_infos.appendAssumeCapacity(.{
                .display_id = monitor.display_id,
                .appkit_frame = .{
                    .x = monitor.frame_x,
                    .y = monitor.frame_y,
                    .width = monitor.frame_width,
                    .height = monitor.frame_height,
                },
                .window_server_frame = .{
                    .x = monitor.frame_x,
                    .y = monitor.frame_y,
                    .width = monitor.frame_width,
                    .height = monitor.frame_height,
                },
                .backing_scale = if (std.math.isFinite(monitor.backing_scale) and monitor.backing_scale > 0)
                    monitor.backing_scale
                else
                    2.0,
            });

            if (self.active_monitor_override == null and monitor.is_main != 0) {
                self.active_monitor_override = monitor.display_id;
            }
        }

        return workspace_runtime.omni_workspace_runtime_import_monitors_impl(
            self.workspace_runtime_owner,
            snapshots.ptr,
            snapshots.len,
        );
    }

    fn syncWindowInventoryFromSystem(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) i32 {
        const query_rc = self.queryVisibleWindows();
        if (query_rc != abi.OMNI_OK) return query_rc;

        self.active_window_keys.clearRetainingCapacity();
        var current_ax_pids = std.AutoHashMap(i32, void).init(self.allocator);
        defer current_ax_pids.deinit();
        var operations = std.ArrayListUnmanaged(WindowInventoryOperation){};
        defer operations.deinit(self.allocator);

        const plan_rc = self.buildWindowInventoryPlan(state_export, &current_ax_pids, &operations);
        if (plan_rc != abi.OMNI_OK) return plan_rc;

        const track_rc = self.syncTrackedAxPids(&current_ax_pids);
        if (track_rc != abi.OMNI_OK) return track_rc;

        const apply_rc = self.applyWindowInventoryPlan(operations.items);
        if (apply_rc != abi.OMNI_OK) return apply_rc;

        const keys_ptr: [*c]const abi.OmniWorkspaceRuntimeWindowKey = if (self.active_window_keys.items.len == 0)
            null
        else
            self.active_window_keys.items.ptr;
        return workspace_runtime.omni_workspace_runtime_window_remove_missing_impl(
            self.workspace_runtime_owner,
            keys_ptr,
            self.active_window_keys.items.len,
            1,
        );
    }

    fn buildWindowInventoryPlan(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        current_ax_pids: *std.AutoHashMap(i32, void),
        operations: *std.ArrayListUnmanaged(WindowInventoryOperation),
    ) i32 {
        const own_pid: i32 = @intCast(c.getpid());

        for (self.visible_windows.items) |window| {
            if (window.id == 0 or window.pid <= 0) continue;
            if (window.pid == own_pid) continue;
            if (!isRectFinite(window.frame) or window.frame.width <= 1 or window.frame.height <= 1) continue;
            current_ax_pids.put(window.pid, {}) catch return abi.OMNI_ERR_OUT_OF_RANGE;

            const workspace_id = self.resolveWorkspaceForWindow(state_export, window.frame) orelse continue;
            const existing_handle = self.findExistingHandle(state_export, window.pid, window.id);

            const request = abi.OmniWorkspaceRuntimeWindowUpsert{
                .pid = window.pid,
                .window_id = @intCast(window.id),
                .workspace_id = workspace_id,
                .has_handle_id = if (existing_handle == null) 0 else 1,
                .handle_id = existing_handle orelse .{ .bytes = [_]u8{0} ** 16 },
            };
            const layout_reason = self.resolveLayoutReason(window.pid, window.id);
            operations.append(self.allocator, .{
                .request = request,
                .layout_reason = layout_reason,
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;

            self.active_window_keys.append(self.allocator, .{
                .pid = window.pid,
                .window_id = @intCast(window.id),
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }

        return abi.OMNI_OK;
    }

    fn applyWindowInventoryPlan(
        self: *RuntimeImpl,
        operations: []const WindowInventoryOperation,
    ) i32 {
        for (operations) |operation| {
            var request = operation.request;
            var handle_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
            const upsert_rc = workspace_runtime.omni_workspace_runtime_window_upsert_impl(
                self.workspace_runtime_owner,
                &request,
                &handle_id,
            );
            if (upsert_rc != abi.OMNI_OK) continue;

            _ = workspace_runtime.omni_workspace_runtime_window_set_layout_reason_impl(
                self.workspace_runtime_owner,
                handle_id,
                operation.layout_reason,
            );
        }
        return abi.OMNI_OK;
    }

    fn queryVisibleWindows(self: *RuntimeImpl) i32 {
        var required: usize = 0;
        const probe_rc = skylight.queryVisibleWindows(null, 0, &required);
        if (probe_rc != abi.OMNI_OK) return probe_rc;

        self.visible_windows.clearRetainingCapacity();
        if (required == 0) return abi.OMNI_OK;

        self.visible_windows.ensureTotalCapacity(self.allocator, required) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        self.visible_windows.items.len = required;

        var written: usize = 0;
        const query_rc = skylight.queryVisibleWindows(
            self.visible_windows.items.ptr,
            self.visible_windows.items.len,
            &written,
        );
        if (query_rc != abi.OMNI_OK) return query_rc;

        if (written <= self.visible_windows.items.len) {
            self.visible_windows.items.len = written;
            return abi.OMNI_OK;
        }

        self.visible_windows.ensureTotalCapacity(self.allocator, written) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        self.visible_windows.items.len = written;
        written = 0;
        const retry_rc = skylight.queryVisibleWindows(
            self.visible_windows.items.ptr,
            self.visible_windows.items.len,
            &written,
        );
        if (retry_rc != abi.OMNI_OK) return retry_rc;
        self.visible_windows.items.len = @min(self.visible_windows.items.len, written);
        return abi.OMNI_OK;
    }

    fn syncTrackedAxPids(self: *RuntimeImpl, current_ax_pids: *std.AutoHashMap(i32, void)) i32 {
        const runtime = self.ax_runtime orelse return abi.OMNI_OK;

        var current_it = current_ax_pids.iterator();
        while (current_it.next()) |entry| {
            const pid = entry.key_ptr.*;
            if (self.tracked_ax_pids.contains(pid)) continue;

            const track_rc = ax_manager.omni_ax_runtime_track_app_impl(runtime, pid, 0, null, 0);
            if (track_rc == abi.OMNI_OK) {
                self.tracked_ax_pids.put(pid, {}) catch return abi.OMNI_ERR_OUT_OF_RANGE;
            } else if (track_rc == abi.OMNI_ERR_OUT_OF_RANGE) {
                return track_rc;
            }
        }

        var stale_pids = std.ArrayListUnmanaged(i32){};
        defer stale_pids.deinit(self.allocator);

        var tracked_it = self.tracked_ax_pids.keyIterator();
        while (tracked_it.next()) |pid_ptr| {
            if (!current_ax_pids.contains(pid_ptr.*)) {
                stale_pids.append(self.allocator, pid_ptr.*) catch return abi.OMNI_ERR_OUT_OF_RANGE;
            }
        }

        for (stale_pids.items) |pid| {
            _ = ax_manager.omni_ax_runtime_untrack_app_impl(runtime, pid);
            _ = self.tracked_ax_pids.remove(pid);
        }

        return abi.OMNI_OK;
    }

    fn resolveWorkspaceForWindow(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        frame: abi.OmniBorderRect,
    ) ?abi.OmniUuid128 {
        const center_x = frame.x + frame.width * 0.5;
        const center_y = frame.y + frame.height * 0.5;

        if (state_export.monitor_count > 0 and state_export.monitors != null) {
            for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
                const contains = pointInRect(
                    center_x,
                    center_y,
                    .{
                        .x = monitor.visible_x,
                        .y = monitor.visible_y,
                        .width = monitor.visible_width,
                        .height = monitor.visible_height,
                    },
                );
                if (!contains) continue;
                if (monitor.has_active_workspace_id != 0) return monitor.active_workspace_id;
            }
        }

        const active_display = self.active_monitor_override orelse optionalDisplayId(
            state_export.has_active_monitor_display_id,
            state_export.active_monitor_display_id,
        );
        if (active_display) |display_id| {
            if (self.activeWorkspaceForDisplay(state_export, display_id)) |workspace_id| {
                return workspace_id;
            }
        }

        if (state_export.monitor_count > 0 and state_export.monitors != null) {
            const monitor = state_export.monitors[0];
            if (monitor.has_active_workspace_id != 0) return monitor.active_workspace_id;
        }

        if (state_export.workspace_count > 0 and state_export.workspaces != null) {
            return state_export.workspaces[0].workspace_id;
        }

        return null;
    }

    fn findExistingHandle(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        pid: i32,
        window_id: u32,
    ) ?abi.OmniUuid128 {
        _ = self;
        if (state_export.window_count == 0 or state_export.windows == null) return null;
        for (state_export.windows[0..state_export.window_count]) |window| {
            if (window.pid != pid) continue;
            const raw_window_id = std.math.cast(u32, window.window_id) orelse continue;
            if (raw_window_id == window_id) {
                return window.handle_id;
            }
        }
        return null;
    }

    fn resolveManagedHandleForWindowId(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        pid: i32,
        window_id: u32,
    ) ?Uuid {
        _ = self;
        if (state_export.window_count == 0 or state_export.windows == null) return null;

        for (state_export.windows[0..state_export.window_count]) |window| {
            if (window.pid != pid) continue;
            if (window.window_id <= 0 or window.window_id > std.math.maxInt(u32)) continue;
            const raw_window_id = std.math.cast(u32, window.window_id) orelse continue;
            if (raw_window_id != window_id) continue;
            if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) return null;
            return window.handle_id.bytes;
        }

        return null;
    }

    fn resolveLayoutReason(self: *RuntimeImpl, pid: i32, window_id: u32) u8 {
        const runtime = self.ax_runtime orelse return abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD;
        var request = abi.OmniAXWindowTypeRequest{
            .pid = pid,
            .window_id = window_id,
            .app_policy = 0,
            .force_floating = 0,
        };
        var window_type: u8 = abi.OMNI_AX_WINDOW_TYPE_TILING;
        const rc = ax_manager.omni_ax_runtime_get_window_type_impl(runtime, &request, &window_type);
        if (rc != abi.OMNI_OK) return abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD;
        return if (window_type == abi.OMNI_AX_WINDOW_TYPE_TILING)
            abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD
        else
            abi.OMNI_WORKSPACE_LAYOUT_REASON_MACOS_HIDDEN_APP;
    }

    fn applyGridFallbackLayoutForWorkspace(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: abi.OmniUuid128,
    ) i32 {
        if (state_export.monitor_count == 0 or state_export.monitors == null) return abi.OMNI_OK;
        if (state_export.window_count == 0 or state_export.windows == null) return abi.OMNI_OK;

        const monitor = monitorForWorkspace(state_export, workspace_id.bytes) orelse return abi.OMNI_OK;

        var managed_count: usize = 0;
        for (state_export.windows[0..state_export.window_count]) |window| {
            if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id.bytes[0..])) continue;
            if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
            if (window.pid <= 0 or window.window_id <= 0) continue;
            if (window.window_id > std.math.maxInt(u32)) continue;
            managed_count += 1;
        }
        if (managed_count == 0) return abi.OMNI_OK;

        var cols: usize = 1;
        while (cols * cols < managed_count) : (cols += 1) {}
        const rows = (managed_count + cols - 1) / cols;
        const working_area = self.workingAreaForMonitor(monitor);
        const cell_w = working_area.width / @as(f64, @floatFromInt(cols));
        const cell_h = working_area.height / @as(f64, @floatFromInt(rows));

        var tile_index: usize = 0;
        for (state_export.windows[0..state_export.window_count]) |window| {
            if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id.bytes[0..])) continue;
            if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
            if (window.pid <= 0 or window.window_id <= 0 or window.window_id > std.math.maxInt(u32)) continue;
            const raw_window_id = std.math.cast(u32, window.window_id) orelse continue;

            const col = tile_index % cols;
            const row = tile_index / cols;
            tile_index += 1;

            self.frame_requests.append(self.allocator, .{
                .pid = window.pid,
                .window_id = raw_window_id,
                .frame = .{
                    .x = working_area.x + @as(f64, @floatFromInt(col)) * cell_w + self.layout_gap * 0.5,
                    .y = working_area.y + @as(f64, @floatFromInt(row)) * cell_h + self.layout_gap * 0.5,
                    .width = @max(1.0, cell_w - self.layout_gap),
                    .height = @max(1.0, cell_h - self.layout_gap),
                },
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }

        return abi.OMNI_OK;
    }

    fn applyDwindleLayoutForWorkspace(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        monitor: abi.OmniWorkspaceRuntimeMonitorRecord,
        workspace_id: Uuid,
    ) i32 {
        const runtime = self.workspace_dwindle_runtimes.getPtr(workspace_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        const ctx: *const dwindle.OmniDwindleLayoutContext = @ptrCast(@alignCast(runtime.context));

        var managed_windows = [_]abi.OmniWorkspaceRuntimeWindowRecord{undefined} ** abi.MAX_WINDOWS;
        var managed_count: usize = 0;
        if (state_export.window_count > 0 and state_export.windows != null) {
            for (state_export.windows[0..state_export.window_count]) |window| {
                if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id[0..])) continue;
                if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
                if (window.pid <= 0 or window.window_id <= 0 or window.window_id > std.math.maxInt(u32)) continue;
                if (managed_count >= abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
                managed_windows[managed_count] = window;
                managed_count += 1;
            }
        }
        if (managed_count == 0) return abi.OMNI_OK;

        const settings = self.dwindleSettingsForDisplay(monitor.display_id);
        const working_area = self.workingAreaForMonitor(monitor);
        var request = abi.OmniDwindleLayoutRequest{
            .screen_x = working_area.x,
            .screen_y = working_area.y,
            .screen_width = working_area.width,
            .screen_height = working_area.height,
            .inner_gap = settings.inner_gap,
            .outer_gap_top = settings.outer_gap_top,
            .outer_gap_bottom = settings.outer_gap_bottom,
            .outer_gap_left = settings.outer_gap_left,
            .outer_gap_right = settings.outer_gap_right,
            .single_window_aspect_width = settings.single_window_aspect_width,
            .single_window_aspect_height = settings.single_window_aspect_height,
            .single_window_aspect_tolerance = default_dwindle_aspect_tolerance,
            .runtime_settings = dwindleRuntimeSettings(settings),
        };

        var constraints = [_]abi.OmniDwindleWindowConstraint{undefined} ** abi.MAX_WINDOWS;
        if (self.ax_runtime) |ax_runtime_owner| {
            for (managed_windows[0..managed_count], 0..) |window, index| {
                var raw_constraints = std.mem.zeroes(abi.OmniAXWindowConstraints);
                const raw_window_id: u32 = @intCast(window.window_id);
                const rc = ax_manager.omni_ax_runtime_get_window_constraints_impl(
                    ax_runtime_owner,
                    window.pid,
                    raw_window_id,
                    &raw_constraints,
                );
                constraints[index] = .{
                    .window_id = window.handle_id,
                    .min_width = if (rc == abi.OMNI_OK) raw_constraints.min_width else 0.0,
                    .min_height = if (rc == abi.OMNI_OK) raw_constraints.min_height else 0.0,
                    .max_width = if (rc == abi.OMNI_OK) raw_constraints.max_width else 0.0,
                    .max_height = if (rc == abi.OMNI_OK) raw_constraints.max_height else 0.0,
                    .has_max_width = if (rc == abi.OMNI_OK) raw_constraints.has_max_width else 0,
                    .has_max_height = if (rc == abi.OMNI_OK) raw_constraints.has_max_height else 0,
                    .is_fixed = if (rc == abi.OMNI_OK) raw_constraints.is_fixed else 0,
                };
            }
        } else {
            for (managed_windows[0..managed_count], 0..) |window, index| {
                constraints[index] = .{
                    .window_id = window.handle_id,
                    .min_width = 0.0,
                    .min_height = 0.0,
                    .max_width = 0.0,
                    .max_height = 0.0,
                    .has_max_width = 0,
                    .has_max_height = 0,
                    .is_fixed = 0,
                };
            }
        }

        var frames = [_]abi.OmniDwindleWindowFrame{undefined} ** abi.MAX_WINDOWS;
        var out_frame_count: usize = 0;
        const rc = dwindle.omni_dwindle_ctx_calculate_layout_impl(
            @constCast(runtime.context),
            &request,
            &constraints[0],
            managed_count,
            &frames[0],
            frames.len,
            &out_frame_count,
        );
        if (rc != abi.OMNI_OK) return rc;

        for (frames[0..@min(out_frame_count, managed_count)]) |frame| {
            const window_record = managedWindowRecordByHandle(state_export, workspace_id, frame.window_id.bytes) orelse continue;
            if (window_record.pid <= 0 or window_record.window_id <= 0 or window_record.window_id > std.math.maxInt(u32)) continue;
            self.frame_requests.append(self.allocator, .{
                .pid = window_record.pid,
                .window_id = @intCast(window_record.window_id),
                .frame = .{
                    .x = frame.frame_x,
                    .y = frame.frame_y,
                    .width = frame.frame_width,
                    .height = frame.frame_height,
                },
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }

        _ = ctx;
        return abi.OMNI_OK;
    }

    fn applyManagedLayout(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) i32 {
        const ax_runtime_owner = self.ax_runtime orelse return abi.OMNI_OK;
        self.frame_requests.clearRetainingCapacity();
        self.runtime_layout_render_failed = false;
        self.logged_border_suppression_for_runtime_failure = false;

        if (state_export.monitor_count == 0 or state_export.monitors == null) return abi.OMNI_OK;

        var any_runtime_animation = false;
        for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
            if (monitor.has_active_workspace_id == 0) continue;
            const workspace_id = monitor.active_workspace_id.bytes;
            const layout_kind = self.layoutKindForWorkspaceId(state_export, workspace_id) orelse .niri;

            if (layout_kind == .dwindle) {
                const dwindle_rc = self.applyDwindleLayoutForWorkspace(state_export, monitor, workspace_id);
                if (dwindle_rc != abi.OMNI_OK) {
                    if (enable_runtime_grid_fallback) {
                        const fallback_rc = self.applyGridFallbackLayoutForWorkspace(state_export, monitor.active_workspace_id);
                        if (fallback_rc != abi.OMNI_OK) {
                            self.noteRuntimeLayoutFailure("dwindle-grid-fallback", fallback_rc);
                            return fallback_rc;
                        }
                        continue;
                    }
                    self.noteRuntimeLayoutFailure("dwindle-layout", dwindle_rc);
                    return dwindle_rc;
                }
                continue;
            }

            var runtime_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
            const snapshot_rc = self.snapshotWorkspaceLayoutRuntimeRecovering(state_export, workspace_id, &runtime_export);
            if (snapshot_rc != abi.OMNI_OK) {
                if (enable_runtime_grid_fallback) {
                    const fallback_rc = self.applyGridFallbackLayoutForWorkspace(state_export, monitor.active_workspace_id);
                    if (fallback_rc != abi.OMNI_OK) {
                        self.noteRuntimeLayoutFailure("niri-grid-fallback", fallback_rc);
                        return fallback_rc;
                    }
                    continue;
                }
                self.noteRuntimeLayoutFailure("niri-runtime-snapshot", snapshot_rc);
                return snapshot_rc;
            }

            if (runtime_export.window_count == 0 or runtime_export.windows == null) continue;

            var rendered_windows = [_]abi.OmniNiriWindowOutput{undefined} ** abi.MAX_WINDOWS;
            var rendered_columns = [_]abi.OmniNiriColumnOutput{undefined} ** abi.MAX_WINDOWS;
            const display_info = displayInfoForMonitor(self.display_infos.items, monitor.display_id);
            const selection = self.buildWorkspaceSelectionState(workspace_id, runtime_export, false);
            const layout_runtime = self.workspace_layout_runtimes.getPtr(workspace_id) orelse {
                self.noteRuntimeLayoutFailure("niri-runtime-missing", abi.OMNI_ERR_OUT_OF_RANGE);
                return abi.OMNI_ERR_OUT_OF_RANGE;
            };
            const working_area = self.workingAreaForMonitor(monitor);
            const monitor_settings = self.niriSettingsForDisplay(monitor.display_id);
            var render_request = abi.OmniNiriRuntimeRenderFromStateRequest{
                .expected_column_count = runtime_export.column_count,
                .expected_window_count = runtime_export.window_count,
                .working_x = working_area.x,
                .working_y = working_area.y,
                .working_width = working_area.width,
                .working_height = working_area.height,
                .view_x = monitor.frame_x,
                .view_y = monitor.frame_y,
                .view_width = monitor.frame_width,
                .view_height = monitor.frame_height,
                .fullscreen_x = working_area.x,
                .fullscreen_y = working_area.y,
                .fullscreen_width = working_area.width,
                .fullscreen_height = working_area.height,
                .primary_gap = self.layout_gap,
                .secondary_gap = self.layout_gap,
                .viewport_span = if (monitor_settings.orientation == abi.OMNI_NIRI_ORIENTATION_HORIZONTAL)
                    working_area.width
                else
                    working_area.height,
                .workspace_offset = 0.0,
                .has_fullscreen_window_id = if (selection.managed_fullscreen_window_id == null) 0 else 1,
                .fullscreen_window_id = if (selection.managed_fullscreen_window_id) |value| .{ .bytes = value } else zeroUuid(),
                .scale = if (display_info) |info| info.backing_scale else 2.0,
                .orientation = monitor_settings.orientation,
                .sample_time = self.last_tick_sample_time,
            };
            var render_output = abi.OmniNiriRuntimeRenderOutput{
                .windows = &rendered_windows[0],
                .window_count = runtime_export.window_count,
                .columns = if (runtime_export.column_count == 0) null else &rendered_columns[0],
                .column_count = runtime_export.column_count,
                .animation_active = 0,
            };
            const render_rc = niri_runtime.omni_niri_runtime_render_from_state_impl(
                layout_runtime.runtime,
                null,
                &render_request,
                &render_output,
            );
            if (render_rc != abi.OMNI_OK) {
                if (enable_runtime_grid_fallback) {
                    const fallback_rc = self.applyGridFallbackLayoutForWorkspace(state_export, monitor.active_workspace_id);
                    if (fallback_rc != abi.OMNI_OK) {
                        self.noteRuntimeLayoutFailure("niri-render-grid-fallback", fallback_rc);
                        return fallback_rc;
                    }
                    continue;
                }
                self.noteRuntimeLayoutFailure("niri-render", render_rc);
                return render_rc;
            }

            any_runtime_animation = any_runtime_animation or render_output.animation_active != 0;

            for (rendered_windows[0..render_output.window_count]) |rendered_window| {
                const window_record = managedWindowRecordByHandle(state_export, workspace_id, rendered_window.window_id.bytes) orelse continue;
                if (window_record.pid <= 0 or window_record.window_id <= 0 or window_record.window_id > std.math.maxInt(u32)) continue;
                self.frame_requests.append(self.allocator, .{
                    .pid = window_record.pid,
                    .window_id = @intCast(window_record.window_id),
                    .frame = .{
                        .x = rendered_window.animated_x,
                        .y = rendered_window.animated_y,
                        .width = rendered_window.animated_width,
                        .height = rendered_window.animated_height,
                    },
                }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
            }
        }

        if (any_runtime_animation) {
            self.markLayoutAnimationStarted(0.20);
        }

        const requests_ptr: [*c]const abi.OmniAXFrameRequest = if (self.frame_requests.items.len == 0)
            null
        else
            self.frame_requests.items.ptr;
        return ax_manager.omni_ax_runtime_apply_frames_batch_impl(
            ax_runtime_owner,
            requests_ptr,
            self.frame_requests.items.len,
        );
    }

    fn updateBorderPresentation(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) i32 {
        self.ensureBorderRuntime();
        const runtime = self.border_runtime orelse return abi.OMNI_OK;
        if (self.runtime_layout_render_failed) {
            if (!self.logged_border_suppression_for_runtime_failure) {
                std.log.warn("border suppressed because runtime layout render failed", .{});
                self.logged_border_suppression_for_runtime_failure = true;
            }
            return border.omni_border_runtime_hide_impl(runtime);
        }
        self.logged_border_suppression_for_runtime_failure = false;
        if (!self.border_enabled or self.lock_screen_active or self.non_managed_focus_active or self.app_fullscreen_active) {
            return border.omni_border_runtime_hide_impl(runtime);
        }
        if (self.display_infos.items.len == 0) {
            return border.omni_border_runtime_hide_impl(runtime);
        }

        const focused = self.resolveFocusedWindowRecord(state_export) orelse {
            return border.omni_border_runtime_hide_impl(runtime);
        };
        if (focused.window_id <= 0 or focused.window_id > std.math.maxInt(u32) or focused.pid <= 0) {
            return border.omni_border_runtime_hide_impl(runtime);
        }

        const ax_runtime_owner = self.ax_runtime orelse return border.omni_border_runtime_hide_impl(runtime);
        const window_id: u32 = @intCast(focused.window_id);

        var focused_frame = abi.OmniBorderRect{ .x = 0, .y = 0, .width = 0, .height = 0 };
        const frame_rc = ax_manager.omni_ax_runtime_get_window_frame_impl(
            ax_runtime_owner,
            focused.pid,
            window_id,
            &focused_frame,
        );
        if (frame_rc != abi.OMNI_OK) {
            return border.omni_border_runtime_hide_impl(runtime);
        }

        var fullscreen: u8 = 0;
        _ = ax_manager.omni_ax_runtime_is_window_fullscreen_impl(
            ax_runtime_owner,
            focused.pid,
            window_id,
            &fullscreen,
        );
        const managed_fullscreen: u8 = if (self.managedFullscreenByWindow(state_export, focused.handle_id.bytes)) 1 else 0;

        var snapshot = abi.OmniBorderSnapshotInput{
            .config = .{
                .enabled = if (self.border_enabled) 1 else 0,
                .width = self.border_width,
                .color = self.border_color,
            },
            .has_focused_window_id = 1,
            .focused_window_id = focused.window_id,
            .has_focused_frame = 1,
            .focused_frame = focused_frame,
            .is_focused_window_in_active_workspace = 1,
            .is_non_managed_focus_active = if (self.non_managed_focus_active) 1 else 0,
            .is_native_fullscreen_active = fullscreen,
            .is_managed_fullscreen_active = managed_fullscreen,
            .defer_updates = 0,
            .update_mode = if (self.layout_animation_active)
                abi.OMNI_BORDER_UPDATE_MODE_REALTIME
            else
                abi.OMNI_BORDER_UPDATE_MODE_COALESCED,
            .layout_animation_active = if (self.layout_animation_active) 1 else 0,
            .force_hide = 0,
            .displays = self.display_infos.items.ptr,
            .display_count = self.display_infos.items.len,
        };
        return border.omni_border_runtime_submit_snapshot_impl(runtime, &snapshot);
    }

    fn managedFullscreenByWindow(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        window_id: Uuid,
    ) bool {
        const window = self.findWindowRecord(state_export, window_id) orelse return false;
        const fullscreen_window = self.managed_fullscreen_by_workspace.get(window.workspace_id.bytes) orelse return false;
        return std.mem.eql(u8, fullscreen_window[0..], window_id[0..]);
    }

    fn resolveFocusedWindowRecord(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) ?abi.OmniWorkspaceRuntimeWindowRecord {
        if (self.focused_window) |focused| {
            if (self.findWindowRecord(state_export, focused)) |record| {
                if (record.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) return null;
                return record;
            }
        }
        return null;
    }

    fn reconcileFocusedWindow(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) void {
        const focused = self.focused_window orelse return;
        const record = self.findWindowRecord(state_export, focused) orelse {
            self.focused_window = null;
            return;
        };
        if (record.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) {
            self.focused_window = null;
        }
    }

    const FocusDirection = enum {
        backward,
        forward,
    };

    fn directionFromRaw(direction: u8) ?FocusDirection {
        return switch (direction) {
            abi.OMNI_NIRI_DIRECTION_LEFT,
            abi.OMNI_NIRI_DIRECTION_UP,
            => .backward,
            abi.OMNI_NIRI_DIRECTION_RIGHT,
            abi.OMNI_NIRI_DIRECTION_DOWN,
            => .forward,
            else => null,
        };
    }

    fn isFocusLayoutAction(kind: u8) bool {
        return switch (kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX,
            => true,
            else => false,
        };
    }

    fn focusByDirection(self: *RuntimeImpl, direction: FocusDirection) i32 {
        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const export_rc = self.exportWorkspaceState(&state_export);
        if (export_rc != abi.OMNI_OK) return export_rc;

        const workspace_id = self.resolveActiveWorkspaceForFocus(state_export) orelse return abi.OMNI_OK;
        var windows = self.collectWorkspaceHandles(state_export, workspace_id) catch return abi.OMNI_OK;
        defer windows.deinit(self.allocator);
        if (windows.items.len == 0) return abi.OMNI_OK;

        var focused_index: usize = 0;
        if (self.focused_window) |focused| {
            for (windows.items, 0..) |candidate, idx| {
                if (std.mem.eql(u8, candidate[0..], focused[0..])) {
                    focused_index = idx;
                    break;
                }
            }
        }

        const target_index = switch (direction) {
            .backward => if (focused_index == 0) windows.items.len - 1 else focused_index - 1,
            .forward => (focused_index + 1) % windows.items.len,
        };
        return self.focusWindowByHandle(windows.items[target_index]);
    }

    fn focusByIndex(self: *RuntimeImpl, raw_index: i64) i32 {
        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const export_rc = self.exportWorkspaceState(&state_export);
        if (export_rc != abi.OMNI_OK) return export_rc;

        const workspace_id = self.resolveActiveWorkspaceForFocus(state_export) orelse return abi.OMNI_OK;
        var windows = self.collectWorkspaceHandles(state_export, workspace_id) catch return abi.OMNI_OK;
        defer windows.deinit(self.allocator);
        if (windows.items.len == 0) return abi.OMNI_OK;

        const target_index: usize = if (raw_index < 0)
            windows.items.len - 1
        else
            @min(@as(usize, @intCast(raw_index)), windows.items.len - 1);
        return self.focusWindowByHandle(windows.items[target_index]);
    }

    fn resolveWorkspaceRuntimeContextRecovering(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
        prefer_first_window: bool,
    ) WorkspaceRuntimeContextResolution {
        var runtime_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
        const snapshot_rc = self.snapshotWorkspaceLayoutRuntimeRecovering(state_export, workspace_id, &runtime_export);
        if (snapshot_rc != abi.OMNI_OK) {
            return .{ .rc = snapshot_rc };
        }

        const layout_runtime = self.workspace_layout_runtimes.getPtr(workspace_id) orelse {
            return .{ .rc = abi.OMNI_ERR_OUT_OF_RANGE };
        };

        return .{
            .context = .{
                .workspace_id = .{ .bytes = workspace_id },
                .layout_runtime = layout_runtime,
                .runtime_export = runtime_export,
                .selection = self.buildWorkspaceSelectionState(workspace_id, runtime_export, prefer_first_window),
            },
        };
    }

    fn resolveActiveWorkspaceRuntimeContextRecovering(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        prefer_first_window: bool,
    ) WorkspaceRuntimeContextResolution {
        const workspace_id = self.resolveActiveWorkspaceForFocus(state_export) orelse return .{};
        return self.resolveWorkspaceRuntimeContextRecovering(state_export, workspace_id.bytes, prefer_first_window);
    }

    fn applyRuntimeTxn(
        self: *RuntimeImpl,
        ctx: WorkspaceRuntimeContext,
        txn: abi.OmniNiriTxnRequest,
        request_focus: bool,
    ) i32 {
        var command_request = abi.OmniNiriRuntimeCommandRequest{
            .txn = txn,
            .sample_time = self.last_tick_sample_time,
        };
        var command_result = std.mem.zeroes(abi.OmniNiriRuntimeCommandResult);
        const rc = niri_runtime.omni_niri_runtime_apply_command_impl(
            ctx.layout_runtime.runtime,
            null,
            &command_request,
            &command_result,
        );
        if (rc != abi.OMNI_OK) return rc;

        if (command_result.txn.structural_animation_active != 0) {
            self.markLayoutAnimationStarted(0.20);
        }

        const workspace_id = ctx.workspace_id.bytes;
        if (command_result.txn.has_target_node_id != 0) {
            self.setSelectedNode(workspace_id, command_result.txn.target_node_id.bytes);
        } else if (command_result.txn.has_target_window_id != 0) {
            self.setSelectedNode(workspace_id, command_result.txn.target_window_id.bytes);
        }

        if (command_result.txn.has_target_window_id != 0) {
            self.focused_window = command_result.txn.target_window_id.bytes;
            self.setLastFocusedWindow(workspace_id, command_result.txn.target_window_id.bytes);
            if (request_focus) {
                const focus_rc = self.focusWindowByHandle(command_result.txn.target_window_id.bytes);
                if (focus_rc != abi.OMNI_OK and focus_rc != abi.OMNI_ERR_PLATFORM and focus_rc != abi.OMNI_ERR_OUT_OF_RANGE) {
                    return focus_rc;
                }
            }
        }

        return abi.OMNI_OK;
    }

    fn buildNavigationTxn(
        self: *RuntimeImpl,
        ctx: WorkspaceRuntimeContext,
        action: abi.OmniControllerLayoutAction,
        out_txn: *abi.OmniNiriTxnRequest,
    ) i32 {
        out_txn.* = std.mem.zeroes(abi.OmniNiriTxnRequest);
        out_txn.kind = abi.OMNI_NIRI_TXN_NAVIGATION;
        out_txn.navigation.orientation = self.niriSettingsForWorkspace(ctx.workspace_id.bytes).orientation;
        out_txn.navigation.infinite_loop = if (self.niri_infinite_loop) 1 else 0;
        if (ctx.selection.actionable_window_id) |window_id| {
            out_txn.navigation.has_source_window_id = 1;
            out_txn.navigation.source_window_id = .{ .bytes = window_id };
        }
        if (ctx.selection.selected_column_id) |column_id| {
            out_txn.navigation.has_source_column_id = 1;
            out_txn.navigation.source_column_id = .{ .bytes = column_id };
        }

        switch (action.kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION => {
                if (!isDirectionValue(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_TARGET;
                out_txn.navigation.direction = action.direction;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_DOWN_OR_LEFT;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_UP_OR_RIGHT;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_COLUMN_FIRST;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_COLUMN_LAST;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_COLUMN_INDEX;
                out_txn.navigation.focus_column_index = action.index;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_WINDOW_TOP;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM => {
                out_txn.navigation.op = abi.OMNI_NIRI_NAV_OP_FOCUS_WINDOW_BOTTOM;
            },
            else => return abi.OMNI_ERR_INVALID_ARGS,
        }

        return abi.OMNI_OK;
    }

    fn workspaceIdForLayoutAction(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) ?Uuid {
        if (action.has_workspace_id != 0) {
            return action.workspace_id.bytes;
        }
        const active_workspace = self.resolveActiveWorkspaceForFocus(state_export) orelse return null;
        return active_workspace.bytes;
    }

    fn activeLayoutKindForLayoutAction(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) ?types.LayoutKind {
        const workspace_id = self.workspaceIdForLayoutAction(state_export, action) orelse return null;
        return self.layoutKindForWorkspaceId(state_export, workspace_id);
    }

    fn upsertWorkspaceLayoutOverride(
        self: *RuntimeImpl,
        workspace_name: abi.OmniWorkspaceRuntimeName,
        layout_kind: types.LayoutKind,
    ) i32 {
        const normalized_kind = self.effectiveLayoutKind(layout_kind);
        const controller_name = controllerNameFromWorkspaceName(workspace_name);
        var existing_index: ?usize = null;
        for (self.workspace_layout_settings.items, 0..) |setting, index| {
            if (controllerNamesEqual(setting.name, controller_name)) {
                existing_index = index;
                break;
            }
        }

        if (normalized_kind == self.default_layout_kind) {
            if (existing_index) |index| {
                var cursor = index;
                while (cursor + 1 < self.workspace_layout_settings.items.len) : (cursor += 1) {
                    self.workspace_layout_settings.items[cursor] = self.workspace_layout_settings.items[cursor + 1];
                }
                self.workspace_layout_settings.items.len -= 1;
            }
            return abi.OMNI_OK;
        }

        if (existing_index) |index| {
            self.workspace_layout_settings.items[index].layout_kind = normalized_kind;
            return abi.OMNI_OK;
        }

        self.workspace_layout_settings.append(self.allocator, .{
            .name = controller_name,
            .layout_kind = normalized_kind,
        }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        return abi.OMNI_OK;
    }

    fn toggleWorkspaceLayout(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) i32 {
        const workspace_id = self.workspaceIdForLayoutAction(state_export, action) orelse return abi.OMNI_OK;
        const workspace = workspaceRecordById(state_export, workspace_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        const current_layout = self.layoutKindForWorkspaceRecord(workspace);
        const next_layout: types.LayoutKind = switch (current_layout) {
            .dwindle => .niri,
            .niri, .default_layout => .dwindle,
        };

        const update_rc = self.upsertWorkspaceLayoutOverride(workspace.name, next_layout);
        if (update_rc != abi.OMNI_OK) return update_rc;

        const sync_rc = self.syncWorkspaceLayoutRuntimes(state_export);
        if (sync_rc != abi.OMNI_OK) return sync_rc;

        self.markLayoutAnimationStarted(0.20);
        return abi.OMNI_OK;
    }

    fn applyDwindleLayoutAction(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) i32 {
        const workspace_id = self.workspaceIdForLayoutAction(state_export, action) orelse return abi.OMNI_OK;
        if (self.layoutKindForWorkspaceId(state_export, workspace_id) != .dwindle) return abi.OMNI_OK;
        if (action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION and self.non_managed_focus_active) {
            return abi.OMNI_OK;
        }

        var request = abi.OmniDwindleOpRequest{
            .op = abi.OMNI_DWINDLE_OP_VALIDATE_SELECTION,
            .payload = undefined,
            .runtime_settings = undefined,
        };
        var result = std.mem.zeroes(abi.OmniDwindleOpResult);
        var removed_window_ids = [_]abi.OmniUuid128{zeroUuid()} ** abi.MAX_WINDOWS;
        var request_focus = false;

        switch (action.kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION => {
                if (!isDirectionValue(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                request.op = abi.OMNI_DWINDLE_OP_MOVE_FOCUS;
                request.payload.move_focus = .{ .direction = action.direction };
                request_focus = true;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION => {
                if (!isDirectionValue(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                request.op = abi.OMNI_DWINDLE_OP_SWAP_WINDOWS;
                request.payload.swap_windows = .{ .direction = action.direction };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_FULLSCREEN => {
                request.op = abi.OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN;
                request.payload.toggle_fullscreen = .{ .unused = 0 };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES => {
                request.op = abi.OMNI_DWINDLE_OP_BALANCE_SIZES;
                request.payload.balance_sizes = .{ .unused = 0 };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD,
            => {
                request.op = abi.OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO;
                request.payload.cycle_split_ratio = .{
                    .forward = if (action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD) 1 else 0,
                };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT => {
                request.op = abi.OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT;
                request.payload.move_selection_to_root = .{
                    .stable = if (self.dwindle_move_to_root_stable) 1 else 0,
                };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT => {
                request.op = abi.OMNI_DWINDLE_OP_TOGGLE_ORIENTATION;
                request.payload.toggle_orientation = .{ .unused = 0 };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT => {
                request.op = abi.OMNI_DWINDLE_OP_SWAP_SPLIT;
                request.payload.swap_split = .{ .unused = 0 };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION => {
                if (!isDirectionValue(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                request.op = abi.OMNI_DWINDLE_OP_RESIZE_SELECTED;
                request.payload.resize_selected = .{
                    .delta = if (action.flag != 0) default_dwindle_resize_step else -default_dwindle_resize_step,
                    .direction = action.direction,
                };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION => {
                if (!isDirectionValue(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                request.op = abi.OMNI_DWINDLE_OP_SET_PRESELECTION;
                request.payload.set_preselection = .{ .direction = action.direction };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR => {
                request.op = abi.OMNI_DWINDLE_OP_CLEAR_PRESELECTION;
                request.payload.clear_preselection = .{ .unused = 0 };
            },
            else => return abi.OMNI_ERR_INVALID_ARGS,
        }

        const rc = self.applyDwindleOp(
            state_export,
            workspace_id,
            &request,
            &result,
            removed_window_ids[0..],
        );
        if (rc != abi.OMNI_OK) return rc;

        self.updateDwindleSelectionStateFromResult(workspace_id, result);
        self.syncManagedFullscreenFromDwindleRuntime(workspace_id);

        if (result.has_focused_window_id != 0) {
            self.focused_window = result.focused_window_id.bytes;
            if (request_focus) {
                const focus_rc = self.focusWindowByHandle(result.focused_window_id.bytes);
                if (focus_rc != abi.OMNI_OK and focus_rc != abi.OMNI_ERR_PLATFORM and focus_rc != abi.OMNI_ERR_OUT_OF_RANGE) {
                    return focus_rc;
                }
            }
        }

        self.markLayoutAnimationStarted(0.20);
        return abi.OMNI_OK;
    }

    fn applyNiriNavigationAction(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) i32 {
        if (self.non_managed_focus_active) return abi.OMNI_OK;

        var resolved = self.resolveActiveWorkspaceRuntimeContextRecovering(state_export, true);
        if (resolved.rc != abi.OMNI_OK) {
            return self.reportPhaseError(resolved.rc, "navigation runtime snapshot failed");
        }
        var ctx = resolved.context orelse return abi.OMNI_OK;
        if (ctx.selection.actionable_window_id == null) return abi.OMNI_OK;

        var txn = std.mem.zeroes(abi.OmniNiriTxnRequest);
        const build_rc = self.buildNavigationTxn(ctx, action, &txn);
        if (build_rc != abi.OMNI_OK) return build_rc;

        var rc = self.applyRuntimeTxn(ctx, txn, true);
        if (rc == abi.OMNI_ERR_OUT_OF_RANGE) {
            self.clearWorkspaceSelectionCache(ctx.workspace_id.bytes);

            const reseed_rc = self.syncWorkspaceLayoutRuntimeForWorkspace(state_export, ctx.workspace_id.bytes);
            if (reseed_rc != abi.OMNI_OK) {
                return self.reportPhaseError(reseed_rc, "navigation runtime reseed failed");
            }

            resolved = self.resolveWorkspaceRuntimeContextRecovering(state_export, ctx.workspace_id.bytes, true);
            if (resolved.rc != abi.OMNI_OK) {
                return self.reportPhaseError(resolved.rc, "navigation runtime snapshot retry failed");
            }
            ctx = resolved.context orelse return abi.OMNI_OK;
            if (ctx.selection.actionable_window_id == null) return abi.OMNI_OK;

            const retry_build_rc = self.buildNavigationTxn(ctx, action, &txn);
            if (retry_build_rc != abi.OMNI_OK) return retry_build_rc;
            rc = self.applyRuntimeTxn(ctx, txn, true);
        }

        if (rc != abi.OMNI_OK and rc != abi.OMNI_ERR_PLATFORM) {
            return self.reportPhaseError(rc, "navigation runtime transaction failed");
        }
        return rc;
    }

    fn applyNiriMutationAction(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) i32 {
        const resolved = self.resolveActiveWorkspaceRuntimeContextRecovering(state_export, true);
        if (resolved.rc != abi.OMNI_OK) return resolved.rc;
        const ctx = resolved.context orelse return abi.OMNI_OK;

        var txn = std.mem.zeroes(abi.OmniNiriTxnRequest);
        txn.kind = abi.OMNI_NIRI_TXN_MUTATION;
        txn.mutation.infinite_loop = if (self.niri_infinite_loop) 1 else 0;
        txn.mutation.max_windows_per_column = self.niri_max_windows_per_column;
        txn.mutation.max_visible_columns = self.niri_max_visible_columns;
        txn.mutation.incoming_spawn_mode = abi.OMNI_NIRI_SPAWN_FOCUSED_COLUMN;
        if (ctx.selection.selected_node_id) |selected_node_id| {
            txn.mutation.has_selected_node_id = 1;
            txn.mutation.selected_node_id = .{ .bytes = selected_node_id };
        }
        if (ctx.selection.focused_window_id) |focused_window_id| {
            txn.mutation.has_focused_window_id = 1;
            txn.mutation.focused_window_id = .{ .bytes = focused_window_id };
        }
        if (ctx.selection.actionable_window_id) |window_id| {
            txn.mutation.has_source_window_id = 1;
            txn.mutation.source_window_id = .{ .bytes = window_id };
        }
        if (ctx.selection.selected_column_id) |column_id| {
            txn.mutation.has_source_column_id = 1;
            txn.mutation.source_column_id = .{ .bytes = column_id };
        }

        switch (action.kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_DIRECTION => {
                txn.mutation.op = mutationOpForDirection(action.direction, false) orelse return abi.OMNI_ERR_INVALID_ARGS;
                txn.mutation.direction = action.direction;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION => {
                txn.mutation.op = mutationOpForDirection(action.direction, true) orelse return abi.OMNI_ERR_INVALID_ARGS;
                txn.mutation.direction = action.direction;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION => {
                if (!isHorizontalDirection(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_MOVE_COLUMN;
                txn.mutation.direction = action.direction;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CONSUME_WINDOW_DIRECTION => {
                if (!isHorizontalDirection(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_CONSUME_WINDOW;
                txn.mutation.direction = action.direction;
                txn.mutation.has_placeholder_column_id = 1;
                txn.mutation.placeholder_column_id = ctx.layout_runtime.generateColumnId(ctx.workspace_id.bytes);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_EXPEL_WINDOW_DIRECTION => {
                if (!isHorizontalDirection(action.direction)) return abi.OMNI_ERR_INVALID_ARGS;
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_EXPEL_WINDOW;
                txn.mutation.direction = action.direction;
                txn.mutation.has_created_column_id = 1;
                txn.mutation.created_column_id = ctx.layout_runtime.generateColumnId(ctx.workspace_id.bytes);
                txn.mutation.has_placeholder_column_id = 1;
                txn.mutation.placeholder_column_id = ctx.layout_runtime.generateColumnId(ctx.workspace_id.bytes);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED => {
                const column_id = ctx.selection.selected_column_id orelse return abi.OMNI_OK;
                const column_index = findRuntimeColumnIndex(ctx.runtime_export, column_id) orelse return abi.OMNI_OK;
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_SET_COLUMN_DISPLAY;
                txn.mutation.source_column_id = ctx.runtime_export.columns[column_index].column_id;
                txn.mutation.has_source_column_id = 1;
                txn.mutation.custom_u8_a = if (ctx.runtime_export.columns[column_index].is_tabbed != 0) 0 else 1;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD,
            => {
                const column_id = ctx.selection.selected_column_id orelse return abi.OMNI_OK;
                const column_index = findRuntimeColumnIndex(ctx.runtime_export, column_id) orelse return abi.OMNI_OK;
                const column = ctx.runtime_export.columns[column_index];
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_SET_COLUMN_WIDTH;
                txn.mutation.source_column_id = column.column_id;
                txn.mutation.has_source_column_id = 1;
                txn.mutation.custom_u8_a = abi.OMNI_NIRI_SIZE_KIND_PROPORTION;
                txn.mutation.custom_f64_a = self.cycleColumnWidthPreset(
                    column,
                    action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD,
                );
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH => {
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_TOGGLE_COLUMN_FULL_WIDTH;
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES => {
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_BALANCE_SIZES;
            },
            else => return abi.OMNI_ERR_INVALID_ARGS,
        }

        return self.applyRuntimeTxn(ctx, txn, false);
    }

    fn applyNiriOverviewInsertAction(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        action: abi.OmniControllerLayoutAction,
    ) i32 {
        const workspace_id = types.optionalUuid(action.has_workspace_id, action.workspace_id) orelse return abi.OMNI_ERR_INVALID_ARGS;
        if (self.layoutKindForWorkspaceId(state_export, workspace_id) != .niri) return abi.OMNI_OK;

        const source_window_id = types.optionalUuid(action.has_window_handle_id, action.window_handle_id) orelse {
            return abi.OMNI_ERR_INVALID_ARGS;
        };
        const source_window = self.findWindowRecord(state_export, source_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        if (source_window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD or
            !std.mem.eql(u8, source_window.workspace_id.bytes[0..], workspace_id[0..]))
        {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        }

        var resolved = self.resolveWorkspaceRuntimeContextRecovering(state_export, workspace_id, false);
        if (resolved.rc != abi.OMNI_OK) {
            return self.reportPhaseError(resolved.rc, "overview insert runtime snapshot failed");
        }
        var ctx = resolved.context orelse return abi.OMNI_OK;

        var txn = std.mem.zeroes(abi.OmniNiriTxnRequest);
        txn.kind = abi.OMNI_NIRI_TXN_MUTATION;
        txn.mutation.infinite_loop = if (self.niri_infinite_loop) 1 else 0;
        txn.mutation.max_windows_per_column = self.niri_max_windows_per_column;
        txn.mutation.max_visible_columns = self.niri_max_visible_columns;
        txn.mutation.incoming_spawn_mode = abi.OMNI_NIRI_SPAWN_FOCUSED_COLUMN;
        txn.mutation.has_source_window_id = 1;
        txn.mutation.source_window_id = .{ .bytes = source_window_id };

        if (ctx.selection.selected_node_id) |selected_node_id| {
            txn.mutation.has_selected_node_id = 1;
            txn.mutation.selected_node_id = .{ .bytes = selected_node_id };
        }
        if (ctx.selection.focused_window_id) |focused_window_id| {
            txn.mutation.has_focused_window_id = 1;
            txn.mutation.focused_window_id = .{ .bytes = focused_window_id };
        }
        if (ctx.selection.selected_column_id) |column_id| {
            txn.mutation.has_source_column_id = 1;
            txn.mutation.source_column_id = .{ .bytes = column_id };
        }

        switch (action.kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW => {
                const target_window_id = types.optionalUuid(
                    action.has_secondary_window_handle_id,
                    action.secondary_window_handle_id,
                ) orelse return abi.OMNI_ERR_INVALID_ARGS;
                const target_window = self.findWindowRecord(state_export, target_window_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
                if (target_window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD or
                    !std.mem.eql(u8, target_window.workspace_id.bytes[0..], workspace_id[0..]))
                {
                    return abi.OMNI_ERR_OUT_OF_RANGE;
                }
                if (action.flag != abi.OMNI_NIRI_INSERT_BEFORE and
                    action.flag != abi.OMNI_NIRI_INSERT_AFTER and
                    action.flag != abi.OMNI_NIRI_INSERT_SWAP)
                {
                    return abi.OMNI_ERR_INVALID_ARGS;
                }
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_BY_MOVE;
                txn.mutation.insert_position = action.flag;
                txn.mutation.has_target_window_id = 1;
                txn.mutation.target_window_id = .{ .bytes = target_window_id };
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN => {
                txn.mutation.op = abi.OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_IN_NEW_COLUMN;
                txn.mutation.insert_column_index = action.index;
                txn.mutation.has_created_column_id = 1;
                txn.mutation.created_column_id = ctx.layout_runtime.generateColumnId(workspace_id);
                txn.mutation.has_placeholder_column_id = 1;
                txn.mutation.placeholder_column_id = ctx.layout_runtime.generateColumnId(workspace_id);
            },
            else => return abi.OMNI_ERR_INVALID_ARGS,
        }

        var rc = self.applyRuntimeTxn(ctx, txn, false);
        if (rc == abi.OMNI_ERR_OUT_OF_RANGE) {
            self.clearWorkspaceSelectionCache(workspace_id);
            const reseed_rc = self.syncWorkspaceLayoutRuntimeForWorkspace(state_export, workspace_id);
            if (reseed_rc != abi.OMNI_OK) {
                return self.reportPhaseError(reseed_rc, "overview insert runtime reseed failed");
            }

            resolved = self.resolveWorkspaceRuntimeContextRecovering(state_export, workspace_id, false);
            if (resolved.rc != abi.OMNI_OK) {
                return self.reportPhaseError(resolved.rc, "overview insert runtime snapshot retry failed");
            }
            ctx = resolved.context orelse return abi.OMNI_OK;

            if (action.kind == abi.OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN) {
                txn.mutation.created_column_id = ctx.layout_runtime.generateColumnId(workspace_id);
                txn.mutation.placeholder_column_id = ctx.layout_runtime.generateColumnId(workspace_id);
            }
            rc = self.applyRuntimeTxn(ctx, txn, false);
        }

        if (rc != abi.OMNI_OK and rc != abi.OMNI_ERR_PLATFORM) {
            return self.reportPhaseError(rc, "overview insert runtime transaction failed");
        }
        return rc;
    }

    fn toggleManagedFullscreen(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
    ) i32 {
        const resolved = self.resolveActiveWorkspaceRuntimeContextRecovering(state_export, true);
        if (resolved.rc != abi.OMNI_OK) return resolved.rc;
        const ctx = resolved.context orelse return abi.OMNI_OK;
        const target_window_id = ctx.selection.actionable_window_id orelse return abi.OMNI_OK;
        const workspace_id = ctx.workspace_id.bytes;

        if (self.managed_fullscreen_by_workspace.get(workspace_id)) |current_window_id| {
            if (std.mem.eql(u8, current_window_id[0..], target_window_id[0..])) {
                self.clearManagedFullscreenWindow(workspace_id);
            } else {
                self.setManagedFullscreenWindow(workspace_id, target_window_id);
            }
        } else {
            self.setManagedFullscreenWindow(workspace_id, target_window_id);
        }

        self.markLayoutAnimationStarted(0.20);
        return abi.OMNI_OK;
    }

    fn toggleNativeFullscreen(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
    ) i32 {
        const resolved = self.resolveActiveWorkspaceRuntimeContextRecovering(state_export, true);
        if (resolved.rc != abi.OMNI_OK) return resolved.rc;
        const ctx = resolved.context orelse return abi.OMNI_OK;
        const target_window_id = ctx.selection.actionable_window_id orelse return abi.OMNI_OK;
        const window = self.findWindowRecord(state_export, target_window_id) orelse return abi.OMNI_OK;
        if (window.pid <= 0 or window.window_id <= 0 or window.window_id > std.math.maxInt(u32)) {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        }

        const ax_runtime_owner = self.ax_runtime orelse return abi.OMNI_ERR_PLATFORM;
        const raw_window_id: u32 = @intCast(window.window_id);
        var fullscreen: u8 = 0;
        const query_rc = ax_manager.omni_ax_runtime_is_window_fullscreen_impl(
            ax_runtime_owner,
            window.pid,
            raw_window_id,
            &fullscreen,
        );
        if (query_rc != abi.OMNI_OK) return query_rc;

        const set_rc = ax_manager.omni_ax_runtime_set_window_fullscreen_impl(
            ax_runtime_owner,
            window.pid,
            raw_window_id,
            if (fullscreen != 0) 0 else 1,
        );
        if (set_rc == abi.OMNI_OK) {
            self.markLayoutAnimationStarted(0.20);
        }
        return set_rc;
    }

    fn resolveActiveWorkspaceForFocus(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
    ) ?abi.OmniUuid128 {
        const active_display = self.active_monitor_override orelse optionalDisplayId(
            state_export.has_active_monitor_display_id,
            state_export.active_monitor_display_id,
        );

        if (active_display) |display_id| {
            return self.activeWorkspaceForDisplay(state_export, display_id);
        }

        if (state_export.monitor_count == 0 or state_export.monitors == null) return null;
        const monitor = state_export.monitors[0];
        if (monitor.has_active_workspace_id != 0) {
            return monitor.active_workspace_id;
        }
        if (state_export.workspace_count > 0 and state_export.workspaces != null) {
            return state_export.workspaces[0].workspace_id;
        }
        return null;
    }

    fn activeWorkspaceForDisplay(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        display_id: u32,
    ) ?abi.OmniUuid128 {
        _ = self;
        if (state_export.monitor_count == 0 or state_export.monitors == null) return null;
        for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
            if (monitor.display_id != display_id) continue;
            if (monitor.has_active_workspace_id == 0) return null;
            return monitor.active_workspace_id;
        }
        return null;
    }

    fn collectWorkspaceHandles(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: abi.OmniUuid128,
    ) !std.ArrayListUnmanaged(Uuid) {
        var result = std.ArrayListUnmanaged(Uuid){};
        errdefer result.deinit(self.allocator);

        if (state_export.window_count == 0 or state_export.windows == null) {
            return result;
        }

        for (state_export.windows[0..state_export.window_count]) |window| {
            if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id.bytes[0..])) continue;
            try result.append(self.allocator, window.handle_id.bytes);
        }

        return result;
    }

    fn focusWindowByHandle(self: *RuntimeImpl, handle_id: Uuid) i32 {
        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const export_rc = self.exportWorkspaceState(&state_export);
        if (export_rc != abi.OMNI_OK) return export_rc;

        const window = self.findWindowRecord(state_export, handle_id) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
        if (window.pid <= 0 or window.window_id <= 0 or window.window_id > std.math.maxInt(u32)) {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        }

        const focus_rc = focus_manager.focusWindow(window.pid, @intCast(window.window_id));
        if (focus_rc == abi.OMNI_OK) {
            self.focused_window = handle_id;
            self.setLastFocusedWindow(window.workspace_id.bytes, handle_id);
            self.setSelectedNode(window.workspace_id.bytes, handle_id);
        }
        return focus_rc;
    }

    fn findWindowRecord(
        self: *RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        handle_id: Uuid,
    ) ?abi.OmniWorkspaceRuntimeWindowRecord {
        _ = self;
        if (state_export.window_count == 0 or state_export.windows == null) return null;
        for (state_export.windows[0..state_export.window_count]) |window| {
            if (std.mem.eql(u8, window.handle_id.bytes[0..], handle_id[0..])) {
                return window;
            }
        }
        return null;
    }

    fn workingAreaForMonitor(
        self: *const RuntimeImpl,
        monitor: abi.OmniWorkspaceRuntimeMonitorRecord,
    ) WorkingArea {
        return .{
            .x = monitor.visible_x + self.outer_gap_left,
            .y = monitor.visible_y + self.outer_gap_bottom,
            .width = @max(0.0, monitor.visible_width - self.outer_gap_left - self.outer_gap_right),
            .height = @max(0.0, monitor.visible_height - self.outer_gap_top - self.outer_gap_bottom),
        };
    }

    fn niriSettingsForDisplay(self: *const RuntimeImpl, display_id: u32) MonitorNiriSettings {
        return self.monitor_niri_settings_by_display.get(display_id) orelse .{};
    }

    fn niriSettingsForWorkspace(self: *RuntimeImpl, workspace_id: Uuid) MonitorNiriSettings {
        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        if (self.exportWorkspaceState(&state_export) != abi.OMNI_OK) return .{};
        if (monitorForWorkspace(state_export, workspace_id)) |monitor| {
            return self.niriSettingsForDisplay(monitor.display_id);
        }
        return .{};
    }

    fn normalizeLayoutKind(raw: u8) types.LayoutKind {
        return switch (raw) {
            abi.OMNI_CONTROLLER_LAYOUT_DWINDLE => .dwindle,
            abi.OMNI_CONTROLLER_LAYOUT_DEFAULT => .default_layout,
            else => .niri,
        };
    }

    fn effectiveLayoutKind(self: *const RuntimeImpl, kind: types.LayoutKind) types.LayoutKind {
        return switch (kind) {
            .default_layout => self.default_layout_kind,
            .niri => .niri,
            .dwindle => .dwindle,
        };
    }

    fn layoutKindForWorkspaceName(self: *const RuntimeImpl, name: abi.OmniWorkspaceRuntimeName) types.LayoutKind {
        const controller_name = controllerNameFromWorkspaceName(name);
        for (self.workspace_layout_settings.items) |setting| {
            if (controllerNamesEqual(setting.name, controller_name)) {
                return self.effectiveLayoutKind(setting.layout_kind);
            }
        }
        return self.default_layout_kind;
    }

    fn layoutKindForWorkspaceRecord(self: *const RuntimeImpl, workspace: abi.OmniWorkspaceRuntimeWorkspaceRecord) types.LayoutKind {
        return self.layoutKindForWorkspaceName(workspace.name);
    }

    fn layoutKindForWorkspaceId(
        self: *const RuntimeImpl,
        state_export: abi.OmniWorkspaceRuntimeStateExport,
        workspace_id: Uuid,
    ) ?types.LayoutKind {
        const workspace = workspaceRecordById(state_export, workspace_id) orelse return null;
        return self.layoutKindForWorkspaceRecord(workspace);
    }

    const DwindleWindowRecordSnapshot = struct {
        node_id: Uuid,
        order_index: usize,
        is_fullscreen: bool,
    };

    fn findDwindleWindowSnapshot(
        ctx: *const dwindle.OmniDwindleLayoutContext,
        handle_id: Uuid,
    ) ?DwindleWindowRecordSnapshot {
        const root_index_i64 = ctx.seed_state.root_node_index;
        if (root_index_i64 < 0) return null;
        var order_index: usize = 0;
        return findDwindleWindowSnapshotRecursive(
            ctx,
            @intCast(root_index_i64),
            handle_id,
            &order_index,
        );
    }

    fn findDwindleWindowSnapshotRecursive(
        ctx: *const dwindle.OmniDwindleLayoutContext,
        node_index: usize,
        handle_id: Uuid,
        order_index: *usize,
    ) ?DwindleWindowRecordSnapshot {
        if (node_index >= ctx.node_count) return null;
        const node = ctx.nodes[node_index];
        if (node.kind == abi.OMNI_DWINDLE_NODE_LEAF) {
            if (node.has_window_id == 0) return null;
            const current_order = order_index.*;
            order_index.* += 1;
            if (std.mem.eql(u8, node.window_id.bytes[0..], handle_id[0..])) {
                return .{
                    .node_id = node.node_id.bytes,
                    .order_index = current_order,
                    .is_fullscreen = node.is_fullscreen != 0,
                };
            }
            return null;
        }

        if (node.first_child_index >= 0) {
            if (findDwindleWindowSnapshotRecursive(
                ctx,
                @intCast(node.first_child_index),
                handle_id,
                order_index,
            )) |snapshot| {
                return snapshot;
            }
        }
        if (node.second_child_index >= 0) {
            if (findDwindleWindowSnapshotRecursive(
                ctx,
                @intCast(node.second_child_index),
                handle_id,
                order_index,
            )) |snapshot| {
                return snapshot;
            }
        }
        return null;
    }

    fn cycleColumnWidthPreset(
        self: *const RuntimeImpl,
        column: abi.OmniNiriRuntimeColumnState,
        forward: bool,
    ) f64 {
        const preset_count = if (self.niri_width_preset_count == 0)
            default_niri_width_presets.len
        else
            self.niri_width_preset_count;
        const presets = if (self.niri_width_preset_count == 0)
            default_niri_width_presets[0..]
        else
            self.niri_width_presets[0..preset_count];

        var current_index: usize = if (presets.len > 1) 1 else 0;
        if (column.is_full_width == 0 and column.width_kind == abi.OMNI_NIRI_SIZE_KIND_PROPORTION) {
            var best_distance = std.math.inf(f64);
            for (presets, 0..) |preset, preset_index| {
                const distance = @abs(preset - column.size_value);
                if (distance < best_distance) {
                    best_distance = distance;
                    current_index = preset_index;
                }
            }
        }

        if (forward) {
            return presets[(current_index + 1) % presets.len];
        }
        return presets[(current_index + presets.len - 1) % presets.len];
    }

    fn updateTickTimerLocked(self: *RuntimeImpl) void {
        const should_run = self.started and (self.layout_animation_deadline != null or
            self.layout_animation_active or
            self.layout_immediate_in_progress or
            self.layout_incremental_in_progress or
            self.layout_full_enumeration_in_progress);

        if (!should_run) {
            self.disarmTickTimerLocked();
            return;
        }

        const interval = 1.0 / 120.0;
        const next_fire = currentSampleTime() + interval;
        if (self.tick_timer == null) {
            var context = c.CFRunLoopTimerContext{
                .version = 0,
                .info = @ptrCast(self),
                .retain = null,
                .release = null,
                .copyDescription = null,
            };
            const timer = c.CFRunLoopTimerCreate(
                c.kCFAllocatorDefault,
                next_fire,
                interval,
                0,
                0,
                tickTimerCallback,
                &context,
            );
            if (timer == null) return;
            self.tick_timer = timer;
            c.CFRunLoopAddTimer(c.CFRunLoopGetMain(), timer, c.kCFRunLoopCommonModes);
            return;
        }

        c.CFRunLoopTimerSetNextFireDate(self.tick_timer, next_fire);
    }

    fn disarmTickTimerLocked(self: *RuntimeImpl) void {
        const timer = self.tick_timer orelse return;
        c.CFRunLoopTimerInvalidate(timer);
        c.CFRelease(timer);
        self.tick_timer = null;
    }

    fn markLayoutAnimationStarted(self: *RuntimeImpl, duration_seconds: f64) void {
        if (self.last_tick_sample_time == 0) {
            self.last_tick_sample_time = currentSampleTime();
        }
        self.layout_animation_active = true;
        self.layout_animation_deadline = self.last_tick_sample_time + @max(0.05, duration_seconds);
        self.updateTickTimerLocked();
    }

    fn applySingleTransferPlan(self: *RuntimeImpl, plan: abi.OmniControllerTransferPlan) i32 {
        const target_workspace_id = self.resolveWorkspaceId(
            plan.has_target_workspace_id,
            plan.target_workspace_id,
            plan.target_workspace_name,
            plan.create_target_workspace_if_missing != 0,
        ) orelse return abi.OMNI_ERR_OUT_OF_RANGE;

        if (plan.has_target_monitor_display_id != 0) {
            const move_rc = workspace_runtime.omni_workspace_runtime_move_workspace_to_monitor_impl(
                self.workspace_runtime_owner,
                target_workspace_id,
                plan.target_monitor_display_id,
            );
            if (move_rc != abi.OMNI_OK and move_rc != abi.OMNI_ERR_OUT_OF_RANGE) {
                return move_rc;
            }
        }

        const window_count = @min(@as(usize, plan.window_count), abi.OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS);
        for (0..window_count) |index| {
            const handle_id = plan.window_ids[index];
            const move_rc = workspace_runtime.omni_workspace_runtime_window_set_workspace_impl(
                self.workspace_runtime_owner,
                handle_id,
                target_workspace_id,
            );
            if (move_rc != abi.OMNI_OK) return move_rc;
        }

        if (plan.follow_focus != 0 and plan.has_target_monitor_display_id != 0) {
            const focus_rc = workspace_runtime.omni_workspace_runtime_set_active_workspace_impl(
                self.workspace_runtime_owner,
                target_workspace_id,
                plan.target_monitor_display_id,
            );
            if (focus_rc != abi.OMNI_OK) return focus_rc;
        }

        return abi.OMNI_OK;
    }

    fn resolveWorkspaceId(
        self: *RuntimeImpl,
        has_workspace_id: u8,
        workspace_id: abi.OmniUuid128,
        fallback_name: abi.OmniControllerName,
        create_if_missing: bool,
    ) ?abi.OmniUuid128 {
        if (has_workspace_id != 0) return workspace_id;

        const name = workspaceNameFromControllerName(fallback_name);
        if (name.length == 0) return null;

        var has_resolved: u8 = 0;
        var resolved = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
        const rc = workspace_runtime.omni_workspace_runtime_workspace_id_by_name_impl(
            self.workspace_runtime_owner,
            name,
            if (create_if_missing) 1 else 0,
            &has_resolved,
            &resolved,
        );
        if (rc != abi.OMNI_OK or has_resolved == 0) return null;
        return resolved;
    }

    fn activeWorkspaceIdForDisplay(
        self: *RuntimeImpl,
        display_id: u32,
    ) ?abi.OmniUuid128 {
        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const rc = workspace_runtime.omni_workspace_runtime_export_state_impl(
            self.workspace_runtime_owner,
            &state_export,
        );
        if (rc != abi.OMNI_OK) return null;
        if (state_export.monitor_count == 0 or state_export.monitors == null) return null;

        for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
            if (monitor.display_id != display_id) continue;
            if (monitor.has_active_workspace_id == 0) return null;
            return monitor.active_workspace_id;
        }
        return null;
    }
};

const RuntimeWindowSnapshot = struct {
    column_id: abi.OmniUuid128,
    order_index: usize,
    column_index: usize,
    row_index: usize,
};

fn zeroUuid() abi.OmniUuid128 {
    return .{ .bytes = [_]u8{0} ** 16 };
}

fn isDirectionValue(direction: u8) bool {
    return switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT,
        abi.OMNI_NIRI_DIRECTION_RIGHT,
        abi.OMNI_NIRI_DIRECTION_UP,
        abi.OMNI_NIRI_DIRECTION_DOWN,
        => true,
        else => false,
    };
}

fn isHorizontalDirection(direction: u8) bool {
    return direction == abi.OMNI_NIRI_DIRECTION_LEFT or direction == abi.OMNI_NIRI_DIRECTION_RIGHT;
}

fn mutationOpForDirection(direction: u8, swap: bool) ?u8 {
    return switch (direction) {
        abi.OMNI_NIRI_DIRECTION_LEFT, abi.OMNI_NIRI_DIRECTION_RIGHT => if (swap)
            abi.OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_HORIZONTAL
        else
            abi.OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_HORIZONTAL,
        abi.OMNI_NIRI_DIRECTION_UP, abi.OMNI_NIRI_DIRECTION_DOWN => if (swap)
            abi.OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_VERTICAL
        else
            abi.OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_VERTICAL,
        else => null,
    };
}

fn clampActiveTile(active_tile_idx: usize, window_count: usize) usize {
    return if (window_count == 0) 0 else @min(active_tile_idx, window_count - 1);
}

fn defaultRuntimeColumnState(column_id: abi.OmniUuid128) abi.OmniNiriRuntimeColumnState {
    return .{
        .column_id = column_id,
        .window_start = 0,
        .window_count = 0,
        .active_tile_idx = 0,
        .is_tabbed = 0,
        .size_value = 1.0,
        .width_kind = abi.OMNI_NIRI_SIZE_KIND_PROPORTION,
        .is_full_width = 0,
        .has_saved_width = 0,
        .saved_width_kind = abi.OMNI_NIRI_SIZE_KIND_PROPORTION,
        .saved_width_value = 1.0,
    };
}

fn defaultRuntimeWindowState(
    window_id: abi.OmniUuid128,
    column_id: abi.OmniUuid128,
    column_index: usize,
) abi.OmniNiriRuntimeWindowState {
    return .{
        .window_id = window_id,
        .column_id = column_id,
        .column_index = column_index,
        .size_value = 1.0,
        .height_kind = abi.OMNI_NIRI_HEIGHT_KIND_AUTO,
        .height_value = 1.0,
    };
}

fn normalizeRuntimeSeedState(
    columns: []abi.OmniNiriRuntimeColumnState,
    windows: []abi.OmniNiriRuntimeWindowState,
) void {
    var next_window_start: usize = 0;
    for (columns, 0..) |*column, column_index| {
        const window_count = @min(column.window_count, windows.len - @min(next_window_start, windows.len));
        column.window_start = next_window_start;
        column.window_count = window_count;
        column.active_tile_idx = clampActiveTile(column.active_tile_idx, window_count);
        var row_index: usize = 0;
        while (row_index < window_count) : (row_index += 1) {
            windows[next_window_start + row_index].column_id = column.column_id;
            windows[next_window_start + row_index].column_index = column_index;
        }
        next_window_start += window_count;
    }
}

fn runtimeColumnsEqual(lhs: abi.OmniNiriRuntimeColumnState, rhs: abi.OmniNiriRuntimeColumnState) bool {
    return std.mem.eql(u8, lhs.column_id.bytes[0..], rhs.column_id.bytes[0..]) and
        lhs.window_start == rhs.window_start and
        lhs.window_count == rhs.window_count and
        lhs.active_tile_idx == rhs.active_tile_idx and
        lhs.is_tabbed == rhs.is_tabbed and
        lhs.size_value == rhs.size_value and
        lhs.width_kind == rhs.width_kind and
        lhs.is_full_width == rhs.is_full_width and
        lhs.has_saved_width == rhs.has_saved_width and
        lhs.saved_width_kind == rhs.saved_width_kind and
        lhs.saved_width_value == rhs.saved_width_value;
}

fn runtimeWindowsEqual(lhs: abi.OmniNiriRuntimeWindowState, rhs: abi.OmniNiriRuntimeWindowState) bool {
    return std.mem.eql(u8, lhs.window_id.bytes[0..], rhs.window_id.bytes[0..]) and
        std.mem.eql(u8, lhs.column_id.bytes[0..], rhs.column_id.bytes[0..]) and
        lhs.column_index == rhs.column_index and
        lhs.size_value == rhs.size_value and
        lhs.height_kind == rhs.height_kind and
        lhs.height_value == rhs.height_value;
}

fn runtimeStateEqualsExport(
    runtime_export: abi.OmniNiriRuntimeStateExport,
    columns: []const abi.OmniNiriRuntimeColumnState,
    windows: []const abi.OmniNiriRuntimeWindowState,
) bool {
    if (runtime_export.column_count != columns.len or runtime_export.window_count != windows.len) return false;
    if (runtime_export.column_count > 0 and runtime_export.columns == null) return false;
    if (runtime_export.window_count > 0 and runtime_export.windows == null) return false;

    for (columns, 0..) |column, index| {
        if (!runtimeColumnsEqual(runtime_export.columns[index], column)) return false;
    }
    for (windows, 0..) |window, index| {
        if (!runtimeWindowsEqual(runtime_export.windows[index], window)) return false;
    }
    return true;
}

fn runtimeExportIsCoherent(runtime_export: abi.OmniNiriRuntimeStateExport) bool {
    if (runtime_export.column_count > abi.MAX_WINDOWS or runtime_export.window_count > abi.MAX_WINDOWS) {
        return false;
    }
    if (runtime_export.column_count > 0 and runtime_export.columns == null) return false;
    if (runtime_export.window_count > 0 and runtime_export.windows == null) return false;

    var covered = [_]bool{false} ** abi.MAX_WINDOWS;
    var covered_count: usize = 0;

    for (0..runtime_export.column_count) |column_index| {
        const column = runtime_export.columns[column_index];
        if (column.window_start > runtime_export.window_count) return false;
        if (column.window_count > runtime_export.window_count - column.window_start) return false;
        if (column.window_count > 0 and column.active_tile_idx >= column.window_count) return false;

        for (column.window_start..column.window_start + column.window_count) |window_index| {
            if (covered[window_index]) return false;
            covered[window_index] = true;
            covered_count += 1;

            const window = runtime_export.windows[window_index];
            if (window.column_index != column_index) return false;
            if (!std.mem.eql(u8, window.column_id.bytes[0..], column.column_id.bytes[0..])) return false;
        }
    }

    return covered_count == runtime_export.window_count;
}

fn workspaceRecordById(
    state_export: abi.OmniWorkspaceRuntimeStateExport,
    workspace_id: Uuid,
) ?abi.OmniWorkspaceRuntimeWorkspaceRecord {
    if (state_export.workspace_count == 0 or state_export.workspaces == null) return null;
    for (state_export.workspaces[0..state_export.workspace_count]) |workspace| {
        if (std.mem.eql(u8, workspace.workspace_id.bytes[0..], workspace_id[0..])) {
            return workspace;
        }
    }
    return null;
}

fn monitorForWorkspace(
    state_export: abi.OmniWorkspaceRuntimeStateExport,
    workspace_id: Uuid,
) ?abi.OmniWorkspaceRuntimeMonitorRecord {
    if (state_export.monitor_count == 0 or state_export.monitors == null) return null;
    for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
        if (monitor.has_active_workspace_id != 0 and
            std.mem.eql(u8, monitor.active_workspace_id.bytes[0..], workspace_id[0..]))
        {
            return monitor;
        }
    }
    const workspace = workspaceRecordById(state_export, workspace_id) orelse return null;
    if (workspace.has_assigned_display_id == 0) return null;
    for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
        if (monitor.display_id == workspace.assigned_display_id) return monitor;
    }
    return null;
}

fn managedWindowIndex(
    managed_windows: *const [abi.MAX_WINDOWS]abi.OmniWorkspaceRuntimeWindowRecord,
    managed_count: usize,
    window_id: Uuid,
) ?usize {
    for (0..managed_count) |index| {
        if (std.mem.eql(u8, managed_windows[index].handle_id.bytes[0..], window_id[0..])) {
            return index;
        }
    }
    return null;
}

fn managedWindowExists(
    state_export: abi.OmniWorkspaceRuntimeStateExport,
    handle_id: Uuid,
) bool {
    return managedWindowRecordByHandle(state_export, null, handle_id) != null;
}

fn managedWindowRecordByHandle(
    state_export: abi.OmniWorkspaceRuntimeStateExport,
    workspace_id: ?Uuid,
    handle_id: Uuid,
) ?abi.OmniWorkspaceRuntimeWindowRecord {
    if (state_export.window_count == 0 or state_export.windows == null) return null;
    for (state_export.windows[0..state_export.window_count]) |window| {
        if (!std.mem.eql(u8, window.handle_id.bytes[0..], handle_id[0..])) continue;
        if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) return null;
        if (workspace_id) |expected_workspace_id| {
            if (!std.mem.eql(u8, window.workspace_id.bytes[0..], expected_workspace_id[0..])) continue;
        }
        return window;
    }
    return null;
}

fn displayInfoForMonitor(
    display_infos: []const abi.OmniBorderDisplayInfo,
    display_id: u32,
) ?abi.OmniBorderDisplayInfo {
    for (display_infos) |info| {
        if (info.display_id == display_id) return info;
    }
    return null;
}

fn findRuntimeWindowIndex(
    runtime_export: abi.OmniNiriRuntimeStateExport,
    window_id: Uuid,
) ?usize {
    if (runtime_export.window_count == 0 or runtime_export.windows == null) return null;
    for (0..runtime_export.window_count) |index| {
        if (std.mem.eql(u8, runtime_export.windows[index].window_id.bytes[0..], window_id[0..])) {
            return index;
        }
    }
    return null;
}

fn findRuntimeColumnIndex(
    runtime_export: abi.OmniNiriRuntimeStateExport,
    column_id: Uuid,
) ?usize {
    if (runtime_export.column_count == 0 or runtime_export.columns == null) return null;
    for (0..runtime_export.column_count) |index| {
        if (std.mem.eql(u8, runtime_export.columns[index].column_id.bytes[0..], column_id[0..])) {
            return index;
        }
    }
    return null;
}

fn selectedColumnActionableWindow(
    runtime_export: abi.OmniNiriRuntimeStateExport,
    column_index: usize,
) ?abi.OmniUuid128 {
    if (runtime_export.column_count == 0 or runtime_export.columns == null) return null;
    if (runtime_export.window_count == 0 or runtime_export.windows == null) return null;
    if (column_index >= runtime_export.column_count) return null;
    const column = runtime_export.columns[column_index];
    if (column.window_count == 0) return null;
    const active_tile_idx = clampActiveTile(column.active_tile_idx, column.window_count);
    const window_index = column.window_start + active_tile_idx;
    if (window_index >= runtime_export.window_count) return null;
    return runtime_export.windows[window_index].window_id;
}

fn runtimeWindowSnapshot(
    runtime_export: abi.OmniNiriRuntimeStateExport,
    window_id: Uuid,
) ?RuntimeWindowSnapshot {
    const window_index = findRuntimeWindowIndex(runtime_export, window_id) orelse return null;
    if (runtime_export.windows == null) return null;
    const window = runtime_export.windows[window_index];
    if (window.column_index >= runtime_export.column_count or runtime_export.columns == null) return null;
    const column = runtime_export.columns[window.column_index];
    const row_index = if (window_index >= column.window_start and
        window_index < column.window_start + column.window_count)
        window_index - column.window_start
    else
        0;
    return .{
        .column_id = window.column_id,
        .order_index = window_index,
        .column_index = window.column_index,
        .row_index = row_index,
    };
}

fn buildWorkspaceSelectionStateForSeed(
    runtime_impl: *RuntimeImpl,
    workspace_id: Uuid,
    columns: []abi.OmniNiriRuntimeColumnState,
    windows: []abi.OmniNiriRuntimeWindowState,
) WorkspaceSelectionState {
    const runtime_export = abi.OmniNiriRuntimeStateExport{
        .columns = if (columns.len == 0) null else columns.ptr,
        .column_count = columns.len,
        .windows = if (windows.len == 0) null else windows.ptr,
        .window_count = windows.len,
    };
    var selection = runtime_impl.buildWorkspaceSelectionState(workspace_id, runtime_export, windows.len > 0);
    if (selection.actionable_window_id) |window_id| {
        if (findRuntimeWindowIndex(runtime_export, window_id)) |window_index| {
            const column_index = windows[window_index].column_index;
            if (column_index < columns.len) {
                const row_index = if (window_index >= columns[column_index].window_start)
                    window_index - columns[column_index].window_start
                else
                    0;
                columns[column_index].active_tile_idx = clampActiveTile(row_index, columns[column_index].window_count);
                selection.selected_column_id = columns[column_index].column_id.bytes;
            }
        }
    }
    return selection;
}

fn runtimeFromHandle(runtime: [*c]OmniWMController) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

fn runtimeFromUserdata(userdata: ?*anyopaque) ?*RuntimeImpl {
    const ptr = userdata orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn snapshotFromHandle(snapshot: [*c]OmniWMControllerSnapshot) ?*SnapshotImpl {
    if (snapshot == null) return null;
    return @ptrCast(@alignCast(snapshot));
}

fn constSnapshotFromHandle(snapshot: [*c]const OmniWMControllerSnapshot) ?*const SnapshotImpl {
    if (snapshot == null) return null;
    return @ptrCast(@alignCast(snapshot));
}

fn currentSampleTime() f64 {
    return c.CFAbsoluteTimeGetCurrent();
}

fn sampleTimeToMillis(sample_time: f64) u64 {
    if (sample_time <= 0) return 0;
    return @intFromFloat(sample_time * 1000.0);
}

fn normalizeOrientation(raw: u8) u8 {
    return switch (raw) {
        abi.OMNI_NIRI_ORIENTATION_HORIZONTAL,
        abi.OMNI_NIRI_ORIENTATION_VERTICAL,
        => raw,
        else => default_niri_orientation,
    };
}

fn normalizeCenterMode(raw: u8) u8 {
    return switch (raw) {
        abi.OMNI_CENTER_NEVER,
        abi.OMNI_CENTER_ALWAYS,
        abi.OMNI_CENTER_ON_OVERFLOW,
        => raw,
        else => abi.OMNI_CENTER_NEVER,
    };
}

fn sanitizeAspectComponent(raw: f64, fallback: f64) f64 {
    if (!std.math.isFinite(raw) or raw <= 0) return fallback;
    return raw;
}

fn sanitizeBorderColor(color: abi.OmniBorderColor) abi.OmniBorderColor {
    return .{
        .red = std.math.clamp(color.red, 0.0, 1.0),
        .green = std.math.clamp(color.green, 0.0, 1.0),
        .blue = std.math.clamp(color.blue, 0.0, 1.0),
        .alpha = std.math.clamp(color.alpha, 0.0, 1.0),
    };
}

fn releaseInputEventRefIfNeeded(event: abi.OmniInputEvent) void {
    if (event.event_ref) |ref| {
        c.CFRelease(@ptrCast(ref));
    }
}

fn tickTimerCallback(_: c.CFRunLoopTimerRef, info: ?*anyopaque) callconv(.c) void {
    const runtime = runtimeFromUserdata(info) orelse return;
    runtime.mutex.lock();
    defer runtime.mutex.unlock();

    if (!runtime.started) {
        runtime.disarmTickTimerLocked();
        return;
    }

    _ = runtime.tick(currentSampleTime());
}

fn optionalDisplayId(has_value: u8, display_id: u32) ?u32 {
    return if (has_value != 0) display_id else null;
}

fn pointInRect(x: f64, y: f64, rect: abi.OmniBorderRect) bool {
    if (!isRectFinite(rect)) return false;
    return x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height;
}

fn isRectFinite(rect: abi.OmniBorderRect) bool {
    return std.math.isFinite(rect.x) and
        std.math.isFinite(rect.y) and
        std.math.isFinite(rect.width) and
        std.math.isFinite(rect.height);
}

fn controllerNameFromWorkspaceName(name: abi.OmniWorkspaceRuntimeName) abi.OmniControllerName {
    var out = abi.OmniControllerName{
        .length = @intCast(@min(@as(usize, name.length), abi.OMNI_CONTROLLER_NAME_CAP)),
        .bytes = [_]u8{0} ** abi.OMNI_CONTROLLER_NAME_CAP,
    };
    std.mem.copyForwards(u8, out.bytes[0..out.length], name.bytes[0..out.length]);
    return out;
}

fn controllerNamesEqual(lhs: abi.OmniControllerName, rhs: abi.OmniControllerName) bool {
    return std.mem.eql(u8, types.nameSlice(lhs), types.nameSlice(rhs));
}

fn workspaceNameFromControllerName(name: abi.OmniControllerName) abi.OmniWorkspaceRuntimeName {
    var out = abi.OmniWorkspaceRuntimeName{
        .length = @intCast(@min(@as(usize, name.length), abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP)),
        .bytes = [_]u8{0} ** abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP,
    };
    std.mem.copyForwards(u8, out.bytes[0..out.length], name.bytes[0..out.length]);
    return out;
}

fn captureSnapshotBridge(userdata: ?*anyopaque, out_snapshot: ?*abi.OmniControllerSnapshot) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_snapshot orelse return abi.OMNI_ERR_INVALID_ARGS;
    return runtime.captureSnapshot(resolved_out);
}

fn applyEffectsBridge(userdata: ?*anyopaque, effect_export: ?*const abi.OmniControllerEffectExport) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_export = effect_export orelse return abi.OMNI_ERR_INVALID_ARGS;
    return runtime.applyEffects(resolved_export);
}

fn reportErrorBridge(userdata: ?*anyopaque, code: i32, message: abi.OmniControllerName) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.reportError(code, message);
    return abi.OMNI_OK;
}

fn focusedWindowChangedBridge(userdata: ?*anyopaque, pid: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.mutex.lock();
    defer runtime.mutex.unlock();
    return runtime.handleFocusedWindowChanged(pid);
}

pub fn omni_wm_controller_create_impl(
    config: ?*const abi.OmniWMControllerConfig,
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    host_vtable: ?*const abi.OmniWMControllerHostVTable,
) [*c]OmniWMController {
    if (workspace_runtime_owner == null) return null;

    var resolved_config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_WM_CONTROLLER_ABI_VERSION) return null;

    const resolved_host = if (host_vtable) |raw|
        raw.*
    else
        abi.OmniWMControllerHostVTable{
            .userdata = null,
            .apply_effects = null,
            .report_error = null,
        };

    const impl = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    impl.* = RuntimeImpl.init(std.heap.c_allocator, workspace_runtime_owner, resolved_host);
    if (!impl.createController()) {
        impl.deinit();
        std.heap.c_allocator.destroy(impl);
        return null;
    }

    return @ptrCast(impl);
}

pub fn omni_wm_controller_destroy_impl(runtime: [*c]OmniWMController) void {
    const impl = runtimeFromHandle(runtime) orelse return;
    impl.deinit();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_wm_controller_start_impl(runtime: [*c]OmniWMController) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.start();
}

pub fn omni_wm_controller_stop_impl(runtime: [*c]OmniWMController) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.stop();
}

pub fn omni_wm_controller_submit_hotkey_impl(
    runtime: [*c]OmniWMController,
    command: ?*const abi.OmniControllerCommand,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_command = command orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.submitHotkey(resolved_command);
}

pub fn omni_wm_controller_submit_os_event_impl(
    runtime: [*c]OmniWMController,
    event: ?*const abi.OmniControllerEvent,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_event = event orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.submitEvent(resolved_event);
}

pub fn omni_wm_controller_apply_settings_impl(
    runtime: [*c]OmniWMController,
    delta: ?*const abi.OmniControllerSettingsDelta,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_delta = delta orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.applySettings(resolved_delta);
}

pub fn omni_wm_controller_set_ax_runtime_impl(
    runtime: [*c]OmniWMController,
    ax_runtime: [*c]ax_manager.OmniAXRuntime,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.setAXRuntime(ax_runtime);
}

pub fn omni_wm_controller_handle_focused_window_changed_impl(
    runtime: [*c]OmniWMController,
    pid: i32,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.handleFocusedWindowChanged(pid);
}

pub fn omni_wm_controller_submit_input_effect_batch_impl(
    runtime: [*c]OmniWMController,
    effects: ?*const abi.OmniInputEffectExport,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_effects = effects orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.submitInputEffectBatch(resolved_effects);
}

pub fn omni_wm_controller_tick_impl(
    runtime: [*c]OmniWMController,
    sample_time: f64,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.tick(sample_time);
}

pub fn omni_wm_controller_flush_impl(runtime: [*c]OmniWMController) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.flush();
}

pub fn omni_wm_controller_seed_lock_state_impl(
    runtime: [*c]OmniWMController,
    locked: u8,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    impl.seedLockStateForStart(locked != 0);
    return abi.OMNI_OK;
}

pub fn omni_wm_controller_query_ui_state_impl(
    runtime: [*c]const OmniWMController,
    out_state: ?*abi.OmniControllerUiState,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_state orelse return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *RuntimeImpl = @constCast(@ptrCast(@alignCast(runtime)));
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.queryUiState(resolved_out);
}

pub fn omni_wm_controller_snapshot_create_impl(
    runtime: [*c]OmniWMController,
) [*c]OmniWMControllerSnapshot {
    const impl = runtimeFromHandle(runtime) orelse return null;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    const snapshot = impl.createFrozenSnapshot() orelse return null;
    return @ptrCast(snapshot);
}

pub fn omni_wm_controller_snapshot_destroy_impl(snapshot: [*c]OmniWMControllerSnapshot) void {
    const impl = snapshotFromHandle(snapshot) orelse return;
    impl.deinit();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_wm_controller_snapshot_query_counts_impl(
    snapshot: [*c]const OmniWMControllerSnapshot,
    out_counts: ?*abi.OmniWMControllerSnapshotCounts,
) i32 {
    const impl = constSnapshotFromHandle(snapshot) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_counts orelse return abi.OMNI_ERR_INVALID_ARGS;
    resolved_out.* = impl.counts;
    return abi.OMNI_OK;
}

pub fn omni_wm_controller_snapshot_query_ui_state_impl(
    snapshot: [*c]const OmniWMControllerSnapshot,
    out_state: ?*abi.OmniControllerUiState,
) i32 {
    const impl = constSnapshotFromHandle(snapshot) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_state orelse return abi.OMNI_ERR_INVALID_ARGS;
    resolved_out.* = impl.ui_state;
    return abi.OMNI_OK;
}

pub fn omni_wm_controller_snapshot_copy_controller_state_impl(
    snapshot: [*c]const OmniWMControllerSnapshot,
    out_snapshot: ?*abi.OmniControllerSnapshot,
    out_monitors: [*c]abi.OmniControllerMonitorSnapshot,
    monitor_capacity: usize,
    out_workspaces: [*c]abi.OmniControllerWorkspaceSnapshot,
    workspace_capacity: usize,
    out_windows: [*c]abi.OmniControllerWindowSnapshot,
    window_capacity: usize,
) i32 {
    const impl = constSnapshotFromHandle(snapshot) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_snapshot orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (monitor_capacity > 0 and out_monitors == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (workspace_capacity > 0 and out_workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_capacity > 0 and out_windows == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (impl.controller_monitor_snapshots.len > monitor_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (impl.controller_workspace_snapshots.len > workspace_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (impl.controller_window_snapshots.len > window_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;

    if (impl.controller_monitor_snapshots.len > 0) {
        std.mem.copyForwards(
            abi.OmniControllerMonitorSnapshot,
            out_monitors[0..impl.controller_monitor_snapshots.len],
            impl.controller_monitor_snapshots,
        );
    }
    if (impl.controller_workspace_snapshots.len > 0) {
        std.mem.copyForwards(
            abi.OmniControllerWorkspaceSnapshot,
            out_workspaces[0..impl.controller_workspace_snapshots.len],
            impl.controller_workspace_snapshots,
        );
    }
    if (impl.controller_window_snapshots.len > 0) {
        std.mem.copyForwards(
            abi.OmniControllerWindowSnapshot,
            out_windows[0..impl.controller_window_snapshots.len],
            impl.controller_window_snapshots,
        );
    }

    resolved_out.* = impl.controller_snapshot;
    resolved_out.monitors = if (impl.controller_monitor_snapshots.len == 0) null else out_monitors;
    resolved_out.workspaces = if (impl.controller_workspace_snapshots.len == 0) null else out_workspaces;
    resolved_out.windows = if (impl.controller_window_snapshots.len == 0) null else out_windows;
    return abi.OMNI_OK;
}

pub fn omni_wm_controller_snapshot_copy_workspace_state_impl(
    snapshot: [*c]const OmniWMControllerSnapshot,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
    out_monitors: [*c]abi.OmniWorkspaceRuntimeMonitorRecord,
    monitor_capacity: usize,
    out_workspaces: [*c]abi.OmniWorkspaceRuntimeWorkspaceRecord,
    workspace_capacity: usize,
    out_windows: [*c]abi.OmniWorkspaceRuntimeWindowRecord,
    window_capacity: usize,
) i32 {
    const impl = constSnapshotFromHandle(snapshot) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_export orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (monitor_capacity > 0 and out_monitors == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (workspace_capacity > 0 and out_workspaces == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_capacity > 0 and out_windows == null) return abi.OMNI_ERR_INVALID_ARGS;

    resolved_out.* = .{
        .monitors = null,
        .monitor_count = impl.workspace_export.monitor_count,
        .workspaces = null,
        .workspace_count = impl.workspace_export.workspace_count,
        .windows = null,
        .window_count = impl.workspace_export.window_count,
        .has_active_monitor_display_id = impl.workspace_export.has_active_monitor_display_id,
        .active_monitor_display_id = impl.workspace_export.active_monitor_display_id,
        .has_previous_monitor_display_id = impl.workspace_export.has_previous_monitor_display_id,
        .previous_monitor_display_id = impl.workspace_export.previous_monitor_display_id,
    };

    if (impl.monitor_records.len > monitor_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (impl.workspace_records.len > workspace_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (impl.window_records.len > window_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;

    if (impl.monitor_records.len > 0) {
        std.mem.copyForwards(
            abi.OmniWorkspaceRuntimeMonitorRecord,
            out_monitors[0..impl.monitor_records.len],
            impl.monitor_records,
        );
        resolved_out.monitors = out_monitors;
    }
    if (impl.workspace_records.len > 0) {
        std.mem.copyForwards(
            abi.OmniWorkspaceRuntimeWorkspaceRecord,
            out_workspaces[0..impl.workspace_records.len],
            impl.workspace_records,
        );
        resolved_out.workspaces = out_workspaces;
    }
    if (impl.window_records.len > 0) {
        std.mem.copyForwards(
            abi.OmniWorkspaceRuntimeWindowRecord,
            out_windows[0..impl.window_records.len],
            impl.window_records,
        );
        resolved_out.windows = out_windows;
    }
    return abi.OMNI_OK;
}

pub fn omni_wm_controller_snapshot_copy_changed_workspaces_impl(
    snapshot: [*c]const OmniWMControllerSnapshot,
    out_workspace_ids: [*c]abi.OmniUuid128,
    workspace_capacity: usize,
    out_workspace_count: ?*usize,
) i32 {
    const impl = constSnapshotFromHandle(snapshot) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_count = out_workspace_count orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (workspace_capacity > 0 and out_workspace_ids == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (impl.changed_workspace_ids.len > workspace_capacity) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (impl.changed_workspace_ids.len > 0) {
        std.mem.copyForwards(
            abi.OmniUuid128,
            out_workspace_ids[0..impl.changed_workspace_ids.len],
            impl.changed_workspace_ids,
        );
    }
    resolved_count.* = impl.changed_workspace_ids.len;
    return abi.OMNI_OK;
}

pub fn omni_wm_controller_export_workspace_state_impl(
    runtime: [*c]OmniWMController,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_export orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.exportWorkspaceState(resolved_out);
}

pub fn omni_wm_controller_query_workspace_projection_counts_impl(
    runtime: [*c]const OmniWMController,
    out_counts: ?*abi.OmniControllerWorkspaceProjectionCounts,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_counts orelse return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *RuntimeImpl = @constCast(@ptrCast(@alignCast(runtime)));
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.queryWorkspaceProjectionCounts(resolved_out);
}

pub fn omni_wm_controller_copy_workspace_projections_impl(
    runtime: [*c]OmniWMController,
    out_records: [*c]abi.OmniControllerWorkspaceProjectionRecord,
    record_capacity: usize,
    out_record_count: ?*usize,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_count = out_record_count orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_records: [*]abi.OmniControllerWorkspaceProjectionRecord = if (record_capacity == 0)
        @ptrFromInt(@alignOf(abi.OmniControllerWorkspaceProjectionRecord))
    else
        out_records orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.copyWorkspaceProjections(resolved_records, record_capacity, resolved_count);
}

pub fn omni_wm_controller_query_workspace_layout_settings_count_impl(
    runtime: [*c]const OmniWMController,
    out_setting_count: ?*usize,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_setting_count orelse return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *RuntimeImpl = @constCast(@ptrCast(@alignCast(runtime)));
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.queryWorkspaceLayoutSettingsCount(resolved_out);
}

pub fn omni_wm_controller_copy_workspace_layout_settings_impl(
    runtime: [*c]OmniWMController,
    out_settings: [*c]abi.OmniControllerWorkspaceLayoutSetting,
    setting_capacity: usize,
    out_setting_count: ?*usize,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_count = out_setting_count orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_settings: [*]abi.OmniControllerWorkspaceLayoutSetting = if (setting_capacity == 0)
        @ptrFromInt(@alignOf(abi.OmniControllerWorkspaceLayoutSetting))
    else
        out_settings orelse return abi.OMNI_ERR_INVALID_ARGS;
    impl.mutex.lock();
    defer impl.mutex.unlock();
    return impl.copyWorkspaceLayoutSettings(resolved_settings, setting_capacity, resolved_count);
}

fn createStartedWorkspaceRuntimeForTest() ![*c]workspace_runtime.OmniWorkspaceRuntime {
    var workspace_config = abi.OmniWorkspaceRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    const runtime_owner = workspace_runtime.omni_workspace_runtime_create_impl(&workspace_config);
    try std.testing.expect(runtime_owner != null);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_start_impl(runtime_owner),
    );
    return runtime_owner;
}

fn createControllerImplForTest(
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
) !*RuntimeImpl {
    var wm_config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_wm_controller_create_impl(&wm_config, workspace_runtime_owner, null);
    try std.testing.expect(runtime != null);
    return @ptrCast(@alignCast(runtime));
}

fn seedWorkspaceForTest(
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    display_id: u32,
) !abi.OmniUuid128 {
    var monitor = abi.OmniWorkspaceRuntimeMonitorSnapshot{
        .display_id = display_id,
        .is_main = 1,
        .frame_x = 0,
        .frame_y = 0,
        .frame_width = 1440,
        .frame_height = 900,
        .visible_x = 0,
        .visible_y = 0,
        .visible_width = 1440,
        .visible_height = 900,
        .name = workspaceNameFromControllerName(types.encodeName("Main")),
    };
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_import_monitors_impl(workspace_runtime_owner, &monitor, 1),
    );

    const workspace_name = workspaceNameFromControllerName(types.encodeName("1"));
    var has_workspace_id: u8 = 0;
    var workspace_id = zeroUuid();
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_workspace_id_by_name_impl(
            workspace_runtime_owner,
            workspace_name,
            1,
            &has_workspace_id,
            &workspace_id,
        ),
    );
    try std.testing.expectEqual(@as(u8, 1), has_workspace_id);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_set_active_workspace_impl(
            workspace_runtime_owner,
            workspace_id,
            display_id,
        ),
    );
    return workspace_id;
}

fn upsertManagedWindowForTest(
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
    pid: i32,
    window_id: i64,
    existing_handle: ?abi.OmniUuid128,
) !abi.OmniUuid128 {
    var request = abi.OmniWorkspaceRuntimeWindowUpsert{
        .pid = pid,
        .window_id = window_id,
        .workspace_id = workspace_id,
        .has_handle_id = if (existing_handle == null) 0 else 1,
        .handle_id = existing_handle orelse zeroUuid(),
    };
    var handle_id = zeroUuid();
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_upsert_impl(
            workspace_runtime_owner,
            &request,
            &handle_id,
        ),
    );
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_set_layout_reason_impl(
            workspace_runtime_owner,
            handle_id,
            abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD,
        ),
    );
    return handle_id;
}

fn exportWorkspaceStateForTest(
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
) !abi.OmniWorkspaceRuntimeStateExport {
    var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_export_state_impl(
            workspace_runtime_owner,
            &state_export,
        ),
    );
    return state_export;
}

fn findWindowSnapshotByHandle(
    snapshot: abi.OmniControllerSnapshot,
    handle_id: abi.OmniUuid128,
) ?abi.OmniControllerWindowSnapshot {
    if (snapshot.window_count == 0 or snapshot.windows == null) return null;
    for (snapshot.windows[0..snapshot.window_count]) |window| {
        if (std.mem.eql(u8, window.handle_id.bytes[0..], handle_id.bytes[0..])) {
            return window;
        }
    }
    return null;
}

fn focusDirectionAction(direction: u8) abi.OmniControllerLayoutAction {
    return .{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION,
        .direction = direction,
        .index = 0,
        .flag = 0,
    };
}

fn renderRuntimeFromExport(
    runtime_owner: [*c]niri_runtime.OmniNiriRuntime,
    runtime_export: abi.OmniNiriRuntimeStateExport,
) i32 {
    var rendered_windows = [_]abi.OmniNiriWindowOutput{undefined} ** abi.MAX_WINDOWS;
    var rendered_columns = [_]abi.OmniNiriColumnOutput{undefined} ** abi.MAX_WINDOWS;
    var request = abi.OmniNiriRuntimeRenderFromStateRequest{
        .expected_column_count = runtime_export.column_count,
        .expected_window_count = runtime_export.window_count,
        .working_x = 0.0,
        .working_y = 0.0,
        .working_width = 1440.0,
        .working_height = 900.0,
        .view_x = 0.0,
        .view_y = 0.0,
        .view_width = 1440.0,
        .view_height = 900.0,
        .fullscreen_x = 0.0,
        .fullscreen_y = 0.0,
        .fullscreen_width = 1440.0,
        .fullscreen_height = 900.0,
        .primary_gap = default_layout_gap,
        .secondary_gap = default_layout_gap,
        .viewport_span = 1440.0,
        .workspace_offset = 0.0,
        .has_fullscreen_window_id = 0,
        .fullscreen_window_id = zeroUuid(),
        .scale = 2.0,
        .orientation = default_niri_orientation,
        .sample_time = 0.0,
    };
    var output = abi.OmniNiriRuntimeRenderOutput{
        .windows = if (runtime_export.window_count == 0) null else &rendered_windows[0],
        .window_count = runtime_export.window_count,
        .columns = if (runtime_export.column_count == 0) null else &rendered_columns[0],
        .column_count = runtime_export.column_count,
        .animation_active = 0,
    };
    return niri_runtime.omni_niri_runtime_render_from_state_impl(runtime_owner, null, &request, &output);
}

fn queryWorkspaceProjectionRecordsViaApiForTest(
    runtime: [*c]OmniWMController,
    allocator: std.mem.Allocator,
) ![]abi.OmniControllerWorkspaceProjectionRecord {
    var counts = std.mem.zeroes(abi.OmniControllerWorkspaceProjectionCounts);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_query_workspace_projection_counts_impl(runtime, &counts),
    );

    const records = try allocator.alloc(abi.OmniControllerWorkspaceProjectionRecord, counts.workspace_count);
    errdefer allocator.free(records);

    var written: usize = 0;
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_copy_workspace_projections_impl(
            runtime,
            if (records.len == 0) null else records.ptr,
            records.len,
            &written,
        ),
    );
    try std.testing.expectEqual(counts.workspace_count, written);
    return records[0..written];
}

fn queryWorkspaceLayoutSettingsViaApiForTest(
    runtime: [*c]OmniWMController,
    allocator: std.mem.Allocator,
) ![]abi.OmniControllerWorkspaceLayoutSetting {
    var count: usize = 0;
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_query_workspace_layout_settings_count_impl(runtime, &count),
    );

    const settings = try allocator.alloc(abi.OmniControllerWorkspaceLayoutSetting, count);
    errdefer allocator.free(settings);

    var written: usize = 0;
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_copy_workspace_layout_settings_impl(
            runtime,
            if (settings.len == 0) null else settings.ptr,
            settings.len,
            &written,
        ),
    );
    try std.testing.expectEqual(count, written);
    return settings[0..written];
}

fn querySnapshotCountsForTest(
    snapshot: [*c]OmniWMControllerSnapshot,
) !abi.OmniWMControllerSnapshotCounts {
    var counts = std.mem.zeroes(abi.OmniWMControllerSnapshotCounts);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_snapshot_query_counts_impl(snapshot, &counts),
    );
    return counts;
}

fn queryChangedWorkspaceIdsViaSnapshotForTest(
    snapshot: [*c]OmniWMControllerSnapshot,
    allocator: std.mem.Allocator,
) ![]abi.OmniUuid128 {
    const counts = try querySnapshotCountsForTest(snapshot);
    const ids = try allocator.alloc(abi.OmniUuid128, counts.changed_workspace_count);
    errdefer allocator.free(ids);

    var written: usize = 0;
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_snapshot_copy_changed_workspaces_impl(
            snapshot,
            if (ids.len == 0) null else ids.ptr,
            ids.len,
            &written,
        ),
    );
    try std.testing.expectEqual(counts.changed_workspace_count, written);
    return ids[0..written];
}

test "wm controller validates create args" {
    var config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_wm_controller_create_impl(&config, null, null);
    try std.testing.expect(runtime == null);
}

test "wm controller workspace projection generation export is stable when state is unchanged" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    _ = try seedWorkspaceForTest(workspace_runtime_owner, 21);
    var config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_wm_controller_create_impl(
        &config,
        workspace_runtime_owner,
        null,
    );
    defer omni_wm_controller_destroy_impl(runtime);
    try std.testing.expect(runtime != null);

    const first = try queryWorkspaceProjectionRecordsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(first);
    const second = try queryWorkspaceProjectionRecordsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqual(@as(usize, 1), first.len);
    try std.testing.expectEqual(first.len, second.len);
    try std.testing.expectEqual(first[0].workspace_id, second[0].workspace_id);
    try std.testing.expectEqual(first[0].layout_generation, second[0].layout_generation);
}

test "wm controller rejects mismatched settings delta size" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const runtime = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(runtime));

    var delta = std.mem.zeroes(abi.OmniControllerSettingsDelta);
    delta.struct_size = @sizeOf(abi.OmniControllerSettingsDelta) - 1;
    delta.has_layout_gap = 1;
    delta.layout_gap = 12.0;

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_ERR_INVALID_ARGS),
        omni_wm_controller_apply_settings_impl(@ptrCast(runtime), &delta),
    );
}

test "wm controller flush preserves tick-owned time state" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    _ = try seedWorkspaceForTest(workspace_runtime_owner, 26);
    const runtime = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(runtime));

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_start_impl(@ptrCast(runtime)),
    );

    runtime.last_tick_sample_time = 42.0;
    runtime.layout_animation_deadline = 99.0;
    runtime.layout_animation_active = true;

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_flush_impl(@ptrCast(runtime)),
    );
    try std.testing.expectEqual(@as(f64, 42.0), runtime.last_tick_sample_time);
    try std.testing.expectEqual(@as(?f64, 99.0), runtime.layout_animation_deadline);
    try std.testing.expect(runtime.layout_animation_active);
}

test "wm controller snapshot export is consistent and drains changed workspaces" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 27);
    _ = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 901, 1001, null);
    const second_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 902, 1002, null);

    const runtime = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(runtime));

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_start_impl(@ptrCast(runtime)),
    );
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_flush_impl(@ptrCast(runtime)),
    );

    const initial_snapshot = omni_wm_controller_snapshot_create_impl(@ptrCast(runtime));
    defer omni_wm_controller_snapshot_destroy_impl(initial_snapshot);
    try std.testing.expect(initial_snapshot != null);

    const initial_counts = try querySnapshotCountsForTest(initial_snapshot);
    try std.testing.expect(initial_counts.monitor_count >= 1);
    try std.testing.expect(initial_counts.workspace_count >= 1);
    try std.testing.expect(initial_counts.window_count >= 2);
    try std.testing.expectEqual(@as(u8, 1), initial_counts.invalidate_all_workspace_projections);

    var ui_state = std.mem.zeroes(abi.OmniControllerUiState);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_snapshot_query_ui_state_impl(initial_snapshot, &ui_state),
    );

    var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    const monitor_records = try std.testing.allocator.alloc(
        abi.OmniWorkspaceRuntimeMonitorRecord,
        initial_counts.monitor_count,
    );
    defer std.testing.allocator.free(monitor_records);
    const workspace_records = try std.testing.allocator.alloc(
        abi.OmniWorkspaceRuntimeWorkspaceRecord,
        initial_counts.workspace_count,
    );
    defer std.testing.allocator.free(workspace_records);
    const window_records = try std.testing.allocator.alloc(
        abi.OmniWorkspaceRuntimeWindowRecord,
        initial_counts.window_count,
    );
    defer std.testing.allocator.free(window_records);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_snapshot_copy_workspace_state_impl(
            initial_snapshot,
            &state_export,
            if (monitor_records.len == 0) null else monitor_records.ptr,
            monitor_records.len,
            if (workspace_records.len == 0) null else workspace_records.ptr,
            workspace_records.len,
            if (window_records.len == 0) null else window_records.ptr,
            window_records.len,
        ),
    );
    try std.testing.expectEqual(initial_counts.monitor_count, state_export.monitor_count);
    try std.testing.expectEqual(initial_counts.workspace_count, state_export.workspace_count);
    try std.testing.expectEqual(initial_counts.window_count, state_export.window_count);

    const drained_snapshot = omni_wm_controller_snapshot_create_impl(@ptrCast(runtime));
    defer omni_wm_controller_snapshot_destroy_impl(drained_snapshot);
    try std.testing.expect(drained_snapshot != null);
    const drained_counts = try querySnapshotCountsForTest(drained_snapshot);
    try std.testing.expectEqual(@as(u8, 0), drained_counts.invalidate_all_workspace_projections);
    try std.testing.expectEqual(@as(usize, 0), drained_counts.changed_workspace_count);

    runtime.setSelectedNode(workspace_id.bytes, second_handle.bytes);

    const changed_snapshot = omni_wm_controller_snapshot_create_impl(@ptrCast(runtime));
    defer omni_wm_controller_snapshot_destroy_impl(changed_snapshot);
    try std.testing.expect(changed_snapshot != null);
    const changed_counts = try querySnapshotCountsForTest(changed_snapshot);
    try std.testing.expectEqual(@as(u8, 0), changed_counts.invalidate_all_workspace_projections);
    try std.testing.expectEqual(@as(usize, 1), changed_counts.changed_workspace_count);

    const changed_ids = try queryChangedWorkspaceIdsViaSnapshotForTest(changed_snapshot, std.testing.allocator);
    defer std.testing.allocator.free(changed_ids);
    try std.testing.expectEqual(@as(usize, 1), changed_ids.len);
    try std.testing.expectEqual(workspace_id, changed_ids[0]);

    const redrained_snapshot = omni_wm_controller_snapshot_create_impl(@ptrCast(runtime));
    defer omni_wm_controller_snapshot_destroy_impl(redrained_snapshot);
    try std.testing.expect(redrained_snapshot != null);
    const redrained_counts = try querySnapshotCountsForTest(redrained_snapshot);
    try std.testing.expectEqual(@as(usize, 0), redrained_counts.changed_workspace_count);
}

test "wm controller owned workspace copies survive runtime mutation during snapshot capture" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 28);
    const first_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 1001, 2001, null);
    const second_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 1002, 2002, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    var owned_state = OwnedWorkspaceState.init(std.testing.allocator);
    defer owned_state.deinit();
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.copyWorkspaceState(&owned_state));

    var active_keys = [_]abi.OmniWorkspaceRuntimeWindowKey{.{
        .pid = 1001,
        .window_id = 2001,
    }};
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_remove_missing_impl(
            workspace_runtime_owner,
            &active_keys[0],
            active_keys.len,
            1,
        ),
    );

    var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.captureSnapshotFromWorkspaceState(owned_state.state_export, &snapshot),
    );
    try std.testing.expect(findWindowSnapshotByHandle(snapshot, first_handle) != null);
    try std.testing.expect(findWindowSnapshotByHandle(snapshot, second_handle) != null);
}

test "wm controller window inventory plan preserves existing handles before runtime mutation" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 29);
    const existing_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 1101, 2101, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    var owned_state = OwnedWorkspaceState.init(std.testing.allocator);
    defer owned_state.deinit();
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.copyWorkspaceState(&owned_state));

    try impl.visible_windows.append(impl.allocator, .{
        .id = 2101,
        .pid = 1101,
        .level = 0,
        .frame = .{
            .x = 40.0,
            .y = 40.0,
            .width = 500.0,
            .height = 400.0,
        },
        .tags = 0,
        .attributes = 0,
        .parent_id = 0,
    });
    try impl.visible_windows.append(impl.allocator, .{
        .id = 2102,
        .pid = 1102,
        .level = 0,
        .frame = .{
            .x = 620.0,
            .y = 40.0,
            .width = 500.0,
            .height = 400.0,
        },
        .tags = 0,
        .attributes = 0,
        .parent_id = 0,
    });

    impl.active_window_keys.clearRetainingCapacity();
    var current_ax_pids = std.AutoHashMap(i32, void).init(std.testing.allocator);
    defer current_ax_pids.deinit();
    var operations = std.ArrayListUnmanaged(WindowInventoryOperation){};
    defer operations.deinit(impl.allocator);

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.buildWindowInventoryPlan(owned_state.state_export, &current_ax_pids, &operations),
    );
    try std.testing.expectEqual(@as(usize, 2), operations.items.len);
    try std.testing.expectEqual(@as(u8, 1), operations.items[0].request.has_handle_id);
    try std.testing.expectEqual(existing_handle, operations.items[0].request.handle_id);
    try std.testing.expectEqual(@as(u8, 0), operations.items[1].request.has_handle_id);

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.applyWindowInventoryPlan(operations.items));

    var refreshed_state = OwnedWorkspaceState.init(std.testing.allocator);
    defer refreshed_state.deinit();
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.copyWorkspaceState(&refreshed_state));
    try std.testing.expectEqual(@as(usize, 2), refreshed_state.state_export.window_count);
    try std.testing.expectEqual(existing_handle, impl.findExistingHandle(refreshed_state.state_export, 1101, 2101).?);
    try std.testing.expect(impl.findExistingHandle(refreshed_state.state_export, 1102, 2102) != null);
}

test "wm controller workspace projection generation increments on selection-only changes" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 22);
    _ = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 701, 801, null);
    const second_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 702, 802, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));

    const before = impl.projectionGenerationForWorkspace(workspace_id.bytes);
    impl.setSelectedNode(workspace_id.bytes, second_handle.bytes);
    const after = impl.projectionGenerationForWorkspace(workspace_id.bytes);

    try std.testing.expect(after != before);

    impl.setSelectedNode(workspace_id.bytes, second_handle.bytes);
    try std.testing.expectEqual(after, impl.projectionGenerationForWorkspace(workspace_id.bytes));
}

test "wm controller workspace projection generation increments on fullscreen and runtime mutation" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 23);
    const first_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 801, 901, null);
    const second_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 802, 902, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));

    const before_fullscreen = impl.projectionGenerationForWorkspace(workspace_id.bytes);
    impl.setManagedFullscreenWindow(workspace_id.bytes, first_handle.bytes);
    const after_fullscreen = impl.projectionGenerationForWorkspace(workspace_id.bytes);
    try std.testing.expect(after_fullscreen != before_fullscreen);

    impl.focused_window = first_handle.bytes;
    impl.setSelectedNode(workspace_id.bytes, first_handle.bytes);
    impl.setLastFocusedWindow(workspace_id.bytes, first_handle.bytes);

    const before_mutation = impl.projectionGenerationForWorkspace(workspace_id.bytes);
    const secondary_workspace_name = workspaceNameFromControllerName(types.encodeName("2"));
    var has_secondary_workspace_id: u8 = 0;
    var secondary_workspace_id = zeroUuid();
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_workspace_id_by_name_impl(
            workspace_runtime_owner,
            secondary_workspace_name,
            1,
            &has_secondary_workspace_id,
            &secondary_workspace_id,
        ),
    );
    try std.testing.expectEqual(@as(u8, 1), has_secondary_workspace_id);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_set_workspace_impl(
            workspace_runtime_owner,
            second_handle,
            secondary_workspace_id,
        ),
    );
    const moved_state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(moved_state_export));
    const after_mutation = impl.projectionGenerationForWorkspace(workspace_id.bytes);
    try std.testing.expect(after_mutation != before_mutation);
}

test "wm controller prunes projection generation entries for removed workspaces" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    _ = try seedWorkspaceForTest(workspace_runtime_owner, 24);
    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const orphan_workspace_id = abi.OmniUuid128{ .bytes = [_]u8{9} ** 16 };
    try impl.projection_generation_by_workspace.put(orphan_workspace_id.bytes, 41);
    try std.testing.expectEqual(@as(u64, 41), impl.projectionGenerationForWorkspace(orphan_workspace_id.bytes));

    var counts = std.mem.zeroes(abi.OmniControllerWorkspaceProjectionCounts);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.queryWorkspaceProjectionCounts(&counts));
    try std.testing.expectEqual(@as(usize, 1), counts.workspace_count);
    try std.testing.expect(impl.projection_generation_by_workspace.get(orphan_workspace_id.bytes) == null);
}

test "wm controller workspace projection count and copy api return stable copied data" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 25);
    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const runtime: [*c]OmniWMController = @ptrCast(impl);
    const records = try queryWorkspaceProjectionRecordsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(records);

    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(workspace_id, records[0].workspace_id);

    const repeated = try queryWorkspaceProjectionRecordsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(repeated);

    try std.testing.expectEqual(records.len, repeated.len);
    try std.testing.expectEqual(records[0].workspace_id, repeated[0].workspace_id);
    try std.testing.expectEqual(records[0].layout_generation, repeated[0].layout_generation);
}

test "wm controller focus navigation is no-op when workspace has no windows" {
    var workspace_config = abi.OmniWorkspaceRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    const workspace_runtime_owner = workspace_runtime.omni_workspace_runtime_create_impl(&workspace_config);
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);
    try std.testing.expect(workspace_runtime_owner != null);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_start_impl(workspace_runtime_owner),
    );

    var wm_config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_wm_controller_create_impl(&wm_config, workspace_runtime_owner, null);
    defer omni_wm_controller_destroy_impl(runtime);
    try std.testing.expect(runtime != null);
    const impl: *RuntimeImpl = @ptrCast(@alignCast(runtime));
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.focusByDirection(.forward));
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.focusByIndex(0),
    );
}

test "wm controller navigation layout actions are no-op for empty workspaces" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    _ = try seedWorkspaceForTest(workspace_runtime_owner, 13);
    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.applySingleLayoutAction(focusDirectionAction(abi.OMNI_NIRI_DIRECTION_LEFT)),
    );
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.applySingleLayoutAction(focusDirectionAction(abi.OMNI_NIRI_DIRECTION_RIGHT)),
    );
    try std.testing.expect(impl.focused_window == null);
}

test "wm controller navigation layout actions are no-op during non-managed focus" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 14);
    const first_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 401, 501, null);
    _ = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 402, 502, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));

    impl.non_managed_focus_active = true;
    impl.focused_window = null;
    try impl.selected_node_by_workspace.put(workspace_id.bytes, first_handle.bytes);
    try impl.last_focused_by_workspace.put(workspace_id.bytes, first_handle.bytes);

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.applySingleLayoutAction(focusDirectionAction(abi.OMNI_NIRI_DIRECTION_LEFT)),
    );
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.applySingleLayoutAction(focusDirectionAction(abi.OMNI_NIRI_DIRECTION_RIGHT)),
    );
    try std.testing.expect(impl.focused_window == null);
    try std.testing.expectEqual(first_handle.bytes, impl.selected_node_by_workspace.get(workspace_id.bytes).?);
}

test "wm controller softens focus platform failures and still dispatches ui effects" {
    var workspace_config = abi.OmniWorkspaceRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    const workspace_runtime_owner = workspace_runtime.omni_workspace_runtime_create_impl(&workspace_config);
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);
    try std.testing.expect(workspace_runtime_owner != null);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_start_impl(workspace_runtime_owner),
    );

    var monitor = abi.OmniWorkspaceRuntimeMonitorSnapshot{
        .display_id = 1,
        .is_main = 1,
        .frame_x = 0,
        .frame_y = 0,
        .frame_width = 100,
        .frame_height = 100,
        .visible_x = 0,
        .visible_y = 0,
        .visible_width = 100,
        .visible_height = 100,
        .name = workspaceNameFromControllerName(types.encodeName("Main")),
    };
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_import_monitors_impl(workspace_runtime_owner, &monitor, 1),
    );

    const workspace_name = workspaceNameFromControllerName(types.encodeName("1"));
    var has_workspace_id: u8 = 0;
    var workspace_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_workspace_id_by_name_impl(
            workspace_runtime_owner,
            workspace_name,
            1,
            &has_workspace_id,
            &workspace_id,
        ),
    );
    try std.testing.expectEqual(@as(u8, 1), has_workspace_id);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_set_active_workspace_impl(
            workspace_runtime_owner,
            workspace_id,
            1,
        ),
    );

    var upsert = abi.OmniWorkspaceRuntimeWindowUpsert{
        .pid = 321,
        .window_id = 654,
        .workspace_id = workspace_id,
        .has_handle_id = 0,
        .handle_id = .{ .bytes = [_]u8{0} ** 16 },
    };
    var handle_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_upsert_impl(
            workspace_runtime_owner,
            &upsert,
            &handle_id,
        ),
    );
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_set_layout_reason_impl(
            workspace_runtime_owner,
            handle_id,
            abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD,
        ),
    );

    const HostState = struct {
        apply_count: usize = 0,
    };
    var host_state = HostState{};
    const apply_effects = struct {
        fn run(userdata: ?*anyopaque, _: ?*const abi.OmniControllerEffectExport) callconv(.c) i32 {
            const state: *HostState = @ptrCast(@alignCast(userdata.?));
            state.apply_count += 1;
            return abi.OMNI_OK;
        }
    }.run;
    var host = abi.OmniWMControllerHostVTable{
        .userdata = @ptrCast(&host_state),
        .apply_effects = apply_effects,
        .report_error = null,
    };

    var wm_config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_wm_controller_create_impl(&wm_config, workspace_runtime_owner, &host);
    defer omni_wm_controller_destroy_impl(runtime);
    try std.testing.expect(runtime != null);

    const previous_hooks = focus_manager.replaceHooks(.{
        .private_focus = struct {
            fn run(_: i32, _: u32) i32 {
                return abi.OMNI_ERR_PLATFORM;
            }
        }.run,
        .activate_application = struct {
            fn run(_: i32) i32 {
                return abi.OMNI_ERR_PLATFORM;
            }
        }.run,
        .raise_window = struct {
            fn run(_: i32, _: u32) i32 {
                return abi.OMNI_ERR_PLATFORM;
            }
        }.run,
    });
    defer _ = focus_manager.replaceHooks(previous_hooks);

    const impl: *RuntimeImpl = @ptrCast(@alignCast(runtime));
    var refresh_plan = abi.OmniControllerRefreshPlan{
        .flags = abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE |
            abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT,
        .has_workspace_id = 1,
        .workspace_id = workspace_id,
        .has_display_id = 1,
        .display_id = 1,
    };
    var ui_action = abi.OmniControllerUiAction{
        .kind = abi.OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER,
    };
    var layout_action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION,
        .direction = abi.OMNI_NIRI_DIRECTION_RIGHT,
        .index = 0,
        .flag = 0,
    };
    var effects = abi.OmniControllerEffectExport{
        .focus_exports = null,
        .focus_export_count = 0,
        .route_plans = null,
        .route_plan_count = 0,
        .transfer_plans = null,
        .transfer_plan_count = 0,
        .refresh_plans = &refresh_plan,
        .refresh_plan_count = 1,
        .ui_actions = &ui_action,
        .ui_action_count = 1,
        .layout_actions = &layout_action,
        .layout_action_count = 1,
    };

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.applyEffects(&effects));
    try std.testing.expectEqual(@as(usize, 1), host_state.apply_count);
}

test "wm controller snapshot preserves niri node and column ids across syncs and empty transitions" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 11);
    const first_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 301, 401, null);
    const second_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 302, 402, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    var state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));
    var snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.captureSnapshotFromWorkspaceState(state_export, &snapshot));

    const first_snapshot = findWindowSnapshotByHandle(snapshot, first_handle).?;
    const second_snapshot = findWindowSnapshotByHandle(snapshot, second_handle).?;
    try std.testing.expectEqual(@as(u8, 1), first_snapshot.has_node_id);
    try std.testing.expectEqual(first_handle, first_snapshot.node_id);
    try std.testing.expectEqual(@as(u8, 1), first_snapshot.has_column_id);
    try std.testing.expectEqual(@as(u8, 1), second_snapshot.has_node_id);
    try std.testing.expectEqual(second_handle, second_snapshot.node_id);
    try std.testing.expectEqual(@as(u8, 1), second_snapshot.has_column_id);

    const first_column_id = first_snapshot.column_id;
    const second_column_id = second_snapshot.column_id;
    try std.testing.expect(!std.mem.eql(u8, first_column_id.bytes[0..], second_column_id.bytes[0..]));

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));
    var repeated_snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.captureSnapshotFromWorkspaceState(state_export, &repeated_snapshot));
    try std.testing.expectEqual(first_column_id, findWindowSnapshotByHandle(repeated_snapshot, first_handle).?.column_id);
    try std.testing.expectEqual(second_column_id, findWindowSnapshotByHandle(repeated_snapshot, second_handle).?.column_id);

    var active_keys = [_]abi.OmniWorkspaceRuntimeWindowKey{.{
        .pid = 301,
        .window_id = 401,
    }};
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_remove_missing_impl(
            workspace_runtime_owner,
            &active_keys[0],
            active_keys.len,
            1,
        ),
    );

    state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));
    var single_snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.captureSnapshotFromWorkspaceState(state_export, &single_snapshot));
    try std.testing.expectEqual(first_column_id, findWindowSnapshotByHandle(single_snapshot, first_handle).?.column_id);
    try std.testing.expect(findWindowSnapshotByHandle(single_snapshot, second_handle) == null);

    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        workspace_runtime.omni_workspace_runtime_window_remove_missing_impl(
            workspace_runtime_owner,
            null,
            0,
            1,
        ),
    );

    state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));
    var runtime_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &runtime_export));
    try std.testing.expectEqual(@as(usize, 1), runtime_export.column_count);
    try std.testing.expectEqual(@as(usize, 0), runtime_export.window_count);
    const placeholder_column_id = runtime_export.columns[0].column_id;

    _ = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 301, 401, first_handle);
    state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));
    var restored_snapshot = std.mem.zeroes(abi.OmniControllerSnapshot);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.captureSnapshotFromWorkspaceState(state_export, &restored_snapshot));
    const restored_window = findWindowSnapshotByHandle(restored_snapshot, first_handle).?;
    try std.testing.expectEqual(first_handle, restored_window.node_id);
    try std.testing.expectEqual(placeholder_column_id, restored_window.column_id);
}

test "wm controller repairs incoherent runtime exports before reuse and render" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 16);
    _ = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 501, 601, null);
    _ = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 502, 602, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    var state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));

    const entry = impl.workspace_layout_runtimes.getPtr(workspace_id.bytes).?;
    var runtime_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &runtime_export));
    try std.testing.expect(runtimeExportIsCoherent(runtime_export));
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), renderRuntimeFromExport(entry.runtime, runtime_export));

    const runtime_ctx: *niri_runtime.OmniNiriRuntime = @ptrCast(@alignCast(entry.runtime));
    runtime_ctx.runtime_columns[0].window_start = 1;
    runtime_ctx.runtime_columns[0].window_count = 2;

    var corrupted_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &corrupted_export));
    try std.testing.expect(!runtimeExportIsCoherent(corrupted_export));
    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_OUT_OF_RANGE), renderRuntimeFromExport(entry.runtime, corrupted_export));

    var repaired_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        impl.snapshotWorkspaceLayoutRuntimeRecovering(state_export, workspace_id.bytes, &repaired_export),
    );
    try std.testing.expect(runtimeExportIsCoherent(repaired_export));
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), renderRuntimeFromExport(entry.runtime, repaired_export));

    state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));
    var resynced_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &resynced_export));
    try std.testing.expect(runtimeExportIsCoherent(resynced_export));
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), renderRuntimeFromExport(entry.runtime, resynced_export));
}

test "wm controller niri mutation actions update runtime-backed layout state" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 17);
    const first_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 601, 701, null);
    const second_handle = try upsertManagedWindowForTest(workspace_runtime_owner, workspace_id, 602, 702, null);

    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.syncWorkspaceLayoutRuntimes(state_export));

    impl.focused_window = first_handle.bytes;
    try impl.selected_node_by_workspace.put(workspace_id.bytes, first_handle.bytes);
    try impl.last_focused_by_workspace.put(workspace_id.bytes, first_handle.bytes);

    var before_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &before_export));
    try std.testing.expectEqual(@as(usize, 2), before_export.column_count);
    const first_column_before = before_export.columns[0].column_id;
    const second_column_before = before_export.columns[1].column_id;

    const move_column_action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION,
        .direction = abi.OMNI_NIRI_DIRECTION_RIGHT,
        .index = 0,
        .flag = 0,
    };
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.applySingleLayoutAction(move_column_action));

    var moved_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &moved_export));
    try std.testing.expectEqual(second_column_before, moved_export.columns[0].column_id);
    try std.testing.expectEqual(first_column_before, moved_export.columns[1].column_id);

    const tabbed_action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED,
        .direction = 0,
        .index = 0,
        .flag = 0,
    };
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.applySingleLayoutAction(tabbed_action));

    var tabbed_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &tabbed_export));
    const selected_column_id = impl.selected_node_by_workspace.get(workspace_id.bytes).?;
    const selected_column_index = findRuntimeColumnIndex(tabbed_export, selected_column_id) orelse blk: {
        const window_index = findRuntimeWindowIndex(tabbed_export, selected_column_id).?;
        break :blk tabbed_export.windows[window_index].column_index;
    };
    try std.testing.expectEqual(@as(u8, 1), tabbed_export.columns[selected_column_index].is_tabbed);

    const full_width_action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH,
        .direction = 0,
        .index = 0,
        .flag = 0,
    };
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.applySingleLayoutAction(full_width_action));

    var fullscreen_export = std.mem.zeroes(abi.OmniNiriRuntimeStateExport);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.snapshotWorkspaceLayoutRuntime(workspace_id.bytes, &fullscreen_export));
    try std.testing.expectEqual(@as(u8, 1), fullscreen_export.columns[selected_column_index].is_full_width);
    try std.testing.expect(findRuntimeWindowIndex(fullscreen_export, second_handle.bytes) != null);
}

test "wm controller toggle workspace layout updates sparse layout override export" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 18);
    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    const action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT,
        .has_workspace_id = 1,
        .workspace_id = workspace_id,
        .direction = 0,
        .index = 0,
        .flag = 0,
    };

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.toggleWorkspaceLayout(state_export, action));

    const runtime: [*c]OmniWMController = @ptrCast(impl);
    const settings = try queryWorkspaceLayoutSettingsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(settings);

    try std.testing.expectEqual(@as(usize, 1), settings.len);
    try std.testing.expect(types.nameEquals(settings[0].name, "1"));
    try std.testing.expectEqual(@as(u8, abi.OMNI_CONTROLLER_LAYOUT_DWINDLE), settings[0].layout_kind);
}

test "wm controller toggle workspace layout removes sparse override when returning to default" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 19);
    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    const action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT,
        .has_workspace_id = 1,
        .workspace_id = workspace_id,
        .direction = 0,
        .index = 0,
        .flag = 0,
    };

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.toggleWorkspaceLayout(state_export, action));
    const refreshed_state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.toggleWorkspaceLayout(refreshed_state_export, action));

    const runtime: [*c]OmniWMController = @ptrCast(impl);
    const settings = try queryWorkspaceLayoutSettingsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(settings);

    try std.testing.expectEqual(@as(usize, 0), settings.len);
}

test "wm controller workspace layout override export remains stable across repeated count and copy calls" {
    const workspace_runtime_owner = try createStartedWorkspaceRuntimeForTest();
    defer workspace_runtime.omni_workspace_runtime_destroy_impl(workspace_runtime_owner);

    const workspace_id = try seedWorkspaceForTest(workspace_runtime_owner, 20);
    const impl = try createControllerImplForTest(workspace_runtime_owner);
    defer omni_wm_controller_destroy_impl(@ptrCast(impl));

    const state_export = try exportWorkspaceStateForTest(workspace_runtime_owner);
    const action = abi.OmniControllerLayoutAction{
        .kind = abi.OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT,
        .has_workspace_id = 1,
        .workspace_id = workspace_id,
        .direction = 0,
        .index = 0,
        .flag = 0,
    };

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), impl.toggleWorkspaceLayout(state_export, action));

    const runtime: [*c]OmniWMController = @ptrCast(impl);
    var first_count: usize = 0;
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_query_workspace_layout_settings_count_impl(runtime, &first_count),
    );
    var second_count: usize = 0;
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_OK),
        omni_wm_controller_query_workspace_layout_settings_count_impl(runtime, &second_count),
    );
    try std.testing.expectEqual(first_count, second_count);

    const first_settings = try queryWorkspaceLayoutSettingsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(first_settings);
    const second_settings = try queryWorkspaceLayoutSettingsViaApiForTest(runtime, std.testing.allocator);
    defer std.testing.allocator.free(second_settings);

    try std.testing.expectEqual(first_settings.len, second_settings.len);
    try std.testing.expectEqual(@as(usize, 1), first_settings.len);
    try std.testing.expect(types.nameEquals(first_settings[0].name, "1"));
    try std.testing.expect(types.nameEquals(second_settings[0].name, "1"));
    try std.testing.expectEqual(first_settings[0].layout_kind, second_settings[0].layout_kind);
}
