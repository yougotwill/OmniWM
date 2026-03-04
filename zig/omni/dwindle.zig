const std = @import("std");
const abi = @import("abi_types.zig");

const MIN_RATIO: f64 = 0.1;
const MAX_RATIO: f64 = 1.9;

pub const OmniDwindleLayoutContext = extern struct {
    node_count: usize,
    nodes: [abi.OMNI_DWINDLE_MAX_NODES]abi.OmniDwindleSeedNode,
    seed_state: abi.OmniDwindleSeedState,
    cached_frame_count: usize,
    cached_frames: [abi.MAX_WINDOWS]abi.OmniDwindleWindowFrame,
};

fn zeroUuid() abi.OmniUuid128 {
    return .{ .bytes = [_]u8{0} ** 16 };
}

fn isZeroUuid(uuid: abi.OmniUuid128) bool {
    return std.mem.eql(u8, uuid.bytes[0..], zeroUuid().bytes[0..]);
}

fn uuidEqual(a: abi.OmniUuid128, b: abi.OmniUuid128) bool {
    return std.mem.eql(u8, a.bytes[0..], b.bytes[0..]);
}

fn isFlag(value: u8) bool {
    return value == 0 or value == 1;
}

fn isFiniteNonNegative(value: f64) bool {
    return std.math.isFinite(value) and value >= 0;
}

fn isValidDirection(direction: u8) bool {
    return switch (direction) {
        abi.OMNI_DWINDLE_DIRECTION_LEFT,
        abi.OMNI_DWINDLE_DIRECTION_RIGHT,
        abi.OMNI_DWINDLE_DIRECTION_UP,
        abi.OMNI_DWINDLE_DIRECTION_DOWN,
        => true,
        else => false,
    };
}

fn isValidOrientation(orientation: u8) bool {
    return switch (orientation) {
        abi.OMNI_DWINDLE_ORIENTATION_HORIZONTAL, abi.OMNI_DWINDLE_ORIENTATION_VERTICAL => true,
        else => false,
    };
}

fn isValidNodeKind(kind: u8) bool {
    return switch (kind) {
        abi.OMNI_DWINDLE_NODE_SPLIT, abi.OMNI_DWINDLE_NODE_LEAF => true,
        else => false,
    };
}

fn isValidOp(op: u8) bool {
    return switch (op) {
        abi.OMNI_DWINDLE_OP_ADD_WINDOW,
        abi.OMNI_DWINDLE_OP_REMOVE_WINDOW,
        abi.OMNI_DWINDLE_OP_SYNC_WINDOWS,
        abi.OMNI_DWINDLE_OP_MOVE_FOCUS,
        abi.OMNI_DWINDLE_OP_SWAP_WINDOWS,
        abi.OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN,
        abi.OMNI_DWINDLE_OP_TOGGLE_ORIENTATION,
        abi.OMNI_DWINDLE_OP_RESIZE_SELECTED,
        abi.OMNI_DWINDLE_OP_BALANCE_SIZES,
        abi.OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO,
        abi.OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT,
        abi.OMNI_DWINDLE_OP_SWAP_SPLIT,
        abi.OMNI_DWINDLE_OP_SET_PRESELECTION,
        abi.OMNI_DWINDLE_OP_CLEAR_PRESELECTION,
        abi.OMNI_DWINDLE_OP_VALIDATE_SELECTION,
        => true,
        else => false,
    };
}

fn parseOptionalIndex(raw: i64, count: usize, out_index: *?usize) i32 {
    if (raw == -1) {
        out_index.* = null;
        return abi.OMNI_OK;
    }
    if (raw < -1) return abi.OMNI_ERR_OUT_OF_RANGE;
    const index = std.math.cast(usize, raw) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (index >= count) return abi.OMNI_ERR_OUT_OF_RANGE;
    out_index.* = index;
    return abi.OMNI_OK;
}

fn resetContext(ctx: *OmniDwindleLayoutContext) void {
    ctx.node_count = 0;
    ctx.seed_state = .{
        .root_node_index = -1,
        .selected_node_index = -1,
        .has_preselection = 0,
        .preselection_direction = abi.OMNI_DWINDLE_DIRECTION_LEFT,
    };
    ctx.cached_frame_count = 0;
}

fn asMutableContext(context: [*c]OmniDwindleLayoutContext) ?*OmniDwindleLayoutContext {
    if (context == null) return null;
    const ptr: *OmniDwindleLayoutContext = @ptrCast(&context[0]);
    return ptr;
}

fn asConstContext(context: [*c]const OmniDwindleLayoutContext) ?*const OmniDwindleLayoutContext {
    if (context == null) return null;
    const ptr: *const OmniDwindleLayoutContext = @ptrCast(&context[0]);
    return ptr;
}

fn initOpResult(out_result: [*c]abi.OmniDwindleOpResult) void {
    out_result[0] = .{
        .applied = 0,
        .has_selected_window_id = 0,
        .selected_window_id = zeroUuid(),
        .has_focused_window_id = 0,
        .focused_window_id = zeroUuid(),
        .has_preselection = 0,
        .preselection_direction = abi.OMNI_DWINDLE_DIRECTION_LEFT,
        .removed_window_count = 0,
    };
}

fn validateNodeIdUniqueness(nodes: [*c]const abi.OmniDwindleSeedNode, node_count: usize) i32 {
    for (0..node_count) |idx| {
        const current = nodes[idx].node_id;
        for ((idx + 1)..node_count) |other_idx| {
            if (uuidEqual(current, nodes[other_idx].node_id)) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }
    return abi.OMNI_OK;
}

fn validateWindowIdUniqueness(nodes: [*c]const abi.OmniDwindleSeedNode, node_count: usize) i32 {
    for (0..node_count) |idx| {
        if (nodes[idx].has_window_id == 0) continue;
        const current = nodes[idx].window_id;
        for ((idx + 1)..node_count) |other_idx| {
            if (nodes[other_idx].has_window_id == 0) continue;
            if (uuidEqual(current, nodes[other_idx].window_id)) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }
    return abi.OMNI_OK;
}

fn validateAcyclicParentChain(nodes: [*c]const abi.OmniDwindleSeedNode, node_count: usize) i32 {
    for (0..node_count) |start_idx| {
        var current_idx = start_idx;
        var steps: usize = 0;

        while (true) {
            const parent_raw = nodes[current_idx].parent_index;
            if (parent_raw == -1) break;

            const parent = std.math.cast(usize, parent_raw) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (parent >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

            steps += 1;
            if (steps > node_count) return abi.OMNI_ERR_INVALID_ARGS;
            current_idx = parent;
        }
    }

    return abi.OMNI_OK;
}

fn validateReachabilityFromRoot(
    nodes: [*c]const abi.OmniDwindleSeedNode,
    node_count: usize,
    root_idx: usize,
) i32 {
    var visited = [_]u8{0} ** abi.OMNI_DWINDLE_MAX_NODES;
    var stack = [_]usize{0} ** abi.OMNI_DWINDLE_MAX_NODES;
    var stack_len: usize = 0;
    var visited_count: usize = 0;

    stack[0] = root_idx;
    stack_len = 1;

    while (stack_len > 0) {
        stack_len -= 1;
        const node_index = stack[stack_len];
        if (node_index >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

        if (visited[node_index] != 0) return abi.OMNI_ERR_INVALID_ARGS;
        visited[node_index] = 1;
        visited_count += 1;

        const node = nodes[node_index];
        if (node.kind == abi.OMNI_DWINDLE_NODE_SPLIT) {
            const first = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const second = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (first >= node_count or second >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

            if (stack_len + 2 > node_count) return abi.OMNI_ERR_INVALID_ARGS;
            stack[stack_len] = first;
            stack_len += 1;
            stack[stack_len] = second;
            stack_len += 1;
        }
    }

    if (visited_count != node_count) return abi.OMNI_ERR_INVALID_ARGS;
    return abi.OMNI_OK;
}

pub fn omni_dwindle_layout_context_create_impl() [*c]OmniDwindleLayoutContext {
    const ctx = std.heap.c_allocator.create(OmniDwindleLayoutContext) catch return null;
    ctx.* = undefined;
    resetContext(ctx);
    return @ptrCast(ctx);
}

pub fn omni_dwindle_layout_context_destroy_impl(context: [*c]OmniDwindleLayoutContext) void {
    const ctx = asMutableContext(context) orelse return;
    std.heap.c_allocator.destroy(ctx);
}

pub fn omni_dwindle_ctx_seed_state_impl(
    context: [*c]OmniDwindleLayoutContext,
    nodes: [*c]const abi.OmniDwindleSeedNode,
    node_count: usize,
    seed_state: [*c]const abi.OmniDwindleSeedState,
) i32 {
    const ctx = asMutableContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (seed_state == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (node_count > abi.OMNI_DWINDLE_MAX_NODES) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (node_count > 0 and nodes == null) return abi.OMNI_ERR_INVALID_ARGS;

    if (!isFlag(seed_state[0].has_preselection)) return abi.OMNI_ERR_INVALID_ARGS;
    if (seed_state[0].has_preselection != 0 and !isValidDirection(seed_state[0].preselection_direction)) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }

    if (node_count == 0) {
        if (seed_state[0].root_node_index != -1 or seed_state[0].selected_node_index != -1) {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        resetContext(ctx);
        ctx.seed_state = seed_state[0];
        return abi.OMNI_OK;
    }

    var root_idx: ?usize = null;
    var selected_idx: ?usize = null;
    var rc = parseOptionalIndex(seed_state[0].root_node_index, node_count, &root_idx);
    if (rc != abi.OMNI_OK) return rc;
    rc = parseOptionalIndex(seed_state[0].selected_node_index, node_count, &selected_idx);
    if (rc != abi.OMNI_OK) return rc;
    if (root_idx == null) return abi.OMNI_ERR_OUT_OF_RANGE;

    for (0..node_count) |idx| {
        const node = nodes[idx];
        if (!isValidNodeKind(node.kind)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!isValidOrientation(node.orientation)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!isFlag(node.has_window_id) or !isFlag(node.is_fullscreen)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!std.math.isFinite(node.ratio)) return abi.OMNI_ERR_INVALID_ARGS;
        if (node.ratio < MIN_RATIO or node.ratio > MAX_RATIO) return abi.OMNI_ERR_OUT_OF_RANGE;

        var parent_idx: ?usize = null;
        var first_child_idx: ?usize = null;
        var second_child_idx: ?usize = null;

        rc = parseOptionalIndex(node.parent_index, node_count, &parent_idx);
        if (rc != abi.OMNI_OK) return rc;
        rc = parseOptionalIndex(node.first_child_index, node_count, &first_child_idx);
        if (rc != abi.OMNI_OK) return rc;
        rc = parseOptionalIndex(node.second_child_index, node_count, &second_child_idx);
        if (rc != abi.OMNI_OK) return rc;

        if (parent_idx != null and parent_idx.? == idx) return abi.OMNI_ERR_INVALID_ARGS;
        if (first_child_idx != null and first_child_idx.? == idx) return abi.OMNI_ERR_INVALID_ARGS;
        if (second_child_idx != null and second_child_idx.? == idx) return abi.OMNI_ERR_INVALID_ARGS;

        switch (node.kind) {
            abi.OMNI_DWINDLE_NODE_SPLIT => {
                if (first_child_idx == null or second_child_idx == null) return abi.OMNI_ERR_INVALID_ARGS;
                if (first_child_idx.? == second_child_idx.?) return abi.OMNI_ERR_INVALID_ARGS;
                if (node.has_window_id != 0 or node.is_fullscreen != 0) return abi.OMNI_ERR_INVALID_ARGS;
            },
            abi.OMNI_DWINDLE_NODE_LEAF => {
                if (first_child_idx != null or second_child_idx != null) return abi.OMNI_ERR_INVALID_ARGS;
                if (node.has_window_id == 0 and node.is_fullscreen != 0) return abi.OMNI_ERR_INVALID_ARGS;
            },
            else => return abi.OMNI_ERR_INVALID_ARGS,
        }
    }

    for (0..node_count) |idx| {
        const node = nodes[idx];
        var parent_idx: ?usize = null;
        rc = parseOptionalIndex(node.parent_index, node_count, &parent_idx);
        if (rc != abi.OMNI_OK) return rc;

        if (parent_idx) |parent| {
            const parent_node = nodes[parent];
            if (parent_node.kind != abi.OMNI_DWINDLE_NODE_SPLIT) return abi.OMNI_ERR_INVALID_ARGS;
            const idx_i64 = std.math.cast(i64, idx) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const matches_first = parent_node.first_child_index == idx_i64;
            const matches_second = parent_node.second_child_index == idx_i64;
            if (!matches_first and !matches_second) return abi.OMNI_ERR_INVALID_ARGS;
        }

        if (node.kind == abi.OMNI_DWINDLE_NODE_SPLIT) {
            const first = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const second = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const idx_i64 = std.math.cast(i64, idx) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (nodes[first].parent_index != idx_i64) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
            if (nodes[second].parent_index != idx_i64) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }

    const root = root_idx.?;
    if (nodes[root].parent_index != -1) return abi.OMNI_ERR_INVALID_ARGS;

    rc = validateNodeIdUniqueness(nodes, node_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = validateWindowIdUniqueness(nodes, node_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = validateAcyclicParentChain(nodes, node_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = validateReachabilityFromRoot(nodes, node_count, root);
    if (rc != abi.OMNI_OK) return rc;

    if (selected_idx) |selected| {
        if (selected >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    ctx.node_count = node_count;
    for (0..node_count) |idx| {
        ctx.nodes[idx] = nodes[idx];
    }
    ctx.seed_state = seed_state[0];
    ctx.cached_frame_count = 0;

    return abi.OMNI_OK;
}

pub fn omni_dwindle_ctx_apply_op_impl(
    context: [*c]OmniDwindleLayoutContext,
    request: [*c]const abi.OmniDwindleOpRequest,
    out_result: [*c]abi.OmniDwindleOpResult,
    out_removed_window_ids: [*c]abi.OmniUuid128,
    out_removed_window_capacity: usize,
) i32 {
    _ = asMutableContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (request == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (out_removed_window_capacity > 0 and out_removed_window_ids == null) return abi.OMNI_ERR_INVALID_ARGS;

    initOpResult(out_result);

    const op = request[0].op;
    if (!isValidOp(op)) return abi.OMNI_ERR_INVALID_ARGS;

    switch (op) {
        abi.OMNI_DWINDLE_OP_ADD_WINDOW => {
            if (isZeroUuid(request[0].payload.add_window.window_id)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_REMOVE_WINDOW => {
            if (isZeroUuid(request[0].payload.remove_window.window_id)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_SYNC_WINDOWS => {
            const payload = request[0].payload.sync_windows;
            if (payload.window_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
            if (payload.window_count > 0 and payload.window_ids == null) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_MOVE_FOCUS => {
            if (!isValidDirection(request[0].payload.move_focus.direction)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_SWAP_WINDOWS => {
            if (!isValidDirection(request[0].payload.swap_windows.direction)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_RESIZE_SELECTED => {
            const payload = request[0].payload.resize_selected;
            if (!isValidDirection(payload.direction)) return abi.OMNI_ERR_INVALID_ARGS;
            if (!std.math.isFinite(payload.delta)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO => {
            if (!isFlag(request[0].payload.cycle_split_ratio.forward)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT => {
            if (!isFlag(request[0].payload.move_selection_to_root.stable)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_SET_PRESELECTION => {
            if (!isValidDirection(request[0].payload.set_preselection.direction)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN,
        abi.OMNI_DWINDLE_OP_TOGGLE_ORIENTATION,
        abi.OMNI_DWINDLE_OP_BALANCE_SIZES,
        abi.OMNI_DWINDLE_OP_SWAP_SPLIT,
        abi.OMNI_DWINDLE_OP_CLEAR_PRESELECTION,
        abi.OMNI_DWINDLE_OP_VALIDATE_SELECTION,
        => {},
        else => return abi.OMNI_ERR_INVALID_ARGS,
    }

    return abi.OMNI_OK;
}

pub fn omni_dwindle_ctx_calculate_layout_impl(
    context: [*c]OmniDwindleLayoutContext,
    request: [*c]const abi.OmniDwindleLayoutRequest,
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
    out_frames: [*c]abi.OmniDwindleWindowFrame,
    out_frame_capacity: usize,
    out_frame_count: [*c]usize,
) i32 {
    const ctx = asMutableContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (request == null or out_frame_count == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (constraint_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (constraint_count > 0 and constraints == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (out_frame_capacity > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (out_frame_capacity > 0 and out_frames == null) return abi.OMNI_ERR_INVALID_ARGS;

    const req = request[0];
    if (!isFiniteNonNegative(req.screen_x) or
        !isFiniteNonNegative(req.screen_y) or
        !isFiniteNonNegative(req.screen_width) or
        !isFiniteNonNegative(req.screen_height) or
        !isFiniteNonNegative(req.inner_gap) or
        !isFiniteNonNegative(req.outer_gap_top) or
        !isFiniteNonNegative(req.outer_gap_bottom) or
        !isFiniteNonNegative(req.outer_gap_left) or
        !isFiniteNonNegative(req.outer_gap_right) or
        !isFiniteNonNegative(req.single_window_aspect_width) or
        !isFiniteNonNegative(req.single_window_aspect_height) or
        !isFiniteNonNegative(req.single_window_aspect_tolerance))
    {
        return abi.OMNI_ERR_INVALID_ARGS;
    }

    out_frame_count[0] = 0;
    ctx.cached_frame_count = 0;
    return abi.OMNI_OK;
}

pub fn omni_dwindle_ctx_find_neighbor_impl(
    context: [*c]const OmniDwindleLayoutContext,
    window_id: abi.OmniUuid128,
    direction: u8,
    inner_gap: f64,
    out_has_neighbor: [*c]u8,
    out_neighbor_window_id: [*c]abi.OmniUuid128,
) i32 {
    _ = asConstContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    _ = window_id;
    if (out_has_neighbor == null or out_neighbor_window_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (!isValidDirection(direction)) return abi.OMNI_ERR_INVALID_ARGS;
    if (!isFiniteNonNegative(inner_gap)) return abi.OMNI_ERR_INVALID_ARGS;

    out_has_neighbor[0] = 0;
    out_neighbor_window_id[0] = zeroUuid();
    return abi.OMNI_OK;
}
