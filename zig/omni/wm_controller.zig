const std = @import("std");
const abi = @import("abi_types.zig");
const border = @import("border.zig");
const controller_runtime = @import("controller_runtime.zig");
const focus_manager = @import("focus_manager.zig");
const ax_manager = @import("../platform/ax_manager.zig");
const monitor_discovery = @import("../platform/monitor_discovery.zig");
const skylight = @import("../platform/skylight.zig");
const workspace_runtime = @import("workspace_runtime.zig");
const c = @cImport({
    @cInclude("unistd.h");
});

pub const OmniWMController = abi.OmniWMController;

const Uuid = [16]u8;
const default_layout_gap: f64 = 10.0;
const default_border_width: f64 = 3.0;
const default_border_color = abi.OmniBorderColor{
    .red = 0.26,
    .green = 0.72,
    .blue = 1.0,
    .alpha = 0.95,
};

const RuntimeImpl = struct {
    allocator: std.mem.Allocator,
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    host: abi.OmniWMControllerHostVTable,
    controller: [*c]controller_runtime.OmniController = null,
    ax_runtime: [*c]ax_manager.OmniAXRuntime = null,
    border_runtime: [*c]border.OmniBorderRuntime = null,
    started: bool = false,

    monitor_snapshots: std.ArrayListUnmanaged(abi.OmniControllerMonitorSnapshot) = .{},
    workspace_snapshots: std.ArrayListUnmanaged(abi.OmniControllerWorkspaceSnapshot) = .{},
    window_snapshots: std.ArrayListUnmanaged(abi.OmniControllerWindowSnapshot) = .{},
    monitor_records: std.ArrayListUnmanaged(abi.OmniMonitorRecord) = .{},
    display_infos: std.ArrayListUnmanaged(abi.OmniBorderDisplayInfo) = .{},
    visible_windows: std.ArrayListUnmanaged(abi.OmniSkyLightWindowInfo) = .{},
    active_window_keys: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeWindowKey) = .{},
    frame_requests: std.ArrayListUnmanaged(abi.OmniAXFrameRequest) = .{},

    selected_node_by_workspace: std.AutoHashMap(Uuid, Uuid),
    last_focused_by_workspace: std.AutoHashMap(Uuid, Uuid),

    focused_window: ?Uuid = null,
    active_monitor_override: ?u32 = null,
    previous_monitor_override: ?u32 = null,

    secure_input_active: bool = false,
    lock_screen_active: bool = false,
    non_managed_focus_active: bool = false,
    app_fullscreen_active: bool = false,
    focus_follows_window_to_monitor: bool = false,
    move_mouse_to_focused_window: bool = false,
    layout_light_session_active: bool = false,
    layout_immediate_in_progress: bool = false,
    layout_incremental_in_progress: bool = false,
    layout_full_enumeration_in_progress: bool = false,
    layout_animation_active: bool = false,
    layout_has_completed_initial_refresh: bool = false,
    layout_animation_deadline: ?f64 = null,
    last_tick_sample_time: f64 = 0,

    fn init(
        allocator: std.mem.Allocator,
        workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
        host: abi.OmniWMControllerHostVTable,
    ) RuntimeImpl {
        return .{
            .allocator = allocator,
            .workspace_runtime_owner = workspace_runtime_owner,
            .host = host,
            .selected_node_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
            .last_focused_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
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
        self.window_snapshots.deinit(self.allocator);
        self.monitor_records.deinit(self.allocator);
        self.display_infos.deinit(self.allocator);
        self.visible_windows.deinit(self.allocator);
        self.active_window_keys.deinit(self.allocator);
        self.frame_requests.deinit(self.allocator);
        self.selected_node_by_workspace.deinit();
        self.last_focused_by_workspace.deinit();
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

    fn createAuxRuntimes(self: *RuntimeImpl) void {
        if (self.ax_runtime == null) {
            var ax_config = abi.OmniAXRuntimeConfig{
                .abi_version = abi.OMNI_AX_RUNTIME_ABI_VERSION,
                .reserved = 0,
            };
            var ax_host = abi.OmniAXHostVTable{
                .userdata = null,
                .on_window_destroyed = null,
                .on_window_destroyed_unknown = null,
                .on_focused_window_changed = null,
            };
            self.ax_runtime = ax_manager.omni_ax_runtime_create_impl(&ax_config, &ax_host);
            if (self.ax_runtime != null) {
                _ = ax_manager.omni_ax_runtime_start_impl(self.ax_runtime);
            }
        }

        if (self.border_runtime == null) {
            self.border_runtime = border.omni_border_runtime_create_impl();
        }
    }

    fn destroyAuxRuntimes(self: *RuntimeImpl) void {
        if (self.border_runtime != null) {
            _ = border.omni_border_runtime_hide_impl(self.border_runtime);
            border.omni_border_runtime_destroy_impl(self.border_runtime);
            self.border_runtime = null;
        }
        if (self.ax_runtime != null) {
            _ = ax_manager.omni_ax_runtime_stop_impl(self.ax_runtime);
            ax_manager.omni_ax_runtime_destroy_impl(self.ax_runtime);
            self.ax_runtime = null;
        }
    }

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        const rc = controller_runtime.omni_controller_start_impl(self.controller);
        if (rc == abi.OMNI_OK) {
            self.started = true;
            _ = self.synchronizeRuntimeStateAndLayout();
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
        if (self.border_runtime != null) {
            _ = border.omni_border_runtime_hide_impl(self.border_runtime);
        }
        return rc;
    }

    fn submitHotkey(self: *RuntimeImpl, command: *const abi.OmniControllerCommand) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        _ = self.synchronizeRuntimeState();
        return controller_runtime.omni_controller_submit_hotkey_impl(self.controller, command);
    }

    fn submitEvent(self: *RuntimeImpl, event: *const abi.OmniControllerEvent) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        _ = self.synchronizeRuntimeState();
        self.mergeEventSnapshotHints(event.*);
        return controller_runtime.omni_controller_submit_os_event_impl(self.controller, event);
    }

    fn applySettings(self: *RuntimeImpl, delta: *const abi.OmniControllerSettingsDelta) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (delta.has_focus_follows_window_to_monitor != 0) {
            self.focus_follows_window_to_monitor = delta.focus_follows_window_to_monitor != 0;
        }
        if (delta.has_move_mouse_to_focused_window != 0) {
            self.move_mouse_to_focused_window = delta.move_mouse_to_focused_window != 0;
        }
        return controller_runtime.omni_controller_apply_settings_impl(self.controller, delta);
    }

    fn tick(self: *RuntimeImpl, sample_time: f64) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        const rc = controller_runtime.omni_controller_tick_impl(self.controller, sample_time);
        if (rc != abi.OMNI_OK) return rc;

        self.last_tick_sample_time = sample_time;

        if (self.layout_animation_deadline) |deadline| {
            if (sample_time >= deadline) {
                self.layout_animation_active = false;
                self.layout_animation_deadline = null;
            }
        }

        self.layout_immediate_in_progress = false;
        self.layout_incremental_in_progress = false;
        self.layout_full_enumeration_in_progress = false;
        return abi.OMNI_OK;
    }

    fn queryUiState(self: *const RuntimeImpl, out_state: *abi.OmniControllerUiState) i32 {
        if (self.controller == null) return abi.OMNI_ERR_INVALID_ARGS;
        return controller_runtime.omni_controller_query_ui_state_impl(self.controller, out_state);
    }

    fn exportWorkspaceState(self: *RuntimeImpl, out_export: *abi.OmniWorkspaceRuntimeStateExport) i32 {
        return workspace_runtime.omni_workspace_runtime_export_state_impl(self.workspace_runtime_owner, out_export);
    }

    fn captureSnapshot(self: *RuntimeImpl, out_snapshot: *abi.OmniControllerSnapshot) i32 {
        _ = self.synchronizeRuntimeState();
        var workspace_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const export_rc = self.exportWorkspaceState(&workspace_export);
        if (export_rc != abi.OMNI_OK) return export_rc;

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
            const selected_node = self.selected_node_by_workspace.get(workspace_id);
            const last_focused = self.last_focused_by_workspace.get(workspace_id);

            self.workspace_snapshots.appendAssumeCapacity(.{
                .workspace_id = workspace.workspace_id,
                .has_assigned_display_id = workspace.has_assigned_display_id,
                .assigned_display_id = workspace.assigned_display_id,
                .is_visible = workspace.is_visible,
                .is_previous_visible = workspace.is_previous_visible,
                .layout_kind = abi.OMNI_CONTROLLER_LAYOUT_NIRI,
                .name = controllerNameFromWorkspaceName(workspace.name),
                .has_selected_node_id = if (selected_node == null) 0 else 1,
                .selected_node_id = if (selected_node) |value| .{ .bytes = value } else .{ .bytes = [_]u8{0} ** 16 },
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

            self.window_snapshots.appendAssumeCapacity(.{
                .handle_id = window.handle_id,
                .pid = window.pid,
                .window_id = window.window_id,
                .workspace_id = window.workspace_id,
                .layout_kind = if (window.layout_reason == abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD)
                    abi.OMNI_CONTROLLER_LAYOUT_NIRI
                else
                    abi.OMNI_CONTROLLER_LAYOUT_DEFAULT,
                .is_hidden = if (window.has_hidden_state != 0) 1 else 0,
                .is_focused = if (is_focused) 1 else 0,
                .is_managed = if (window.layout_reason == abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) 1 else 0,
                .has_node_id = 0,
                .node_id = .{ .bytes = [_]u8{0} ** 16 },
                .has_column_id = 0,
                .column_id = .{ .bytes = [_]u8{0} ** 16 },
                .order_index = @intCast(index),
                .column_index = @intCast(index),
                .row_index = 0,
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
        if (layout_rc != abi.OMNI_OK) return layout_rc;

        self.absorbFocusEffects(effects);
        const focus_rc = self.applyFocusEffects(effects);
        if (focus_rc != abi.OMNI_OK) return focus_rc;

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
            return callback(self.host.userdata, &ui_only);
        }
        return abi.OMNI_OK;
    }

    fn reportError(self: *RuntimeImpl, code: i32, message: abi.OmniControllerName) void {
        if (self.host.report_error) |callback| {
            _ = callback(self.host.userdata, code, message);
        }
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
                    self.selected_node_by_workspace.put(workspace_id, focus_export.selected_node_id.bytes) catch {};
                }
                if (focus_export.has_focused_window_id != 0) {
                    self.last_focused_by_workspace.put(workspace_id, focus_export.focused_window_id.bytes) catch {};
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
            abi.OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE,
            abi.OMNI_CONTROLLER_ROUTE_SUMMON_WORKSPACE,
            => {
                const resolved_display = target_display_id orelse return abi.OMNI_ERR_OUT_OF_RANGE;
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

        for (effects.layout_actions[0..effects.layout_action_count]) |action| {
            const rc = self.applySingleLayoutAction(action);
            if (rc != abi.OMNI_OK) return rc;
        }

        return abi.OMNI_OK;
    }

    fn applySingleLayoutAction(self: *RuntimeImpl, action: abi.OmniControllerLayoutAction) i32 {
        switch (action.kind) {
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION => {
                const direction = directionFromRaw(action.direction) orelse return abi.OMNI_ERR_INVALID_ARGS;
                return self.focusByDirection(direction);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT => {
                return self.focusByDirection(.backward);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT => {
                return self.focusByDirection(.forward);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP,
            => {
                return self.focusByIndex(0);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST,
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM,
            => {
                return self.focusByIndex(-1);
            },
            abi.OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX => {
                return self.focusByIndex(action.index);
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
            if (focus_rc != abi.OMNI_OK and focus_rc != abi.OMNI_ERR_OUT_OF_RANGE) {
                return focus_rc;
            }
        }

        return abi.OMNI_OK;
    }

    fn applyRefreshPlans(self: *RuntimeImpl, effects: abi.OmniControllerEffectExport) i32 {
        if (effects.refresh_plan_count == 0) return abi.OMNI_OK;
        if (effects.refresh_plans == null) return abi.OMNI_ERR_INVALID_ARGS;

        for (effects.refresh_plans[0..effects.refresh_plan_count]) |plan| {
            self.applySingleRefreshPlan(plan);
        }
        const runtime_rc = self.synchronizeRuntimeStateAndLayout();
        if (runtime_rc != abi.OMNI_OK) return runtime_rc;
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
        const sync_rc = self.synchronizeRuntimeState();
        if (sync_rc != abi.OMNI_OK and sync_rc != abi.OMNI_ERR_PLATFORM) {
            return sync_rc;
        }

        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const export_rc = self.exportWorkspaceState(&state_export);
        if (export_rc != abi.OMNI_OK) return export_rc;

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

        var state_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const export_rc = self.exportWorkspaceState(&state_export);
        if (export_rc != abi.OMNI_OK) return export_rc;

        const windows_rc = self.syncWindowInventoryFromSystem(state_export);
        if (windows_rc != abi.OMNI_OK and windows_rc != abi.OMNI_ERR_PLATFORM) {
            return windows_rc;
        }

        var refreshed_export = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
        const refreshed_rc = self.exportWorkspaceState(&refreshed_export);
        if (refreshed_rc == abi.OMNI_OK) {
            self.reconcileFocusedWindow(refreshed_export);
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
        const own_pid: i32 = @intCast(c.getpid());

        for (self.visible_windows.items) |window| {
            if (window.id == 0 or window.pid <= 0) continue;
            if (window.pid == own_pid) continue;
            if (!isRectFinite(window.frame) or window.frame.width <= 1 or window.frame.height <= 1) continue;

            const workspace_id = self.resolveWorkspaceForWindow(state_export, window.frame) orelse continue;
            const existing_handle = self.findExistingHandle(state_export, window.pid, window.id);

            var request = abi.OmniWorkspaceRuntimeWindowUpsert{
                .pid = window.pid,
                .window_id = @intCast(window.id),
                .workspace_id = workspace_id,
                .has_handle_id = if (existing_handle == null) 0 else 1,
                .handle_id = existing_handle orelse .{ .bytes = [_]u8{0} ** 16 },
            };
            var handle_id = abi.OmniUuid128{ .bytes = [_]u8{0} ** 16 };
            const upsert_rc = workspace_runtime.omni_workspace_runtime_window_upsert_impl(
                self.workspace_runtime_owner,
                &request,
                &handle_id,
            );
            if (upsert_rc != abi.OMNI_OK) continue;

            const layout_reason = self.resolveLayoutReason(window.pid, window.id);
            _ = workspace_runtime.omni_workspace_runtime_window_set_layout_reason_impl(
                self.workspace_runtime_owner,
                handle_id,
                layout_reason,
            );

            self.active_window_keys.append(self.allocator, .{
                .pid = window.pid,
                .window_id = @intCast(window.id),
            }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
        }

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

    fn applyManagedLayout(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) i32 {
        const runtime = self.ax_runtime orelse return abi.OMNI_OK;
        self.frame_requests.clearRetainingCapacity();

        if (state_export.monitor_count == 0 or state_export.monitors == null) return abi.OMNI_OK;
        if (state_export.window_count == 0 or state_export.windows == null) return abi.OMNI_OK;

        for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
            if (monitor.has_active_workspace_id == 0) continue;
            const workspace_id = monitor.active_workspace_id;

            var managed_count: usize = 0;
            for (state_export.windows[0..state_export.window_count]) |window| {
                if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id.bytes[0..])) continue;
                if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
                if (window.pid <= 0 or window.window_id <= 0) continue;
                if (window.window_id > std.math.maxInt(u32)) continue;
                managed_count += 1;
            }
            if (managed_count == 0) continue;

            var cols: usize = 1;
            while (cols * cols < managed_count) : (cols += 1) {}
            const rows = (managed_count + cols - 1) / cols;

            const cell_w = monitor.visible_width / @as(f64, @floatFromInt(cols));
            const cell_h = monitor.visible_height / @as(f64, @floatFromInt(rows));

            var tile_index: usize = 0;
            for (state_export.windows[0..state_export.window_count]) |window| {
                if (!std.mem.eql(u8, window.workspace_id.bytes[0..], workspace_id.bytes[0..])) continue;
                if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
                if (window.pid <= 0 or window.window_id <= 0) continue;
                const raw_window_id = std.math.cast(u32, window.window_id) orelse continue;

                const col = tile_index % cols;
                const row = tile_index / cols;
                tile_index += 1;

                const frame = abi.OmniBorderRect{
                    .x = monitor.visible_x + @as(f64, @floatFromInt(col)) * cell_w + default_layout_gap * 0.5,
                    .y = monitor.visible_y + @as(f64, @floatFromInt(row)) * cell_h + default_layout_gap * 0.5,
                    .width = @max(1.0, cell_w - default_layout_gap),
                    .height = @max(1.0, cell_h - default_layout_gap),
                };
                self.frame_requests.append(self.allocator, .{
                    .pid = window.pid,
                    .window_id = raw_window_id,
                    .frame = frame,
                }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
            }
        }

        const requests_ptr: [*c]const abi.OmniAXFrameRequest = if (self.frame_requests.items.len == 0)
            null
        else
            self.frame_requests.items.ptr;
        return ax_manager.omni_ax_runtime_apply_frames_batch_impl(
            runtime,
            requests_ptr,
            self.frame_requests.items.len,
        );
    }

    fn updateBorderPresentation(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) i32 {
        const runtime = self.border_runtime orelse return abi.OMNI_OK;
        if (self.non_managed_focus_active or self.app_fullscreen_active) {
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

        var snapshot = abi.OmniBorderSnapshotInput{
            .config = .{
                .enabled = 1,
                .width = default_border_width,
                .color = default_border_color,
            },
            .has_focused_window_id = 1,
            .focused_window_id = focused.window_id,
            .has_focused_frame = 1,
            .focused_frame = focused_frame,
            .is_focused_window_in_active_workspace = 1,
            .is_non_managed_focus_active = if (self.non_managed_focus_active) 1 else 0,
            .is_native_fullscreen_active = fullscreen,
            .is_managed_fullscreen_active = 0,
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

    fn resolveFocusedWindowRecord(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) ?abi.OmniWorkspaceRuntimeWindowRecord {
        if (self.focused_window) |focused| {
            if (self.findWindowRecord(state_export, focused)) |record| {
                return record;
            }
        }

        if (state_export.window_count == 0 or state_export.windows == null) {
            return null;
        }
        if (state_export.monitor_count > 0 and state_export.monitors != null) {
            for (state_export.monitors[0..state_export.monitor_count]) |monitor| {
                if (monitor.has_active_workspace_id == 0) continue;
                for (state_export.windows[0..state_export.window_count]) |window| {
                    if (window.layout_reason != abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD) continue;
                    if (!std.mem.eql(u8, window.workspace_id.bytes[0..], monitor.active_workspace_id.bytes[0..])) continue;
                    self.focused_window = window.handle_id.bytes;
                    return window;
                }
            }
        }

        return null;
    }

    fn reconcileFocusedWindow(self: *RuntimeImpl, state_export: abi.OmniWorkspaceRuntimeStateExport) void {
        const focused = self.focused_window orelse return;
        if (self.findWindowRecord(state_export, focused) == null) {
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
            self.last_focused_by_workspace.put(window.workspace_id.bytes, handle_id) catch {};
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

    fn markLayoutAnimationStarted(self: *RuntimeImpl, duration_seconds: f64) void {
        self.layout_animation_active = true;
        self.layout_animation_deadline = self.last_tick_sample_time + @max(0.05, duration_seconds);
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

fn runtimeFromHandle(runtime: [*c]OmniWMController) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

fn runtimeFromUserdata(userdata: ?*anyopaque) ?*RuntimeImpl {
    const ptr = userdata orelse return null;
    return @ptrCast(@alignCast(ptr));
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
    return impl.start();
}

pub fn omni_wm_controller_stop_impl(runtime: [*c]OmniWMController) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}

pub fn omni_wm_controller_submit_hotkey_impl(
    runtime: [*c]OmniWMController,
    command: ?*const abi.OmniControllerCommand,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_command = command orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.submitHotkey(resolved_command);
}

pub fn omni_wm_controller_submit_os_event_impl(
    runtime: [*c]OmniWMController,
    event: ?*const abi.OmniControllerEvent,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_event = event orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.submitEvent(resolved_event);
}

pub fn omni_wm_controller_apply_settings_impl(
    runtime: [*c]OmniWMController,
    delta: ?*const abi.OmniControllerSettingsDelta,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_delta = delta orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.applySettings(resolved_delta);
}

pub fn omni_wm_controller_tick_impl(
    runtime: [*c]OmniWMController,
    sample_time: f64,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.tick(sample_time);
}

pub fn omni_wm_controller_query_ui_state_impl(
    runtime: [*c]const OmniWMController,
    out_state: ?*abi.OmniControllerUiState,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_state orelse return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *const RuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.queryUiState(resolved_out);
}

pub fn omni_wm_controller_export_workspace_state_impl(
    runtime: [*c]OmniWMController,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_export orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.exportWorkspaceState(resolved_out);
}

test "wm controller validates create args" {
    var config = abi.OmniWMControllerConfig{
        .abi_version = abi.OMNI_WM_CONTROLLER_ABI_VERSION,
        .reserved = 0,
    };
    const runtime = omni_wm_controller_create_impl(&config, null, null);
    try std.testing.expect(runtime == null);
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
