#pragma once
#include <stddef.h>
#include <stdint.h>

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

enum {
    OMNI_OK = 0,
    OMNI_ERR_INVALID_ARGS = -1,
    OMNI_ERR_OUT_OF_RANGE = -2
};

/// Solve axis layout for window_count windows.
///
/// is_tabbed: 0 = normal (weighted) layout, 1 = tabbed (all windows share one span).
///
/// Returns 0 on success.
/// Returns -1 if out_count < window_count or window_count exceeds the internal limit.
int32_t omni_axis_solve(
    const OmniAxisInput *windows,
    size_t window_count,
    double available_space,
    double gap_size,
    uint8_t is_tabbed,
    OmniAxisOutput *out,
    size_t out_count);

/// Tabbed variant (all windows get the same span, gaps are ignored).
/// Equivalent to calling omni_axis_solve with is_tabbed = 1.
int32_t omni_axis_solve_tabbed(
    const OmniAxisInput *windows,
    size_t window_count,
    double available_space,
    double gap_size,
    OmniAxisOutput *out,
    size_t out_count);

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

int32_t omni_viewport_find_snap_target(
    const double *spans,
    size_t span_count,
    double gap,
    double viewport_span,
    double projected_view_pos,
    double current_view_pos,
    uint8_t center_mode,
    uint8_t always_center_single_column,
    OmniSnapResult *out_result);

int32_t omni_niri_layout_pass(
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
    size_t out_window_count);
