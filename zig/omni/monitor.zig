const std = @import("std");
const abi = @import("abi_types.zig");

pub const Point = struct {
    x: f64,
    y: f64,
};

pub const Monitor = struct {
    display_id: u32,
    is_main: bool,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    visible_x: f64,
    visible_y: f64,
    visible_width: f64,
    visible_height: f64,
    name: abi.OmniWorkspaceRuntimeName,
};

fn abs(value: f64) f64 {
    return @abs(value);
}

pub fn fallbackMonitor() Monitor {
    return .{
        .display_id = 1,
        .is_main = true,
        .frame_x = 0.0,
        .frame_y = 0.0,
        .frame_width = 1440.0,
        .frame_height = 900.0,
        .visible_x = 0.0,
        .visible_y = 0.0,
        .visible_width = 1440.0,
        .visible_height = 900.0,
        .name = encodeName("Fallback"),
    };
}

pub fn fromSnapshot(snapshot: abi.OmniWorkspaceRuntimeMonitorSnapshot) Monitor {
    return .{
        .display_id = snapshot.display_id,
        .is_main = snapshot.is_main != 0,
        .frame_x = snapshot.frame_x,
        .frame_y = snapshot.frame_y,
        .frame_width = snapshot.frame_width,
        .frame_height = snapshot.frame_height,
        .visible_x = snapshot.visible_x,
        .visible_y = snapshot.visible_y,
        .visible_width = snapshot.visible_width,
        .visible_height = snapshot.visible_height,
        .name = snapshot.name,
    };
}

pub fn nameSlice(name: abi.OmniWorkspaceRuntimeName) []const u8 {
    const clamped = @min(@as(usize, name.length), abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP);
    return name.bytes[0..clamped];
}

pub fn encodeName(value: []const u8) abi.OmniWorkspaceRuntimeName {
    const clamped_len = @min(value.len, abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP);
    var result = abi.OmniWorkspaceRuntimeName{
        .length = @intCast(clamped_len),
        .bytes = [_]u8{0} ** abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP,
    };
    std.mem.copyForwards(u8, result.bytes[0..clamped_len], value[0..clamped_len]);
    return result;
}

pub fn sortByPosition(monitors: []Monitor) void {
    std.sort.insertion(Monitor, monitors, {}, struct {
        fn lessThan(_: void, lhs: Monitor, rhs: Monitor) bool {
            return sortLessThan(lhs, rhs);
        }
    }.lessThan);
}

pub fn sortLessThan(lhs: Monitor, rhs: Monitor) bool {
    if (lhs.frame_x != rhs.frame_x) {
        return lhs.frame_x < rhs.frame_x;
    }
    const lhs_max_y = lhs.frame_y + lhs.frame_height;
    const rhs_max_y = rhs.frame_y + rhs.frame_height;
    if (lhs_max_y != rhs_max_y) {
        return lhs_max_y > rhs_max_y;
    }
    return lhs.display_id < rhs.display_id;
}

pub fn anchorPoint(value: Monitor) Point {
    return .{
        .x = value.frame_x,
        .y = value.frame_y + value.frame_height,
    };
}

pub fn mainOrFirst(monitors: []const Monitor) ?Monitor {
    if (monitors.len == 0) {
        return null;
    }
    for (monitors) |value| {
        if (value.is_main) {
            return value;
        }
    }
    return monitors[0];
}

pub fn findByDisplayId(monitors: []const Monitor, display_id: u32) ?Monitor {
    for (monitors) |value| {
        if (value.display_id == display_id) {
            return value;
        }
    }
    return null;
}

fn centerX(value: Monitor) f64 {
    return value.frame_x + (value.frame_width / 2.0);
}

fn centerY(value: Monitor) f64 {
    return value.frame_y + (value.frame_height / 2.0);
}

fn distanceSquaredBetweenCenters(lhs: Monitor, rhs: Monitor) f64 {
    const dx = centerX(lhs) - centerX(rhs);
    const dy = centerY(lhs) - centerY(rhs);
    return (dx * dx) + (dy * dy);
}

fn monitorDelta(from: Monitor, to: Monitor) struct { dx: f64, dy: f64 } {
    return .{
        .dx = centerX(to) - centerX(from),
        .dy = centerY(to) - centerY(from),
    };
}

fn containsPoint(value: Monitor, point: Point) bool {
    return point.x >= value.frame_x and
        point.x <= value.frame_x + value.frame_width and
        point.y >= value.frame_y and
        point.y <= value.frame_y + value.frame_height;
}

fn rectDistanceSquared(value: Monitor, point: Point) f64 {
    const max_x = value.frame_x + value.frame_width;
    const max_y = value.frame_y + value.frame_height;
    const clamped_x = @min(@max(point.x, value.frame_x), max_x);
    const clamped_y = @min(@max(point.y, value.frame_y), max_y);
    const dx = point.x - clamped_x;
    const dy = point.y - clamped_y;
    return (dx * dx) + (dy * dy);
}

pub fn approximateByAnchor(monitors: []const Monitor, point: Point) ?Monitor {
    if (monitors.len == 0) {
        return null;
    }
    for (monitors) |value| {
        if (containsPoint(value, point)) {
            return value;
        }
    }
    var best: ?Monitor = null;
    var best_distance = std.math.inf(f64);
    for (monitors) |value| {
        const distance = rectDistanceSquared(value, point);
        if (best == null or distance < best_distance) {
            best = value;
            best_distance = distance;
        }
    }
    return best;
}

const SelectionMode = enum {
    directional,
    wrapped,
};

const SelectionRank = struct {
    primary: f64,
    secondary: f64,
    distance: ?f64,
};

fn selectionRank(candidate: Monitor, current: Monitor, direction: u8, mode: SelectionMode) SelectionRank {
    const delta = monitorDelta(current, candidate);
    return switch (mode) {
        .directional => switch (direction) {
            abi.OMNI_NIRI_DIRECTION_LEFT, abi.OMNI_NIRI_DIRECTION_RIGHT => .{
                .primary = abs(delta.dx),
                .secondary = abs(delta.dy),
                .distance = distanceSquaredBetweenCenters(candidate, current),
            },
            abi.OMNI_NIRI_DIRECTION_UP, abi.OMNI_NIRI_DIRECTION_DOWN => .{
                .primary = abs(delta.dy),
                .secondary = abs(delta.dx),
                .distance = distanceSquaredBetweenCenters(candidate, current),
            },
            else => .{ .primary = 0.0, .secondary = 0.0, .distance = null },
        },
        .wrapped => switch (direction) {
            abi.OMNI_NIRI_DIRECTION_RIGHT => .{
                .primary = centerX(candidate),
                .secondary = abs(delta.dy),
                .distance = null,
            },
            abi.OMNI_NIRI_DIRECTION_LEFT => .{
                .primary = -centerX(candidate),
                .secondary = abs(delta.dy),
                .distance = null,
            },
            abi.OMNI_NIRI_DIRECTION_UP => .{
                .primary = centerY(candidate),
                .secondary = abs(delta.dx),
                .distance = null,
            },
            abi.OMNI_NIRI_DIRECTION_DOWN => .{
                .primary = -centerY(candidate),
                .secondary = abs(delta.dx),
                .distance = null,
            },
            else => .{ .primary = 0.0, .secondary = 0.0, .distance = null },
        },
    };
}

fn betterCandidate(lhs: Monitor, rhs: Monitor, current: Monitor, direction: u8, mode: SelectionMode) bool {
    const lhs_rank = selectionRank(lhs, current, direction, mode);
    const rhs_rank = selectionRank(rhs, current, direction, mode);

    if (lhs_rank.primary != rhs_rank.primary) {
        return lhs_rank.primary < rhs_rank.primary;
    }
    if (lhs_rank.secondary != rhs_rank.secondary) {
        return lhs_rank.secondary < rhs_rank.secondary;
    }
    if (lhs_rank.distance != null and rhs_rank.distance != null and lhs_rank.distance.? != rhs_rank.distance.?) {
        return lhs_rank.distance.? < rhs_rank.distance.?;
    }
    return sortLessThan(lhs, rhs);
}

pub fn adjacentMonitor(monitors: []const Monitor, from_display_id: u32, direction: u8, wrap: bool) ?Monitor {
    const current = findByDisplayId(monitors, from_display_id) orelse return null;

    var best_directional: ?Monitor = null;
    var best_wrapped: ?Monitor = null;
    for (monitors) |candidate| {
        if (candidate.display_id == from_display_id) {
            continue;
        }

        const delta = monitorDelta(current, candidate);
        const directional_match = switch (direction) {
            abi.OMNI_NIRI_DIRECTION_LEFT => delta.dx < 0,
            abi.OMNI_NIRI_DIRECTION_RIGHT => delta.dx > 0,
            abi.OMNI_NIRI_DIRECTION_UP => delta.dy > 0,
            abi.OMNI_NIRI_DIRECTION_DOWN => delta.dy < 0,
            else => false,
        };
        if (directional_match) {
            if (best_directional == null or betterCandidate(candidate, best_directional.?, current, direction, .directional)) {
                best_directional = candidate;
            }
            continue;
        }

        if (!wrap) {
            continue;
        }
        if (best_wrapped == null or betterCandidate(candidate, best_wrapped.?, current, direction, .wrapped)) {
            best_wrapped = candidate;
        }
    }
    return best_directional orelse best_wrapped;
}

test "monitor adjacency prefers directional and wraps by axis rank" {
    var monitors = [_]Monitor{
        .{
            .display_id = 1,
            .is_main = true,
            .frame_x = 0.0,
            .frame_y = 0.0,
            .frame_width = 100.0,
            .frame_height = 100.0,
            .visible_x = 0.0,
            .visible_y = 0.0,
            .visible_width = 100.0,
            .visible_height = 100.0,
            .name = encodeName("A"),
        },
        .{
            .display_id = 2,
            .is_main = false,
            .frame_x = 120.0,
            .frame_y = 0.0,
            .frame_width = 100.0,
            .frame_height = 100.0,
            .visible_x = 120.0,
            .visible_y = 0.0,
            .visible_width = 100.0,
            .visible_height = 100.0,
            .name = encodeName("B"),
        },
        .{
            .display_id = 3,
            .is_main = false,
            .frame_x = 0.0,
            .frame_y = 140.0,
            .frame_width = 100.0,
            .frame_height = 100.0,
            .visible_x = 0.0,
            .visible_y = 140.0,
            .visible_width = 100.0,
            .visible_height = 100.0,
            .name = encodeName("C"),
        },
    };

    const right = adjacentMonitor(monitors[0..], 1, abi.OMNI_NIRI_DIRECTION_RIGHT, false).?;
    try std.testing.expectEqual(@as(u32, 2), right.display_id);

    const wrapped_left = adjacentMonitor(monitors[0..], 1, abi.OMNI_NIRI_DIRECTION_LEFT, true).?;
    try std.testing.expectEqual(@as(u32, 2), wrapped_left.display_id);
}
