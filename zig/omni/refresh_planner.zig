const std = @import("std");
const abi = @import("abi_types.zig");
const types = @import("controller_types.zig");

pub fn pushRefreshPlan(
    state: *types.RuntimeState,
    flags: u32,
    workspace_id: ?types.Uuid,
    display_id: ?u32,
) !void {
    var refresh_plan = abi.OmniControllerRefreshPlan{
        .flags = flags,
        .has_workspace_id = 0,
        .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        .has_display_id = 0,
        .display_id = 0,
    };
    types.writeOptionalUuid(&refresh_plan.has_workspace_id, &refresh_plan.workspace_id, workspace_id);
    types.writeOptionalDisplayId(&refresh_plan.has_display_id, &refresh_plan.display_id, display_id);
    try state.effects.refresh_plans.append(state.allocator, refresh_plan);
}

const refresh_mode_mask: u32 = abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE |
    abi.OMNI_CONTROLLER_REFRESH_FULL |
    abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL |
    abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT;

fn modePriority(flags: u32) u8 {
    if (flags & abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE != 0) {
        return 3;
    }
    if (flags & abi.OMNI_CONTROLLER_REFRESH_FULL != 0) {
        return 2;
    }
    if (flags & (abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL | abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT) != 0) {
        return 1;
    }
    return 0;
}

fn canonicalModeFlags(priority: u8) u32 {
    return switch (priority) {
        3 => abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE,
        2 => abi.OMNI_CONTROLLER_REFRESH_FULL,
        1 => abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL | abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT,
        else => 0,
    };
}

/// Normalize refresh dispatch semantics before exporting effects:
/// - pick one dominant refresh mode (immediate > full > incremental/apply_layout)
/// - clear mode bits on all plans
/// - attach canonical mode bits to the dominant plan
pub fn normalizeForDispatch(state: *types.RuntimeState) void {
    const plans = state.effects.refresh_plans.items;
    if (plans.len == 0) {
        return;
    }

    var dominant_priority: u8 = 0;
    var dominant_index: usize = 0;
    for (plans, 0..) |plan, index| {
        const priority = modePriority(plan.flags);
        if (priority > dominant_priority) {
            dominant_priority = priority;
            dominant_index = index;
        }
    }

    if (dominant_priority == 0) {
        return;
    }

    for (state.effects.refresh_plans.items) |*plan| {
        plan.flags &= ~refresh_mode_mask;
    }
    state.effects.refresh_plans.items[dominant_index].flags |= canonicalModeFlags(dominant_priority);
}

test "normalizeForDispatch keeps strongest refresh mode only" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    try pushRefreshPlan(
        &state,
        abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL | abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR,
        null,
        null,
    );
    try pushRefreshPlan(
        &state,
        abi.OMNI_CONTROLLER_REFRESH_FULL | abi.OMNI_CONTROLLER_REFRESH_HIDE_BORDER,
        null,
        null,
    );
    try pushRefreshPlan(
        &state,
        abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE | abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE,
        null,
        null,
    );

    normalizeForDispatch(&state);

    try std.testing.expectEqual(@as(usize, 3), state.effects.refresh_plans.items.len);
    try std.testing.expectEqual(
        @as(u32, abi.OMNI_CONTROLLER_REFRESH_UPDATE_WORKSPACE_BAR),
        state.effects.refresh_plans.items[0].flags,
    );
    try std.testing.expectEqual(
        @as(u32, abi.OMNI_CONTROLLER_REFRESH_HIDE_BORDER),
        state.effects.refresh_plans.items[1].flags,
    );
    try std.testing.expectEqual(
        @as(u32, abi.OMNI_CONTROLLER_REFRESH_IMMEDIATE | abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE),
        state.effects.refresh_plans.items[2].flags,
    );
}

test "normalizeForDispatch canonicalizes incremental mode bits" {
    var state = types.RuntimeState.init(std.testing.allocator);
    defer state.deinit();

    try pushRefreshPlan(
        &state,
        abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT | abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE,
        null,
        null,
    );

    normalizeForDispatch(&state);

    try std.testing.expectEqual(@as(usize, 1), state.effects.refresh_plans.items.len);
    try std.testing.expectEqual(
        @as(u32, abi.OMNI_CONTROLLER_REFRESH_INCREMENTAL |
            abi.OMNI_CONTROLLER_REFRESH_APPLY_LAYOUT |
            abi.OMNI_CONTROLLER_REFRESH_HIDE_INACTIVE),
        state.effects.refresh_plans.items[0].flags,
    );
}
