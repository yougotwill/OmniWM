#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct OmniNiriLayoutContext OmniNiriLayoutContext;
typedef struct OmniNiriRuntime OmniNiriRuntime;
typedef struct OmniBorderRuntime OmniBorderRuntime;
typedef struct OmniDwindleLayoutContext OmniDwindleLayoutContext;
typedef struct OmniController OmniController;
typedef struct OmniWMController OmniWMController;
typedef struct OmniMonitorRuntime OmniMonitorRuntime;
typedef struct OmniPlatformRuntime OmniPlatformRuntime;
typedef struct OmniWorkspaceObserverRuntime OmniWorkspaceObserverRuntime;
typedef struct OmniLockObserverRuntime OmniLockObserverRuntime;
typedef struct OmniAXRuntime OmniAXRuntime;
typedef struct OmniWorkspaceRuntime OmniWorkspaceRuntime;
typedef struct OmniInputRuntime OmniInputRuntime;
typedef struct OmniServiceLifecycle OmniServiceLifecycle;

/// Input descriptor for one window on a single axis.
/// Zig struct OmniAxisInput must match this layout exactly.
typedef struct {
    double weight;
    double min_constraint;
    double max_constraint;
    uint8_t has_max_constraint;
    uint8_t is_constraint_fixed;
    uint8_t has_fixed_value;
    double fixed_value; // ignored when has_fixed_value == 0
} OmniAxisInput;

/// Result for one window on a single axis.
typedef struct {
    double value;
    uint8_t was_constrained;
} OmniAxisOutput;

typedef enum {
    OMNI_CENTER_NEVER = 0,
    OMNI_CENTER_ALWAYS = 1,
    OMNI_CENTER_ON_OVERFLOW = 2
} OmniCenterMode;

typedef struct {
    double view_pos;
    size_t column_index;
} OmniSnapResult;

enum {
    OMNI_VIEWPORT_GESTURE_HISTORY_CAP = 64
};

typedef struct {
    uint8_t is_trackpad;
    size_t history_count;
    size_t history_head;
    double tracker_position;
    double current_view_offset;
    double stationary_view_offset;
    double delta_from_tracker;
    double history_deltas[OMNI_VIEWPORT_GESTURE_HISTORY_CAP];
    double history_timestamps[OMNI_VIEWPORT_GESTURE_HISTORY_CAP];
} OmniViewportGestureState;

typedef struct {
    size_t resolved_column_index;
    double offset_delta;
    double adjusted_target_offset;
    double target_offset;
    double snap_delta;
    uint8_t snap_to_target_immediately;
} OmniViewportTransitionResult;

typedef struct {
    double target_offset;
    double offset_delta;
    uint8_t is_noop;
} OmniViewportEnsureVisibleResult;

typedef struct {
    uint8_t applied;
    double new_offset;
    double selection_progress;
    uint8_t has_selection_steps;
    int64_t selection_steps;
} OmniViewportScrollResult;

typedef struct {
    double current_view_offset;
    double selection_progress;
    uint8_t has_selection_steps;
    int64_t selection_steps;
} OmniViewportGestureUpdateResult;

typedef struct {
    size_t resolved_column_index;
    double spring_from;
    double spring_to;
    double initial_velocity;
} OmniViewportGestureEndResult;

typedef struct {
    double current_offset;
    double target_offset;
    int64_t active_column_index;
    double selection_progress;
    uint8_t is_gesture;
    uint8_t is_animating;
} OmniNiriRuntimeViewportStatus;

typedef struct {
    double red;
    double green;
    double blue;
    double alpha;
} OmniBorderColor;

typedef struct {
    uint8_t enabled;
    double width;
    OmniBorderColor color;
} OmniBorderConfig;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} OmniBorderRect;

typedef struct {
    uint32_t display_id;
    OmniBorderRect appkit_frame;
    OmniBorderRect window_server_frame;
    double backing_scale;
} OmniBorderDisplayInfo;

typedef struct {
    OmniBorderConfig config;
    uint8_t has_focused_window_id;
    int64_t focused_window_id;
    uint8_t has_focused_frame;
    OmniBorderRect focused_frame;
    uint8_t is_focused_window_in_active_workspace;
    uint8_t is_non_managed_focus_active;
    uint8_t is_native_fullscreen_active;
    uint8_t is_managed_fullscreen_active;
    uint8_t defer_updates;
    uint8_t update_mode;
    uint8_t layout_animation_active;
    const OmniBorderDisplayInfo *displays;
    size_t display_count;
} OmniBorderPresentationInput;

typedef struct {
    OmniBorderConfig config;
    uint8_t has_focused_window_id;
    int64_t focused_window_id;
    uint8_t has_focused_frame;
    OmniBorderRect focused_frame;
    uint8_t is_focused_window_in_active_workspace;
    uint8_t is_non_managed_focus_active;
    uint8_t is_native_fullscreen_active;
    uint8_t is_managed_fullscreen_active;
    uint8_t defer_updates;
    uint8_t update_mode;
    uint8_t layout_animation_active;
    uint8_t force_hide;
    const OmniBorderDisplayInfo *displays;
    size_t display_count;
} OmniBorderSnapshotInput;

typedef struct {
    int64_t focused_window_id;
    OmniBorderRect focused_frame;
    uint8_t update_mode;
    const OmniBorderDisplayInfo *displays;
    size_t display_count;
} OmniBorderMotionInput;

typedef struct {
    uint8_t has_main_connection_id;
    uint8_t has_window_query_windows;
    uint8_t has_window_query_result_copy_windows;
    uint8_t has_window_iterator_advance;
    uint8_t has_window_iterator_get_bounds;
    uint8_t has_window_iterator_get_window_id;
    uint8_t has_window_iterator_get_pid;
    uint8_t has_window_iterator_get_level;
    uint8_t has_window_iterator_get_tags;
    uint8_t has_window_iterator_get_attributes;
    uint8_t has_window_iterator_get_parent_id;
    uint8_t has_transaction_create;
    uint8_t has_transaction_commit;
    uint8_t has_transaction_order_window;
    uint8_t has_transaction_move_window_with_group;
    uint8_t has_transaction_set_window_level;
    uint8_t has_move_window;
    uint8_t has_get_window_bounds;
    uint8_t has_disable_update;
    uint8_t has_reenable_update;
    uint8_t has_new_window;
    uint8_t has_release_window;
    uint8_t has_window_context_create;
    uint8_t has_set_window_shape;
    uint8_t has_set_window_resolution;
    uint8_t has_set_window_opacity;
    uint8_t has_set_window_tags;
    uint8_t has_flush_window_content_region;
    uint8_t has_new_region_with_rect;
    uint8_t has_register_connection_notify_proc;
    uint8_t has_unregister_connection_notify_proc;
    uint8_t has_request_notifications_for_windows;
    uint8_t has_register_notify_proc;
    uint8_t has_unregister_notify_proc;
} OmniSkyLightCapabilities;

typedef struct {
    uint8_t has_set_front_process_with_options;
    uint8_t has_post_event_record_to;
    uint8_t has_get_process_for_pid;
    uint8_t has_ax_get_window;
} OmniPrivateCapabilities;

typedef struct {
    uint32_t id;
    int32_t pid;
    int32_t level;
    OmniBorderRect frame;
    uint64_t tags;
    uint32_t attributes;
    uint32_t parent_id;
} OmniSkyLightWindowInfo;

typedef struct {
    uint32_t window_id;
    double origin_x;
    double origin_y;
} OmniSkyLightMoveRequest;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniPlatformRuntimeConfig;

typedef int32_t (*OmniPlatformOnWindowCreatedFn)(
    void *userdata,
    uint32_t window_id,
    uint64_t space_id);

typedef int32_t (*OmniPlatformOnWindowDestroyedFn)(
    void *userdata,
    uint32_t window_id,
    uint64_t space_id);

typedef int32_t (*OmniPlatformOnWindowClosedFn)(
    void *userdata,
    uint32_t window_id);

typedef int32_t (*OmniPlatformOnWindowMovedFn)(
    void *userdata,
    uint32_t window_id);

typedef int32_t (*OmniPlatformOnWindowResizedFn)(
    void *userdata,
    uint32_t window_id);

typedef int32_t (*OmniPlatformOnFrontAppChangedFn)(
    void *userdata,
    int32_t pid);

typedef int32_t (*OmniPlatformOnWindowTitleChangedFn)(
    void *userdata,
    uint32_t window_id);

typedef struct {
    void *userdata;
    OmniPlatformOnWindowCreatedFn on_window_created;
    OmniPlatformOnWindowDestroyedFn on_window_destroyed;
    OmniPlatformOnWindowClosedFn on_window_closed;
    OmniPlatformOnWindowMovedFn on_window_moved;
    OmniPlatformOnWindowResizedFn on_window_resized;
    OmniPlatformOnFrontAppChangedFn on_front_app_changed;
    OmniPlatformOnWindowTitleChangedFn on_window_title_changed;
} OmniPlatformHostVTable;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniMonitorRuntimeConfig;

typedef int32_t (*OmniMonitorOnDisplaysChangedFn)(
    void *userdata,
    uint32_t display_id,
    uint32_t change_flags);

typedef struct {
    void *userdata;
    OmniMonitorOnDisplaysChangedFn on_displays_changed;
} OmniMonitorHostVTable;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniWorkspaceObserverRuntimeConfig;

typedef int32_t (*OmniWorkspaceObserverOnAppFn)(
    void *userdata,
    int32_t pid);

typedef int32_t (*OmniWorkspaceObserverOnActiveSpaceChangedFn)(
    void *userdata);

typedef struct {
    void *userdata;
    OmniWorkspaceObserverOnAppFn on_app_launched;
    OmniWorkspaceObserverOnAppFn on_app_terminated;
    OmniWorkspaceObserverOnAppFn on_app_activated;
    OmniWorkspaceObserverOnAppFn on_app_hidden;
    OmniWorkspaceObserverOnAppFn on_app_unhidden;
    OmniWorkspaceObserverOnActiveSpaceChangedFn on_active_space_changed;
} OmniWorkspaceObserverHostVTable;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniLockObserverRuntimeConfig;

typedef int32_t (*OmniLockObserverOnLockedFn)(
    void *userdata);

typedef int32_t (*OmniLockObserverOnUnlockedFn)(
    void *userdata);

typedef struct {
    void *userdata;
    OmniLockObserverOnLockedFn on_locked;
    OmniLockObserverOnUnlockedFn on_unlocked;
} OmniLockObserverHostVTable;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniAXRuntimeConfig;

typedef int32_t (*OmniAXOnWindowDestroyedFn)(
    void *userdata,
    int32_t pid,
    uint32_t window_id);

typedef int32_t (*OmniAXOnWindowDestroyedUnknownFn)(
    void *userdata);

typedef int32_t (*OmniAXOnFocusedWindowChangedFn)(
    void *userdata,
    int32_t pid);

typedef struct {
    void *userdata;
    OmniAXOnWindowDestroyedFn on_window_destroyed;
    OmniAXOnWindowDestroyedUnknownFn on_window_destroyed_unknown;
    OmniAXOnFocusedWindowChangedFn on_focused_window_changed;
} OmniAXHostVTable;

typedef struct {
    int32_t pid;
    uint32_t window_id;
    uint8_t window_type;
} OmniAXWindowRecord;

typedef struct {
    int32_t pid;
    uint32_t window_id;
    OmniBorderRect frame;
} OmniAXFrameRequest;

typedef struct {
    int32_t pid;
    uint32_t window_id;
} OmniAXWindowKey;

typedef struct {
    int32_t pid;
    uint32_t window_id;
    int32_t app_policy;
    uint8_t force_floating;
} OmniAXWindowTypeRequest;

typedef struct {
    double min_width;
    double min_height;
    double max_width;
    double max_height;
    uint8_t has_max_width;
    uint8_t has_max_height;
    uint8_t is_fixed;
} OmniAXWindowConstraints;

enum {
    OMNI_WORKSPACE_RUNTIME_NAME_CAP = 64
};

enum {
    OMNI_INPUT_BINDING_ID_CAP = 96
};

typedef enum {
    OMNI_BORDER_UPDATE_MODE_COALESCED = 0,
    OMNI_BORDER_UPDATE_MODE_REALTIME = 1
} OmniBorderUpdateMode;

typedef enum {
    OMNI_NIRI_ORIENTATION_HORIZONTAL = 0,
    OMNI_NIRI_ORIENTATION_VERTICAL = 1
} OmniNiriOrientation;

typedef enum {
    OMNI_NIRI_SIZING_NORMAL = 0,
    OMNI_NIRI_SIZING_FULLSCREEN = 1
} OmniNiriSizingMode;

typedef enum {
    OMNI_NIRI_HIDE_NONE = 0,
    OMNI_NIRI_HIDE_LEFT = 1,
    OMNI_NIRI_HIDE_RIGHT = 2
} OmniNiriHideSide;

typedef struct {
    double span;
    double render_offset_x;
    double render_offset_y;
    uint8_t is_tabbed;
    double tab_indicator_width;
    size_t window_start;
    size_t window_count;
} OmniNiriColumnInput;

typedef struct {
    double weight;
    double min_constraint;
    double max_constraint;
    uint8_t has_max_constraint;
    uint8_t is_constraint_fixed;
    uint8_t has_fixed_value;
    double fixed_value;
    uint8_t sizing_mode;
    double render_offset_x;
    double render_offset_y;
} OmniNiriWindowInput;

typedef struct {
    uint8_t bytes[16];
} OmniUuid128;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniWorkspaceRuntimeConfig;

typedef struct {
    uint8_t length;
    uint8_t bytes[OMNI_WORKSPACE_RUNTIME_NAME_CAP];
} OmniWorkspaceRuntimeName;

typedef struct {
    uint32_t display_id;
    uint8_t is_main;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    double visible_x;
    double visible_y;
    double visible_width;
    double visible_height;
    uint8_t has_notch;
    double backing_scale;
    OmniWorkspaceRuntimeName name;
} OmniMonitorRecord;

typedef struct {
    uint32_t display_id;
    uint8_t is_main;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    double visible_x;
    double visible_y;
    double visible_width;
    double visible_height;
    OmniWorkspaceRuntimeName name;
} OmniWorkspaceRuntimeMonitorSnapshot;

typedef struct {
    OmniWorkspaceRuntimeName workspace_name;
    uint8_t assignment_kind;
    int32_t sequence_number;
    OmniWorkspaceRuntimeName monitor_pattern;
} OmniWorkspaceRuntimeMonitorAssignment;

typedef struct {
    const OmniWorkspaceRuntimeName *persistent_names;
    size_t persistent_name_count;
    const OmniWorkspaceRuntimeMonitorAssignment *monitor_assignments;
    size_t monitor_assignment_count;
} OmniWorkspaceRuntimeSettingsImport;

typedef struct {
    uint32_t display_id;
    uint8_t is_main;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    double visible_x;
    double visible_y;
    double visible_width;
    double visible_height;
    OmniWorkspaceRuntimeName name;
    uint8_t has_active_workspace_id;
    OmniUuid128 active_workspace_id;
    uint8_t has_previous_workspace_id;
    OmniUuid128 previous_workspace_id;
} OmniWorkspaceRuntimeMonitorRecord;

typedef struct {
    OmniUuid128 workspace_id;
    OmniWorkspaceRuntimeName name;
    uint8_t has_assigned_monitor_anchor;
    double assigned_monitor_anchor_x;
    double assigned_monitor_anchor_y;
    uint8_t has_assigned_display_id;
    uint32_t assigned_display_id;
    uint8_t is_visible;
    uint8_t is_previous_visible;
    uint8_t is_persistent;
} OmniWorkspaceRuntimeWorkspaceRecord;

typedef struct {
    int32_t pid;
    int64_t window_id;
} OmniWorkspaceRuntimeWindowKey;

typedef struct {
    double proportional_x;
    double proportional_y;
    uint8_t has_reference_display_id;
    uint32_t reference_display_id;
    uint8_t workspace_inactive;
} OmniWorkspaceRuntimeWindowHiddenState;

typedef struct {
    int32_t pid;
    int64_t window_id;
    OmniUuid128 workspace_id;
    uint8_t has_handle_id;
    OmniUuid128 handle_id;
} OmniWorkspaceRuntimeWindowUpsert;

typedef struct {
    OmniUuid128 handle_id;
    int32_t pid;
    int64_t window_id;
    OmniUuid128 workspace_id;
    uint8_t has_hidden_state;
    OmniWorkspaceRuntimeWindowHiddenState hidden_state;
    uint8_t layout_reason;
} OmniWorkspaceRuntimeWindowRecord;

typedef struct {
    const OmniWorkspaceRuntimeMonitorRecord *monitors;
    size_t monitor_count;
    const OmniWorkspaceRuntimeWorkspaceRecord *workspaces;
    size_t workspace_count;
    const OmniWorkspaceRuntimeWindowRecord *windows;
    size_t window_count;
    uint8_t has_active_monitor_display_id;
    uint32_t active_monitor_display_id;
    uint8_t has_previous_monitor_display_id;
    uint32_t previous_monitor_display_id;
} OmniWorkspaceRuntimeStateExport;

typedef struct {
    OmniUuid128 window_id;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    double animated_x;
    double animated_y;
    double animated_width;
    double animated_height;
    double resolved_span;
    uint8_t was_constrained;
    uint8_t hide_side;
    size_t column_index;
} OmniNiriWindowOutput;

typedef struct {
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    uint8_t hide_side;
    uint8_t is_visible;
} OmniNiriColumnOutput;

typedef enum {
    OMNI_NIRI_RESIZE_EDGE_TOP = 0b0001,
    OMNI_NIRI_RESIZE_EDGE_BOTTOM = 0b0010,
    OMNI_NIRI_RESIZE_EDGE_LEFT = 0b0100,
    OMNI_NIRI_RESIZE_EDGE_RIGHT = 0b1000
} OmniNiriResizeEdge;

typedef struct {
    size_t window_index;
    size_t column_index;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    uint8_t is_fullscreen;
} OmniNiriHitTestWindow;

typedef struct {
    uint8_t is_valid;
    double min_y;
    double max_y;
    size_t post_insertion_count;
} OmniNiriColumnDropzoneMeta;

typedef struct {
    int64_t window_index;
    uint8_t edges;
} OmniNiriResizeHitResult;

typedef enum {
    OMNI_NIRI_INSERT_BEFORE = 0,
    OMNI_NIRI_INSERT_AFTER = 1,
    OMNI_NIRI_INSERT_SWAP = 2
} OmniNiriInsertPosition;

typedef enum {
    OMNI_NIRI_SPAWN_NEW_COLUMN = 0,
    OMNI_NIRI_SPAWN_FOCUSED_COLUMN = 1
} OmniNiriIncomingSpawnMode;

typedef struct {
    int64_t window_index;
    uint8_t insert_position;
} OmniNiriMoveTargetResult;

typedef struct {
    double target_frame_x;
    double target_frame_y;
    double target_frame_width;
    double target_frame_height;
    double column_min_y;
    double column_max_y;
    double gap;
    uint8_t insert_position;
    size_t post_insertion_count;
} OmniNiriDropzoneInput;

typedef struct {
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    uint8_t is_valid;
} OmniNiriDropzoneResult;

typedef struct {
    uint8_t edges;
    double start_x;
    double start_y;
    double current_x;
    double current_y;
    double original_column_width;
    double min_column_width;
    double max_column_width;
    double original_window_weight;
    double min_window_weight;
    double max_window_weight;
    double pixels_per_weight;
    uint8_t has_original_view_offset;
    double original_view_offset;
} OmniNiriResizeInput;

typedef struct {
    uint8_t changed_width;
    double new_column_width;
    uint8_t changed_weight;
    double new_window_weight;
    uint8_t adjust_view_offset;
    double new_view_offset;
} OmniNiriResizeResult;

enum {
    OMNI_OK = 0,
    OMNI_ERR_INVALID_ARGS = -1,
    OMNI_ERR_OUT_OF_RANGE = -2,
    OMNI_ERR_PLATFORM = -3
};

enum {
    OMNI_MONITOR_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_PLATFORM_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_AX_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_INPUT_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_WORKSPACE_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_WORKSPACE_OBSERVER_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_LOCK_OBSERVER_RUNTIME_ABI_VERSION = 1
};

enum {
    OMNI_WM_CONTROLLER_ABI_VERSION = 1
};

enum {
    OMNI_SERVICE_LIFECYCLE_ABI_VERSION = 1
};

typedef enum {
    OMNI_SERVICE_LIFECYCLE_STATE_STOPPED = 0,
    OMNI_SERVICE_LIFECYCLE_STATE_STARTING = 1,
    OMNI_SERVICE_LIFECYCLE_STATE_RUNNING = 2,
    OMNI_SERVICE_LIFECYCLE_STATE_STOPPING = 3,
    OMNI_SERVICE_LIFECYCLE_STATE_FAILED = 4
} OmniServiceLifecycleState;

typedef enum {
    OMNI_WORKSPACE_MONITOR_ASSIGNMENT_ANY = 0,
    OMNI_WORKSPACE_MONITOR_ASSIGNMENT_MAIN = 1,
    OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SECONDARY = 2,
    OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SEQUENCE_NUMBER = 3,
    OMNI_WORKSPACE_MONITOR_ASSIGNMENT_NAME_PATTERN = 4
} OmniWorkspaceMonitorAssignmentKind;

typedef enum {
    OMNI_WORKSPACE_LAYOUT_REASON_STANDARD = 0,
    OMNI_WORKSPACE_LAYOUT_REASON_MACOS_HIDDEN_APP = 1
} OmniWorkspaceLayoutReason;

typedef enum {
    OMNI_AX_WINDOW_TYPE_TILING = 0,
    OMNI_AX_WINDOW_TYPE_FLOATING = 1
} OmniAXWindowType;

/// Compute viewport offset needed to reveal a target container index.
/// Returns 0 on success, -1 for invalid args, -2 when index/range is invalid.
int32_t omni_viewport_compute_visible_offset(
    const double *spans,
    size_t span_count,
    size_t container_index,
    double gap,
    double viewport_span,
    double current_view_start,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    int64_t from_container_index,
    double *out_target_offset);

/// Compute transition plan values for switching active container to requested index.
/// Returns 0 on success, -1 for invalid args, -2 for range errors.
int32_t omni_viewport_transition_to_column(
    const double *spans,
    size_t span_count,
    size_t current_active_index,
    size_t requested_index,
    double gap,
    double viewport_span,
    double current_target_offset,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    int64_t from_container_index,
    double scale,
    OmniViewportTransitionResult *out_result);

/// Compute offset plan to ensure a target container is visible.
/// Returns 0 on success, -1 for invalid args, -2 for range errors.
int32_t omni_viewport_ensure_visible(
    const double *spans,
    size_t span_count,
    size_t active_container_index,
    size_t target_container_index,
    double gap,
    double viewport_span,
    double current_offset,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    int64_t from_container_index,
    double epsilon,
    OmniViewportEnsureVisibleResult *out_result);

/// Apply one viewport scroll delta and report clamped offset/selection-step effects.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_viewport_scroll_step(
    const double *spans,
    size_t span_count,
    double delta_pixels,
    double viewport_span,
    double gap,
    double current_offset,
    double selection_progress,
    uint8_t change_selection,
    OmniViewportScrollResult *out_result);

/// Initialize gesture tracker/kernel state for a new gesture sequence.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_viewport_gesture_begin(
    double current_view_offset,
    uint8_t is_trackpad,
    OmniViewportGestureState *out_state);

/// Compute current gesture velocity from tracker history.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_viewport_gesture_velocity(
    const OmniViewportGestureState *gesture_state,
    double *out_velocity);

/// Advance gesture tracker state with one delta event.
/// Returns 0 on success, -1 for invalid args, -2 for range errors.
int32_t omni_viewport_gesture_update(
    OmniViewportGestureState *gesture_state,
    const double *spans,
    size_t span_count,
    size_t active_container_index,
    double delta_pixels,
    double timestamp,
    double gap,
    double viewport_span,
    double selection_progress,
    OmniViewportGestureUpdateResult *out_result);

/// Resolve gesture end target and spring endpoints from the current gesture state.
/// Returns 0 on success, -1 for invalid args, -2 for range errors.
int32_t omni_viewport_gesture_end(
    const OmniViewportGestureState *gesture_state,
    const double *spans,
    size_t span_count,
    size_t active_container_index,
    double gap,
    double viewport_span,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    OmniViewportGestureEndResult *out_result);

/// Create a reusable Niri layout context.
/// Returns NULL on allocation failure.
OmniNiriLayoutContext *omni_niri_layout_context_create(void);

/// Destroy a reusable Niri layout context.
void omni_niri_layout_context_destroy(OmniNiriLayoutContext *context);

/// Seed context interaction buffers directly (primarily for tests/parity harnesses).
/// Returns 0 on success, -1 for invalid args, -2 for capacity errors.
int32_t omni_niri_layout_context_set_interaction(
    OmniNiriLayoutContext *context,
    const OmniNiriHitTestWindow *windows,
    size_t window_count,
    const OmniNiriColumnDropzoneMeta *column_dropzones,
    size_t column_count);

/// Layout-pass v3 emits the same outputs as v2 and updates interaction feed in context.
/// `out_windows` may be NULL only when `window_count == 0` and `out_window_count == 0`.
/// Returns 0 on success, -1 for invalid args, -2 for range/assignment/capacity errors.
int32_t omni_niri_layout_pass_v3(
    OmniNiriLayoutContext *context,
    const OmniNiriColumnInput *columns,
    size_t column_count,
    const OmniNiriWindowInput *windows,
    size_t window_count,
    double working_x,
    double working_y,
    double working_width,
    double working_height,
    double view_x,
    double view_y,
    double view_width,
    double view_height,
    double fullscreen_x,
    double fullscreen_y,
    double fullscreen_width,
    double fullscreen_height,
    double primary_gap,
    double secondary_gap,
    double view_start,
    double viewport_span,
    double workspace_offset,
    double scale,
    uint8_t orientation,
    OmniNiriWindowOutput *out_windows,
    size_t out_window_count,
    OmniNiriColumnOutput *out_columns,
    size_t out_column_count);

/// Hit-test tiled windows and return first containing window index.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_hit_test_tiled(
    const OmniNiriHitTestWindow *windows,
    size_t window_count,
    double point_x,
    double point_y,
    int64_t *out_window_index);

/// Hit-test tiled windows from reusable context feed.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_ctx_hit_test_tiled(
    const OmniNiriLayoutContext *context,
    double point_x,
    double point_y,
    int64_t *out_window_index);

/// Hit-test resize edges around tiled windows.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_hit_test_resize(
    const OmniNiriHitTestWindow *windows,
    size_t window_count,
    double point_x,
    double point_y,
    double threshold,
    OmniNiriResizeHitResult *out_result);

/// Hit-test resize edges from reusable context feed.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_ctx_hit_test_resize(
    const OmniNiriLayoutContext *context,
    double point_x,
    double point_y,
    double threshold,
    OmniNiriResizeHitResult *out_result);

/// Resolve move target under cursor, with swap or insert semantics.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_hit_test_move_target(
    const OmniNiriHitTestWindow *windows,
    size_t window_count,
    double point_x,
    double point_y,
    int64_t excluding_window_index,
    uint8_t is_insert_mode,
    OmniNiriMoveTargetResult *out_result);

/// Hit-test move targets from reusable context feed.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_ctx_hit_test_move_target(
    const OmniNiriLayoutContext *context,
    double point_x,
    double point_y,
    int64_t excluding_window_index,
    uint8_t is_insert_mode,
    OmniNiriMoveTargetResult *out_result);

/// Compute insertion dropzone frame for before/after/swap placement.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_insertion_dropzone(
    const OmniNiriDropzoneInput *input,
    OmniNiriDropzoneResult *out_result);

/// Compute insertion dropzone using context metadata and target window index.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_ctx_insertion_dropzone(
    const OmniNiriLayoutContext *context,
    int64_t target_window_index,
    double gap,
    uint8_t insert_position,
    OmniNiriDropzoneResult *out_result);

/// Compute interactive resize updates for column width/window weight.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_resize_compute(
    const OmniNiriResizeInput *input,
    OmniNiriResizeResult *out_result);

typedef struct {
    OmniUuid128 column_id;
    size_t window_start;
    size_t window_count;
    size_t active_tile_idx;
    uint8_t is_tabbed;
    double size_value;
    uint8_t width_kind;
    uint8_t is_full_width;
    uint8_t has_saved_width;
    uint8_t saved_width_kind;
    double saved_width_value;
} OmniNiriStateColumnInput;

typedef struct {
    OmniUuid128 window_id;
    OmniUuid128 column_id;
    size_t column_index;
    double size_value;
    uint8_t height_kind;
    double height_value;
} OmniNiriStateWindowInput;

typedef struct {
    OmniUuid128 column_id;
    size_t window_start;
    size_t window_count;
    size_t active_tile_idx;
    uint8_t is_tabbed;
    double size_value;
    uint8_t width_kind;
    uint8_t is_full_width;
    uint8_t has_saved_width;
    uint8_t saved_width_kind;
    double saved_width_value;
} OmniNiriRuntimeColumnState;

typedef struct {
    OmniUuid128 window_id;
    OmniUuid128 column_id;
    size_t column_index;
    double size_value;
    uint8_t height_kind;
    double height_value;
} OmniNiriRuntimeWindowState;

typedef struct {
    const OmniNiriRuntimeColumnState *columns;
    size_t column_count;
    const OmniNiriRuntimeWindowState *windows;
    size_t window_count;
} OmniNiriRuntimeStateExport;

typedef enum {
    OMNI_NIRI_TXN_LAYOUT = 0,
    OMNI_NIRI_TXN_NAVIGATION = 1,
    OMNI_NIRI_TXN_MUTATION = 2,
    OMNI_NIRI_TXN_WORKSPACE = 3
} OmniNiriTxnKind;

enum {
    OMNI_NIRI_RUNTIME_HINT_MAX_COLUMNS = 2
};

typedef struct {
    OmniUuid128 column_id;
    size_t order_index;
    size_t window_start;
    size_t window_count;
    size_t active_tile_idx;
    uint8_t is_tabbed;
    double size_value;
    uint8_t width_kind;
    uint8_t is_full_width;
    uint8_t has_saved_width;
    uint8_t saved_width_kind;
    double saved_width_value;
} OmniNiriDeltaColumnRecord;

typedef struct {
    OmniUuid128 window_id;
    OmniUuid128 column_id;
    size_t column_order_index;
    size_t row_index;
    double size_value;
    uint8_t height_kind;
    double height_value;
} OmniNiriDeltaWindowRecord;

typedef struct {
    const OmniNiriDeltaColumnRecord *columns;
    size_t column_count;
    const OmniNiriDeltaWindowRecord *windows;
    size_t window_count;
    const OmniUuid128 *removed_column_ids;
    size_t removed_column_count;
    const OmniUuid128 *removed_window_ids;
    size_t removed_window_count;
    uint8_t refresh_tabbed_visibility_count;
    OmniUuid128 refresh_tabbed_visibility_column_ids[OMNI_NIRI_RUNTIME_HINT_MAX_COLUMNS];
    uint8_t reset_all_column_cached_widths;
    uint8_t has_delegate_move_column;
    OmniUuid128 delegate_move_column_id;
    uint8_t delegate_move_direction;
    uint8_t has_target_window_id;
    OmniUuid128 target_window_id;
    uint8_t has_target_node_id;
    uint8_t target_node_kind;
    OmniUuid128 target_node_id;
    uint8_t has_source_selection_window_id;
    OmniUuid128 source_selection_window_id;
    uint8_t has_target_selection_window_id;
    OmniUuid128 target_selection_window_id;
    uint8_t has_moved_window_id;
    OmniUuid128 moved_window_id;
    uint64_t generation;
} OmniNiriTxnDeltaExport;

typedef struct {
    size_t column_count;
    size_t window_count;
    int64_t first_invalid_column_index;
    int64_t first_invalid_window_index;
    int32_t first_error_code;
} OmniNiriStateValidationResult;

/// Validate snapshot bounds, ownership, and assignment consistency.
/// Returns 0 when valid, otherwise -1/-2 and fills first_invalid_* fields.
int32_t omni_niri_validate_state_snapshot(
    const OmniNiriStateColumnInput *columns,
    size_t column_count,
    const OmniNiriStateWindowInput *windows,
    size_t window_count,
    OmniNiriStateValidationResult *out_result);

/// Seed authoritative runtime state into a reusable context.
/// Returns 0 on success, -1 for invalid args, -2 for capacity/range failures.
int32_t omni_niri_ctx_seed_runtime_state(
    OmniNiriLayoutContext *context,
    const OmniNiriRuntimeColumnState *columns,
    size_t column_count,
    const OmniNiriRuntimeWindowState *windows,
    size_t window_count);

typedef enum {
    OMNI_NIRI_DIRECTION_LEFT = 0,
    OMNI_NIRI_DIRECTION_RIGHT = 1,
    OMNI_NIRI_DIRECTION_UP = 2,
    OMNI_NIRI_DIRECTION_DOWN = 3
} OmniNiriDirection;

typedef enum {
    OMNI_NIRI_NAV_OP_MOVE_BY_COLUMNS = 0,
    OMNI_NIRI_NAV_OP_MOVE_VERTICAL = 1,
    OMNI_NIRI_NAV_OP_FOCUS_TARGET = 2,
    OMNI_NIRI_NAV_OP_FOCUS_DOWN_OR_LEFT = 3,
    OMNI_NIRI_NAV_OP_FOCUS_UP_OR_RIGHT = 4,
    OMNI_NIRI_NAV_OP_FOCUS_COLUMN_FIRST = 5,
    OMNI_NIRI_NAV_OP_FOCUS_COLUMN_LAST = 6,
    OMNI_NIRI_NAV_OP_FOCUS_COLUMN_INDEX = 7,
    OMNI_NIRI_NAV_OP_FOCUS_WINDOW_INDEX = 8,
    OMNI_NIRI_NAV_OP_FOCUS_WINDOW_TOP = 9,
    OMNI_NIRI_NAV_OP_FOCUS_WINDOW_BOTTOM = 10
} OmniNiriNavigationOp;

typedef struct {
    uint8_t op;
    uint8_t direction;
    uint8_t orientation;
    uint8_t infinite_loop;
    int64_t selected_window_index;
    int64_t selected_column_index;
    int64_t selected_row_index;
    int64_t step;
    int64_t target_row_index;
    int64_t target_column_index;
    int64_t target_window_index;
} OmniNiriNavigationRequest;

typedef struct {
    uint8_t has_target;
    int64_t target_window_index;
    uint8_t update_source_active_tile;
    int64_t source_column_index;
    int64_t source_active_tile_idx;
    uint8_t update_target_active_tile;
    int64_t target_column_index;
    int64_t target_active_tile_idx;
    uint8_t refresh_tabbed_visibility_source;
    uint8_t refresh_tabbed_visibility_target;
} OmniNiriNavigationResult;

typedef struct {
    OmniNiriNavigationRequest request;
} OmniNiriNavigationApplyRequest;

typedef struct {
    uint8_t applied;
    uint8_t has_target_window_id;
    OmniUuid128 target_window_id;
    uint8_t update_source_active_tile;
    OmniUuid128 source_column_id;
    int64_t source_active_tile_idx;
    uint8_t update_target_active_tile;
    OmniUuid128 target_column_id;
    int64_t target_active_tile_idx;
    uint8_t refresh_tabbed_visibility_source;
    OmniUuid128 refresh_source_column_id;
    uint8_t refresh_tabbed_visibility_target;
    OmniUuid128 refresh_target_column_id;
} OmniNiriNavigationApplyResult;

typedef enum {
    OMNI_NIRI_SIZE_KIND_PROPORTION = 0,
    OMNI_NIRI_SIZE_KIND_FIXED = 1
} OmniNiriSizeKind;

typedef enum {
    OMNI_NIRI_HEIGHT_KIND_AUTO = 0,
    OMNI_NIRI_HEIGHT_KIND_FIXED = 1
} OmniNiriHeightKind;

typedef enum {
    OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_VERTICAL = 0,
    OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_VERTICAL = 1,
    OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_HORIZONTAL = 2,
    OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_HORIZONTAL = 3,
    OMNI_NIRI_MUTATION_OP_SWAP_WINDOWS_BY_MOVE = 4,
    OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_BY_MOVE = 5,
    OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_TO_COLUMN = 6,
    OMNI_NIRI_MUTATION_OP_CREATE_COLUMN_AND_MOVE = 7,
    OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_IN_NEW_COLUMN = 8,
    OMNI_NIRI_MUTATION_OP_MOVE_COLUMN = 9,
    OMNI_NIRI_MUTATION_OP_CONSUME_WINDOW = 10,
    OMNI_NIRI_MUTATION_OP_EXPEL_WINDOW = 11,
    OMNI_NIRI_MUTATION_OP_CLEANUP_EMPTY_COLUMN = 12,
    OMNI_NIRI_MUTATION_OP_NORMALIZE_COLUMN_SIZES = 13,
    OMNI_NIRI_MUTATION_OP_NORMALIZE_WINDOW_SIZES = 14,
    OMNI_NIRI_MUTATION_OP_BALANCE_SIZES = 15,
    OMNI_NIRI_MUTATION_OP_ADD_WINDOW = 16,
    OMNI_NIRI_MUTATION_OP_REMOVE_WINDOW = 17,
    OMNI_NIRI_MUTATION_OP_VALIDATE_SELECTION = 18,
    OMNI_NIRI_MUTATION_OP_FALLBACK_SELECTION_ON_REMOVAL = 19,
    OMNI_NIRI_MUTATION_OP_SET_COLUMN_DISPLAY = 20,
    OMNI_NIRI_MUTATION_OP_SET_COLUMN_ACTIVE_TILE = 21,
    OMNI_NIRI_MUTATION_OP_SET_COLUMN_WIDTH = 22,
    OMNI_NIRI_MUTATION_OP_TOGGLE_COLUMN_FULL_WIDTH = 23,
    OMNI_NIRI_MUTATION_OP_SET_WINDOW_HEIGHT = 24,
    OMNI_NIRI_MUTATION_OP_CLEAR_WORKSPACE = 25
} OmniNiriMutationOp;

typedef enum {
    OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE = 0,
    OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS = 1,
    OMNI_NIRI_MUTATION_EDIT_MOVE_WINDOW_TO_COLUMN_INDEX = 2,
    OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMN_WIDTH_STATE = 3,
    OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOW_SIZE_HEIGHT = 4,
    OMNI_NIRI_MUTATION_EDIT_RESET_WINDOW_SIZE_HEIGHT = 5,
    OMNI_NIRI_MUTATION_EDIT_REMOVE_COLUMN_IF_EMPTY = 6,
    OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY = 7,
    OMNI_NIRI_MUTATION_EDIT_DELEGATE_MOVE_COLUMN = 8,
    OMNI_NIRI_MUTATION_EDIT_CREATE_COLUMN_ADJACENT_AND_MOVE_WINDOW = 9,
    OMNI_NIRI_MUTATION_EDIT_INSERT_NEW_COLUMN_AT_INDEX_AND_MOVE_WINDOW = 10,
    OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMNS = 11,
    OMNI_NIRI_MUTATION_EDIT_NORMALIZE_COLUMNS_BY_FACTOR = 12,
    OMNI_NIRI_MUTATION_EDIT_NORMALIZE_COLUMN_WINDOWS_BY_FACTOR = 13,
    OMNI_NIRI_MUTATION_EDIT_BALANCE_COLUMNS = 14,
    OMNI_NIRI_MUTATION_EDIT_INSERT_INCOMING_WINDOW_INTO_COLUMN = 15,
    OMNI_NIRI_MUTATION_EDIT_INSERT_INCOMING_WINDOW_IN_NEW_COLUMN = 16,
    OMNI_NIRI_MUTATION_EDIT_REMOVE_WINDOW_BY_INDEX = 17,
    OMNI_NIRI_MUTATION_EDIT_RESET_ALL_COLUMN_CACHED_WIDTHS = 18
} OmniNiriMutationEditKind;

typedef enum {
    OMNI_NIRI_MUTATION_NODE_NONE = 0,
    OMNI_NIRI_MUTATION_NODE_WINDOW = 1,
    OMNI_NIRI_MUTATION_NODE_COLUMN = 2
} OmniNiriMutationNodeKind;

typedef struct {
    uint8_t op;
    uint8_t direction;
    uint8_t infinite_loop;
    uint8_t insert_position;
    int64_t source_window_index;
    int64_t target_window_index;
    int64_t max_windows_per_column;
    int64_t source_column_index;
    int64_t target_column_index;
    int64_t insert_column_index;
    int64_t max_visible_columns;
    uint8_t selected_node_kind;
    int64_t selected_node_index;
    int64_t focused_window_index;
    uint8_t incoming_spawn_mode;
} OmniNiriMutationRequest;

typedef struct {
    uint8_t kind;
    int64_t subject_index;
    int64_t related_index;
    int64_t value_a;
    int64_t value_b;
    double scalar_a;
    double scalar_b;
} OmniNiriMutationEdit;

enum {
    OMNI_NIRI_MUTATION_MAX_EDITS = 32
};

typedef struct {
    uint8_t applied;
    uint8_t has_target_window;
    int64_t target_window_index;
    uint8_t has_target_node;
    uint8_t target_node_kind;
    int64_t target_node_index;
    size_t edit_count;
    OmniNiriMutationEdit edits[OMNI_NIRI_MUTATION_MAX_EDITS];
} OmniNiriMutationResult;

typedef struct {
    OmniNiriMutationRequest request;
    uint8_t has_incoming_window_id;
    OmniUuid128 incoming_window_id;
    uint8_t has_created_column_id;
    OmniUuid128 created_column_id;
    uint8_t has_placeholder_column_id;
    OmniUuid128 placeholder_column_id;
} OmniNiriMutationApplyRequest;

typedef struct {
    uint8_t applied;
    uint8_t has_target_window_id;
    OmniUuid128 target_window_id;
    uint8_t has_target_node_id;
    uint8_t target_node_kind;
    OmniUuid128 target_node_id;
    uint8_t refresh_tabbed_visibility_count;
    OmniUuid128 refresh_tabbed_visibility_column_ids[OMNI_NIRI_RUNTIME_HINT_MAX_COLUMNS];
    uint8_t reset_all_column_cached_widths;
    uint8_t has_delegate_move_column;
    OmniUuid128 delegate_move_column_id;
    uint8_t delegate_move_direction;
} OmniNiriMutationApplyResult;

typedef enum {
    OMNI_NIRI_WORKSPACE_OP_MOVE_WINDOW_TO_WORKSPACE = 0,
    OMNI_NIRI_WORKSPACE_OP_MOVE_COLUMN_TO_WORKSPACE = 1
} OmniNiriWorkspaceOp;

typedef enum {
    OMNI_NIRI_WORKSPACE_EDIT_SET_SOURCE_SELECTION_WINDOW = 0,
    OMNI_NIRI_WORKSPACE_EDIT_SET_SOURCE_SELECTION_NONE = 1,
    OMNI_NIRI_WORKSPACE_EDIT_REUSE_TARGET_EMPTY_COLUMN = 2,
    OMNI_NIRI_WORKSPACE_EDIT_CREATE_TARGET_COLUMN_APPEND = 3,
    OMNI_NIRI_WORKSPACE_EDIT_PRUNE_TARGET_EMPTY_COLUMNS_IF_NO_WINDOWS = 4,
    OMNI_NIRI_WORKSPACE_EDIT_REMOVE_SOURCE_COLUMN_IF_EMPTY = 5,
    OMNI_NIRI_WORKSPACE_EDIT_ENSURE_SOURCE_PLACEHOLDER_IF_NO_COLUMNS = 6,
    OMNI_NIRI_WORKSPACE_EDIT_SET_TARGET_SELECTION_MOVED_WINDOW = 7,
    OMNI_NIRI_WORKSPACE_EDIT_SET_TARGET_SELECTION_MOVED_COLUMN_FIRST_WINDOW = 8
} OmniNiriWorkspaceEditKind;

typedef struct {
    uint8_t op;
    int64_t source_window_index;
    int64_t source_column_index;
    int64_t max_visible_columns;
} OmniNiriWorkspaceRequest;

typedef struct {
    uint8_t kind;
    int64_t subject_index;
    int64_t related_index;
    int64_t value_a;
    int64_t value_b;
} OmniNiriWorkspaceEdit;

enum {
    OMNI_NIRI_WORKSPACE_MAX_EDITS = 16
};

typedef struct {
    uint8_t applied;
    size_t edit_count;
    OmniNiriWorkspaceEdit edits[OMNI_NIRI_WORKSPACE_MAX_EDITS];
} OmniNiriWorkspaceResult;

typedef struct {
    OmniNiriWorkspaceRequest request;
    uint8_t has_target_created_column_id;
    OmniUuid128 target_created_column_id;
    uint8_t has_source_placeholder_column_id;
    OmniUuid128 source_placeholder_column_id;
} OmniNiriWorkspaceApplyRequest;

typedef struct {
    uint8_t applied;
    uint8_t has_source_selection_window_id;
    OmniUuid128 source_selection_window_id;
    uint8_t has_target_selection_window_id;
    OmniUuid128 target_selection_window_id;
    uint8_t has_moved_window_id;
    OmniUuid128 moved_window_id;
} OmniNiriWorkspaceApplyResult;

typedef struct {
    uint8_t op;
    uint8_t direction;
    uint8_t orientation;
    uint8_t infinite_loop;
    uint8_t has_source_window_id;
    OmniUuid128 source_window_id;
    uint8_t has_source_column_id;
    OmniUuid128 source_column_id;
    uint8_t has_target_window_id;
    OmniUuid128 target_window_id;
    uint8_t has_target_column_id;
    OmniUuid128 target_column_id;
    int64_t step;
    int64_t target_row_index;
    int64_t focus_column_index;
    int64_t focus_window_index;
} OmniNiriTxnNavigationPayload;

typedef struct {
    uint8_t op;
    uint8_t direction;
    uint8_t infinite_loop;
    uint8_t insert_position;
    uint8_t has_source_window_id;
    OmniUuid128 source_window_id;
    uint8_t has_target_window_id;
    OmniUuid128 target_window_id;
    int64_t max_windows_per_column;
    uint8_t has_source_column_id;
    OmniUuid128 source_column_id;
    uint8_t has_target_column_id;
    OmniUuid128 target_column_id;
    int64_t insert_column_index;
    int64_t max_visible_columns;
    uint8_t has_selected_node_id;
    OmniUuid128 selected_node_id;
    uint8_t has_focused_window_id;
    OmniUuid128 focused_window_id;
    uint8_t incoming_spawn_mode;
    uint8_t has_incoming_window_id;
    OmniUuid128 incoming_window_id;
    uint8_t has_created_column_id;
    OmniUuid128 created_column_id;
    uint8_t has_placeholder_column_id;
    OmniUuid128 placeholder_column_id;
    uint8_t custom_u8_a;
    uint8_t custom_u8_b;
    int64_t custom_i64_a;
    int64_t custom_i64_b;
    double custom_f64_a;
    double custom_f64_b;
} OmniNiriTxnMutationPayload;

typedef struct {
    uint8_t op;
    uint8_t has_source_window_id;
    OmniUuid128 source_window_id;
    uint8_t has_source_column_id;
    OmniUuid128 source_column_id;
    int64_t max_visible_columns;
    uint8_t has_target_created_column_id;
    OmniUuid128 target_created_column_id;
    uint8_t has_source_placeholder_column_id;
    OmniUuid128 source_placeholder_column_id;
} OmniNiriTxnWorkspacePayload;

typedef struct {
    uint8_t kind;
    OmniNiriTxnNavigationPayload navigation;
    OmniNiriTxnMutationPayload mutation;
    OmniNiriTxnWorkspacePayload workspace;
    size_t max_delta_columns;
    size_t max_delta_windows;
    size_t max_removed_ids;
} OmniNiriTxnRequest;

typedef struct {
    uint8_t applied;
    uint8_t kind;
    uint8_t structural_animation_active;
    uint8_t has_target_window_id;
    OmniUuid128 target_window_id;
    uint8_t has_target_node_id;
    uint8_t target_node_kind;
    OmniUuid128 target_node_id;
    uint8_t changed_source_context;
    uint8_t changed_target_context;
    int32_t error_code;
    size_t delta_column_count;
    size_t delta_window_count;
    size_t removed_column_count;
    size_t removed_window_count;
} OmniNiriTxnResult;

typedef struct {
    const OmniNiriRuntimeColumnState *columns;
    size_t column_count;
    const OmniNiriRuntimeWindowState *windows;
    size_t window_count;
} OmniNiriRuntimeSeedRequest;

typedef struct {
    OmniNiriTxnRequest txn;
    double sample_time;
} OmniNiriRuntimeCommandRequest;

typedef struct {
    OmniNiriTxnResult txn;
} OmniNiriRuntimeCommandResult;

typedef struct {
    size_t expected_column_count;
    size_t expected_window_count;
    double working_x;
    double working_y;
    double working_width;
    double working_height;
    double view_x;
    double view_y;
    double view_width;
    double view_height;
    double fullscreen_x;
    double fullscreen_y;
    double fullscreen_width;
    double fullscreen_height;
    double primary_gap;
    double secondary_gap;
    double viewport_span;
    double workspace_offset;
    uint8_t has_fullscreen_window_id;
    OmniUuid128 fullscreen_window_id;
    double scale;
    uint8_t orientation;
    double sample_time;
} OmniNiriRuntimeRenderFromStateRequest;

typedef struct {
    OmniNiriWindowOutput *windows;
    size_t window_count;
    OmniNiriColumnOutput *columns;
    size_t column_count;
    uint8_t animation_active;
} OmniNiriRuntimeRenderOutput;

/// Apply one Niri runtime transaction and update context-owned delta buffers.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_niri_ctx_apply_txn(
    OmniNiriLayoutContext *source_context,
    OmniNiriLayoutContext *target_context,
    const OmniNiriTxnRequest *request,
    OmniNiriTxnResult *out_result);

/// Export context-owned transaction delta pointers/counts from last apply.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_ctx_export_delta(
    const OmniNiriLayoutContext *context,
    OmniNiriTxnDeltaExport *out_export);

/// Create a Niri runtime owner for authoritative state.
/// Returns NULL on allocation failure.
OmniNiriRuntime *omni_niri_runtime_create(void);

/// Create a border runtime owner for focused-window presentation.
/// Returns NULL on allocation failure or missing platform symbols.
OmniBorderRuntime *omni_border_runtime_create(void);

/// Destroy a runtime owner.
void omni_niri_runtime_destroy(OmniNiriRuntime *runtime);

/// Destroy a border runtime owner.
void omni_border_runtime_destroy(OmniBorderRuntime *runtime);

/// Synchronize border config into the runtime.
/// Returns 0 on success, -1 for invalid args, -3 for platform failures.
int32_t omni_border_runtime_apply_config(
    OmniBorderRuntime *runtime,
    const OmniBorderConfig *config);

/// Compatibility wrapper for legacy callers.
/// Prefer omni_border_runtime_submit_snapshot for all new integrations.
/// Returns 0 on success, -1 for invalid args, -3 for platform failures.
int32_t omni_border_runtime_apply_presentation(
    OmniBorderRuntime *runtime,
    const OmniBorderPresentationInput *input);

/// Submit a complete border snapshot (config + presentation flags + displays).
/// Returns 0 on success, -1 for invalid args, -3 for platform failures.
int32_t omni_border_runtime_submit_snapshot(
    OmniBorderRuntime *runtime,
    const OmniBorderSnapshotInput *snapshot);

/// Apply focused-window motion using previously seeded runtime state.
/// Returns 0 on success, -1 for invalid args, -3 for platform failures.
int32_t omni_border_runtime_apply_motion(
    OmniBorderRuntime *runtime,
    const OmniBorderMotionInput *input);

/// Clear cached display transforms and hide any visible border.
/// Returns 0 on success, -1 for invalid args, -3 for platform failures.
int32_t omni_border_runtime_invalidate_displays(
    OmniBorderRuntime *runtime);

/// Hide any visible border.
/// Returns 0 on success, -1 for invalid args, -3 for platform failures.
int32_t omni_border_runtime_hide(
    OmniBorderRuntime *runtime);

int32_t omni_skylight_get_capabilities(
    OmniSkyLightCapabilities *out_capabilities);

int32_t omni_skylight_get_main_connection_id(void);

int32_t omni_skylight_order_window(
    uint32_t window_id,
    uint32_t relative_to_window_id,
    int32_t order);

int32_t omni_skylight_move_window(
    uint32_t window_id,
    double origin_x,
    double origin_y);

int32_t omni_skylight_batch_move_windows(
    const OmniSkyLightMoveRequest *requests,
    size_t request_count);

int32_t omni_skylight_get_window_bounds(
    uint32_t window_id,
    OmniBorderRect *out_rect);

int32_t omni_skylight_query_visible_windows(
    OmniSkyLightWindowInfo *out_windows,
    size_t out_capacity,
    size_t *out_written);

int32_t omni_skylight_query_window_info(
    uint32_t window_id,
    OmniSkyLightWindowInfo *out_info);

int32_t omni_skylight_subscribe_window_notifications(
    const uint32_t *window_ids,
    size_t window_count);

int32_t omni_private_get_capabilities(
    OmniPrivateCapabilities *out_capabilities);

int32_t omni_private_get_ax_window_id(
    void *ax_element,
    uint32_t *out_window_id);

int32_t omni_private_focus_window(
    int32_t pid,
    uint32_t window_id);

int32_t omni_monitor_query_current(
    OmniMonitorRecord *out_monitors,
    size_t out_capacity,
    size_t *out_written);

OmniMonitorRuntime *omni_monitor_runtime_create(
    const OmniMonitorRuntimeConfig *config,
    const OmniMonitorHostVTable *host_vtable);

void omni_monitor_runtime_destroy(OmniMonitorRuntime *runtime);

int32_t omni_monitor_runtime_start(OmniMonitorRuntime *runtime);

int32_t omni_monitor_runtime_stop(OmniMonitorRuntime *runtime);

OmniWorkspaceObserverRuntime *omni_workspace_observer_runtime_create(
    const OmniWorkspaceObserverRuntimeConfig *config,
    const OmniWorkspaceObserverHostVTable *host_vtable);

void omni_workspace_observer_runtime_destroy(OmniWorkspaceObserverRuntime *runtime);

int32_t omni_workspace_observer_runtime_start(OmniWorkspaceObserverRuntime *runtime);

int32_t omni_workspace_observer_runtime_stop(OmniWorkspaceObserverRuntime *runtime);

OmniLockObserverRuntime *omni_lock_observer_runtime_create(
    const OmniLockObserverRuntimeConfig *config,
    const OmniLockObserverHostVTable *host_vtable);

void omni_lock_observer_runtime_destroy(OmniLockObserverRuntime *runtime);

int32_t omni_lock_observer_runtime_start(OmniLockObserverRuntime *runtime);

int32_t omni_lock_observer_runtime_stop(OmniLockObserverRuntime *runtime);

OmniPlatformRuntime *omni_platform_runtime_create(
    const OmniPlatformRuntimeConfig *config,
    const OmniPlatformHostVTable *host_vtable);

void omni_platform_runtime_destroy(OmniPlatformRuntime *runtime);

int32_t omni_platform_runtime_start(OmniPlatformRuntime *runtime);

int32_t omni_platform_runtime_stop(OmniPlatformRuntime *runtime);

int32_t omni_platform_runtime_subscribe_windows(
    OmniPlatformRuntime *runtime,
    const uint32_t *window_ids,
    size_t window_count);

OmniAXRuntime *omni_ax_runtime_create(
    const OmniAXRuntimeConfig *config,
    const OmniAXHostVTable *host_vtable);

void omni_ax_runtime_destroy(OmniAXRuntime *runtime);

int32_t omni_ax_runtime_start(OmniAXRuntime *runtime);

int32_t omni_ax_runtime_stop(OmniAXRuntime *runtime);

int32_t omni_ax_runtime_track_app(
    OmniAXRuntime *runtime,
    int32_t pid,
    int32_t app_policy,
    const char *bundle_id,
    uint8_t force_floating);

int32_t omni_ax_runtime_untrack_app(
    OmniAXRuntime *runtime,
    int32_t pid);

int32_t omni_ax_runtime_enumerate_windows(
    OmniAXRuntime *runtime,
    OmniAXWindowRecord *out_windows,
    size_t out_capacity,
    size_t *out_written);

int32_t omni_ax_runtime_apply_frames_batch(
    OmniAXRuntime *runtime,
    const OmniAXFrameRequest *requests,
    size_t request_count);

int32_t omni_ax_runtime_cancel_frame_jobs(
    OmniAXRuntime *runtime,
    const OmniAXWindowKey *keys,
    size_t key_count);

int32_t omni_ax_runtime_suppress_frame_writes(
    OmniAXRuntime *runtime,
    const OmniAXWindowKey *keys,
    size_t key_count);

int32_t omni_ax_runtime_unsuppress_frame_writes(
    OmniAXRuntime *runtime,
    const OmniAXWindowKey *keys,
    size_t key_count);

int32_t omni_ax_runtime_get_window_frame(
    OmniAXRuntime *runtime,
    int32_t pid,
    uint32_t window_id,
    OmniBorderRect *out_rect);

int32_t omni_ax_runtime_set_window_frame(
    OmniAXRuntime *runtime,
    int32_t pid,
    uint32_t window_id,
    const OmniBorderRect *frame);

int32_t omni_ax_runtime_get_window_type(
    OmniAXRuntime *runtime,
    const OmniAXWindowTypeRequest *request,
    uint8_t *out_type);

int32_t omni_ax_runtime_is_window_fullscreen(
    OmniAXRuntime *runtime,
    int32_t pid,
    uint32_t window_id,
    uint8_t *out_fullscreen);

int32_t omni_ax_runtime_set_window_fullscreen(
    OmniAXRuntime *runtime,
    int32_t pid,
    uint32_t window_id,
    uint8_t fullscreen);

int32_t omni_ax_runtime_get_window_constraints(
    OmniAXRuntime *runtime,
    int32_t pid,
    uint32_t window_id,
    OmniAXWindowConstraints *out_constraints);

int32_t omni_sleep_prevention_create_assertion(
    uint32_t *out_assertion_id);

int32_t omni_sleep_prevention_release_assertion(
    uint32_t assertion_id);

uint8_t omni_ax_permission_is_trusted(void);

uint8_t omni_ax_permission_request_prompt(void);

uint8_t omni_ax_permission_poll_until_trusted(
    uint32_t max_wait_millis,
    uint32_t poll_interval_millis);

OmniWorkspaceRuntime *omni_workspace_runtime_create(
    const OmniWorkspaceRuntimeConfig *config);

void omni_workspace_runtime_destroy(OmniWorkspaceRuntime *runtime);

int32_t omni_workspace_runtime_start(OmniWorkspaceRuntime *runtime);

int32_t omni_workspace_runtime_stop(OmniWorkspaceRuntime *runtime);

int32_t omni_workspace_runtime_import_monitors(
    OmniWorkspaceRuntime *runtime,
    const OmniWorkspaceRuntimeMonitorSnapshot *monitors,
    size_t monitor_count);

int32_t omni_workspace_runtime_import_settings(
    OmniWorkspaceRuntime *runtime,
    const OmniWorkspaceRuntimeSettingsImport *settings);

int32_t omni_workspace_runtime_export_state(
    OmniWorkspaceRuntime *runtime,
    OmniWorkspaceRuntimeStateExport *out_export);

int32_t omni_workspace_runtime_workspace_id_by_name(
    OmniWorkspaceRuntime *runtime,
    OmniWorkspaceRuntimeName name,
    uint8_t create_if_missing,
    uint8_t *out_has_workspace_id,
    OmniUuid128 *out_workspace_id);

int32_t omni_workspace_runtime_set_active_workspace(
    OmniWorkspaceRuntime *runtime,
    OmniUuid128 workspace_id,
    uint32_t monitor_display_id);

int32_t omni_workspace_runtime_summon_workspace_by_name(
    OmniWorkspaceRuntime *runtime,
    OmniWorkspaceRuntimeName name,
    uint32_t monitor_display_id,
    uint8_t *out_has_workspace_id,
    OmniUuid128 *out_workspace_id);

int32_t omni_workspace_runtime_move_workspace_to_monitor(
    OmniWorkspaceRuntime *runtime,
    OmniUuid128 workspace_id,
    uint32_t target_monitor_display_id);

int32_t omni_workspace_runtime_swap_workspaces(
    OmniWorkspaceRuntime *runtime,
    OmniUuid128 workspace_1_id,
    uint32_t monitor_1_display_id,
    OmniUuid128 workspace_2_id,
    uint32_t monitor_2_display_id);

int32_t omni_workspace_runtime_adjacent_monitor(
    OmniWorkspaceRuntime *runtime,
    uint32_t from_monitor_display_id,
    uint8_t direction,
    uint8_t wrap_around,
    uint8_t *out_has_monitor,
    OmniWorkspaceRuntimeMonitorRecord *out_monitor);

int32_t omni_workspace_runtime_window_upsert(
    OmniWorkspaceRuntime *runtime,
    const OmniWorkspaceRuntimeWindowUpsert *request,
    OmniUuid128 *out_handle_id);

int32_t omni_workspace_runtime_window_remove(
    OmniWorkspaceRuntime *runtime,
    OmniWorkspaceRuntimeWindowKey key);

int32_t omni_workspace_runtime_window_set_workspace(
    OmniWorkspaceRuntime *runtime,
    OmniUuid128 handle_id,
    OmniUuid128 workspace_id);

int32_t omni_workspace_runtime_window_set_hidden_state(
    OmniWorkspaceRuntime *runtime,
    OmniUuid128 handle_id,
    uint8_t has_hidden_state,
    OmniWorkspaceRuntimeWindowHiddenState hidden_state);

int32_t omni_workspace_runtime_window_set_layout_reason(
    OmniWorkspaceRuntime *runtime,
    OmniUuid128 handle_id,
    uint8_t layout_reason);

int32_t omni_workspace_runtime_window_remove_missing(
    OmniWorkspaceRuntime *runtime,
    const OmniWorkspaceRuntimeWindowKey *active_keys,
    size_t active_key_count,
    uint32_t required_consecutive_misses);

/// Seed authoritative runtime state.
/// Returns 0 on success, -1 for invalid args, -2 for capacity/range failures.
int32_t omni_niri_runtime_seed(
    OmniNiriRuntime *runtime,
    const OmniNiriRuntimeSeedRequest *request);

/// Apply one runtime command (navigation/mutation/workspace transaction).
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_niri_runtime_apply_command(
    OmniNiriRuntime *source_runtime,
    OmniNiriRuntime *target_runtime,
    const OmniNiriRuntimeCommandRequest *request,
    OmniNiriRuntimeCommandResult *out_result);

/// Render current runtime state into frame outputs.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_niri_runtime_render_from_state(
    OmniNiriRuntime *runtime,
    OmniNiriLayoutContext *layout_context,
    const OmniNiriRuntimeRenderFromStateRequest *request,
    OmniNiriRuntimeRenderOutput *out_output);

/// Start the workspace-switch structural animation track for a runtime.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_start_workspace_switch_animation(
    OmniNiriRuntime *runtime,
    double sample_time);

/// Start the mutation structural animation track for a runtime.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_start_mutation_animation(
    OmniNiriRuntime *runtime,
    double sample_time);

/// Cancel any active runtime animation track.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_cancel_animation(
    OmniNiriRuntime *runtime);

/// Query whether the runtime still has an active animation track at `sample_time`.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_animation_active(
    OmniNiriRuntime *runtime,
    double sample_time,
    uint8_t *out_active);

/// Query the current Niri runtime viewport motion state at `sample_time`.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_viewport_status(
    OmniNiriRuntime *runtime,
    double sample_time,
    OmniNiriRuntimeViewportStatus *out_status);

/// Begin a runtime-owned viewport gesture sequence.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_viewport_begin_gesture(
    OmniNiriRuntime *runtime,
    double sample_time,
    uint8_t is_trackpad);

/// Advance a runtime-owned viewport gesture sequence.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_niri_runtime_viewport_update_gesture(
    OmniNiriRuntime *runtime,
    double delta_pixels,
    double timestamp,
    double gap,
    double viewport_span,
    OmniViewportGestureUpdateResult *out_result);

/// Finish a runtime-owned viewport gesture sequence and start the snap spring.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_niri_runtime_viewport_end_gesture(
    OmniNiriRuntime *runtime,
    double gap,
    double viewport_span,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    double sample_time,
    double display_refresh_rate,
    uint8_t reduce_motion,
    OmniViewportGestureEndResult *out_result);

/// Transition the runtime-owned viewport toward a selected column.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_niri_runtime_viewport_transition_to_column(
    OmniNiriRuntime *runtime,
    size_t requested_index,
    double gap,
    double viewport_span,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    uint8_t animate,
    double scale,
    double sample_time,
    double display_refresh_rate,
    uint8_t reduce_motion,
    OmniViewportTransitionResult *out_result);

/// Force the runtime-owned viewport offset to a static value.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_viewport_set_offset(
    OmniNiriRuntime *runtime,
    double offset);

/// Cancel runtime-owned viewport gesture/spring motion at `sample_time`.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_viewport_cancel(
    OmniNiriRuntime *runtime,
    double sample_time);

/// Export full runtime snapshot pointers/counts.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_niri_runtime_snapshot(
    const OmniNiriRuntime *runtime,
    OmniNiriRuntimeStateExport *out_export);

typedef enum {
    OMNI_DWINDLE_NODE_SPLIT = 0,
    OMNI_DWINDLE_NODE_LEAF = 1
} OmniDwindleNodeKind;

typedef enum {
    OMNI_DWINDLE_ORIENTATION_HORIZONTAL = 0,
    OMNI_DWINDLE_ORIENTATION_VERTICAL = 1
} OmniDwindleOrientation;

typedef enum {
    OMNI_DWINDLE_DIRECTION_LEFT = 0,
    OMNI_DWINDLE_DIRECTION_RIGHT = 1,
    OMNI_DWINDLE_DIRECTION_UP = 2,
    OMNI_DWINDLE_DIRECTION_DOWN = 3
} OmniDwindleDirection;

typedef enum {
    OMNI_DWINDLE_OP_ADD_WINDOW = 0,
    OMNI_DWINDLE_OP_REMOVE_WINDOW = 1,
    OMNI_DWINDLE_OP_SYNC_WINDOWS = 2,
    OMNI_DWINDLE_OP_MOVE_FOCUS = 3,
    OMNI_DWINDLE_OP_SWAP_WINDOWS = 4,
    OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN = 5,
    OMNI_DWINDLE_OP_TOGGLE_ORIENTATION = 6,
    OMNI_DWINDLE_OP_RESIZE_SELECTED = 7,
    OMNI_DWINDLE_OP_BALANCE_SIZES = 8,
    OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO = 9,
    OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT = 10,
    OMNI_DWINDLE_OP_SWAP_SPLIT = 11,
    OMNI_DWINDLE_OP_SET_PRESELECTION = 12,
    OMNI_DWINDLE_OP_CLEAR_PRESELECTION = 13,
    OMNI_DWINDLE_OP_VALIDATE_SELECTION = 14
} OmniDwindleOp;

enum {
    /// Equivalent to (MAX_WINDOWS * 2) - 1 where MAX_WINDOWS is 512 in Zig ABI.
    OMNI_DWINDLE_MAX_NODES = 1023
};

typedef struct {
    OmniUuid128 node_id;
    int64_t parent_index;
    int64_t first_child_index;
    int64_t second_child_index;
    uint8_t kind;
    uint8_t orientation;
    double ratio;
    uint8_t has_window_id;
    OmniUuid128 window_id;
    uint8_t is_fullscreen;
} OmniDwindleSeedNode;

typedef struct {
    int64_t root_node_index;
    int64_t selected_node_index;
    uint8_t has_preselection;
    uint8_t preselection_direction;
} OmniDwindleSeedState;

typedef struct {
    uint8_t smart_split;
    double default_split_ratio;
    double split_width_multiplier;
    double inner_gap;
} OmniDwindleRuntimeSettings;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} OmniDwindleRect;

typedef struct {
    double screen_x;
    double screen_y;
    double screen_width;
    double screen_height;
    double inner_gap;
    double outer_gap_top;
    double outer_gap_bottom;
    double outer_gap_left;
    double outer_gap_right;
    double single_window_aspect_width;
    double single_window_aspect_height;
    double single_window_aspect_tolerance;
    OmniDwindleRuntimeSettings runtime_settings;
} OmniDwindleLayoutRequest;

typedef struct {
    OmniUuid128 window_id;
    double min_width;
    double min_height;
    double max_width;
    double max_height;
    uint8_t has_max_width;
    uint8_t has_max_height;
    uint8_t is_fixed;
} OmniDwindleWindowConstraint;

typedef struct {
    OmniUuid128 window_id;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
} OmniDwindleWindowFrame;

typedef struct {
    OmniUuid128 window_id;
    uint8_t has_active_window_frame;
    OmniDwindleRect active_window_frame;
} OmniDwindleAddWindowPayload;

typedef struct {
    OmniUuid128 window_id;
} OmniDwindleRemoveWindowPayload;

typedef struct {
    const OmniUuid128 *window_ids;
    size_t window_count;
} OmniDwindleSyncWindowsPayload;

typedef struct {
    uint8_t direction;
} OmniDwindleMoveFocusPayload;

typedef struct {
    uint8_t direction;
} OmniDwindleSwapWindowsPayload;

typedef struct {
    uint8_t unused;
} OmniDwindleToggleFullscreenPayload;

typedef struct {
    uint8_t unused;
} OmniDwindleToggleOrientationPayload;

typedef struct {
    double delta;
    uint8_t direction;
} OmniDwindleResizeSelectedPayload;

typedef struct {
    uint8_t unused;
} OmniDwindleBalanceSizesPayload;

typedef struct {
    uint8_t forward;
} OmniDwindleCycleSplitRatioPayload;

typedef struct {
    uint8_t stable;
} OmniDwindleMoveSelectionToRootPayload;

typedef struct {
    uint8_t unused;
} OmniDwindleSwapSplitPayload;

typedef struct {
    uint8_t direction;
} OmniDwindleSetPreselectionPayload;

typedef struct {
    uint8_t unused;
} OmniDwindleClearPreselectionPayload;

typedef struct {
    uint8_t unused;
} OmniDwindleValidateSelectionPayload;

typedef union {
    OmniDwindleAddWindowPayload add_window;
    OmniDwindleRemoveWindowPayload remove_window;
    OmniDwindleSyncWindowsPayload sync_windows;
    OmniDwindleMoveFocusPayload move_focus;
    OmniDwindleSwapWindowsPayload swap_windows;
    OmniDwindleToggleFullscreenPayload toggle_fullscreen;
    OmniDwindleToggleOrientationPayload toggle_orientation;
    OmniDwindleResizeSelectedPayload resize_selected;
    OmniDwindleBalanceSizesPayload balance_sizes;
    OmniDwindleCycleSplitRatioPayload cycle_split_ratio;
    OmniDwindleMoveSelectionToRootPayload move_selection_to_root;
    OmniDwindleSwapSplitPayload swap_split;
    OmniDwindleSetPreselectionPayload set_preselection;
    OmniDwindleClearPreselectionPayload clear_preselection;
    OmniDwindleValidateSelectionPayload validate_selection;
} OmniDwindleOpPayload;

typedef struct {
    uint8_t op;
    OmniDwindleOpPayload payload;
    OmniDwindleRuntimeSettings runtime_settings;
} OmniDwindleOpRequest;

typedef struct {
    uint8_t applied;
    uint8_t has_selected_window_id;
    OmniUuid128 selected_window_id;
    uint8_t has_focused_window_id;
    OmniUuid128 focused_window_id;
    uint8_t has_preselection;
    uint8_t preselection_direction;
    size_t removed_window_count;
} OmniDwindleOpResult;

/// Create a reusable Dwindle layout context.
/// Returns NULL on allocation failure.
OmniDwindleLayoutContext *omni_dwindle_layout_context_create(void);

/// Destroy a reusable Dwindle layout context.
void omni_dwindle_layout_context_destroy(OmniDwindleLayoutContext *context);

/// Seed deterministic Dwindle state topology into context.
/// Returns 0 on success, -1 for invalid args, -2 for range/topology failures.
int32_t omni_dwindle_ctx_seed_state(
    OmniDwindleLayoutContext *context,
    const OmniDwindleSeedNode *nodes,
    size_t node_count,
    const OmniDwindleSeedState *seed_state);

/// Apply one deterministic Dwindle operation request.
/// Returns 0 on success, -1 for invalid args, -2 for range failures.
int32_t omni_dwindle_ctx_apply_op(
    OmniDwindleLayoutContext *context,
    const OmniDwindleOpRequest *request,
    OmniDwindleOpResult *out_result,
    OmniUuid128 *out_removed_window_ids,
    size_t out_removed_window_capacity);

/// Calculate Dwindle layout outputs for current deterministic context state.
/// Returns 0 on success, -1 for invalid args, -2 for range failures.
int32_t omni_dwindle_ctx_calculate_layout(
    OmniDwindleLayoutContext *context,
    const OmniDwindleLayoutRequest *request,
    const OmniDwindleWindowConstraint *constraints,
    size_t constraint_count,
    OmniDwindleWindowFrame *out_frames,
    size_t out_frame_capacity,
    size_t *out_frame_count);

/// Find directional geometric neighbor for a window in current context state.
/// Returns 0 on success, -1 for invalid args, -2 for range failures.
int32_t omni_dwindle_ctx_find_neighbor(
    const OmniDwindleLayoutContext *context,
    OmniUuid128 window_id,
    uint8_t direction,
    double inner_gap,
    uint8_t *out_has_neighbor,
    OmniUuid128 *out_neighbor_window_id);

enum {
    OMNI_CONTROLLER_ABI_VERSION = 1,
    OMNI_CONTROLLER_NAME_CAP = 64,
    OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS = 128,
    OMNI_CONTROLLER_UI_WORKSPACE_CAP = 32
};

typedef enum {
    OMNI_INPUT_EFFECT_DISPATCH_EVENT = 0
} OmniInputEffectKind;

typedef enum {
    OMNI_INPUT_EVENT_MOUSE_MOVED = 0,
    OMNI_INPUT_EVENT_LEFT_MOUSE_DOWN = 1,
    OMNI_INPUT_EVENT_LEFT_MOUSE_DRAGGED = 2,
    OMNI_INPUT_EVENT_LEFT_MOUSE_UP = 3,
    OMNI_INPUT_EVENT_SCROLL_WHEEL = 4,
    OMNI_INPUT_EVENT_GESTURE = 5,
    OMNI_INPUT_EVENT_SECURE_INPUT_CHANGED = 6
} OmniInputEventKind;

typedef enum {
    OMNI_INPUT_TAP_KIND_MOUSE = 0,
    OMNI_INPUT_TAP_KIND_GESTURE = 1,
    OMNI_INPUT_TAP_KIND_SECURE_INPUT = 2
} OmniInputTapKind;

typedef enum {
    OMNI_INPUT_TAP_HEALTH_DISABLED_TIMEOUT = 0,
    OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT = 1
} OmniInputTapHealthReason;

typedef enum {
    OMNI_CONTROLLER_LAYOUT_DEFAULT = 0,
    OMNI_CONTROLLER_LAYOUT_NIRI = 1,
    OMNI_CONTROLLER_LAYOUT_DWINDLE = 2
} OmniControllerLayoutKind;

typedef enum {
    OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_DIRECTION = 0,
    OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_PREVIOUS = 1,
    OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_NEXT = 2,
    OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_LAST = 3,
    OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX = 4,
    OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_NEXT = 5,
    OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_PREVIOUS = 6,
    OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE = 7,
    OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE = 8,
    OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_DIRECTION = 9,
    OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_NEXT = 10,
    OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_PREVIOUS = 11,
    OMNI_CONTROLLER_COMMAND_SWAP_WORKSPACE_WITH_MONITOR_DIRECTION = 12,
    OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX = 13,
    OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_UP = 14,
    OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN = 15,
    OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_MONITOR_DIRECTION = 16,
    OMNI_CONTROLLER_COMMAND_MOVE_WINDOW_TO_WORKSPACE_ON_MONITOR = 17,
    OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_WORKSPACE_INDEX = 18,
    OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_UP = 19,
    OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN = 20,
    OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_MONITOR_DIRECTION = 21,
    OMNI_CONTROLLER_COMMAND_WORKSPACE_BACK_AND_FORTH = 22,
    OMNI_CONTROLLER_COMMAND_OPEN_WINDOW_FINDER = 23,
    OMNI_CONTROLLER_COMMAND_RAISE_ALL_FLOATING_WINDOWS = 24,
    OMNI_CONTROLLER_COMMAND_OPEN_MENU_ANYWHERE = 25,
    OMNI_CONTROLLER_COMMAND_OPEN_MENU_PALETTE = 26,
    OMNI_CONTROLLER_COMMAND_TOGGLE_HIDDEN_BAR = 27,
    OMNI_CONTROLLER_COMMAND_TOGGLE_QUAKE_TERMINAL = 28,
    OMNI_CONTROLLER_COMMAND_TOGGLE_OVERVIEW = 29,
    OMNI_CONTROLLER_COMMAND_FOCUS_PREVIOUS = 30,
    OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION = 31,
    OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION = 32,
    OMNI_CONTROLLER_COMMAND_SWAP_DIRECTION = 33,
    OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN = 34,
    OMNI_CONTROLLER_COMMAND_TOGGLE_NATIVE_FULLSCREEN = 35,
    OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_DIRECTION = 36,
    OMNI_CONTROLLER_COMMAND_CONSUME_WINDOW_DIRECTION = 37,
    OMNI_CONTROLLER_COMMAND_EXPEL_WINDOW_DIRECTION = 38,
    OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_TABBED = 39,
    OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT = 40,
    OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT = 41,
    OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST = 42,
    OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST = 43,
    OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX = 44,
    OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP = 45,
    OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM = 46,
    OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_FORWARD = 47,
    OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_BACKWARD = 48,
    OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_FULL_WIDTH = 49,
    OMNI_CONTROLLER_COMMAND_BALANCE_SIZES = 50,
    OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT = 51,
    OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT = 52,
    OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT = 53,
    OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION = 54,
    OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION = 55,
    OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR = 56,
    OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT = 57
} OmniControllerCommandKind;

typedef enum {
    OMNI_CONTROLLER_EVENT_REFRESH_SESSION = 0,
    OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED = 1,
    OMNI_CONTROLLER_EVENT_LOCK_SCREEN_CHANGED = 2,
    OMNI_CONTROLLER_EVENT_APP_ACTIVATED = 3,
    OMNI_CONTROLLER_EVENT_APP_HIDDEN = 4,
    OMNI_CONTROLLER_EVENT_APP_UNHIDDEN = 5,
    OMNI_CONTROLLER_EVENT_MONITOR_RECONFIGURED = 6,
    OMNI_CONTROLLER_EVENT_FOCUS_CHANGED = 7,
    OMNI_CONTROLLER_EVENT_WINDOW_REMOVED = 8,
    OMNI_CONTROLLER_EVENT_RECOVER_FOCUS = 9
} OmniControllerEventKind;

typedef enum {
    OMNI_CONTROLLER_REFRESH_REASON_TIMER = 0,
    OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CREATED = 1,
    OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED = 2,
    OMNI_CONTROLLER_REFRESH_REASON_APP_HIDDEN = 3,
    OMNI_CONTROLLER_REFRESH_REASON_APP_UNHIDDEN = 4,
    OMNI_CONTROLLER_REFRESH_REASON_MONITOR_RECONFIGURED = 5
} OmniControllerRefreshReason;

typedef enum {
    OMNI_CONTROLLER_ROUTE_FOCUS_MONITOR = 0,
    OMNI_CONTROLLER_ROUTE_SWITCH_WORKSPACE = 1,
    OMNI_CONTROLLER_ROUTE_FOCUS_WORKSPACE_ANYWHERE = 2,
    OMNI_CONTROLLER_ROUTE_SUMMON_WORKSPACE = 3,
    OMNI_CONTROLLER_ROUTE_MOVE_WORKSPACE_TO_MONITOR = 4,
    OMNI_CONTROLLER_ROUTE_SWAP_WORKSPACES = 5
} OmniControllerRouteKind;

typedef enum {
    OMNI_CONTROLLER_TRANSFER_MOVE_WINDOW = 0,
    OMNI_CONTROLLER_TRANSFER_MOVE_COLUMN = 1
} OmniControllerTransferKind;

typedef enum {
    OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_WINDOW = 0,
    OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_WINDOW = 1,
    OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_NIRI_WINDOW = 2,
    OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_DWINDLE_WINDOW = 3,
    OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_NIRI_COLUMN = 4,
    OMNI_CONTROLLER_TRANSFER_MODE_NIRI_TO_DWINDLE_BATCH = 5,
    OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_NIRI_COLUMN = 6,
    OMNI_CONTROLLER_TRANSFER_MODE_DWINDLE_TO_DWINDLE_BATCH = 7
} OmniControllerTransferMode;

typedef enum {
    OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER = 0,
    OMNI_CONTROLLER_UI_RAISE_ALL_FLOATING_WINDOWS = 1,
    OMNI_CONTROLLER_UI_OPEN_MENU_ANYWHERE = 2,
    OMNI_CONTROLLER_UI_OPEN_MENU_PALETTE = 3,
    OMNI_CONTROLLER_UI_TOGGLE_HIDDEN_BAR = 4,
    OMNI_CONTROLLER_UI_TOGGLE_QUAKE_TERMINAL = 5,
    OMNI_CONTROLLER_UI_TOGGLE_OVERVIEW = 6,
    OMNI_CONTROLLER_UI_SHOW_SECURE_INPUT = 7,
    OMNI_CONTROLLER_UI_HIDE_SECURE_INPUT = 8
} OmniControllerUiActionKind;

typedef enum {
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DIRECTION = 0,
    OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_DIRECTION = 1,
    OMNI_CONTROLLER_LAYOUT_ACTION_SWAP_DIRECTION = 2,
    OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_FULLSCREEN = 3,
    OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_NATIVE_FULLSCREEN = 4,
    OMNI_CONTROLLER_LAYOUT_ACTION_MOVE_COLUMN_DIRECTION = 5,
    OMNI_CONTROLLER_LAYOUT_ACTION_CONSUME_WINDOW_DIRECTION = 6,
    OMNI_CONTROLLER_LAYOUT_ACTION_EXPEL_WINDOW_DIRECTION = 7,
    OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_TABBED = 8,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_DOWN_OR_LEFT = 9,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_UP_OR_RIGHT = 10,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_FIRST = 11,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_LAST = 12,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_COLUMN_INDEX = 13,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_TOP = 14,
    OMNI_CONTROLLER_LAYOUT_ACTION_FOCUS_WINDOW_BOTTOM = 15,
    OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_FORWARD = 16,
    OMNI_CONTROLLER_LAYOUT_ACTION_CYCLE_COLUMN_WIDTH_BACKWARD = 17,
    OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_COLUMN_FULL_WIDTH = 18,
    OMNI_CONTROLLER_LAYOUT_ACTION_BALANCE_SIZES = 19,
    OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_MOVE_TO_ROOT = 20,
    OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_TOGGLE_SPLIT = 21,
    OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_SWAP_SPLIT = 22,
    OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_RESIZE_DIRECTION = 23,
    OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_DIRECTION = 24,
    OMNI_CONTROLLER_LAYOUT_ACTION_DWINDLE_PRESELECT_CLEAR = 25,
    OMNI_CONTROLLER_LAYOUT_ACTION_TOGGLE_WORKSPACE_LAYOUT = 26
} OmniControllerLayoutActionKind;

enum {
    OMNI_CONTROLLER_REFRESH_HIDE_BORDER = 1 << 0,
    OMNI_CONTROLLER_REFRESH_IMMEDIATE = 1 << 1,
    OMNI_CONTROLLER_REFRESH_INCREMENTAL = 1 << 2,
    OMNI_CONTROLLER_REFRESH_FULL = 1 << 3,
    OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE = 1 << 4,
    OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR = 1 << 5,
    OMNI_CONTROLLER_REFRESH_START_WORKSPACE_ANIMATION = 1 << 6,
    OMNI_CONTROLLER_REFRESH_STOP_SCROLL_ANIMATION = 1 << 7,
    OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT = 1 << 8
};

typedef struct {
    uint8_t length;
    char bytes[OMNI_CONTROLLER_NAME_CAP];
} OmniControllerName;

typedef struct {
    uint32_t display_id;
    uint8_t is_main;
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    double visible_x;
    double visible_y;
    double visible_width;
    double visible_height;
    OmniControllerName name;
} OmniControllerMonitorSnapshot;

typedef struct {
    OmniUuid128 workspace_id;
    uint8_t has_assigned_display_id;
    uint32_t assigned_display_id;
    uint8_t is_visible;
    uint8_t is_previous_visible;
    uint8_t layout_kind;
    OmniControllerName name;
    uint8_t has_selected_node_id;
    OmniUuid128 selected_node_id;
    uint8_t has_last_focused_window_id;
    OmniUuid128 last_focused_window_id;
} OmniControllerWorkspaceSnapshot;

typedef struct {
    OmniUuid128 handle_id;
    int32_t pid;
    int64_t window_id;
    OmniUuid128 workspace_id;
    uint8_t layout_kind;
    uint8_t is_hidden;
    uint8_t is_focused;
    uint8_t is_managed;
    uint8_t has_node_id;
    OmniUuid128 node_id;
    uint8_t has_column_id;
    OmniUuid128 column_id;
    int64_t order_index;
    int64_t column_index;
    int64_t row_index;
} OmniControllerWindowSnapshot;

typedef struct {
    const OmniControllerMonitorSnapshot *monitors;
    size_t monitor_count;
    const OmniControllerWorkspaceSnapshot *workspaces;
    size_t workspace_count;
    const OmniControllerWindowSnapshot *windows;
    size_t window_count;
    uint8_t has_focused_window_id;
    OmniUuid128 focused_window_id;
    uint8_t has_active_monitor_display_id;
    uint32_t active_monitor_display_id;
    uint8_t has_previous_monitor_display_id;
    uint32_t previous_monitor_display_id;
    uint8_t secure_input_active;
    uint8_t lock_screen_active;
    uint8_t non_managed_focus_active;
    uint8_t app_fullscreen_active;
    uint8_t focus_follows_window_to_monitor;
    uint8_t move_mouse_to_focused_window;
    uint8_t layout_light_session_active;
    uint8_t layout_immediate_in_progress;
    uint8_t layout_incremental_in_progress;
    uint8_t layout_full_enumeration_in_progress;
    uint8_t layout_animation_active;
    uint8_t layout_has_completed_initial_refresh;
} OmniControllerSnapshot;

typedef struct {
    uint8_t kind;
    uint8_t direction;
    int64_t workspace_index;
    uint8_t monitor_direction;
    uint8_t has_workspace_id;
    OmniUuid128 workspace_id;
    uint8_t has_window_handle_id;
    OmniUuid128 window_handle_id;
} OmniControllerCommand;

typedef struct {
    uint8_t length;
    uint8_t bytes[OMNI_INPUT_BINDING_ID_CAP];
} OmniInputBindingId;

typedef struct {
    OmniInputBindingId binding_id;
    uint32_t key_code;
    uint32_t modifiers;
    uint8_t enabled;
} OmniInputBinding;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniInputRuntimeConfig;

typedef struct {
    uint8_t hotkeys_enabled;
    uint8_t mouse_enabled;
    uint8_t gestures_enabled;
    uint8_t secure_input_enabled;
} OmniInputOptions;

typedef struct {
    uint8_t kind;
    uint8_t reserved[3];
    double location_x;
    double location_y;
    double delta_x;
    double delta_y;
    uint32_t momentum_phase;
    uint32_t phase;
    uint64_t modifiers;
    void *event_ref;
} OmniInputEvent;

typedef struct {
    uint8_t kind;
    uint8_t reserved[7];
    OmniInputEvent event;
} OmniInputEffect;

typedef struct {
    const OmniInputEffect *effects;
    size_t effect_count;
} OmniInputEffectExport;

typedef struct {
    OmniInputBindingId binding_id;
} OmniInputRegistrationFailure;

typedef int32_t (*OmniInputOnHotkeyCommandFn)(
    void *userdata,
    OmniControllerCommand command);

typedef int32_t (*OmniInputOnSecureInputStateChangedFn)(
    void *userdata,
    uint8_t is_secure_input_active);

typedef int32_t (*OmniInputOnMouseEffectBatchFn)(
    void *userdata,
    const OmniInputEffectExport *effects);

typedef int32_t (*OmniInputOnTapHealthNotificationFn)(
    void *userdata,
    uint8_t tap_kind,
    uint8_t reason);

typedef struct {
    void *userdata;
    OmniInputOnHotkeyCommandFn on_hotkey_command;
    OmniInputOnSecureInputStateChangedFn on_secure_input_state_changed;
    OmniInputOnMouseEffectBatchFn on_mouse_effect_batch;
    OmniInputOnTapHealthNotificationFn on_tap_health_notification;
} OmniInputHostVTable;

typedef struct {
    uint8_t kind;
    uint8_t enabled;
    uint8_t refresh_reason;
    uint8_t has_display_id;
    uint32_t display_id;
    int32_t pid;
    uint8_t has_window_handle_id;
    OmniUuid128 window_handle_id;
    uint8_t has_workspace_id;
    OmniUuid128 workspace_id;
} OmniControllerEvent;

typedef struct {
    uint8_t has_active_monitor_display_id;
    uint32_t active_monitor_display_id;
    uint8_t has_previous_monitor_display_id;
    uint32_t previous_monitor_display_id;
    uint8_t has_workspace_id;
    OmniUuid128 workspace_id;
    uint8_t has_selected_node_id;
    OmniUuid128 selected_node_id;
    uint8_t has_focused_window_id;
    OmniUuid128 focused_window_id;
    uint8_t clear_focus;
    uint8_t non_managed_focus_active;
    uint8_t app_fullscreen_active;
} OmniControllerFocusExport;

typedef struct {
    uint8_t kind;
    uint8_t create_target_workspace_if_missing;
    uint8_t animate_workspace_switch;
    uint8_t follow_focus;
    uint8_t has_source_display_id;
    uint32_t source_display_id;
    uint8_t has_target_display_id;
    uint32_t target_display_id;
    uint8_t has_source_workspace_id;
    OmniUuid128 source_workspace_id;
    uint8_t has_target_workspace_id;
    OmniUuid128 target_workspace_id;
    OmniControllerName source_workspace_name;
    OmniControllerName target_workspace_name;
} OmniControllerRoutePlan;

typedef struct {
    uint8_t kind;
    uint8_t mode;
    uint8_t create_target_workspace_if_missing;
    uint8_t follow_focus;
    uint8_t window_count;
    OmniUuid128 window_ids[OMNI_CONTROLLER_MAX_TRANSFER_WINDOWS];
    uint8_t has_source_workspace_id;
    OmniUuid128 source_workspace_id;
    OmniControllerName source_workspace_name;
    uint8_t has_target_workspace_id;
    OmniUuid128 target_workspace_id;
    OmniControllerName target_workspace_name;
    uint8_t has_target_monitor_display_id;
    uint32_t target_monitor_display_id;
    uint8_t has_source_fallback_window_id;
    OmniUuid128 source_fallback_window_id;
    uint8_t has_target_focus_window_id;
    OmniUuid128 target_focus_window_id;
    uint8_t has_source_selection_node_id;
    OmniUuid128 source_selection_node_id;
    uint8_t has_target_selection_node_id;
    OmniUuid128 target_selection_node_id;
} OmniControllerTransferPlan;

typedef struct {
    uint32_t flags;
    uint8_t has_workspace_id;
    OmniUuid128 workspace_id;
    uint8_t has_display_id;
    uint32_t display_id;
} OmniControllerRefreshPlan;

typedef struct {
    uint8_t kind;
} OmniControllerUiAction;

typedef struct {
    uint8_t kind;
    uint8_t direction;
    int64_t index;
    uint8_t flag;
} OmniControllerLayoutAction;

typedef struct {
    const OmniControllerFocusExport *focus_exports;
    size_t focus_export_count;
    const OmniControllerRoutePlan *route_plans;
    size_t route_plan_count;
    const OmniControllerTransferPlan *transfer_plans;
    size_t transfer_plan_count;
    const OmniControllerRefreshPlan *refresh_plans;
    size_t refresh_plan_count;
    const OmniControllerUiAction *ui_actions;
    size_t ui_action_count;
    const OmniControllerLayoutAction *layout_actions;
    size_t layout_action_count;
} OmniControllerEffectExport;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniControllerConfig;

typedef struct {
    uint8_t has_focus_follows_window_to_monitor;
    uint8_t focus_follows_window_to_monitor;
    uint8_t has_move_mouse_to_focused_window;
    uint8_t move_mouse_to_focused_window;
} OmniControllerSettingsDelta;

typedef struct {
    uint8_t has_focused_window_id;
    OmniUuid128 focused_window_id;
    uint8_t has_active_monitor_display_id;
    uint32_t active_monitor_display_id;
    uint8_t has_previous_monitor_display_id;
    uint32_t previous_monitor_display_id;
    uint8_t secure_input_active;
    uint8_t lock_screen_active;
    size_t visible_workspace_count;
    OmniUuid128 visible_workspace_ids[OMNI_CONTROLLER_UI_WORKSPACE_CAP];
} OmniControllerUiState;

typedef int32_t (*OmniControllerCaptureSnapshotFn)(
    void *userdata,
    OmniControllerSnapshot *out_snapshot);

typedef int32_t (*OmniControllerApplyEffectsFn)(
    void *userdata,
    const OmniControllerEffectExport *effects);

typedef int32_t (*OmniControllerReportErrorFn)(
    void *userdata,
    int32_t code,
    OmniControllerName message);

typedef struct {
    void *userdata;
    OmniControllerCaptureSnapshotFn capture_snapshot;
    OmniControllerApplyEffectsFn apply_effects;
    OmniControllerReportErrorFn report_error;
} OmniControllerPlatformVTable;

typedef int32_t (*OmniWMControllerApplyEffectsFn)(
    void *userdata,
    const OmniControllerEffectExport *effects);

typedef int32_t (*OmniWMControllerReportErrorFn)(
    void *userdata,
    int32_t code,
    OmniControllerName message);

typedef struct {
    void *userdata;
    OmniWMControllerApplyEffectsFn apply_effects;
    OmniWMControllerReportErrorFn report_error;
} OmniWMControllerHostVTable;

typedef struct {
    uint32_t abi_version;
    uint32_t reserved;
} OmniWMControllerConfig;

typedef struct {
    uint32_t abi_version;
    uint8_t poll_ax_permission;
    uint8_t request_ax_prompt;
    uint8_t reserved[2];
    uint32_t ax_poll_timeout_millis;
    uint32_t ax_poll_interval_millis;
} OmniServiceLifecycleConfig;

typedef struct {
    OmniWMController *wm_controller;
    OmniInputRuntime *input_runtime;
    OmniPlatformRuntime *platform_runtime;
    OmniWorkspaceObserverRuntime *workspace_observer_runtime;
    OmniLockObserverRuntime *lock_observer_runtime;
    OmniAXRuntime *ax_runtime;
    OmniMonitorRuntime *monitor_runtime;
} OmniServiceLifecycleHandles;

typedef int32_t (*OmniServiceLifecycleStateChangedFn)(
    void *userdata,
    uint8_t state);

typedef int32_t (*OmniServiceLifecycleErrorFn)(
    void *userdata,
    int32_t code,
    OmniControllerName message);

typedef struct {
    void *userdata;
    OmniServiceLifecycleStateChangedFn on_state_changed;
    OmniServiceLifecycleErrorFn on_error;
} OmniServiceLifecycleHostVTable;

/// Create a controller owner.
/// Returns NULL on allocation failure or invalid platform vtable.
OmniController *omni_controller_create(
    const OmniControllerConfig *config,
    const OmniControllerPlatformVTable *platform_vtable);

/// Destroy a controller owner.
void omni_controller_destroy(OmniController *controller);

/// Start controller processing.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_controller_start(OmniController *controller);

/// Stop controller processing and clear queued effects.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_controller_stop(OmniController *controller);

/// Submit one normalized hotkey command.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_controller_submit_hotkey(
    OmniController *controller,
    const OmniControllerCommand *command);

/// Submit one normalized OS/runtime event.
/// Returns 0 on success, -1 for invalid args, -2 for range/capacity failures.
int32_t omni_controller_submit_os_event(
    OmniController *controller,
    const OmniControllerEvent *event);

/// Apply runtime settings delta.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_controller_apply_settings(
    OmniController *controller,
    const OmniControllerSettingsDelta *settings_delta);

/// Advance any runtime-owned timers.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_controller_tick(
    OmniController *controller,
    double sample_time);

/// Query UI-facing runtime state.
/// Returns 0 on success, -1 for invalid args.
int32_t omni_controller_query_ui_state(
    const OmniController *controller,
    OmniControllerUiState *out_state);

OmniInputRuntime *omni_input_runtime_create(
    const OmniInputRuntimeConfig *config,
    const OmniInputHostVTable *host_vtable);

void omni_input_runtime_destroy(OmniInputRuntime *runtime);

int32_t omni_input_runtime_start(OmniInputRuntime *runtime);

int32_t omni_input_runtime_stop(OmniInputRuntime *runtime);

int32_t omni_input_runtime_set_bindings(
    OmniInputRuntime *runtime,
    const OmniInputBinding *bindings,
    size_t binding_count);

int32_t omni_input_runtime_set_options(
    OmniInputRuntime *runtime,
    const OmniInputOptions *options);

int32_t omni_input_runtime_submit_event(
    OmniInputRuntime *runtime,
    const OmniInputEvent *event);

int32_t omni_input_runtime_query_registration_failures(
    OmniInputRuntime *runtime,
    OmniInputRegistrationFailure *out_failures,
    size_t out_capacity,
    size_t *out_written);

OmniWMController *omni_wm_controller_create(
    const OmniWMControllerConfig *config,
    OmniWorkspaceRuntime *workspace_runtime_owner,
    const OmniWMControllerHostVTable *host_vtable);

void omni_wm_controller_destroy(OmniWMController *runtime_owner);

int32_t omni_wm_controller_start(OmniWMController *runtime_owner);

int32_t omni_wm_controller_stop(OmniWMController *runtime_owner);

int32_t omni_wm_controller_submit_hotkey(
    OmniWMController *runtime_owner,
    const OmniControllerCommand *command);

int32_t omni_wm_controller_submit_os_event(
    OmniWMController *runtime_owner,
    const OmniControllerEvent *event);

int32_t omni_wm_controller_apply_settings(
    OmniWMController *runtime_owner,
    const OmniControllerSettingsDelta *settings_delta);

int32_t omni_wm_controller_tick(
    OmniWMController *runtime_owner,
    double sample_time);

int32_t omni_wm_controller_query_ui_state(
    const OmniWMController *runtime_owner,
    OmniControllerUiState *out_state);

int32_t omni_wm_controller_export_workspace_state(
    OmniWMController *runtime_owner,
    OmniWorkspaceRuntimeStateExport *out_export);

int32_t omni_ui_bridge_submit_hotkey(
    OmniWMController *runtime_owner,
    const OmniControllerCommand *command);

int32_t omni_ui_bridge_apply_settings(
    OmniWMController *runtime_owner,
    const OmniControllerSettingsDelta *settings_delta);

int32_t omni_ui_bridge_query_ui_state(
    const OmniWMController *runtime_owner,
    OmniControllerUiState *out_state);

int32_t omni_ui_bridge_export_workspace_state(
    OmniWMController *runtime_owner,
    OmniWorkspaceRuntimeStateExport *out_export);

OmniServiceLifecycle *omni_service_lifecycle_create(
    const OmniServiceLifecycleConfig *config,
    const OmniServiceLifecycleHandles *handles,
    const OmniServiceLifecycleHostVTable *host_vtable);

void omni_service_lifecycle_destroy(OmniServiceLifecycle *runtime_owner);

int32_t omni_service_lifecycle_start(OmniServiceLifecycle *runtime_owner);

int32_t omni_service_lifecycle_stop(OmniServiceLifecycle *runtime_owner);

int32_t omni_service_lifecycle_query_state(
    const OmniServiceLifecycle *runtime_owner,
    uint8_t *out_state);

int32_t omni_focus_activate_application(int32_t pid);

int32_t omni_focus_raise_window(int32_t pid, uint32_t window_id);

int32_t omni_focus_window(int32_t pid, uint32_t window_id);

double omni_animation_cubic_ease_in_out(double t);

double omni_animation_spring_progress(
    double t,
    double response,
    double damping_ratio);

uint8_t omni_mouse_gesture_early_exit_action(uint8_t phase);
