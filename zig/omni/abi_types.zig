pub const OmniAxisInput = extern struct {
    weight: f64,
    min_constraint: f64,
    max_constraint: f64,
    has_max_constraint: u8,
    is_constraint_fixed: u8,
    has_fixed_value: u8,
    fixed_value: f64,
};
pub const OmniAxisOutput = extern struct {
    value: f64,
    was_constrained: u8,
};
pub const OmniSnapResult = extern struct {
    view_pos: f64,
    column_index: usize,
};
pub const OmniViewportGestureState = extern struct {
    is_trackpad: u8,
    history_count: usize,
    history_head: usize,
    tracker_position: f64,
    current_view_offset: f64,
    stationary_view_offset: f64,
    delta_from_tracker: f64,
    history_deltas: [OMNI_VIEWPORT_GESTURE_HISTORY_CAP]f64,
    history_timestamps: [OMNI_VIEWPORT_GESTURE_HISTORY_CAP]f64,
};
pub const OmniViewportTransitionResult = extern struct {
    resolved_column_index: usize,
    offset_delta: f64,
    adjusted_target_offset: f64,
    target_offset: f64,
    snap_delta: f64,
    snap_to_target_immediately: u8,
};
pub const OmniViewportEnsureVisibleResult = extern struct {
    target_offset: f64,
    offset_delta: f64,
    is_noop: u8,
};
pub const OmniViewportScrollResult = extern struct {
    applied: u8,
    new_offset: f64,
    selection_progress: f64,
    has_selection_steps: u8,
    selection_steps: i64,
};
pub const OmniViewportGestureUpdateResult = extern struct {
    current_view_offset: f64,
    selection_progress: f64,
    has_selection_steps: u8,
    selection_steps: i64,
};
pub const OmniViewportGestureEndResult = extern struct {
    resolved_column_index: usize,
    spring_from: f64,
    spring_to: f64,
    initial_velocity: f64,
};
pub const OmniNiriRuntimeViewportStatus = extern struct {
    current_offset: f64,
    target_offset: f64,
    active_column_index: i64,
    selection_progress: f64,
    is_gesture: u8,
    is_animating: u8,
};
pub const OmniBorderColor = extern struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};
pub const OmniBorderConfig = extern struct {
    enabled: u8,
    width: f64,
    color: OmniBorderColor,
};
pub const OmniBorderRect = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};
pub const OmniBorderDisplayInfo = extern struct {
    display_id: u32,
    appkit_frame: OmniBorderRect,
    window_server_frame: OmniBorderRect,
    backing_scale: f64,
};
pub const OmniBorderPresentationInput = extern struct {
    config: OmniBorderConfig,
    has_focused_window_id: u8,
    focused_window_id: i64,
    has_focused_frame: u8,
    focused_frame: OmniBorderRect,
    is_focused_window_in_active_workspace: u8,
    is_non_managed_focus_active: u8,
    is_native_fullscreen_active: u8,
    is_managed_fullscreen_active: u8,
    defer_updates: u8,
    update_mode: u8,
    layout_animation_active: u8,
    displays: [*c]const OmniBorderDisplayInfo,
    display_count: usize,
};
pub const OmniBorderSnapshotInput = extern struct {
    config: OmniBorderConfig,
    has_focused_window_id: u8,
    focused_window_id: i64,
    has_focused_frame: u8,
    focused_frame: OmniBorderRect,
    is_focused_window_in_active_workspace: u8,
    is_non_managed_focus_active: u8,
    is_native_fullscreen_active: u8,
    is_managed_fullscreen_active: u8,
    defer_updates: u8,
    update_mode: u8,
    layout_animation_active: u8,
    force_hide: u8,
    displays: [*c]const OmniBorderDisplayInfo,
    display_count: usize,
};
pub const OmniBorderMotionInput = extern struct {
    focused_window_id: i64,
    focused_frame: OmniBorderRect,
    update_mode: u8,
    displays: [*c]const OmniBorderDisplayInfo,
    display_count: usize,
};
pub const OmniSkyLightCapabilities = extern struct {
    has_main_connection_id: u8,
    has_window_query_windows: u8,
    has_window_query_result_copy_windows: u8,
    has_window_iterator_advance: u8,
    has_window_iterator_get_bounds: u8,
    has_window_iterator_get_window_id: u8,
    has_window_iterator_get_pid: u8,
    has_window_iterator_get_level: u8,
    has_window_iterator_get_tags: u8,
    has_window_iterator_get_attributes: u8,
    has_window_iterator_get_parent_id: u8,
    has_transaction_create: u8,
    has_transaction_commit: u8,
    has_transaction_order_window: u8,
    has_transaction_move_window_with_group: u8,
    has_transaction_set_window_level: u8,
    has_move_window: u8,
    has_get_window_bounds: u8,
    has_disable_update: u8,
    has_reenable_update: u8,
    has_new_window: u8,
    has_release_window: u8,
    has_window_context_create: u8,
    has_set_window_shape: u8,
    has_set_window_resolution: u8,
    has_set_window_opacity: u8,
    has_set_window_tags: u8,
    has_flush_window_content_region: u8,
    has_new_region_with_rect: u8,
    has_register_connection_notify_proc: u8,
    has_unregister_connection_notify_proc: u8,
    has_request_notifications_for_windows: u8,
    has_register_notify_proc: u8,
    has_unregister_notify_proc: u8,
};
pub const OmniPrivateCapabilities = extern struct {
    has_set_front_process_with_options: u8,
    has_post_event_record_to: u8,
    has_get_process_for_pid: u8,
    has_ax_get_window: u8,
};
pub const OmniSkyLightWindowInfo = extern struct {
    id: u32,
    pid: i32,
    level: i32,
    frame: OmniBorderRect,
    tags: u64,
    attributes: u32,
    parent_id: u32,
};
pub const OmniSkyLightMoveRequest = extern struct {
    window_id: u32,
    origin_x: f64,
    origin_y: f64,
};
pub const OmniPlatformRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniPlatformRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniPlatformHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_window_created: ?*const fn (?*anyopaque, u32, u64) callconv(.c) i32,
    on_window_destroyed: ?*const fn (?*anyopaque, u32, u64) callconv(.c) i32,
    on_window_closed: ?*const fn (?*anyopaque, u32) callconv(.c) i32,
    on_window_moved: ?*const fn (?*anyopaque, u32) callconv(.c) i32,
    on_window_resized: ?*const fn (?*anyopaque, u32) callconv(.c) i32,
    on_front_app_changed: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
    on_window_title_changed: ?*const fn (?*anyopaque, u32) callconv(.c) i32,
};
pub const OmniMonitorRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniMonitorRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniMonitorHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_displays_changed: ?*const fn (?*anyopaque, u32, u32) callconv(.c) i32,
};
pub const OmniWorkspaceObserverRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniWorkspaceObserverRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniWorkspaceObserverHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_app_launched: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
    on_app_terminated: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
    on_app_activated: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
    on_app_hidden: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
    on_app_unhidden: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
    on_active_space_changed: ?*const fn (?*anyopaque) callconv(.c) i32,
};
pub const OmniLockObserverRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniLockObserverRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniLockObserverHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_locked: ?*const fn (?*anyopaque) callconv(.c) i32,
    on_unlocked: ?*const fn (?*anyopaque) callconv(.c) i32,
};
pub const OmniAXRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniAXRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniAXHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_window_destroyed: ?*const fn (?*anyopaque, i32, u32) callconv(.c) i32,
    on_window_destroyed_unknown: ?*const fn (?*anyopaque) callconv(.c) i32,
    on_focused_window_changed: ?*const fn (?*anyopaque, i32) callconv(.c) i32,
};
pub const OmniAXWindowRecord = extern struct {
    pid: i32,
    window_id: u32,
    window_type: u8,
};
pub const OmniAXFrameRequest = extern struct {
    pid: i32,
    window_id: u32,
    frame: OmniBorderRect,
};
pub const OmniAXWindowKey = extern struct {
    pid: i32,
    window_id: u32,
};
pub const OmniAXWindowTypeRequest = extern struct {
    pid: i32,
    window_id: u32,
    app_policy: i32,
    force_floating: u8,
};
pub const OmniAXWindowConstraints = extern struct {
    min_width: f64,
    min_height: f64,
    max_width: f64,
    max_height: f64,
    has_max_width: u8,
    has_max_height: u8,
    is_fixed: u8,
};
pub const OmniWorkspaceRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniWorkspaceRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniWorkspaceRuntimeName = extern struct {
    length: u8,
    bytes: [OMNI_WORKSPACE_RUNTIME_NAME_CAP]u8,
};
pub const OmniMonitorRecord = extern struct {
    display_id: u32,
    is_main: u8,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    visible_x: f64,
    visible_y: f64,
    visible_width: f64,
    visible_height: f64,
    has_notch: u8,
    backing_scale: f64,
    name: OmniWorkspaceRuntimeName,
};
pub const OmniWorkspaceRuntimeMonitorSnapshot = extern struct {
    display_id: u32,
    is_main: u8,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    visible_x: f64,
    visible_y: f64,
    visible_width: f64,
    visible_height: f64,
    name: OmniWorkspaceRuntimeName,
};
pub const OmniWorkspaceRuntimeMonitorAssignment = extern struct {
    workspace_name: OmniWorkspaceRuntimeName,
    assignment_kind: u8,
    sequence_number: i32,
    monitor_pattern: OmniWorkspaceRuntimeName,
};
pub const OmniWorkspaceRuntimeSettingsImport = extern struct {
    persistent_names: [*c]const OmniWorkspaceRuntimeName,
    persistent_name_count: usize,
    monitor_assignments: [*c]const OmniWorkspaceRuntimeMonitorAssignment,
    monitor_assignment_count: usize,
};
pub const OmniWorkspaceRuntimeMonitorRecord = extern struct {
    display_id: u32,
    is_main: u8,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    visible_x: f64,
    visible_y: f64,
    visible_width: f64,
    visible_height: f64,
    name: OmniWorkspaceRuntimeName,
    has_active_workspace_id: u8,
    active_workspace_id: OmniUuid128,
    has_previous_workspace_id: u8,
    previous_workspace_id: OmniUuid128,
};
pub const OmniWorkspaceRuntimeWorkspaceRecord = extern struct {
    workspace_id: OmniUuid128,
    name: OmniWorkspaceRuntimeName,
    has_assigned_monitor_anchor: u8,
    assigned_monitor_anchor_x: f64,
    assigned_monitor_anchor_y: f64,
    has_assigned_display_id: u8,
    assigned_display_id: u32,
    is_visible: u8,
    is_previous_visible: u8,
    is_persistent: u8,
};
pub const OmniWorkspaceRuntimeWindowKey = extern struct {
    pid: i32,
    window_id: i64,
};
pub const OmniWorkspaceRuntimeWindowHiddenState = extern struct {
    proportional_x: f64,
    proportional_y: f64,
    has_reference_display_id: u8,
    reference_display_id: u32,
    workspace_inactive: u8,
};
pub const OmniWorkspaceRuntimeWindowUpsert = extern struct {
    pid: i32,
    window_id: i64,
    workspace_id: OmniUuid128,
    has_handle_id: u8,
    handle_id: OmniUuid128,
};
pub const OmniWorkspaceRuntimeWindowRecord = extern struct {
    handle_id: OmniUuid128,
    pid: i32,
    window_id: i64,
    workspace_id: OmniUuid128,
    has_hidden_state: u8,
    hidden_state: OmniWorkspaceRuntimeWindowHiddenState,
    layout_reason: u8,
};
pub const OmniWorkspaceRuntimeStateExport = extern struct {
    monitors: [*c]const OmniWorkspaceRuntimeMonitorRecord,
    monitor_count: usize,
    workspaces: [*c]const OmniWorkspaceRuntimeWorkspaceRecord,
    workspace_count: usize,
    windows: [*c]const OmniWorkspaceRuntimeWindowRecord,
    window_count: usize,
    has_active_monitor_display_id: u8,
    active_monitor_display_id: u32,
    has_previous_monitor_display_id: u8,
    previous_monitor_display_id: u32,
};
pub const OmniWorkspaceRuntimeStateCounts = extern struct {
    monitor_count: usize,
    workspace_count: usize,
    window_count: usize,
};
pub const OmniNiriColumnInput = extern struct {
    span: f64,
    render_offset_x: f64,
    render_offset_y: f64,
    is_tabbed: u8,
    tab_indicator_width: f64,
    window_start: usize,
    window_count: usize,
};
pub const OmniNiriWindowInput = extern struct {
    weight: f64,
    min_constraint: f64,
    max_constraint: f64,
    has_max_constraint: u8,
    is_constraint_fixed: u8,
    has_fixed_value: u8,
    fixed_value: f64,
    sizing_mode: u8,
    render_offset_x: f64,
    render_offset_y: f64,
};
pub const OmniNiriWindowOutput = extern struct {
    window_id: OmniUuid128,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    animated_x: f64,
    animated_y: f64,
    animated_width: f64,
    animated_height: f64,
    resolved_span: f64,
    was_constrained: u8,
    hide_side: u8,
    column_index: usize,
};
pub const OmniNiriColumnOutput = extern struct {
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    hide_side: u8,
    is_visible: u8,
};
pub const OmniNiriHitTestWindow = extern struct {
    window_index: usize,
    column_index: usize,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    is_fullscreen: u8,
};
pub const OmniNiriColumnDropzoneMeta = extern struct {
    is_valid: u8,
    min_y: f64,
    max_y: f64,
    post_insertion_count: usize,
};
pub const OmniNiriResizeHitResult = extern struct {
    window_index: i64,
    edges: u8,
};
pub const OmniNiriMoveTargetResult = extern struct {
    window_index: i64,
    insert_position: u8,
};
pub const OmniNiriDropzoneInput = extern struct {
    target_frame_x: f64,
    target_frame_y: f64,
    target_frame_width: f64,
    target_frame_height: f64,
    column_min_y: f64,
    column_max_y: f64,
    gap: f64,
    insert_position: u8,
    post_insertion_count: usize,
};
pub const OmniNiriDropzoneResult = extern struct {
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    is_valid: u8,
};
pub const OmniNiriResizeInput = extern struct {
    edges: u8,
    start_x: f64,
    start_y: f64,
    current_x: f64,
    current_y: f64,
    original_column_width: f64,
    min_column_width: f64,
    max_column_width: f64,
    original_window_weight: f64,
    min_window_weight: f64,
    max_window_weight: f64,
    pixels_per_weight: f64,
    has_original_view_offset: u8,
    original_view_offset: f64,
};
pub const OmniNiriResizeResult = extern struct {
    changed_width: u8,
    new_column_width: f64,
    changed_weight: u8,
    new_window_weight: f64,
    adjust_view_offset: u8,
    new_view_offset: f64,
};
pub const OmniUuid128 = extern struct {
    bytes: [16]u8,
};
pub const OmniNiriStateColumnInput = extern struct {
    column_id: OmniUuid128,
    window_start: usize,
    window_count: usize,
    active_tile_idx: usize,
    is_tabbed: u8,
    size_value: f64,
    width_kind: u8,
    is_full_width: u8,
    has_saved_width: u8,
    saved_width_kind: u8,
    saved_width_value: f64,
};
pub const OmniNiriStateWindowInput = extern struct {
    window_id: OmniUuid128,
    column_id: OmniUuid128,
    column_index: usize,
    size_value: f64,
    height_kind: u8,
    height_value: f64,
};
pub const OmniNiriRuntimeColumnState = extern struct {
    column_id: OmniUuid128,
    window_start: usize,
    window_count: usize,
    active_tile_idx: usize,
    is_tabbed: u8,
    size_value: f64,
    width_kind: u8,
    is_full_width: u8,
    has_saved_width: u8,
    saved_width_kind: u8,
    saved_width_value: f64,
};
pub const OmniNiriRuntimeWindowState = extern struct {
    window_id: OmniUuid128,
    column_id: OmniUuid128,
    column_index: usize,
    size_value: f64,
    height_kind: u8,
    height_value: f64,
};
pub const OmniNiriRuntimeStateExport = extern struct {
    columns: [*c]const OmniNiriRuntimeColumnState,
    column_count: usize,
    windows: [*c]const OmniNiriRuntimeWindowState,
    window_count: usize,
};
pub const OmniNiriDeltaColumnRecord = extern struct {
    column_id: OmniUuid128,
    order_index: usize,
    window_start: usize,
    window_count: usize,
    active_tile_idx: usize,
    is_tabbed: u8,
    size_value: f64,
    width_kind: u8,
    is_full_width: u8,
    has_saved_width: u8,
    saved_width_kind: u8,
    saved_width_value: f64,
};
pub const OmniNiriDeltaWindowRecord = extern struct {
    window_id: OmniUuid128,
    column_id: OmniUuid128,
    column_order_index: usize,
    row_index: usize,
    size_value: f64,
    height_kind: u8,
    height_value: f64,
};
pub const OmniNiriTxnDeltaExport = extern struct {
    columns: [*c]const OmniNiriDeltaColumnRecord,
    column_count: usize,
    windows: [*c]const OmniNiriDeltaWindowRecord,
    window_count: usize,
    removed_column_ids: [*c]const OmniUuid128,
    removed_column_count: usize,
    removed_window_ids: [*c]const OmniUuid128,
    removed_window_count: usize,
    refresh_tabbed_visibility_count: u8,
    refresh_tabbed_visibility_column_ids: [OMNI_NIRI_RUNTIME_HINT_MAX_COLUMNS]OmniUuid128,
    reset_all_column_cached_widths: u8,
    has_delegate_move_column: u8,
    delegate_move_column_id: OmniUuid128,
    delegate_move_direction: u8,
    has_target_window_id: u8,
    target_window_id: OmniUuid128,
    has_target_node_id: u8,
    target_node_kind: u8,
    target_node_id: OmniUuid128,
    has_source_selection_window_id: u8,
    source_selection_window_id: OmniUuid128,
    has_target_selection_window_id: u8,
    target_selection_window_id: OmniUuid128,
    has_moved_window_id: u8,
    moved_window_id: OmniUuid128,
    generation: u64,
};
pub const OmniNiriStateValidationResult = extern struct {
    column_count: usize,
    window_count: usize,
    first_invalid_column_index: i64,
    first_invalid_window_index: i64,
    first_error_code: i32,
};
pub const OmniNiriNavigationRequest = extern struct {
    op: u8,
    direction: u8,
    orientation: u8,
    infinite_loop: u8,
    selected_window_index: i64,
    selected_column_index: i64,
    selected_row_index: i64,
    step: i64,
    target_row_index: i64,
    target_column_index: i64,
    target_window_index: i64,
};
pub const OmniNiriNavigationResult = extern struct {
    has_target: u8,
    target_window_index: i64,
    update_source_active_tile: u8,
    source_column_index: i64,
    source_active_tile_idx: i64,
    update_target_active_tile: u8,
    target_column_index: i64,
    target_active_tile_idx: i64,
    refresh_tabbed_visibility_source: u8,
    refresh_tabbed_visibility_target: u8,
};
pub const OmniNiriNavigationApplyRequest = extern struct {
    request: OmniNiriNavigationRequest,
};
pub const OmniNiriNavigationApplyResult = extern struct {
    applied: u8,
    has_target_window_id: u8,
    target_window_id: OmniUuid128,
    update_source_active_tile: u8,
    source_column_id: OmniUuid128,
    source_active_tile_idx: i64,
    update_target_active_tile: u8,
    target_column_id: OmniUuid128,
    target_active_tile_idx: i64,
    refresh_tabbed_visibility_source: u8,
    refresh_source_column_id: OmniUuid128,
    refresh_tabbed_visibility_target: u8,
    refresh_target_column_id: OmniUuid128,
};
pub const OmniNiriMutationRequest = extern struct {
    op: u8,
    direction: u8,
    infinite_loop: u8,
    insert_position: u8,
    source_window_index: i64,
    target_window_index: i64,
    max_windows_per_column: i64,
    source_column_index: i64,
    target_column_index: i64,
    insert_column_index: i64,
    max_visible_columns: i64,
    selected_node_kind: u8,
    selected_node_index: i64,
    focused_window_index: i64,
    incoming_spawn_mode: u8,
};
pub const OmniNiriMutationEdit = extern struct {
    kind: u8,
    subject_index: i64,
    related_index: i64,
    value_a: i64,
    value_b: i64,
    scalar_a: f64,
    scalar_b: f64,
};
pub const OmniNiriMutationResult = extern struct {
    applied: u8,
    has_target_window: u8,
    target_window_index: i64,
    has_target_node: u8,
    target_node_kind: u8,
    target_node_index: i64,
    edit_count: usize,
    edits: [OMNI_NIRI_MUTATION_MAX_EDITS]OmniNiriMutationEdit,
};
pub const OmniNiriMutationApplyRequest = extern struct {
    request: OmniNiriMutationRequest,
    has_incoming_window_id: u8,
    incoming_window_id: OmniUuid128,
    has_created_column_id: u8,
    created_column_id: OmniUuid128,
    has_placeholder_column_id: u8,
    placeholder_column_id: OmniUuid128,
};
pub const OmniNiriMutationApplyResult = extern struct {
    applied: u8,
    has_target_window_id: u8,
    target_window_id: OmniUuid128,
    has_target_node_id: u8,
    target_node_kind: u8,
    target_node_id: OmniUuid128,
    refresh_tabbed_visibility_count: u8,
    refresh_tabbed_visibility_column_ids: [OMNI_NIRI_RUNTIME_HINT_MAX_COLUMNS]OmniUuid128,
    reset_all_column_cached_widths: u8,
    has_delegate_move_column: u8,
    delegate_move_column_id: OmniUuid128,
    delegate_move_direction: u8,
};
pub const OmniNiriWorkspaceRequest = extern struct {
    op: u8,
    source_window_index: i64,
    source_column_index: i64,
    max_visible_columns: i64,
};
pub const OmniNiriWorkspaceEdit = extern struct {
    kind: u8,
    subject_index: i64,
    related_index: i64,
    value_a: i64,
    value_b: i64,
};
pub const OmniNiriWorkspaceResult = extern struct {
    applied: u8,
    edit_count: usize,
    edits: [OMNI_NIRI_WORKSPACE_MAX_EDITS]OmniNiriWorkspaceEdit,
};
pub const OmniNiriWorkspaceApplyRequest = extern struct {
    request: OmniNiriWorkspaceRequest,
    has_target_created_column_id: u8,
    target_created_column_id: OmniUuid128,
    has_source_placeholder_column_id: u8,
    source_placeholder_column_id: OmniUuid128,
};
pub const OmniNiriWorkspaceApplyResult = extern struct {
    applied: u8,
    has_source_selection_window_id: u8,
    source_selection_window_id: OmniUuid128,
    has_target_selection_window_id: u8,
    target_selection_window_id: OmniUuid128,
    has_moved_window_id: u8,
    moved_window_id: OmniUuid128,
};
pub const OmniNiriTxnNavigationPayload = extern struct {
    op: u8,
    direction: u8,
    orientation: u8,
    infinite_loop: u8,
    has_source_window_id: u8,
    source_window_id: OmniUuid128,
    has_source_column_id: u8,
    source_column_id: OmniUuid128,
    has_target_window_id: u8,
    target_window_id: OmniUuid128,
    has_target_column_id: u8,
    target_column_id: OmniUuid128,
    step: i64,
    target_row_index: i64,
    focus_column_index: i64,
    focus_window_index: i64,
};
pub const OmniNiriTxnMutationPayload = extern struct {
    op: u8,
    direction: u8,
    infinite_loop: u8,
    insert_position: u8,
    has_source_window_id: u8,
    source_window_id: OmniUuid128,
    has_target_window_id: u8,
    target_window_id: OmniUuid128,
    max_windows_per_column: i64,
    has_source_column_id: u8,
    source_column_id: OmniUuid128,
    has_target_column_id: u8,
    target_column_id: OmniUuid128,
    insert_column_index: i64,
    max_visible_columns: i64,
    has_selected_node_id: u8,
    selected_node_id: OmniUuid128,
    has_focused_window_id: u8,
    focused_window_id: OmniUuid128,
    incoming_spawn_mode: u8,
    has_incoming_window_id: u8,
    incoming_window_id: OmniUuid128,
    has_created_column_id: u8,
    created_column_id: OmniUuid128,
    has_placeholder_column_id: u8,
    placeholder_column_id: OmniUuid128,
    custom_u8_a: u8,
    custom_u8_b: u8,
    custom_i64_a: i64,
    custom_i64_b: i64,
    custom_f64_a: f64,
    custom_f64_b: f64,
};
pub const OmniNiriTxnWorkspacePayload = extern struct {
    op: u8,
    has_source_window_id: u8,
    source_window_id: OmniUuid128,
    has_source_column_id: u8,
    source_column_id: OmniUuid128,
    max_visible_columns: i64,
    has_target_created_column_id: u8,
    target_created_column_id: OmniUuid128,
    has_source_placeholder_column_id: u8,
    source_placeholder_column_id: OmniUuid128,
};
pub const OmniNiriTxnRequest = extern struct {
    kind: u8,
    navigation: OmniNiriTxnNavigationPayload,
    mutation: OmniNiriTxnMutationPayload,
    workspace: OmniNiriTxnWorkspacePayload,
    max_delta_columns: usize,
    max_delta_windows: usize,
    max_removed_ids: usize,
};
pub const OmniNiriTxnResult = extern struct {
    applied: u8,
    kind: u8,
    structural_animation_active: u8,
    has_target_window_id: u8,
    target_window_id: OmniUuid128,
    has_target_node_id: u8,
    target_node_kind: u8,
    target_node_id: OmniUuid128,
    changed_source_context: u8,
    changed_target_context: u8,
    error_code: i32,
    delta_column_count: usize,
    delta_window_count: usize,
    removed_column_count: usize,
    removed_window_count: usize,
};
pub const OmniNiriRuntimeSeedRequest = extern struct {
    columns: [*c]const OmniNiriRuntimeColumnState,
    column_count: usize,
    windows: [*c]const OmniNiriRuntimeWindowState,
    window_count: usize,
};
pub const OmniNiriRuntimeCommandRequest = extern struct {
    txn: OmniNiriTxnRequest,
    sample_time: f64,
};
pub const OmniNiriRuntimeCommandResult = extern struct {
    txn: OmniNiriTxnResult,
};
pub const OmniNiriRuntimeRenderFromStateRequest = extern struct {
    expected_column_count: usize,
    expected_window_count: usize,
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
    viewport_span: f64,
    workspace_offset: f64,
    has_fullscreen_window_id: u8,
    fullscreen_window_id: OmniUuid128,
    scale: f64,
    orientation: u8,
    sample_time: f64,
};
pub const OmniNiriRuntimeRenderOutput = extern struct {
    windows: [*c]OmniNiriWindowOutput,
    window_count: usize,
    columns: [*c]OmniNiriColumnOutput,
    column_count: usize,
    animation_active: u8,
};
pub const OmniDwindleSeedNode = extern struct {
    node_id: OmniUuid128,
    parent_index: i64,
    first_child_index: i64,
    second_child_index: i64,
    kind: u8,
    orientation: u8,
    ratio: f64,
    has_window_id: u8,
    window_id: OmniUuid128,
    is_fullscreen: u8,
};
pub const OmniDwindleSeedState = extern struct {
    root_node_index: i64,
    selected_node_index: i64,
    has_preselection: u8,
    preselection_direction: u8,
};
pub const OmniDwindleRuntimeSettings = extern struct {
    smart_split: u8,
    default_split_ratio: f64,
    split_width_multiplier: f64,
    inner_gap: f64,
};
pub const OmniDwindleRect = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};
pub const OmniDwindleLayoutRequest = extern struct {
    screen_x: f64,
    screen_y: f64,
    screen_width: f64,
    screen_height: f64,
    inner_gap: f64,
    outer_gap_top: f64,
    outer_gap_bottom: f64,
    outer_gap_left: f64,
    outer_gap_right: f64,
    single_window_aspect_width: f64,
    single_window_aspect_height: f64,
    single_window_aspect_tolerance: f64,
    runtime_settings: OmniDwindleRuntimeSettings,
};
pub const OmniDwindleWindowConstraint = extern struct {
    window_id: OmniUuid128,
    min_width: f64,
    min_height: f64,
    max_width: f64,
    max_height: f64,
    has_max_width: u8,
    has_max_height: u8,
    is_fixed: u8,
};
pub const OmniDwindleWindowFrame = extern struct {
    window_id: OmniUuid128,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
};
pub const OmniDwindleAddWindowPayload = extern struct {
    window_id: OmniUuid128,
    has_active_window_frame: u8,
    active_window_frame: OmniDwindleRect,
};
pub const OmniDwindleRemoveWindowPayload = extern struct {
    window_id: OmniUuid128,
};
pub const OmniDwindleSyncWindowsPayload = extern struct {
    window_ids: [*c]const OmniUuid128,
    window_count: usize,
};
pub const OmniDwindleMoveFocusPayload = extern struct {
    direction: u8,
};
pub const OmniDwindleSwapWindowsPayload = extern struct {
    direction: u8,
};
pub const OmniDwindleToggleFullscreenPayload = extern struct {
    unused: u8,
};
pub const OmniDwindleToggleOrientationPayload = extern struct {
    unused: u8,
};
pub const OmniDwindleResizeSelectedPayload = extern struct {
    delta: f64,
    direction: u8,
};
pub const OmniDwindleBalanceSizesPayload = extern struct {
    unused: u8,
};
pub const OmniDwindleCycleSplitRatioPayload = extern struct {
    forward: u8,
};
pub const OmniDwindleMoveSelectionToRootPayload = extern struct {
    stable: u8,
};
pub const OmniDwindleSwapSplitPayload = extern struct {
    unused: u8,
};
pub const OmniDwindleSetPreselectionPayload = extern struct {
    direction: u8,
};
pub const OmniDwindleClearPreselectionPayload = extern struct {
    unused: u8,
};
pub const OmniDwindleValidateSelectionPayload = extern struct {
    unused: u8,
};
pub const OmniDwindleOpPayload = extern union {
    add_window: OmniDwindleAddWindowPayload,
    remove_window: OmniDwindleRemoveWindowPayload,
    sync_windows: OmniDwindleSyncWindowsPayload,
    move_focus: OmniDwindleMoveFocusPayload,
    swap_windows: OmniDwindleSwapWindowsPayload,
    toggle_fullscreen: OmniDwindleToggleFullscreenPayload,
    toggle_orientation: OmniDwindleToggleOrientationPayload,
    resize_selected: OmniDwindleResizeSelectedPayload,
    balance_sizes: OmniDwindleBalanceSizesPayload,
    cycle_split_ratio: OmniDwindleCycleSplitRatioPayload,
    move_selection_to_root: OmniDwindleMoveSelectionToRootPayload,
    swap_split: OmniDwindleSwapSplitPayload,
    set_preselection: OmniDwindleSetPreselectionPayload,
    clear_preselection: OmniDwindleClearPreselectionPayload,
    validate_selection: OmniDwindleValidateSelectionPayload,
};
pub const OmniDwindleOpRequest = extern struct {
    op: u8,
    payload: OmniDwindleOpPayload,
    runtime_settings: OmniDwindleRuntimeSettings,
};
pub const OmniDwindleOpResult = extern struct {
    applied: u8,
    has_selected_window_id: u8,
    selected_window_id: OmniUuid128,
    has_focused_window_id: u8,
    focused_window_id: OmniUuid128,
    has_preselection: u8,
    preselection_direction: u8,
    removed_window_count: usize,
};
pub const OmniControllerName = extern struct {
    length: u8,
    bytes: [OMNI_CONTROLLER_NAME_CAP]u8,
};
pub const OmniControllerMonitorSnapshot = extern struct {
    display_id: u32,
    is_main: u8,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    visible_x: f64,
    visible_y: f64,
    visible_width: f64,
    visible_height: f64,
    name: OmniControllerName,
};
pub const OmniControllerWorkspaceSnapshot = extern struct {
    workspace_id: OmniUuid128,
    has_assigned_display_id: u8,
    assigned_display_id: u32,
    is_visible: u8,
    is_previous_visible: u8,
    layout_kind: u8,
    name: OmniControllerName,
    has_selected_node_id: u8,
    selected_node_id: OmniUuid128,
    has_last_focused_window_id: u8,
    last_focused_window_id: OmniUuid128,
};
pub const OmniControllerWorkspaceProjectionRecord = extern struct {
    workspace_id: OmniUuid128,
    layout_generation: u64,
};
pub const OmniControllerWorkspaceProjectionCounts = extern struct {
    workspace_count: usize,
};
pub const OmniControllerWindowSnapshot = extern struct {
    handle_id: OmniUuid128,
    pid: i32,
    window_id: i64,
    workspace_id: OmniUuid128,
    layout_kind: u8,
    is_hidden: u8,
    is_focused: u8,
    is_managed: u8,
    has_node_id: u8,
    node_id: OmniUuid128,
    has_column_id: u8,
    column_id: OmniUuid128,
    order_index: i64,
    column_index: i64,
    row_index: i64,
};
pub const OmniControllerSnapshot = extern struct {
    monitors: [*c]const OmniControllerMonitorSnapshot,
    monitor_count: usize,
    workspaces: [*c]const OmniControllerWorkspaceSnapshot,
    workspace_count: usize,
    windows: [*c]const OmniControllerWindowSnapshot,
    window_count: usize,
    has_focused_window_id: u8,
    focused_window_id: OmniUuid128,
    has_active_monitor_display_id: u8,
    active_monitor_display_id: u32,
    has_previous_monitor_display_id: u8,
    previous_monitor_display_id: u32,
    secure_input_active: u8,
    lock_screen_active: u8,
    non_managed_focus_active: u8,
    app_fullscreen_active: u8,
    focus_follows_window_to_monitor: u8,
    move_mouse_to_focused_window: u8,
    layout_light_session_active: u8,
    layout_immediate_in_progress: u8,
    layout_incremental_in_progress: u8,
    layout_full_enumeration_in_progress: u8,
    layout_animation_active: u8,
    layout_has_completed_initial_refresh: u8,
};
pub const OmniControllerCommand = extern struct {
    kind: u8,
    direction: u8,
    workspace_index: i64,
    monitor_direction: u8,
    has_workspace_id: u8,
    workspace_id: OmniUuid128,
    has_window_handle_id: u8,
    window_handle_id: OmniUuid128,
    has_secondary_window_handle_id: u8 = 0,
    secondary_window_handle_id: OmniUuid128 = .{ .bytes = [_]u8{0} ** 16 },
};
pub const OmniInputRuntime = extern struct {
    _opaque: u8 = 0,
};
pub const OmniInputRuntimeConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniInputBindingId = extern struct {
    length: u8,
    bytes: [OMNI_INPUT_BINDING_ID_CAP]u8,
};
pub const OmniInputBinding = extern struct {
    binding_id: OmniInputBindingId,
    key_code: u32,
    modifiers: u32,
    enabled: u8,
};
pub const OmniInputOptions = extern struct {
    hotkeys_enabled: u8,
    mouse_enabled: u8,
    gestures_enabled: u8,
    secure_input_enabled: u8,
};
pub const OmniInputEvent = extern struct {
    kind: u8,
    reserved: [3]u8,
    location_x: f64,
    location_y: f64,
    delta_x: f64,
    delta_y: f64,
    momentum_phase: u32,
    phase: u32,
    modifiers: u64,
    event_ref: ?*anyopaque,
};
pub const OmniInputEffect = extern struct {
    kind: u8,
    reserved: [7]u8,
    event: OmniInputEvent,
};
pub const OmniInputEffectExport = extern struct {
    effects: [*c]const OmniInputEffect,
    effect_count: usize,
};
pub const OmniInputRegistrationFailure = extern struct {
    binding_id: OmniInputBindingId,
};
pub const OmniInputHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_hotkey_command: ?*const fn (?*anyopaque, OmniControllerCommand) callconv(.c) i32,
    on_secure_input_state_changed: ?*const fn (?*anyopaque, u8) callconv(.c) i32,
    on_mouse_effect_batch: ?*const fn (?*anyopaque, ?*const OmniInputEffectExport) callconv(.c) i32,
    on_tap_health_notification: ?*const fn (?*anyopaque, u8, u8) callconv(.c) i32,
};
pub const OmniControllerEvent = extern struct {
    kind: u8,
    enabled: u8,
    refresh_reason: u8,
    has_display_id: u8,
    display_id: u32,
    pid: i32,
    has_window_handle_id: u8,
    window_handle_id: OmniUuid128,
    has_workspace_id: u8,
    workspace_id: OmniUuid128,
};
pub const OmniControllerFocusExport = extern struct {
    has_active_monitor_display_id: u8,
    active_monitor_display_id: u32,
    has_previous_monitor_display_id: u8,
    previous_monitor_display_id: u32,
    has_workspace_id: u8,
    workspace_id: OmniUuid128,
    has_selected_node_id: u8,
    selected_node_id: OmniUuid128,
    has_focused_window_id: u8,
    focused_window_id: OmniUuid128,
    clear_focus: u8,
    non_managed_focus_active: u8,
    app_fullscreen_active: u8,
};
pub const OmniControllerRoutePlan = extern struct {
    kind: u8,
    create_target_workspace_if_missing: u8,
    animate_workspace_switch: u8,
    follow_focus: u8,
    has_source_display_id: u8,
    source_display_id: u32,
    has_target_display_id: u8,
    target_display_id: u32,
    has_source_workspace_id: u8,
    source_workspace_id: OmniUuid128,
    has_target_workspace_id: u8,
    target_workspace_id: OmniUuid128,
    source_workspace_name: OmniControllerName,
    target_workspace_name: OmniControllerName,
};
pub const OmniControllerTransferPlan = extern struct {
    kind: u8,
    mode: u8,
    create_target_workspace_if_missing: u8,
    follow_focus: u8,
    window_count: u8,
    window_ids: [OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS]OmniUuid128,
    has_source_workspace_id: u8,
    source_workspace_id: OmniUuid128,
    source_workspace_name: OmniControllerName,
    has_target_workspace_id: u8,
    target_workspace_id: OmniUuid128,
    target_workspace_name: OmniControllerName,
    has_target_monitor_display_id: u8,
    target_monitor_display_id: u32,
    has_source_fallback_window_id: u8,
    source_fallback_window_id: OmniUuid128,
    has_target_focus_window_id: u8,
    target_focus_window_id: OmniUuid128,
    has_source_selection_node_id: u8,
    source_selection_node_id: OmniUuid128,
    has_target_selection_node_id: u8,
    target_selection_node_id: OmniUuid128,
};
pub const OmniControllerRefreshPlan = extern struct {
    flags: u32,
    has_workspace_id: u8,
    workspace_id: OmniUuid128,
    has_display_id: u8,
    display_id: u32,
};
pub const OmniControllerUiAction = extern struct {
    kind: u8,
};
pub const OmniControllerLayoutAction = extern struct {
    kind: u8,
    direction: u8,
    index: i64,
    flag: u8,
    has_workspace_id: u8 = 0,
    workspace_id: OmniUuid128 = .{ .bytes = [_]u8{0} ** 16 },
    has_window_handle_id: u8 = 0,
    window_handle_id: OmniUuid128 = .{ .bytes = [_]u8{0} ** 16 },
    has_secondary_window_handle_id: u8 = 0,
    secondary_window_handle_id: OmniUuid128 = .{ .bytes = [_]u8{0} ** 16 },
};
pub const OmniControllerEffectExport = extern struct {
    focus_exports: [*c]const OmniControllerFocusExport,
    focus_export_count: usize,
    route_plans: [*c]const OmniControllerRoutePlan,
    route_plan_count: usize,
    transfer_plans: [*c]const OmniControllerTransferPlan,
    transfer_plan_count: usize,
    refresh_plans: [*c]const OmniControllerRefreshPlan,
    refresh_plan_count: usize,
    ui_actions: [*c]const OmniControllerUiAction,
    ui_action_count: usize,
    layout_actions: [*c]const OmniControllerLayoutAction,
    layout_action_count: usize,
};
pub const OmniControllerConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniControllerMonitorNiriSettings = extern struct {
    display_id: u32,
    orientation: u8,
    center_focused_column: u8,
    always_center_single_column: u8,
    single_window_aspect_width: f64,
    single_window_aspect_height: f64,
};
pub const OmniControllerMonitorDwindleSettings = extern struct {
    display_id: u32,
    smart_split: u8,
    default_split_ratio: f64,
    split_width_multiplier: f64,
    inner_gap: f64,
    outer_gap_top: f64,
    outer_gap_bottom: f64,
    outer_gap_left: f64,
    outer_gap_right: f64,
    single_window_aspect_width: f64,
    single_window_aspect_height: f64,
};
pub const OmniControllerWorkspaceLayoutSetting = extern struct {
    name: OmniControllerName,
    layout_kind: u8,
};
pub const OmniControllerSettingsDelta = extern struct {
    struct_size: usize,
    has_focus_follows_mouse: u8,
    focus_follows_mouse: u8,
    has_focus_follows_window_to_monitor: u8,
    focus_follows_window_to_monitor: u8,
    has_move_mouse_to_focused_window: u8,
    move_mouse_to_focused_window: u8,
    has_layout_gap: u8,
    layout_gap: f64,
    has_outer_gap_left: u8,
    outer_gap_left: f64,
    has_outer_gap_right: u8,
    outer_gap_right: f64,
    has_outer_gap_top: u8,
    outer_gap_top: f64,
    has_outer_gap_bottom: u8,
    outer_gap_bottom: f64,
    has_niri_max_visible_columns: u8,
    niri_max_visible_columns: i64,
    has_niri_max_windows_per_column: u8,
    niri_max_windows_per_column: i64,
    has_niri_infinite_loop: u8,
    niri_infinite_loop: u8,
    has_niri_width_presets: u8,
    niri_width_preset_count: usize,
    niri_width_presets: [OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP]f64,
    has_border_enabled: u8,
    border_enabled: u8,
    has_border_width: u8,
    border_width: f64,
    has_border_color: u8,
    border_color: OmniBorderColor,
    has_default_layout_kind: u8,
    default_layout_kind: u8,
    has_dwindle_move_to_root_stable: u8,
    dwindle_move_to_root_stable: u8,
    monitor_niri_settings: [*c]const OmniControllerMonitorNiriSettings,
    monitor_niri_settings_count: usize,
    monitor_dwindle_settings: [*c]const OmniControllerMonitorDwindleSettings,
    monitor_dwindle_settings_count: usize,
    workspace_layout_settings: [*c]const OmniControllerWorkspaceLayoutSetting,
    workspace_layout_settings_count: usize,
};
pub const OmniControllerUiState = extern struct {
    has_focused_window_id: u8,
    focused_window_id: OmniUuid128,
    has_active_monitor_display_id: u8,
    active_monitor_display_id: u32,
    has_previous_monitor_display_id: u8,
    previous_monitor_display_id: u32,
    secure_input_active: u8,
    lock_screen_active: u8,
    visible_workspace_count: usize,
    visible_workspace_ids: [OMNI_CONTROLLER_UI_WORKSPACE_CAP]OmniUuid128,
};
pub const OmniControllerPlatformVTable = extern struct {
    userdata: ?*anyopaque,
    capture_snapshot: ?*const fn (?*anyopaque, ?*OmniControllerSnapshot) callconv(.c) i32,
    apply_effects: ?*const fn (?*anyopaque, ?*const OmniControllerEffectExport) callconv(.c) i32,
    report_error: ?*const fn (?*anyopaque, i32, OmniControllerName) callconv(.c) i32,
};
pub const OmniWMController = extern struct {
    _opaque: u8 = 0,
};
pub const OmniWMControllerSnapshot = extern struct {
    _opaque: u8 = 0,
};
pub const OmniWMControllerConfig = extern struct {
    abi_version: u32,
    reserved: u32,
};
pub const OmniWMControllerSnapshotCounts = extern struct {
    monitor_count: usize,
    workspace_count: usize,
    window_count: usize,
    changed_workspace_count: usize,
    invalidate_all_workspace_projections: u8,
};
pub const OmniWMControllerHostVTable = extern struct {
    userdata: ?*anyopaque,
    apply_effects: ?*const fn (?*anyopaque, ?*const OmniControllerEffectExport) callconv(.c) i32,
    report_error: ?*const fn (?*anyopaque, i32, OmniControllerName) callconv(.c) i32,
};
pub const OmniServiceLifecycle = extern struct {
    _opaque: u8 = 0,
};
pub const OmniServiceLifecycleConfig = extern struct {
    abi_version: u32,
    poll_ax_permission: u8,
    request_ax_prompt: u8,
    reserved: [2]u8,
    ax_poll_timeout_millis: u32,
    ax_poll_interval_millis: u32,
};
pub const OmniServiceLifecycleHandles = extern struct {
    wm_controller: [*c]OmniWMController,
    input_runtime: [*c]OmniInputRuntime,
    platform_runtime: [*c]OmniPlatformRuntime,
    workspace_observer_runtime: [*c]OmniWorkspaceObserverRuntime,
    lock_observer_runtime: [*c]OmniLockObserverRuntime,
    ax_runtime: [*c]OmniAXRuntime,
    monitor_runtime: [*c]OmniMonitorRuntime,
};
pub const OmniServiceLifecycleHostVTable = extern struct {
    userdata: ?*anyopaque,
    on_state_changed: ?*const fn (?*anyopaque, u8) callconv(.c) i32,
    on_error: ?*const fn (?*anyopaque, i32, OmniControllerName) callconv(.c) i32,
    on_secure_input_state_changed: ?*const fn (?*anyopaque, u8) callconv(.c) i32,
    on_tap_health_notification: ?*const fn (?*anyopaque, u8, u8) callconv(.c) i32,
};
pub const MAX_WINDOWS: usize = 512;
pub const OMNI_OK: i32 = 0;
pub const OMNI_ERR_INVALID_ARGS: i32 = -1;
pub const OMNI_ERR_OUT_OF_RANGE: i32 = -2;
pub const OMNI_ERR_PLATFORM: i32 = -3;
pub const OMNI_ERR_UNSUPPORTED: i32 = -4;
pub const OMNI_BORDER_UPDATE_MODE_COALESCED: u8 = 0;
pub const OMNI_BORDER_UPDATE_MODE_REALTIME: u8 = 1;
pub const OMNI_CENTER_NEVER: u8 = 0;
pub const OMNI_CENTER_ALWAYS: u8 = 1;
pub const OMNI_CENTER_ON_OVERFLOW: u8 = 2;
pub const OMNI_VIEWPORT_GESTURE_HISTORY_CAP: usize = 64;
pub const OMNI_NIRI_ORIENTATION_HORIZONTAL: u8 = 0;
pub const OMNI_NIRI_ORIENTATION_VERTICAL: u8 = 1;
pub const OMNI_NIRI_SIZING_NORMAL: u8 = 0;
pub const OMNI_NIRI_SIZING_FULLSCREEN: u8 = 1;
pub const OMNI_NIRI_HIDE_NONE: u8 = 0;
pub const OMNI_NIRI_HIDE_LEFT: u8 = 1;
pub const OMNI_NIRI_HIDE_RIGHT: u8 = 2;
pub const OMNI_NIRI_RESIZE_EDGE_TOP: u8 = 0b0001;
pub const OMNI_NIRI_RESIZE_EDGE_BOTTOM: u8 = 0b0010;
pub const OMNI_NIRI_RESIZE_EDGE_LEFT: u8 = 0b0100;
pub const OMNI_NIRI_RESIZE_EDGE_RIGHT: u8 = 0b1000;
pub const OMNI_NIRI_INSERT_BEFORE: u8 = 0;
pub const OMNI_NIRI_INSERT_AFTER: u8 = 1;
pub const OMNI_NIRI_INSERT_SWAP: u8 = 2;
pub const OMNI_NIRI_SPAWN_NEW_COLUMN: u8 = 0;
pub const OMNI_NIRI_SPAWN_FOCUSED_COLUMN: u8 = 1;
pub const OMNI_NIRI_DIRECTION_LEFT: u8 = 0;
pub const OMNI_NIRI_DIRECTION_RIGHT: u8 = 1;
pub const OMNI_NIRI_DIRECTION_UP: u8 = 2;
pub const OMNI_NIRI_DIRECTION_DOWN: u8 = 3;
pub const OMNI_NIRI_TXN_LAYOUT: u8 = 0;
pub const OMNI_NIRI_TXN_NAVIGATION: u8 = 1;
pub const OMNI_NIRI_TXN_MUTATION: u8 = 2;
pub const OMNI_NIRI_TXN_WORKSPACE: u8 = 3;
pub const OMNI_NIRI_NAV_OP_MOVE_BY_COLUMNS: u8 = 0;
pub const OMNI_NIRI_NAV_OP_MOVE_VERTICAL: u8 = 1;
pub const OMNI_NIRI_NAV_OP_FOCUS_TARGET: u8 = 2;
pub const OMNI_NIRI_NAV_OP_FOCUS_DOWN_OR_LEFT: u8 = 3;
pub const OMNI_NIRI_NAV_OP_FOCUS_UP_OR_RIGHT: u8 = 4;
pub const OMNI_NIRI_NAV_OP_FOCUS_COLUMN_FIRST: u8 = 5;
pub const OMNI_NIRI_NAV_OP_FOCUS_COLUMN_LAST: u8 = 6;
pub const OMNI_NIRI_NAV_OP_FOCUS_COLUMN_INDEX: u8 = 7;
pub const OMNI_NIRI_NAV_OP_FOCUS_WINDOW_INDEX: u8 = 8;
pub const OMNI_NIRI_NAV_OP_FOCUS_WINDOW_TOP: u8 = 9;
pub const OMNI_NIRI_NAV_OP_FOCUS_WINDOW_BOTTOM: u8 = 10;
pub const OMNI_NIRI_SIZE_KIND_PROPORTION: u8 = 0;
pub const OMNI_NIRI_SIZE_KIND_FIXED: u8 = 1;
pub const OMNI_NIRI_HEIGHT_KIND_AUTO: u8 = 0;
pub const OMNI_NIRI_HEIGHT_KIND_FIXED: u8 = 1;
pub const OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_VERTICAL: u8 = 0;
pub const OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_VERTICAL: u8 = 1;
pub const OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_HORIZONTAL: u8 = 2;
pub const OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_HORIZONTAL: u8 = 3;
pub const OMNI_NIRI_MUTATION_OP_SWAP_WINDOWS_BY_MOVE: u8 = 4;
pub const OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_BY_MOVE: u8 = 5;
pub const OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_TO_COLUMN: u8 = 6;
pub const OMNI_NIRI_MUTATION_OP_CREATE_COLUMN_AND_MOVE: u8 = 7;
pub const OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_IN_NEW_COLUMN: u8 = 8;
pub const OMNI_NIRI_MUTATION_OP_MOVE_COLUMN: u8 = 9;
pub const OMNI_NIRI_MUTATION_OP_CONSUME_WINDOW: u8 = 10;
pub const OMNI_NIRI_MUTATION_OP_EXPEL_WINDOW: u8 = 11;
pub const OMNI_NIRI_MUTATION_OP_CLEANUP_EMPTY_COLUMN: u8 = 12;
pub const OMNI_NIRI_MUTATION_OP_NORMALIZE_COLUMN_SIZES: u8 = 13;
pub const OMNI_NIRI_MUTATION_OP_NORMALIZE_WINDOW_SIZES: u8 = 14;
pub const OMNI_NIRI_MUTATION_OP_BALANCE_SIZES: u8 = 15;
pub const OMNI_NIRI_MUTATION_OP_ADD_WINDOW: u8 = 16;
pub const OMNI_NIRI_MUTATION_OP_REMOVE_WINDOW: u8 = 17;
pub const OMNI_NIRI_MUTATION_OP_VALIDATE_SELECTION: u8 = 18;
pub const OMNI_NIRI_MUTATION_OP_FALLBACK_SELECTION_ON_REMOVAL: u8 = 19;
pub const OMNI_NIRI_MUTATION_OP_SET_COLUMN_DISPLAY: u8 = 20;
pub const OMNI_NIRI_MUTATION_OP_SET_COLUMN_ACTIVE_TILE: u8 = 21;
pub const OMNI_NIRI_MUTATION_OP_SET_COLUMN_WIDTH: u8 = 22;
pub const OMNI_NIRI_MUTATION_OP_TOGGLE_COLUMN_FULL_WIDTH: u8 = 23;
pub const OMNI_NIRI_MUTATION_OP_SET_WINDOW_HEIGHT: u8 = 24;
pub const OMNI_NIRI_MUTATION_OP_CLEAR_WORKSPACE: u8 = 25;
pub const OMNI_NIRI_MUTATION_NODE_NONE: u8 = 0;
pub const OMNI_NIRI_MUTATION_NODE_WINDOW: u8 = 1;
pub const OMNI_NIRI_MUTATION_NODE_COLUMN: u8 = 2;
pub const OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE: u8 = 0;
pub const OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS: u8 = 1;
pub const OMNI_NIRI_MUTATION_EDIT_MOVE_WINDOW_TO_COLUMN_INDEX: u8 = 2;
pub const OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMN_WIDTH_STATE: u8 = 3;
pub const OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOW_SIZE_HEIGHT: u8 = 4;
pub const OMNI_NIRI_MUTATION_EDIT_RESET_WINDOW_SIZE_HEIGHT: u8 = 5;
pub const OMNI_NIRI_MUTATION_EDIT_REMOVE_COLUMN_IF_EMPTY: u8 = 6;
pub const OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY: u8 = 7;
pub const OMNI_NIRI_MUTATION_EDIT_DELEGATE_MOVE_COLUMN: u8 = 8;
pub const OMNI_NIRI_MUTATION_EDIT_CREATE_COLUMN_ADJACENT_AND_MOVE_WINDOW: u8 = 9;
pub const OMNI_NIRI_MUTATION_EDIT_INSERT_NEW_COLUMN_AT_INDEX_AND_MOVE_WINDOW: u8 = 10;
pub const OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMNS: u8 = 11;
pub const OMNI_NIRI_MUTATION_EDIT_NORMALIZE_COLUMNS_BY_FACTOR: u8 = 12;
pub const OMNI_NIRI_MUTATION_EDIT_NORMALIZE_COLUMN_WINDOWS_BY_FACTOR: u8 = 13;
pub const OMNI_NIRI_MUTATION_EDIT_BALANCE_COLUMNS: u8 = 14;
pub const OMNI_NIRI_MUTATION_EDIT_INSERT_INCOMING_WINDOW_INTO_COLUMN: u8 = 15;
pub const OMNI_NIRI_MUTATION_EDIT_INSERT_INCOMING_WINDOW_IN_NEW_COLUMN: u8 = 16;
pub const OMNI_NIRI_MUTATION_EDIT_REMOVE_WINDOW_BY_INDEX: u8 = 17;
pub const OMNI_NIRI_MUTATION_EDIT_RESET_ALL_COLUMN_CACHED_WIDTHS: u8 = 18;
pub const OMNI_NIRI_MUTATION_MAX_EDITS: usize = 32;
pub const OMNI_NIRI_RUNTIME_HINT_MAX_COLUMNS: usize = 2;
pub const OMNI_NIRI_WORKSPACE_OP_MOVE_WINDOW_TO_WORKSPACE: u8 = 0;
pub const OMNI_NIRI_WORKSPACE_OP_MOVE_COLUMN_TO_WORKSPACE: u8 = 1;
pub const OMNI_NIRI_WORKSPACE_EDIT_SET_SOURCE_SELECTION_WINDOW: u8 = 0;
pub const OMNI_NIRI_WORKSPACE_EDIT_SET_SOURCE_SELECTION_NONE: u8 = 1;
pub const OMNI_NIRI_WORKSPACE_EDIT_REUSE_TARGET_EMPTY_COLUMN: u8 = 2;
pub const OMNI_NIRI_WORKSPACE_EDIT_CREATE_TARGET_COLUMN_APPEND: u8 = 3;
pub const OMNI_NIRI_WORKSPACE_EDIT_PRUNE_TARGET_EMPTY_COLUMNS_IF_NO_WINDOWS: u8 = 4;
pub const OMNI_NIRI_WORKSPACE_EDIT_REMOVE_SOURCE_COLUMN_IF_EMPTY: u8 = 5;
pub const OMNI_NIRI_WORKSPACE_EDIT_ENSURE_SOURCE_PLACEHOLDER_IF_NO_COLUMNS: u8 = 6;
pub const OMNI_NIRI_WORKSPACE_EDIT_SET_TARGET_SELECTION_MOVED_WINDOW: u8 = 7;
pub const OMNI_NIRI_WORKSPACE_EDIT_SET_TARGET_SELECTION_MOVED_COLUMN_FIRST_WINDOW: u8 = 8;
pub const OMNI_NIRI_WORKSPACE_MAX_EDITS: usize = 16;
pub const OMNI_DWINDLE_MAX_NODES: usize = (MAX_WINDOWS * 2) - 1;
pub const OMNI_DWINDLE_NODE_SPLIT: u8 = 0;
pub const OMNI_DWINDLE_NODE_LEAF: u8 = 1;
pub const OMNI_DWINDLE_ORIENTATION_HORIZONTAL: u8 = 0;
pub const OMNI_DWINDLE_ORIENTATION_VERTICAL: u8 = 1;
pub const OMNI_DWINDLE_DIRECTION_LEFT: u8 = 0;
pub const OMNI_DWINDLE_DIRECTION_RIGHT: u8 = 1;
pub const OMNI_DWINDLE_DIRECTION_UP: u8 = 2;
pub const OMNI_DWINDLE_DIRECTION_DOWN: u8 = 3;
pub const OMNI_DWINDLE_OP_ADD_WINDOW: u8 = 0;
pub const OMNI_DWINDLE_OP_REMOVE_WINDOW: u8 = 1;
pub const OMNI_DWINDLE_OP_SYNC_WINDOWS: u8 = 2;
pub const OMNI_DWINDLE_OP_MOVE_FOCUS: u8 = 3;
pub const OMNI_DWINDLE_OP_SWAP_WINDOWS: u8 = 4;
pub const OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN: u8 = 5;
pub const OMNI_DWINDLE_OP_TOGGLE_ORIENTATION: u8 = 6;
pub const OMNI_DWINDLE_OP_RESIZE_SELECTED: u8 = 7;
pub const OMNI_DWINDLE_OP_BALANCE_SIZES: u8 = 8;
pub const OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO: u8 = 9;
pub const OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT: u8 = 10;
pub const OMNI_DWINDLE_OP_SWAP_SPLIT: u8 = 11;
pub const OMNI_DWINDLE_OP_SET_PRESELECTION: u8 = 12;
pub const OMNI_DWINDLE_OP_CLEAR_PRESELECTION: u8 = 13;
pub const OMNI_DWINDLE_OP_VALIDATE_SELECTION: u8 = 14;
pub const OMNI_CONTROLLER_ABI_VERSION: u32 = 2;
pub const OMNI_CONTROLLER_NAME_CAP: usize = 64;
pub const OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS: usize = 128;
pub const OMNI_CONTROLLER_UI_WORKSPACE_CAP: usize = 32;
pub const OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP: usize = 8;
pub const OMNI_CONTROLLER_LAYOUT_DEFAULT: u8 = 0;
pub const OMNI_CONTROLLER_LAYOUT_NIRI: u8 = 1;
pub const OMNI_CONTROLLER_LAYOUT_DWINDLE: u8 = 2;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_DIRECTION: u8 = 0;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_PREVIOUS: u8 = 1;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_NEXT: u8 = 2;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_LAST: u8 = 3;
pub const OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX: u8 = 4;
pub const OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_NEXT: u8 = 5;
pub const OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_PREVIOUS: u8 = 6;
pub const OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE: u8 = 7;
pub const OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE: u8 = 8;
pub const OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_DIRECTION: u8 = 9;
pub const OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_NEXT: u8 = 10;
pub const OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_PREVIOUS: u8 = 11;
pub const OMNI_CONTROLLER_COMMAND_SWAP_WORKSPACE_WITH_MONITOR_DIRECTION: u8 = 12;
pub const OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX: u8 = 13;
pub const OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_UP: u8 = 14;
pub const OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN: u8 = 15;
pub const OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_MONITOR_DIRECTION: u8 = 16;
pub const OMNI_CONTROLLER_COMMAND_MOVE_WINDOW_TO_WORKSPACE_ON_MONITOR: u8 = 17;
pub const OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_WORKSPACE_INDEX: u8 = 18;
pub const OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_UP: u8 = 19;
pub const OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN: u8 = 20;
pub const OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_MONITOR_DIRECTION: u8 = 21;
pub const OMNI_CONTROLLER_COMMAND_WORKSPACE_BACK_AND_FORTH: u8 = 22;
pub const OMNI_CONTROLLER_COMMAND_OPEN_WINDOW_FINDER: u8 = 23;
pub const OMNI_CONTROLLER_COMMAND_RAISE_ALL_FLOATING_WINDOWS: u8 = 24;
pub const OMNI_CONTROLLER_COMMAND_OPEN_MENU_ANYWHERE: u8 = 25;
pub const OMNI_CONTROLLER_COMMAND_OPEN_MENU_PALETTE: u8 = 26;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_HIDDEN_BAR: u8 = 27;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_QUAKE_TERMINAL: u8 = 28;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_OVERVIEW: u8 = 29;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_PREVIOUS: u8 = 30;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION: u8 = 31;
pub const OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION: u8 = 32;
pub const OMNI_CONTROLLER_COMMAND_SWAP_DIRECTION: u8 = 33;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN: u8 = 34;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_NATIVE_FULLSCREEN: u8 = 35;
pub const OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_DIRECTION: u8 = 36;
pub const OMNI_CONTROLLER_COMMAND_CONSUME_WINDOW_DIRECTION: u8 = 37;
pub const OMNI_CONTROLLER_COMMAND_EXPEL_WINDOW_DIRECTION: u8 = 38;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_TABBED: u8 = 39;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT: u8 = 40;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT: u8 = 41;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST: u8 = 42;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST: u8 = 43;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX: u8 = 44;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP: u8 = 45;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM: u8 = 46;
pub const OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_FORWARD: u8 = 47;
pub const OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_BACKWARD: u8 = 48;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_FULL_WIDTH: u8 = 49;
pub const OMNI_CONTROLLER_COMMAND_BALANCE_SIZES: u8 = 50;
pub const OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT: u8 = 51;
pub const OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT: u8 = 52;
pub const OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT: u8 = 53;
pub const OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION: u8 = 54;
pub const OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION: u8 = 55;
pub const OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR: u8 = 56;
pub const OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT: u8 = 57;
pub const OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_HANDLE: u8 = 58;
pub const OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW: u8 = 59;
pub const OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN: u8 = 60;
pub const OMNI_CONTROLLER_COMMAND_SET_ACTIVE_WORKSPACE_ON_MONITOR: u8 = 61;
pub const OMNI_CONTROLLER_EVENT_REFRESH_SESSION: u8 = 0;
pub const OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED: u8 = 1;
pub const OMNI_CONTROLLER_EVENT_LOCK_SCREEN_CHANGED: u8 = 2;
pub const OMNI_CONTROLLER_EVENT_APP_ACTIVATED: u8 = 3;
pub const OMNI_CONTROLLER_EVENT_APP_HIDDEN: u8 = 4;
pub const OMNI_CONTROLLER_EVENT_APP_UNHIDDEN: u8 = 5;
pub const OMNI_CONTROLLER_EVENT_MONITOR_RECONFIGURED: u8 = 6;
pub const OMNI_CONTROLLER_EVENT_FOCUS_CHANGED: u8 = 7;
pub const OMNI_CONTROLLER_EVENT_WINDOW_REMOVED: u8 = 8;
pub const OMNI_CONTROLLER_EVENT_RECOVER_FOCUS: u8 = 9;
pub const OMNI_CONTROLLER_REFRESH_REASON_TIMER: u8 = 0;
pub const OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CREATED: u8 = 1;
pub const OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED: u8 = 2;
pub const OMNI_CONTROLLER_REFRESH_REASON_APP_HIDDEN: u8 = 3;
pub const OMNI_CONTROLLER_REFRESH_REASON_APP_UNHIDDEN: u8 = 4;
pub const OMNI_CONTROLLER_REFRESH_REASON_MONITOR_RECONFIGURED: u8 = 5;
pub const OMNI_CONTROLLER_ROUTE_FOCUS_MONITOR: u8 = 0;
pub const OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE: u8 = 1;
pub const OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE: u8 = 2;
pub const OMNI_CONTROLLER_ROUTE_SUMMON_WORKSPACE: u8 = 3;
pub const OMNI_CONTROLLER_ROUTE_MOVE_WORKSPACE_TO_MONITOR: u8 = 4;
pub const OMNI_CONTROLLER_ROUTE_SWAP_WORKSPACES: u8 = 5;
pub const OMNI_CONTROLLER_TRANSFER_MOVE_WINDOW: u8 = 0;
pub const OMNI_CONTROLLER_TRANSFER_MOVE_COLUMN: u8 = 1;
pub const OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_WINDOW: u8 = 0;
pub const OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_WINDOW: u8 = 1;
pub const OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_NIRI_WINDOW: u8 = 2;
pub const OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_DWINDLE_WINDOW: u8 = 3;
pub const OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_COLUMN: u8 = 4;
pub const OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_BATCH: u8 = 5;
pub const OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_NIRI_COLUMN: u8 = 6;
pub const OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_DWINDLE_BATCH: u8 = 7;
pub const OMNI_WM_CONTROLLER_ABI_VERSION: u32 = 2;
pub const OMNI_SERVICE_LIFECYCLE_ABI_VERSION: u32 = 1;
pub const OMNI_MONITOR_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_PLATFORM_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_AX_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_INPUT_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_WORKSPACE_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_WORKSPACE_OBSERVER_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_LOCK_OBSERVER_RUNTIME_ABI_VERSION: u32 = 1;
pub const OMNI_INPUT_BINDING_ID_CAP: usize = 96;
pub const OMNI_WORKSPACE_RUNTIME_NAME_CAP: usize = 64;
pub const OMNI_INPUT_EFFECT_DISPATCH_EVENT: u8 = 0;
pub const OMNI_INPUT_EVENT_MOUSE_MOVED: u8 = 0;
pub const OMNI_INPUT_EVENT_LEFT_MOUSE_DOWN: u8 = 1;
pub const OMNI_INPUT_EVENT_LEFT_MOUSE_DRAGGED: u8 = 2;
pub const OMNI_INPUT_EVENT_LEFT_MOUSE_UP: u8 = 3;
pub const OMNI_INPUT_EVENT_SCROLL_WHEEL: u8 = 4;
pub const OMNI_INPUT_EVENT_GESTURE: u8 = 5;
pub const OMNI_INPUT_EVENT_SECURE_INPUT_CHANGED: u8 = 6;
pub const OMNI_INPUT_TAP_KIND_MOUSE: u8 = 0;
pub const OMNI_INPUT_TAP_KIND_GESTURE: u8 = 1;
pub const OMNI_INPUT_TAP_KIND_SECURE_INPUT: u8 = 2;
pub const OMNI_INPUT_TAP_HEALTH_DISABLED_TIMEOUT: u8 = 0;
pub const OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT: u8 = 1;
pub const OMNI_WORKSPACE_MONITOR_ASSIGNMENT_ANY: u8 = 0;
pub const OMNI_WORKSPACE_MONITOR_ASSIGNMENT_MAIN: u8 = 1;
pub const OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SECONDARY: u8 = 2;
pub const OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SEQUENCE_NUMBER: u8 = 3;
pub const OMNI_WORKSPACE_MONITOR_ASSIGNMENT_NAME_PATTERN: u8 = 4;
pub const OMNI_WORKSPACE_LAYOUT_REASON_STANDARD: u8 = 0;
pub const OMNI_WORKSPACE_LAYOUT_REASON_MACOS_HIDDEN_APP: u8 = 1;
pub const OMNI_AX_WINDOW_TYPE_TILING: u8 = 0;
pub const OMNI_AX_WINDOW_TYPE_FLOATING: u8 = 1;
pub const OMNI_CONTROLLER_REFRESH_HIDE_BORDER: u32 = 1 << 0;
pub const OMNI_CONTROLLER_REFRESH_IMMEDIATE: u32 = 1 << 1;
pub const OMNI_CONTROLLER_REFRESH_INCREMENTAL: u32 = 1 << 2;
pub const OMNI_CONTROLLER_REFRESH_FULL: u32 = 1 << 3;
pub const OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE: u32 = 1 << 4;
pub const OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR: u32 = 1 << 5;
pub const OMNI_CONTROLLER_REFRESH_START_WORKSPACE_ANIMATION: u32 = 1 << 6;
pub const OMNI_CONTROLLER_REFRESH_STOP_SCROLL_ANIMATION: u32 = 1 << 7;
pub const OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT: u32 = 1 << 8;
pub const OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER: u8 = 0;
pub const OMNI_CONTROLLER_UI_RAISE_ALL_FLOATING_WINDOWS: u8 = 1;
pub const OMNI_CONTROLLER_UI_OPEN_MENU_ANYWHERE: u8 = 2;
pub const OMNI_CONTROLLER_UI_OPEN_MENU_PALETTE: u8 = 3;
pub const OMNI_CONTROLLER_UI_TOGGLE_HIDDEN_BAR: u8 = 4;
pub const OMNI_CONTROLLER_UI_TOGGLE_QUAKE_TERMINAL: u8 = 5;
pub const OMNI_CONTROLLER_UI_TOGGLE_OVERVIEW: u8 = 6;
pub const OMNI_CONTROLLER_UI_SHOW_SECURE_INPUT: u8 = 7;
pub const OMNI_CONTROLLER_UI_HIDE_SECURE_INPUT: u8 = 8;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION: u8 = 0;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_DIRECTION: u8 = 1;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION: u8 = 2;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_FULLSCREEN: u8 = 3;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_NATIVE_FULLSCREEN: u8 = 4;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION: u8 = 5;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_CONSUME_WINDOW_DIRECTION: u8 = 6;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_EXPEL_WINDOW_DIRECTION: u8 = 7;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED: u8 = 8;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT: u8 = 9;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT: u8 = 10;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST: u8 = 11;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST: u8 = 12;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX: u8 = 13;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP: u8 = 14;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM: u8 = 15;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD: u8 = 16;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD: u8 = 17;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH: u8 = 18;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES: u8 = 19;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT: u8 = 20;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT: u8 = 21;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT: u8 = 22;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION: u8 = 23;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION: u8 = 24;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR: u8 = 25;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT: u8 = 26;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW: u8 = 27;
pub const OMNI_CONTROLLER_LAYOUT_ACTION_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN: u8 = 28;
pub const OMNI_SERVICE_LIFECYCLE_STATE_STOPPED: u8 = 0;
pub const OMNI_SERVICE_LIFECYCLE_STATE_STARTING: u8 = 1;
pub const OMNI_SERVICE_LIFECYCLE_STATE_RUNNING: u8 = 2;
pub const OMNI_SERVICE_LIFECYCLE_STATE_STOPPING: u8 = 3;
pub const OMNI_SERVICE_LIFECYCLE_STATE_FAILED: u8 = 4;
