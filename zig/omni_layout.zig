const abi = @import("omni/abi_types.zig");
const state_validation = @import("omni/state_validation.zig");
const interaction = @import("omni/interaction.zig");
const layout_context = @import("omni/layout_context.zig");
const runtime = @import("omni/runtime.zig");
const viewport = @import("omni/viewport.zig");
const dwindle = @import("omni/dwindle.zig");
const border = @import("omni/border.zig");
const controller_runtime = @import("omni/controller_runtime.zig");
const wm_controller = @import("omni/wm_controller.zig");
const service_lifecycle = @import("omni/service_lifecycle.zig");
const ui_bridge = @import("omni/ui_bridge.zig");
const mouse_handler = @import("omni/mouse_handler.zig");
const focus_manager = @import("omni/focus_manager.zig");
const animation = @import("omni/animation.zig");
const workspace_runtime = @import("omni/workspace_runtime.zig");
const skylight_platform = @import("platform/skylight.zig");
const private_apis = @import("platform/private_apis.zig");
const platform_runtime = @import("platform/platform_runtime.zig");
const ax_manager = @import("platform/ax_manager.zig");
const input_runtime = @import("platform/input_runtime.zig");
const monitor_discovery = @import("platform/monitor_discovery.zig");
const workspace_observer = @import("platform/workspace_observer.zig");
const lock_observer = @import("platform/lock_observer.zig");
const sleep = @import("platform/sleep.zig");
const ax_permission = @import("platform/ax_permission.zig");
export fn omni_niri_validate_state_snapshot(
    columns: [*c]const abi.OmniNiriStateColumnInput,
    column_count: usize,
    windows: [*c]const abi.OmniNiriStateWindowInput,
    window_count: usize,
    out_result: [*c]abi.OmniNiriStateValidationResult,
) i32 {
    return state_validation.omni_niri_validate_state_snapshot_impl(
        columns,
        column_count,
        windows,
        window_count,
        out_result,
    );
}
export fn omni_niri_layout_context_create() [*c]layout_context.OmniNiriLayoutContext {
    return layout_context.omni_niri_layout_context_create_impl();
}
export fn omni_border_runtime_create() [*c]border.OmniBorderRuntime {
    return border.omni_border_runtime_create_impl();
}
export fn omni_niri_layout_context_destroy(context: [*c]layout_context.OmniNiriLayoutContext) void {
    layout_context.omni_niri_layout_context_destroy_impl(context);
}
export fn omni_border_runtime_destroy(runtime_owner: [*c]border.OmniBorderRuntime) void {
    border.omni_border_runtime_destroy_impl(runtime_owner);
}
export fn omni_border_runtime_apply_config(
    runtime_owner: [*c]border.OmniBorderRuntime,
    config: [*c]const abi.OmniBorderConfig,
) i32 {
    return border.omni_border_runtime_apply_config_impl(runtime_owner, config);
}
export fn omni_border_runtime_apply_presentation(
    runtime_owner: [*c]border.OmniBorderRuntime,
    input: [*c]const abi.OmniBorderPresentationInput,
) i32 {
    return border.omni_border_runtime_apply_presentation_impl(runtime_owner, input);
}
export fn omni_border_runtime_submit_snapshot(
    runtime_owner: [*c]border.OmniBorderRuntime,
    snapshot: [*c]const abi.OmniBorderSnapshotInput,
) i32 {
    return border.omni_border_runtime_submit_snapshot_impl(runtime_owner, snapshot);
}
export fn omni_border_runtime_apply_motion(
    runtime_owner: [*c]border.OmniBorderRuntime,
    input: [*c]const abi.OmniBorderMotionInput,
) i32 {
    return border.omni_border_runtime_apply_motion_impl(runtime_owner, input);
}
export fn omni_border_runtime_invalidate_displays(runtime_owner: [*c]border.OmniBorderRuntime) i32 {
    return border.omni_border_runtime_invalidate_displays_impl(runtime_owner);
}
export fn omni_border_runtime_hide(runtime_owner: [*c]border.OmniBorderRuntime) i32 {
    return border.omni_border_runtime_hide_impl(runtime_owner);
}
export fn omni_skylight_get_capabilities(
    out_capabilities: [*c]abi.OmniSkyLightCapabilities,
) i32 {
    return skylight_platform.getCapabilities(out_capabilities);
}
export fn omni_skylight_get_main_connection_id() i32 {
    return skylight_platform.mainConnectionId();
}
export fn omni_skylight_order_window(
    window_id: u32,
    relative_to_window_id: u32,
    order: i32,
) i32 {
    return skylight_platform.orderWindow(window_id, relative_to_window_id, order);
}
export fn omni_skylight_move_window(
    window_id: u32,
    origin_x: f64,
    origin_y: f64,
) i32 {
    return skylight_platform.moveWindow(window_id, origin_x, origin_y);
}
export fn omni_skylight_batch_move_windows(
    requests: [*c]const abi.OmniSkyLightMoveRequest,
    request_count: usize,
) i32 {
    return skylight_platform.batchMoveWindows(requests, request_count);
}
export fn omni_skylight_get_window_bounds(
    window_id: u32,
    out_rect: [*c]abi.OmniBorderRect,
) i32 {
    return skylight_platform.getWindowBounds(window_id, out_rect);
}
export fn omni_skylight_query_visible_windows(
    out_windows: [*c]abi.OmniSkyLightWindowInfo,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    return skylight_platform.queryVisibleWindows(out_windows, out_capacity, out_written);
}
export fn omni_skylight_query_window_info(
    window_id: u32,
    out_info: [*c]abi.OmniSkyLightWindowInfo,
) i32 {
    return skylight_platform.queryWindowInfo(window_id, out_info);
}
export fn omni_skylight_subscribe_window_notifications(
    window_ids: [*c]const u32,
    window_count: usize,
) i32 {
    return skylight_platform.subscribeWindowNotifications(window_ids, window_count);
}
export fn omni_private_get_capabilities(
    out_capabilities: [*c]abi.OmniPrivateCapabilities,
) i32 {
    return private_apis.getCapabilities(out_capabilities);
}
export fn omni_private_get_ax_window_id(
    ax_element: ?*anyopaque,
    out_window_id: [*c]u32,
) i32 {
    return private_apis.getAXWindowId(ax_element, out_window_id);
}
export fn omni_private_focus_window(
    pid: i32,
    window_id: u32,
) i32 {
    return private_apis.focusWindow(pid, window_id);
}
export fn omni_monitor_query_current(
    out_monitors: [*c]abi.OmniMonitorRecord,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    return monitor_discovery.omni_monitor_query_current_impl(
        out_monitors,
        out_capacity,
        out_written,
    );
}
export fn omni_monitor_runtime_create(
    config: ?*const abi.OmniMonitorRuntimeConfig,
    host_vtable: ?*const abi.OmniMonitorHostVTable,
) [*c]monitor_discovery.OmniMonitorRuntime {
    return monitor_discovery.omni_monitor_runtime_create_impl(config, host_vtable);
}
export fn omni_monitor_runtime_destroy(
    runtime_owner: [*c]monitor_discovery.OmniMonitorRuntime,
) void {
    monitor_discovery.omni_monitor_runtime_destroy_impl(runtime_owner);
}
export fn omni_monitor_runtime_start(
    runtime_owner: [*c]monitor_discovery.OmniMonitorRuntime,
) i32 {
    return monitor_discovery.omni_monitor_runtime_start_impl(runtime_owner);
}
export fn omni_monitor_runtime_stop(
    runtime_owner: [*c]monitor_discovery.OmniMonitorRuntime,
) i32 {
    return monitor_discovery.omni_monitor_runtime_stop_impl(runtime_owner);
}
export fn omni_workspace_observer_runtime_create(
    config: ?*const abi.OmniWorkspaceObserverRuntimeConfig,
    host_vtable: ?*const abi.OmniWorkspaceObserverHostVTable,
) [*c]workspace_observer.OmniWorkspaceObserverRuntime {
    return workspace_observer.omni_workspace_observer_runtime_create_impl(config, host_vtable);
}
export fn omni_workspace_observer_runtime_destroy(
    runtime_owner: [*c]workspace_observer.OmniWorkspaceObserverRuntime,
) void {
    workspace_observer.omni_workspace_observer_runtime_destroy_impl(runtime_owner);
}
export fn omni_workspace_observer_runtime_start(
    runtime_owner: [*c]workspace_observer.OmniWorkspaceObserverRuntime,
) i32 {
    return workspace_observer.omni_workspace_observer_runtime_start_impl(runtime_owner);
}
export fn omni_workspace_observer_runtime_stop(
    runtime_owner: [*c]workspace_observer.OmniWorkspaceObserverRuntime,
) i32 {
    return workspace_observer.omni_workspace_observer_runtime_stop_impl(runtime_owner);
}
export fn omni_lock_observer_runtime_create(
    config: ?*const abi.OmniLockObserverRuntimeConfig,
    host_vtable: ?*const abi.OmniLockObserverHostVTable,
) [*c]lock_observer.OmniLockObserverRuntime {
    return lock_observer.omni_lock_observer_runtime_create_impl(config, host_vtable);
}
export fn omni_lock_observer_runtime_destroy(
    runtime_owner: [*c]lock_observer.OmniLockObserverRuntime,
) void {
    lock_observer.omni_lock_observer_runtime_destroy_impl(runtime_owner);
}
export fn omni_lock_observer_runtime_start(
    runtime_owner: [*c]lock_observer.OmniLockObserverRuntime,
) i32 {
    return lock_observer.omni_lock_observer_runtime_start_impl(runtime_owner);
}
export fn omni_lock_observer_runtime_stop(
    runtime_owner: [*c]lock_observer.OmniLockObserverRuntime,
) i32 {
    return lock_observer.omni_lock_observer_runtime_stop_impl(runtime_owner);
}
export fn omni_platform_runtime_create(
    config: ?*const abi.OmniPlatformRuntimeConfig,
    host_vtable: ?*const abi.OmniPlatformHostVTable,
) [*c]platform_runtime.OmniPlatformRuntime {
    return platform_runtime.omni_platform_runtime_create_impl(config, host_vtable);
}
export fn omni_platform_runtime_destroy(
    platform_runtime_owner: [*c]platform_runtime.OmniPlatformRuntime,
) void {
    platform_runtime.omni_platform_runtime_destroy_impl(platform_runtime_owner);
}
export fn omni_platform_runtime_start(
    platform_runtime_owner: [*c]platform_runtime.OmniPlatformRuntime,
) i32 {
    return platform_runtime.omni_platform_runtime_start_impl(platform_runtime_owner);
}
export fn omni_platform_runtime_stop(
    platform_runtime_owner: [*c]platform_runtime.OmniPlatformRuntime,
) i32 {
    return platform_runtime.omni_platform_runtime_stop_impl(platform_runtime_owner);
}
export fn omni_platform_runtime_subscribe_windows(
    platform_runtime_owner: [*c]platform_runtime.OmniPlatformRuntime,
    window_ids: [*c]const u32,
    window_count: usize,
) i32 {
    return platform_runtime.omni_platform_runtime_subscribe_windows_impl(
        platform_runtime_owner,
        window_ids,
        window_count,
    );
}
export fn omni_ax_runtime_create(
    config: ?*const abi.OmniAXRuntimeConfig,
    host_vtable: ?*const abi.OmniAXHostVTable,
) [*c]ax_manager.OmniAXRuntime {
    return ax_manager.omni_ax_runtime_create_impl(config, host_vtable);
}
export fn omni_ax_runtime_destroy(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
) void {
    ax_manager.omni_ax_runtime_destroy_impl(runtime_owner);
}
export fn omni_ax_runtime_start(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
) i32 {
    return ax_manager.omni_ax_runtime_start_impl(runtime_owner);
}
export fn omni_ax_runtime_stop(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
) i32 {
    return ax_manager.omni_ax_runtime_stop_impl(runtime_owner);
}
export fn omni_ax_runtime_track_app(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
    app_policy: i32,
    bundle_id: [*c]const u8,
    force_floating: u8,
) i32 {
    return ax_manager.omni_ax_runtime_track_app_impl(runtime_owner, pid, app_policy, bundle_id, force_floating);
}
export fn omni_ax_runtime_untrack_app(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
) i32 {
    return ax_manager.omni_ax_runtime_untrack_app_impl(runtime_owner, pid);
}
export fn omni_ax_runtime_enumerate_windows(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    out_windows: [*c]abi.OmniAXWindowRecord,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    return ax_manager.omni_ax_runtime_enumerate_windows_impl(runtime_owner, out_windows, out_capacity, out_written);
}
export fn omni_ax_runtime_apply_frames_batch(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    requests: [*c]const abi.OmniAXFrameRequest,
    request_count: usize,
) i32 {
    return ax_manager.omni_ax_runtime_apply_frames_batch_impl(runtime_owner, requests, request_count);
}
export fn omni_ax_runtime_cancel_frame_jobs(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    keys: [*c]const abi.OmniAXWindowKey,
    key_count: usize,
) i32 {
    return ax_manager.omni_ax_runtime_cancel_frame_jobs_impl(runtime_owner, keys, key_count);
}
export fn omni_ax_runtime_suppress_frame_writes(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    keys: [*c]const abi.OmniAXWindowKey,
    key_count: usize,
) i32 {
    return ax_manager.omni_ax_runtime_suppress_frame_writes_impl(runtime_owner, keys, key_count);
}
export fn omni_ax_runtime_unsuppress_frame_writes(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    keys: [*c]const abi.OmniAXWindowKey,
    key_count: usize,
) i32 {
    return ax_manager.omni_ax_runtime_unsuppress_frame_writes_impl(runtime_owner, keys, key_count);
}
export fn omni_ax_runtime_get_window_frame(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
    window_id: u32,
    out_rect: [*c]abi.OmniBorderRect,
) i32 {
    return ax_manager.omni_ax_runtime_get_window_frame_impl(runtime_owner, pid, window_id, out_rect);
}
export fn omni_ax_runtime_set_window_frame(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
    window_id: u32,
    frame: [*c]const abi.OmniBorderRect,
) i32 {
    return ax_manager.omni_ax_runtime_set_window_frame_impl(runtime_owner, pid, window_id, frame);
}
export fn omni_ax_runtime_get_window_type(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    request: [*c]const abi.OmniAXWindowTypeRequest,
    out_type: [*c]u8,
) i32 {
    return ax_manager.omni_ax_runtime_get_window_type_impl(runtime_owner, request, out_type);
}
export fn omni_ax_runtime_is_window_fullscreen(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
    window_id: u32,
    out_fullscreen: [*c]u8,
) i32 {
    return ax_manager.omni_ax_runtime_is_window_fullscreen_impl(runtime_owner, pid, window_id, out_fullscreen);
}
export fn omni_ax_runtime_set_window_fullscreen(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
    window_id: u32,
    fullscreen: u8,
) i32 {
    return ax_manager.omni_ax_runtime_set_window_fullscreen_impl(runtime_owner, pid, window_id, fullscreen);
}
export fn omni_ax_runtime_get_window_constraints(
    runtime_owner: [*c]ax_manager.OmniAXRuntime,
    pid: i32,
    window_id: u32,
    out_constraints: [*c]abi.OmniAXWindowConstraints,
) i32 {
    return ax_manager.omni_ax_runtime_get_window_constraints_impl(runtime_owner, pid, window_id, out_constraints);
}
export fn omni_sleep_prevention_create_assertion(
    out_assertion_id: [*c]u32,
) i32 {
    return sleep.omni_sleep_prevention_create_assertion_impl(out_assertion_id);
}
export fn omni_sleep_prevention_release_assertion(
    assertion_id: u32,
) i32 {
    return sleep.omni_sleep_prevention_release_assertion_impl(assertion_id);
}
export fn omni_ax_permission_is_trusted() u8 {
    return ax_permission.omni_ax_permission_is_trusted_impl();
}
export fn omni_ax_permission_request_prompt() u8 {
    return ax_permission.omni_ax_permission_request_prompt_impl();
}
export fn omni_ax_permission_poll_until_trusted(
    max_wait_millis: u32,
    poll_interval_millis: u32,
) u8 {
    return ax_permission.omni_ax_permission_poll_until_trusted_impl(max_wait_millis, poll_interval_millis);
}
export fn omni_workspace_runtime_create(
    config: ?*const abi.OmniWorkspaceRuntimeConfig,
) [*c]workspace_runtime.OmniWorkspaceRuntime {
    return workspace_runtime.omni_workspace_runtime_create_impl(config);
}
export fn omni_workspace_runtime_destroy(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
) void {
    workspace_runtime.omni_workspace_runtime_destroy_impl(runtime_owner);
}
export fn omni_workspace_runtime_start(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
) i32 {
    return workspace_runtime.omni_workspace_runtime_start_impl(runtime_owner);
}
export fn omni_workspace_runtime_stop(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
) i32 {
    return workspace_runtime.omni_workspace_runtime_stop_impl(runtime_owner);
}
export fn omni_workspace_runtime_import_monitors(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    monitors: [*c]const abi.OmniWorkspaceRuntimeMonitorSnapshot,
    monitor_count: usize,
) i32 {
    return workspace_runtime.omni_workspace_runtime_import_monitors_impl(
        runtime_owner,
        monitors,
        monitor_count,
    );
}
export fn omni_workspace_runtime_import_settings(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    settings: ?*const abi.OmniWorkspaceRuntimeSettingsImport,
) i32 {
    return workspace_runtime.omni_workspace_runtime_import_settings_impl(runtime_owner, settings);
}
export fn omni_workspace_runtime_export_state(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    return workspace_runtime.omni_workspace_runtime_export_state_impl(runtime_owner, out_export);
}
export fn omni_workspace_runtime_workspace_id_by_name(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    name: abi.OmniWorkspaceRuntimeName,
    create_if_missing: u8,
    out_has_workspace_id: [*c]u8,
    out_workspace_id: [*c]abi.OmniUuid128,
) i32 {
    return workspace_runtime.omni_workspace_runtime_workspace_id_by_name_impl(
        runtime_owner,
        name,
        create_if_missing,
        out_has_workspace_id,
        out_workspace_id,
    );
}
export fn omni_workspace_runtime_set_active_workspace(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
    monitor_display_id: u32,
) i32 {
    return workspace_runtime.omni_workspace_runtime_set_active_workspace_impl(
        runtime_owner,
        workspace_id,
        monitor_display_id,
    );
}
export fn omni_workspace_runtime_summon_workspace_by_name(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    name: abi.OmniWorkspaceRuntimeName,
    monitor_display_id: u32,
    out_has_workspace_id: [*c]u8,
    out_workspace_id: [*c]abi.OmniUuid128,
) i32 {
    return workspace_runtime.omni_workspace_runtime_summon_workspace_by_name_impl(
        runtime_owner,
        name,
        monitor_display_id,
        out_has_workspace_id,
        out_workspace_id,
    );
}
export fn omni_workspace_runtime_move_workspace_to_monitor(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    workspace_id: abi.OmniUuid128,
    target_monitor_display_id: u32,
) i32 {
    return workspace_runtime.omni_workspace_runtime_move_workspace_to_monitor_impl(
        runtime_owner,
        workspace_id,
        target_monitor_display_id,
    );
}
export fn omni_workspace_runtime_swap_workspaces(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    workspace_1_id: abi.OmniUuid128,
    monitor_1_display_id: u32,
    workspace_2_id: abi.OmniUuid128,
    monitor_2_display_id: u32,
) i32 {
    return workspace_runtime.omni_workspace_runtime_swap_workspaces_impl(
        runtime_owner,
        workspace_1_id,
        monitor_1_display_id,
        workspace_2_id,
        monitor_2_display_id,
    );
}
export fn omni_workspace_runtime_adjacent_monitor(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    from_monitor_display_id: u32,
    direction: u8,
    wrap_around: u8,
    out_has_monitor: [*c]u8,
    out_monitor: [*c]abi.OmniWorkspaceRuntimeMonitorRecord,
) i32 {
    return workspace_runtime.omni_workspace_runtime_adjacent_monitor_impl(
        runtime_owner,
        from_monitor_display_id,
        direction,
        wrap_around,
        out_has_monitor,
        out_monitor,
    );
}
export fn omni_workspace_runtime_window_upsert(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    request: ?*const abi.OmniWorkspaceRuntimeWindowUpsert,
    out_handle_id: [*c]abi.OmniUuid128,
) i32 {
    return workspace_runtime.omni_workspace_runtime_window_upsert_impl(
        runtime_owner,
        request,
        out_handle_id,
    );
}
export fn omni_workspace_runtime_window_remove(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    key: abi.OmniWorkspaceRuntimeWindowKey,
) i32 {
    return workspace_runtime.omni_workspace_runtime_window_remove_impl(runtime_owner, key);
}
export fn omni_workspace_runtime_window_set_workspace(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    handle_id: abi.OmniUuid128,
    workspace_id: abi.OmniUuid128,
) i32 {
    return workspace_runtime.omni_workspace_runtime_window_set_workspace_impl(
        runtime_owner,
        handle_id,
        workspace_id,
    );
}
export fn omni_workspace_runtime_window_set_hidden_state(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    handle_id: abi.OmniUuid128,
    has_hidden_state: u8,
    hidden_state: abi.OmniWorkspaceRuntimeWindowHiddenState,
) i32 {
    return workspace_runtime.omni_workspace_runtime_window_set_hidden_state_impl(
        runtime_owner,
        handle_id,
        has_hidden_state,
        hidden_state,
    );
}
export fn omni_workspace_runtime_window_set_layout_reason(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    handle_id: abi.OmniUuid128,
    layout_reason: u8,
) i32 {
    return workspace_runtime.omni_workspace_runtime_window_set_layout_reason_impl(
        runtime_owner,
        handle_id,
        layout_reason,
    );
}
export fn omni_workspace_runtime_window_remove_missing(
    runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    active_keys: [*c]const abi.OmniWorkspaceRuntimeWindowKey,
    active_key_count: usize,
    required_consecutive_misses: u32,
) i32 {
    return workspace_runtime.omni_workspace_runtime_window_remove_missing_impl(
        runtime_owner,
        active_keys,
        active_key_count,
        required_consecutive_misses,
    );
}
export fn omni_input_runtime_create(
    config: ?*const abi.OmniInputRuntimeConfig,
    host_vtable: ?*const abi.OmniInputHostVTable,
) [*c]input_runtime.OmniInputRuntime {
    return input_runtime.omni_input_runtime_create_impl(config, host_vtable);
}
export fn omni_input_runtime_destroy(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
) void {
    input_runtime.omni_input_runtime_destroy_impl(runtime_owner);
}
export fn omni_input_runtime_start(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
) i32 {
    return input_runtime.omni_input_runtime_start_impl(runtime_owner);
}
export fn omni_input_runtime_stop(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
) i32 {
    return input_runtime.omni_input_runtime_stop_impl(runtime_owner);
}
export fn omni_input_runtime_set_bindings(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
    bindings: [*c]const abi.OmniInputBinding,
    binding_count: usize,
) i32 {
    return input_runtime.omni_input_runtime_set_bindings_impl(
        runtime_owner,
        bindings,
        binding_count,
    );
}
export fn omni_input_runtime_set_options(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
    options: ?*const abi.OmniInputOptions,
) i32 {
    return input_runtime.omni_input_runtime_set_options_impl(runtime_owner, options);
}
export fn omni_input_runtime_submit_event(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
    event: ?*const abi.OmniInputEvent,
) i32 {
    return input_runtime.omni_input_runtime_submit_event_impl(runtime_owner, event);
}
export fn omni_input_runtime_query_registration_failures(
    runtime_owner: [*c]input_runtime.OmniInputRuntime,
    out_failures: [*c]abi.OmniInputRegistrationFailure,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    return input_runtime.omni_input_runtime_query_registration_failures_impl(
        runtime_owner,
        out_failures,
        out_capacity,
        out_written,
    );
}
export fn omni_niri_layout_context_set_interaction(
    context: [*c]layout_context.OmniNiriLayoutContext,
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    column_dropzones: [*c]const abi.OmniNiriColumnDropzoneMeta,
    column_count: usize,
) i32 {
    return layout_context.omni_niri_layout_context_set_interaction_impl(
        context,
        windows,
        window_count,
        column_dropzones,
        column_count,
    );
}
export fn omni_niri_layout_pass_v3(
    context: [*c]layout_context.OmniNiriLayoutContext,
    columns: [*c]const abi.OmniNiriColumnInput,
    column_count: usize,
    windows: [*c]const abi.OmniNiriWindowInput,
    window_count: usize,
    working_x: f64,
    working_y: f64,
    working_width: f64,
    working_height: f64,
    view_x: f64,
    view_y: f64,
    view_width: f64,
    view_height: f64,
    fullscreen_x: f64,
    fullscreen_y: f64,
    fullscreen_width: f64,
    fullscreen_height: f64,
    primary_gap: f64,
    secondary_gap: f64,
    view_start: f64,
    viewport_span: f64,
    workspace_offset: f64,
    scale: f64,
    orientation: u8,
    out_windows: [*c]abi.OmniNiriWindowOutput,
    out_window_count: usize,
    out_columns: [*c]abi.OmniNiriColumnOutput,
    out_column_count: usize,
) i32 {
    return layout_context.omni_niri_layout_pass_v3_impl(
        context,
        columns,
        column_count,
        windows,
        window_count,
        working_x,
        working_y,
        working_width,
        working_height,
        view_x,
        view_y,
        view_width,
        view_height,
        fullscreen_x,
        fullscreen_y,
        fullscreen_width,
        fullscreen_height,
        primary_gap,
        secondary_gap,
        view_start,
        viewport_span,
        workspace_offset,
        scale,
        orientation,
        out_windows,
        out_window_count,
        out_columns,
        out_column_count,
    );
}
export fn omni_niri_hit_test_tiled(
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    point_x: f64,
    point_y: f64,
    out_window_index: [*c]i64,
) i32 {
    return interaction.omni_niri_hit_test_tiled_impl(
        windows,
        window_count,
        point_x,
        point_y,
        out_window_index,
    );
}
export fn omni_niri_ctx_hit_test_tiled(
    context: [*c]const layout_context.OmniNiriLayoutContext,
    point_x: f64,
    point_y: f64,
    out_window_index: [*c]i64,
) i32 {
    return layout_context.omni_niri_ctx_hit_test_tiled_impl(
        context,
        point_x,
        point_y,
        out_window_index,
    );
}
export fn omni_niri_hit_test_resize(
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    point_x: f64,
    point_y: f64,
    threshold: f64,
    out_result: [*c]abi.OmniNiriResizeHitResult,
) i32 {
    return interaction.omni_niri_hit_test_resize_impl(
        windows,
        window_count,
        point_x,
        point_y,
        threshold,
        out_result,
    );
}
export fn omni_niri_ctx_hit_test_resize(
    context: [*c]const layout_context.OmniNiriLayoutContext,
    point_x: f64,
    point_y: f64,
    threshold: f64,
    out_result: [*c]abi.OmniNiriResizeHitResult,
) i32 {
    return layout_context.omni_niri_ctx_hit_test_resize_impl(
        context,
        point_x,
        point_y,
        threshold,
        out_result,
    );
}
export fn omni_niri_hit_test_move_target(
    windows: [*c]const abi.OmniNiriHitTestWindow,
    window_count: usize,
    point_x: f64,
    point_y: f64,
    excluding_window_index: i64,
    is_insert_mode: u8,
    out_result: [*c]abi.OmniNiriMoveTargetResult,
) i32 {
    return interaction.omni_niri_hit_test_move_target_impl(
        windows,
        window_count,
        point_x,
        point_y,
        excluding_window_index,
        is_insert_mode,
        out_result,
    );
}
export fn omni_niri_ctx_hit_test_move_target(
    context: [*c]const layout_context.OmniNiriLayoutContext,
    point_x: f64,
    point_y: f64,
    excluding_window_index: i64,
    is_insert_mode: u8,
    out_result: [*c]abi.OmniNiriMoveTargetResult,
) i32 {
    return layout_context.omni_niri_ctx_hit_test_move_target_impl(
        context,
        point_x,
        point_y,
        excluding_window_index,
        is_insert_mode,
        out_result,
    );
}
export fn omni_niri_insertion_dropzone(
    input: [*c]const abi.OmniNiriDropzoneInput,
    out_result: [*c]abi.OmniNiriDropzoneResult,
) i32 {
    return interaction.omni_niri_insertion_dropzone_impl(input, out_result);
}
export fn omni_niri_ctx_insertion_dropzone(
    context: [*c]const layout_context.OmniNiriLayoutContext,
    target_window_index: i64,
    gap: f64,
    insert_position: u8,
    out_result: [*c]abi.OmniNiriDropzoneResult,
) i32 {
    return layout_context.omni_niri_ctx_insertion_dropzone_impl(
        context,
        target_window_index,
        gap,
        insert_position,
        out_result,
    );
}
export fn omni_niri_ctx_seed_runtime_state(
    context: [*c]layout_context.OmniNiriLayoutContext,
    columns: [*c]const abi.OmniNiriRuntimeColumnState,
    column_count: usize,
    windows: [*c]const abi.OmniNiriRuntimeWindowState,
    window_count: usize,
) i32 {
    return layout_context.omni_niri_ctx_seed_runtime_state_impl(
        context,
        columns,
        column_count,
        windows,
        window_count,
    );
}
export fn omni_niri_ctx_apply_txn(
    source_context: [*c]layout_context.OmniNiriLayoutContext,
    target_context: [*c]layout_context.OmniNiriLayoutContext,
    request: [*c]const abi.OmniNiriTxnRequest,
    out_result: [*c]abi.OmniNiriTxnResult,
) i32 {
    return layout_context.omni_niri_ctx_apply_txn_impl(
        source_context,
        target_context,
        request,
        out_result,
    );
}
export fn omni_niri_ctx_export_delta(
    context: [*c]const layout_context.OmniNiriLayoutContext,
    out_export: [*c]abi.OmniNiriTxnDeltaExport,
) i32 {
    return layout_context.omni_niri_ctx_export_delta_impl(
        context,
        out_export,
    );
}
export fn omni_niri_runtime_create() [*c]runtime.OmniNiriRuntime {
    return runtime.omni_niri_runtime_create_impl();
}
export fn omni_niri_runtime_destroy(runtime_context: [*c]runtime.OmniNiriRuntime) void {
    runtime.omni_niri_runtime_destroy_impl(runtime_context);
}
export fn omni_niri_runtime_seed(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    request: [*c]const abi.OmniNiriRuntimeSeedRequest,
) i32 {
    return runtime.omni_niri_runtime_seed_impl(
        runtime_context,
        request,
    );
}
export fn omni_niri_runtime_apply_command(
    source_runtime: [*c]runtime.OmniNiriRuntime,
    target_runtime: [*c]runtime.OmniNiriRuntime,
    request: [*c]const abi.OmniNiriRuntimeCommandRequest,
    out_result: [*c]abi.OmniNiriRuntimeCommandResult,
) i32 {
    return runtime.omni_niri_runtime_apply_command_impl(
        source_runtime,
        target_runtime,
        request,
        out_result,
    );
}
export fn omni_niri_runtime_render_from_state(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    layout: [*c]layout_context.OmniNiriLayoutContext,
    request: [*c]const abi.OmniNiriRuntimeRenderFromStateRequest,
    out_output: [*c]abi.OmniNiriRuntimeRenderOutput,
) i32 {
    return runtime.omni_niri_runtime_render_from_state_impl(
        runtime_context,
        layout,
        request,
        out_output,
    );
}
export fn omni_niri_runtime_start_workspace_switch_animation(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    sample_time: f64,
) i32 {
    return runtime.omni_niri_runtime_start_workspace_switch_animation_impl(
        runtime_context,
        sample_time,
    );
}
export fn omni_niri_runtime_start_mutation_animation(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    sample_time: f64,
) i32 {
    return runtime.omni_niri_runtime_start_mutation_animation_impl(
        runtime_context,
        sample_time,
    );
}
export fn omni_niri_runtime_cancel_animation(
    runtime_context: [*c]runtime.OmniNiriRuntime,
) i32 {
    return runtime.omni_niri_runtime_cancel_animation_impl(runtime_context);
}
export fn omni_niri_runtime_animation_active(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    sample_time: f64,
    out_active: [*c]u8,
) i32 {
    return runtime.omni_niri_runtime_animation_active_impl(
        runtime_context,
        sample_time,
        out_active,
    );
}
export fn omni_niri_runtime_viewport_status(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    sample_time: f64,
    out_status: [*c]abi.OmniNiriRuntimeViewportStatus,
) i32 {
    return runtime.omni_niri_runtime_viewport_status_impl(
        runtime_context,
        sample_time,
        out_status,
    );
}
export fn omni_niri_runtime_viewport_begin_gesture(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    sample_time: f64,
    is_trackpad: u8,
) i32 {
    return runtime.omni_niri_runtime_viewport_begin_gesture_impl(
        runtime_context,
        sample_time,
        is_trackpad,
    );
}
export fn omni_niri_runtime_viewport_update_gesture(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    delta_pixels: f64,
    timestamp: f64,
    gap: f64,
    viewport_span: f64,
    out_result: [*c]abi.OmniViewportGestureUpdateResult,
) i32 {
    return runtime.omni_niri_runtime_viewport_update_gesture_impl(
        runtime_context,
        delta_pixels,
        timestamp,
        gap,
        viewport_span,
        out_result,
    );
}
export fn omni_niri_runtime_viewport_end_gesture(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    gap: f64,
    viewport_span: f64,
    center_mode: u8,
    always_center_single_column: u8,
    sample_time: f64,
    display_refresh_rate: f64,
    reduce_motion: u8,
    out_result: [*c]abi.OmniViewportGestureEndResult,
) i32 {
    return runtime.omni_niri_runtime_viewport_end_gesture_impl(
        runtime_context,
        gap,
        viewport_span,
        center_mode,
        always_center_single_column,
        sample_time,
        display_refresh_rate,
        reduce_motion,
        out_result,
    );
}
export fn omni_niri_runtime_viewport_transition_to_column(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    requested_index: usize,
    gap: f64,
    viewport_span: f64,
    center_mode: u8,
    always_center_single_column: u8,
    animate: u8,
    scale: f64,
    sample_time: f64,
    display_refresh_rate: f64,
    reduce_motion: u8,
    out_result: [*c]abi.OmniViewportTransitionResult,
) i32 {
    return runtime.omni_niri_runtime_viewport_transition_to_column_impl(
        runtime_context,
        requested_index,
        gap,
        viewport_span,
        center_mode,
        always_center_single_column,
        animate,
        scale,
        sample_time,
        display_refresh_rate,
        reduce_motion,
        out_result,
    );
}
export fn omni_niri_runtime_viewport_set_offset(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    offset: f64,
) i32 {
    return runtime.omni_niri_runtime_viewport_set_offset_impl(
        runtime_context,
        offset,
    );
}
export fn omni_niri_runtime_viewport_cancel(
    runtime_context: [*c]runtime.OmniNiriRuntime,
    sample_time: f64,
) i32 {
    return runtime.omni_niri_runtime_viewport_cancel_impl(
        runtime_context,
        sample_time,
    );
}
export fn omni_niri_runtime_snapshot(
    runtime_context: [*c]const runtime.OmniNiriRuntime,
    out_export: [*c]abi.OmniNiriRuntimeStateExport,
) i32 {
    return runtime.omni_niri_runtime_snapshot_impl(
        runtime_context,
        out_export,
    );
}
export fn omni_controller_create(
    config: [*c]const abi.OmniControllerConfig,
    platform_vtable: [*c]const abi.OmniControllerPlatformVTable,
) [*c]controller_runtime.OmniController {
    return controller_runtime.omni_controller_create_impl(config, platform_vtable);
}
export fn omni_controller_destroy(controller: [*c]controller_runtime.OmniController) void {
    controller_runtime.omni_controller_destroy_impl(controller);
}
export fn omni_controller_start(controller: [*c]controller_runtime.OmniController) i32 {
    return controller_runtime.omni_controller_start_impl(controller);
}
export fn omni_controller_stop(controller: [*c]controller_runtime.OmniController) i32 {
    return controller_runtime.omni_controller_stop_impl(controller);
}
export fn omni_controller_submit_hotkey(
    controller: [*c]controller_runtime.OmniController,
    command: [*c]const abi.OmniControllerCommand,
) i32 {
    return controller_runtime.omni_controller_submit_hotkey_impl(controller, command);
}
export fn omni_controller_submit_os_event(
    controller: [*c]controller_runtime.OmniController,
    event: [*c]const abi.OmniControllerEvent,
) i32 {
    return controller_runtime.omni_controller_submit_os_event_impl(controller, event);
}
export fn omni_controller_apply_settings(
    controller: [*c]controller_runtime.OmniController,
    settings_delta: [*c]const abi.OmniControllerSettingsDelta,
) i32 {
    return controller_runtime.omni_controller_apply_settings_impl(controller, settings_delta);
}
export fn omni_controller_tick(
    controller: [*c]controller_runtime.OmniController,
    sample_time: f64,
) i32 {
    return controller_runtime.omni_controller_tick_impl(controller, sample_time);
}
export fn omni_controller_query_ui_state(
    controller: [*c]const controller_runtime.OmniController,
    out_state: [*c]abi.OmniControllerUiState,
) i32 {
    return controller_runtime.omni_controller_query_ui_state_impl(controller, out_state);
}
export fn omni_wm_controller_create(
    config: [*c]const abi.OmniWMControllerConfig,
    workspace_runtime_owner: [*c]workspace_runtime.OmniWorkspaceRuntime,
    host_vtable: [*c]const abi.OmniWMControllerHostVTable,
) [*c]wm_controller.OmniWMController {
    return wm_controller.omni_wm_controller_create_impl(
        config,
        workspace_runtime_owner,
        host_vtable,
    );
}
export fn omni_wm_controller_destroy(runtime_owner: [*c]wm_controller.OmniWMController) void {
    wm_controller.omni_wm_controller_destroy_impl(runtime_owner);
}
export fn omni_wm_controller_start(runtime_owner: [*c]wm_controller.OmniWMController) i32 {
    return wm_controller.omni_wm_controller_start_impl(runtime_owner);
}
export fn omni_wm_controller_stop(runtime_owner: [*c]wm_controller.OmniWMController) i32 {
    return wm_controller.omni_wm_controller_stop_impl(runtime_owner);
}
export fn omni_wm_controller_submit_hotkey(
    runtime_owner: [*c]wm_controller.OmniWMController,
    command: [*c]const abi.OmniControllerCommand,
) i32 {
    return wm_controller.omni_wm_controller_submit_hotkey_impl(runtime_owner, command);
}
export fn omni_wm_controller_submit_os_event(
    runtime_owner: [*c]wm_controller.OmniWMController,
    event: [*c]const abi.OmniControllerEvent,
) i32 {
    return wm_controller.omni_wm_controller_submit_os_event_impl(runtime_owner, event);
}
export fn omni_wm_controller_apply_settings(
    runtime_owner: [*c]wm_controller.OmniWMController,
    settings_delta: [*c]const abi.OmniControllerSettingsDelta,
) i32 {
    return wm_controller.omni_wm_controller_apply_settings_impl(runtime_owner, settings_delta);
}
export fn omni_wm_controller_tick(
    runtime_owner: [*c]wm_controller.OmniWMController,
    sample_time: f64,
) i32 {
    return wm_controller.omni_wm_controller_tick_impl(runtime_owner, sample_time);
}
export fn omni_wm_controller_query_ui_state(
    runtime_owner: [*c]const wm_controller.OmniWMController,
    out_state: [*c]abi.OmniControllerUiState,
) i32 {
    return wm_controller.omni_wm_controller_query_ui_state_impl(runtime_owner, out_state);
}
export fn omni_wm_controller_export_workspace_state(
    runtime_owner: [*c]wm_controller.OmniWMController,
    out_export: [*c]abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    return wm_controller.omni_wm_controller_export_workspace_state_impl(runtime_owner, out_export);
}
export fn omni_ui_bridge_submit_hotkey(
    runtime_owner: [*c]wm_controller.OmniWMController,
    command: [*c]const abi.OmniControllerCommand,
) i32 {
    return ui_bridge.omni_ui_bridge_submit_hotkey_impl(runtime_owner, command);
}
export fn omni_ui_bridge_apply_settings(
    runtime_owner: [*c]wm_controller.OmniWMController,
    settings_delta: [*c]const abi.OmniControllerSettingsDelta,
) i32 {
    return ui_bridge.omni_ui_bridge_apply_settings_impl(runtime_owner, settings_delta);
}
export fn omni_ui_bridge_query_ui_state(
    runtime_owner: [*c]const wm_controller.OmniWMController,
    out_state: [*c]abi.OmniControllerUiState,
) i32 {
    return ui_bridge.omni_ui_bridge_query_ui_state_impl(runtime_owner, out_state);
}
export fn omni_ui_bridge_export_workspace_state(
    runtime_owner: [*c]wm_controller.OmniWMController,
    out_export: [*c]abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    return ui_bridge.omni_ui_bridge_export_workspace_state_impl(runtime_owner, out_export);
}
export fn omni_service_lifecycle_create(
    config: [*c]const abi.OmniServiceLifecycleConfig,
    handles: [*c]const abi.OmniServiceLifecycleHandles,
    host_vtable: [*c]const abi.OmniServiceLifecycleHostVTable,
) [*c]service_lifecycle.OmniServiceLifecycle {
    return service_lifecycle.omni_service_lifecycle_create_impl(config, handles, host_vtable);
}
export fn omni_service_lifecycle_destroy(runtime_owner: [*c]service_lifecycle.OmniServiceLifecycle) void {
    service_lifecycle.omni_service_lifecycle_destroy_impl(runtime_owner);
}
export fn omni_service_lifecycle_start(runtime_owner: [*c]service_lifecycle.OmniServiceLifecycle) i32 {
    return service_lifecycle.omni_service_lifecycle_start_impl(runtime_owner);
}
export fn omni_service_lifecycle_stop(runtime_owner: [*c]service_lifecycle.OmniServiceLifecycle) i32 {
    return service_lifecycle.omni_service_lifecycle_stop_impl(runtime_owner);
}
export fn omni_service_lifecycle_query_state(
    runtime_owner: [*c]const service_lifecycle.OmniServiceLifecycle,
    out_state: [*c]u8,
) i32 {
    return service_lifecycle.omni_service_lifecycle_query_state_impl(runtime_owner, out_state);
}
export fn omni_focus_activate_application(pid: i32) i32 {
    return focus_manager.activateApplication(pid);
}
export fn omni_focus_raise_window(pid: i32, window_id: u32) i32 {
    return focus_manager.raiseWindow(pid, window_id);
}
export fn omni_focus_window(pid: i32, window_id: u32) i32 {
    return focus_manager.focusWindow(pid, window_id);
}
export fn omni_animation_cubic_ease_in_out(t: f64) f64 {
    return animation.cubicEaseInOut(t);
}
export fn omni_animation_spring_progress(
    t: f64,
    response: f64,
    damping_ratio: f64,
) f64 {
    return animation.springProgress(.{
        .response = response,
        .damping_ratio = damping_ratio,
    }, t);
}
export fn omni_mouse_gesture_early_exit_action(phase: u8) u8 {
    const resolved_phase = switch (phase) {
        0 => mouse_handler.GesturePhase.idle,
        1 => mouse_handler.GesturePhase.armed,
        2 => mouse_handler.GesturePhase.committed,
        else => mouse_handler.GesturePhase.idle,
    };
    const action = mouse_handler.earlyExitAction(resolved_phase);
    return switch (action) {
        .none => 0,
        .focus_follows_mouse => 1,
        .begin_drag => 2,
        .update_drag => 3,
        .end_drag => 4,
        .scroll => 5,
        .gesture => 6,
    };
}
export fn omni_dwindle_layout_context_create() [*c]dwindle.OmniDwindleLayoutContext {
    return dwindle.omni_dwindle_layout_context_create_impl();
}
export fn omni_dwindle_layout_context_destroy(context: [*c]dwindle.OmniDwindleLayoutContext) void {
    dwindle.omni_dwindle_layout_context_destroy_impl(context);
}
export fn omni_dwindle_ctx_seed_state(
    context: [*c]dwindle.OmniDwindleLayoutContext,
    nodes: [*c]const abi.OmniDwindleSeedNode,
    node_count: usize,
    seed_state: [*c]const abi.OmniDwindleSeedState,
) i32 {
    return dwindle.omni_dwindle_ctx_seed_state_impl(
        context,
        nodes,
        node_count,
        seed_state,
    );
}
export fn omni_dwindle_ctx_apply_op(
    context: [*c]dwindle.OmniDwindleLayoutContext,
    request: [*c]const abi.OmniDwindleOpRequest,
    out_result: [*c]abi.OmniDwindleOpResult,
    out_removed_window_ids: [*c]abi.OmniUuid128,
    out_removed_window_capacity: usize,
) i32 {
    return dwindle.omni_dwindle_ctx_apply_op_impl(
        context,
        request,
        out_result,
        out_removed_window_ids,
        out_removed_window_capacity,
    );
}
export fn omni_dwindle_ctx_calculate_layout(
    context: [*c]dwindle.OmniDwindleLayoutContext,
    request: [*c]const abi.OmniDwindleLayoutRequest,
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
    out_frames: [*c]abi.OmniDwindleWindowFrame,
    out_frame_capacity: usize,
    out_frame_count: [*c]usize,
) i32 {
    return dwindle.omni_dwindle_ctx_calculate_layout_impl(
        context,
        request,
        constraints,
        constraint_count,
        out_frames,
        out_frame_capacity,
        out_frame_count,
    );
}
export fn omni_dwindle_ctx_find_neighbor(
    context: [*c]const dwindle.OmniDwindleLayoutContext,
    window_id: abi.OmniUuid128,
    direction: u8,
    inner_gap: f64,
    out_has_neighbor: [*c]u8,
    out_neighbor_window_id: [*c]abi.OmniUuid128,
) i32 {
    return dwindle.omni_dwindle_ctx_find_neighbor_impl(
        context,
        window_id,
        direction,
        inner_gap,
        out_has_neighbor,
        out_neighbor_window_id,
    );
}
export fn omni_niri_resize_compute(
    input: [*c]const abi.OmniNiriResizeInput,
    out_result: [*c]abi.OmniNiriResizeResult,
) i32 {
    return interaction.omni_niri_resize_compute_impl(input, out_result);
}
export fn omni_viewport_compute_visible_offset(
    spans: [*c]const f64,
    span_count: usize,
    container_index: usize,
    gap: f64,
    viewport_span: f64,
    current_view_start: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    out_target_offset: [*c]f64,
) i32 {
    return viewport.omni_viewport_compute_visible_offset_impl(
        spans,
        span_count,
        container_index,
        gap,
        viewport_span,
        current_view_start,
        center_mode,
        always_center_single_column,
        from_container_index,
        out_target_offset,
    );
}
export fn omni_viewport_transition_to_column(
    spans: [*c]const f64,
    span_count: usize,
    current_active_index: usize,
    requested_index: usize,
    gap: f64,
    viewport_span: f64,
    current_target_offset: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    scale: f64,
    out_result: [*c]abi.OmniViewportTransitionResult,
) i32 {
    return viewport.omni_viewport_transition_to_column_impl(
        spans,
        span_count,
        current_active_index,
        requested_index,
        gap,
        viewport_span,
        current_target_offset,
        center_mode,
        always_center_single_column,
        from_container_index,
        scale,
        out_result,
    );
}
export fn omni_viewport_ensure_visible(
    spans: [*c]const f64,
    span_count: usize,
    active_container_index: usize,
    target_container_index: usize,
    gap: f64,
    viewport_span: f64,
    current_offset: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    epsilon: f64,
    out_result: [*c]abi.OmniViewportEnsureVisibleResult,
) i32 {
    return viewport.omni_viewport_ensure_visible_impl(
        spans,
        span_count,
        active_container_index,
        target_container_index,
        gap,
        viewport_span,
        current_offset,
        center_mode,
        always_center_single_column,
        from_container_index,
        epsilon,
        out_result,
    );
}
export fn omni_viewport_scroll_step(
    spans: [*c]const f64,
    span_count: usize,
    delta_pixels: f64,
    viewport_span: f64,
    gap: f64,
    current_offset: f64,
    selection_progress: f64,
    change_selection: u8,
    out_result: [*c]abi.OmniViewportScrollResult,
) i32 {
    return viewport.omni_viewport_scroll_step_impl(
        spans,
        span_count,
        delta_pixels,
        viewport_span,
        gap,
        current_offset,
        selection_progress,
        change_selection,
        out_result,
    );
}
export fn omni_viewport_gesture_begin(
    current_view_offset: f64,
    is_trackpad: u8,
    out_state: [*c]abi.OmniViewportGestureState,
) i32 {
    return viewport.omni_viewport_gesture_begin_impl(
        current_view_offset,
        is_trackpad,
        out_state,
    );
}
export fn omni_viewport_gesture_velocity(
    gesture_state: [*c]const abi.OmniViewportGestureState,
    out_velocity: [*c]f64,
) i32 {
    return viewport.omni_viewport_gesture_velocity_impl(
        gesture_state,
        out_velocity,
    );
}
export fn omni_viewport_gesture_update(
    gesture_state: [*c]abi.OmniViewportGestureState,
    spans: [*c]const f64,
    span_count: usize,
    active_container_index: usize,
    delta_pixels: f64,
    timestamp: f64,
    gap: f64,
    viewport_span: f64,
    selection_progress: f64,
    out_result: [*c]abi.OmniViewportGestureUpdateResult,
) i32 {
    return viewport.omni_viewport_gesture_update_impl(
        gesture_state,
        spans,
        span_count,
        active_container_index,
        delta_pixels,
        timestamp,
        gap,
        viewport_span,
        selection_progress,
        out_result,
    );
}
export fn omni_viewport_gesture_end(
    gesture_state: [*c]const abi.OmniViewportGestureState,
    spans: [*c]const f64,
    span_count: usize,
    active_container_index: usize,
    gap: f64,
    viewport_span: f64,
    center_mode: u8,
    always_center_single_column: u8,
    out_result: [*c]abi.OmniViewportGestureEndResult,
) i32 {
    return viewport.omni_viewport_gesture_end_impl(
        gesture_state,
        spans,
        span_count,
        active_container_index,
        gap,
        viewport_span,
        center_mode,
        always_center_single_column,
        out_result,
    );
}
