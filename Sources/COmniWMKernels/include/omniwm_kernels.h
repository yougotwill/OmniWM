#ifndef OMNIWM_KERNELS_H
#define OMNIWM_KERNELS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    OMNIWM_KERNELS_STATUS_OK = 0,
    OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT = 1,
    OMNIWM_KERNELS_STATUS_ALLOCATION_FAILED = 2,
};

enum {
    OMNIWM_CENTER_FOCUSED_COLUMN_NEVER = 0,
    OMNIWM_CENTER_FOCUSED_COLUMN_ALWAYS = 1,
    OMNIWM_CENTER_FOCUSED_COLUMN_ON_OVERFLOW = 2,
};

enum {
    OMNIWM_DWINDLE_NODE_KIND_SPLIT = 0,
    OMNIWM_DWINDLE_NODE_KIND_LEAF = 1,
};

enum {
    OMNIWM_DWINDLE_ORIENTATION_HORIZONTAL = 0,
    OMNIWM_DWINDLE_ORIENTATION_VERTICAL = 1,
};

enum {
    OMNIWM_NIRI_ORIENTATION_HORIZONTAL = 0,
    OMNIWM_NIRI_ORIENTATION_VERTICAL = 1,
};

enum {
    OMNIWM_NIRI_WINDOW_SIZING_NORMAL = 0,
    OMNIWM_NIRI_WINDOW_SIZING_FULLSCREEN = 1,
};

enum {
    OMNIWM_NIRI_HIDDEN_EDGE_NONE = 0,
    OMNIWM_NIRI_HIDDEN_EDGE_MINIMUM = 1,
    OMNIWM_NIRI_HIDDEN_EDGE_MAXIMUM = 2,
};

typedef struct {
    double weight;
    double min_constraint;
    double max_constraint;
    double fixed_value;
    uint8_t has_max_constraint;
    uint8_t is_constraint_fixed;
    uint8_t has_fixed_value;
} omniwm_axis_input;

typedef struct {
    double value;
    uint8_t was_constrained;
} omniwm_axis_output;

typedef struct {
    int32_t root_index;
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
    double minimum_dimension;
    double gap_sticks_tolerance;
    double split_ratio_min;
    double split_ratio_max;
    double split_fraction_divisor;
    double split_fraction_min;
    double split_fraction_max;
} omniwm_dwindle_layout_input;

typedef struct {
    int32_t first_child_index;
    int32_t second_child_index;
    double split_ratio;
    double min_width;
    double min_height;
    uint32_t kind;
    uint32_t orientation;
    uint8_t has_window;
    uint8_t fullscreen;
} omniwm_dwindle_node_input;

typedef struct {
    double x;
    double y;
    double width;
    double height;
    uint8_t has_frame;
} omniwm_dwindle_node_frame;

typedef struct {
    double working_x;
    double working_y;
    double working_width;
    double working_height;
    double view_x;
    double view_y;
    double view_width;
    double view_height;
    double scale;
    double primary_gap;
    double secondary_gap;
    double tab_indicator_width;
    double view_offset;
    double workspace_offset;
    double single_window_aspect_ratio;
    double single_window_aspect_tolerance;
    int32_t active_container_index;
    int32_t hidden_placement_monitor_index;
    uint32_t orientation;
    uint8_t single_window_mode;
} omniwm_niri_layout_input;

typedef struct {
    double span;
    double render_offset_x;
    double render_offset_y;
    uint32_t window_start_index;
    uint32_t window_count;
    uint8_t is_tabbed;
    uint8_t has_manual_single_window_width_override;
} omniwm_niri_container_input;

typedef struct {
    double weight;
    double min_constraint;
    double max_constraint;
    double fixed_value;
    double render_offset_x;
    double render_offset_y;
    uint8_t has_max_constraint;
    uint8_t is_constraint_fixed;
    uint8_t has_fixed_value;
    uint8_t sizing_mode;
} omniwm_niri_window_input;

typedef struct {
    double frame_x;
    double frame_y;
    double frame_width;
    double frame_height;
    double visible_x;
    double visible_y;
    double visible_width;
    double visible_height;
} omniwm_niri_hidden_placement_monitor;

typedef struct {
    double canonical_x;
    double canonical_y;
    double canonical_width;
    double canonical_height;
    double rendered_x;
    double rendered_y;
    double rendered_width;
    double rendered_height;
} omniwm_niri_container_output;

typedef struct {
    double canonical_x;
    double canonical_y;
    double canonical_width;
    double canonical_height;
    double rendered_x;
    double rendered_y;
    double rendered_width;
    double rendered_height;
    double resolved_span;
    uint8_t hidden_edge;
} omniwm_niri_window_output;

int32_t omniwm_axis_solve(
    const omniwm_axis_input *inputs,
    size_t count,
    double available_space,
    double gap_size,
    uint8_t is_tabbed,
    omniwm_axis_output *outputs
);

int32_t omniwm_dwindle_solve(
    const omniwm_dwindle_layout_input *input,
    const omniwm_dwindle_node_input *nodes,
    size_t node_count,
    omniwm_dwindle_node_frame *outputs,
    size_t output_count
);

int32_t omniwm_niri_layout_solve(
    const omniwm_niri_layout_input *input,
    const omniwm_niri_container_input *containers,
    size_t container_count,
    const omniwm_niri_window_input *windows,
    size_t window_count,
    const omniwm_niri_hidden_placement_monitor *monitors,
    size_t monitor_count,
    omniwm_niri_container_output *container_outputs,
    size_t container_output_count,
    omniwm_niri_window_output *window_outputs,
    size_t window_output_count
);

double omniwm_geometry_container_position(
    const double *spans,
    size_t count,
    double gap,
    size_t index
);

double omniwm_geometry_total_span(
    const double *spans,
    size_t count,
    double gap
);

double omniwm_geometry_centered_offset(
    const double *spans,
    size_t count,
    double gap,
    double viewport_span,
    size_t index
);

double omniwm_geometry_visible_offset(
    const double *spans,
    size_t count,
    double gap,
    double viewport_span,
    int32_t index,
    double current_view_start,
    uint32_t center_mode,
    uint8_t always_center_single_column,
    int32_t from_index,
    double scale
);

typedef struct {
    uint32_t display_id;
    double anchor_x;
    double anchor_y;
    double frame_width;
    double frame_height;
} omniwm_restore_snapshot;

typedef struct {
    uint32_t display_id;
    double frame_min_x;
    double frame_max_y;
    double anchor_x;
    double anchor_y;
    double frame_width;
    double frame_height;
} omniwm_restore_monitor;

typedef struct {
    uint32_t snapshot_index;
    uint32_t monitor_index;
} omniwm_restore_assignment;

int32_t omniwm_restore_resolve_assignments(
    const omniwm_restore_snapshot *snapshots,
    size_t snapshot_count,
    const omniwm_restore_monitor *monitors,
    size_t monitor_count,
    const uint8_t *name_penalties,
    size_t name_penalty_count,
    omniwm_restore_assignment *assignments,
    size_t assignment_capacity,
    size_t *assignment_count
);

#ifdef __cplusplus
}
#endif

#endif
