const std = @import("std");
const abi = @import("abi_types.zig");

fn command(kind: u8, direction: u8, workspace_index: i64, monitor_direction: u8) abi.OmniControllerCommand {
    return .{
        .kind = kind,
        .direction = direction,
        .workspace_index = workspace_index,
        .monitor_direction = monitor_direction,
        .has_workspace_id = 0,
        .workspace_id = std.mem.zeroes(abi.OmniUuid128),
        .has_window_handle_id = 0,
        .window_handle_id = std.mem.zeroes(abi.OmniUuid128),
    };
}

fn parseDirection(raw: []const u8) ?u8 {
    if (std.mem.eql(u8, raw, "left")) return abi.OMNI_NIRI_DIRECTION_LEFT;
    if (std.mem.eql(u8, raw, "right")) return abi.OMNI_NIRI_DIRECTION_RIGHT;
    if (std.mem.eql(u8, raw, "up")) return abi.OMNI_NIRI_DIRECTION_UP;
    if (std.mem.eql(u8, raw, "down")) return abi.OMNI_NIRI_DIRECTION_DOWN;
    return null;
}

fn parseIndex(raw: []const u8) ?i64 {
    const value = std.fmt.parseInt(u8, raw, 10) catch return null;
    if (value > 8) return null;
    return @intCast(value);
}

fn parseIndexed(raw: []const u8, comptime prefix: []const u8) ?i64 {
    if (!std.mem.startsWith(u8, raw, prefix)) return null;
    return parseIndex(raw[prefix.len..]);
}

fn parseDirectionalCommand(raw: []const u8, comptime prefix: []const u8, kind: u8) ?abi.OmniControllerCommand {
    if (!std.mem.startsWith(u8, raw, prefix)) return null;
    const dir = parseDirection(raw[prefix.len..]) orelse return null;
    return command(kind, dir, 0, 0);
}

pub fn commandForBindingId(binding_id: []const u8) ?abi.OmniControllerCommand {
    if (parseIndexed(binding_id, "switchWorkspace.")) |index| {
        return command(abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX, 0, index, 0);
    }
    if (parseIndexed(binding_id, "moveToWorkspace.")) |index| {
        return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX, 0, index, 0);
    }
    if (parseIndexed(binding_id, "moveColumnToWorkspace.")) |index| {
        return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_WORKSPACE_INDEX, 0, index, 0);
    }
    if (parseIndexed(binding_id, "focusColumn.")) |index| {
        return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX, 0, index, 0);
    }
    if (parseIndexed(binding_id, "summonWorkspace.")) |index| {
        return command(abi.OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE, 0, index, 0);
    }

    if (parseDirectionalCommand(binding_id, "moveColumnToMonitor.", abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_MONITOR_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "moveWorkspaceToMonitor.", abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "moveToMonitor.", abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_MONITOR_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "focusMonitor.", abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "consumeWindow.", abi.OMNI_CONTROLLER_COMMAND_CONSUME_WINDOW_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "expelWindow.", abi.OMNI_CONTROLLER_COMMAND_EXPEL_WINDOW_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "focus.", abi.OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "move.", abi.OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "swap.", abi.OMNI_CONTROLLER_COMMAND_SWAP_DIRECTION)) |mapped| return mapped;
    if (parseDirectionalCommand(binding_id, "moveColumn.", abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_DIRECTION)) |mapped| return mapped;

    if (std.mem.startsWith(u8, binding_id, "resizeGrow.")) {
        const dir = parseDirection(binding_id["resizeGrow.".len..]) orelse return null;
        return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION, dir, 0, 1);
    }
    if (std.mem.startsWith(u8, binding_id, "resizeShrink.")) {
        const dir = parseDirection(binding_id["resizeShrink.".len..]) orelse return null;
        return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION, dir, 0, 0);
    }
    if (std.mem.startsWith(u8, binding_id, "preselect.")) {
        const dir = parseDirection(binding_id["preselect.".len..]) orelse return null;
        return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION, dir, 0, 0);
    }

    if (std.mem.eql(u8, binding_id, "workspaceBackAndForth")) return command(abi.OMNI_CONTROLLER_COMMAND_WORKSPACE_BACK_AND_FORTH, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "switchWorkspace.next")) return command(abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_NEXT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "switchWorkspace.previous")) return command(abi.OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_PREVIOUS, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusPrevious")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_PREVIOUS, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusDownOrLeft")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusUpOrRight")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveWindowToWorkspaceUp")) return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_UP, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveWindowToWorkspaceDown")) return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveColumnToWorkspaceUp")) return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_UP, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveColumnToWorkspaceDown")) return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusMonitorNext")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_NEXT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusMonitorPrevious")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_PREVIOUS, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusMonitorLast")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_LAST, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveWorkspaceToMonitor.next")) return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_NEXT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveWorkspaceToMonitor.previous")) return command(abi.OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_PREVIOUS, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleFullscreen")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleNativeFullscreen")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_NATIVE_FULLSCREEN, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleColumnTabbed")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_TABBED, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusColumnFirst")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusColumnLast")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusWindowTop")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "focusWindowBottom")) return command(abi.OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "cycleColumnWidthForward")) return command(abi.OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_FORWARD, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "cycleColumnWidthBackward")) return command(abi.OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_BACKWARD, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleColumnFullWidth")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_FULL_WIDTH, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "balanceSizes")) return command(abi.OMNI_CONTROLLER_COMMAND_BALANCE_SIZES, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "moveToRoot")) return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleSplit")) return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "swapSplit")) return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "preselectClear")) return command(abi.OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "openWindowFinder")) return command(abi.OMNI_CONTROLLER_COMMAND_OPEN_WINDOW_FINDER, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "raiseAllFloatingWindows")) return command(abi.OMNI_CONTROLLER_COMMAND_RAISE_ALL_FLOATING_WINDOWS, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "openMenuAnywhere")) return command(abi.OMNI_CONTROLLER_COMMAND_OPEN_MENU_ANYWHERE, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "openMenuPalette")) return command(abi.OMNI_CONTROLLER_COMMAND_OPEN_MENU_PALETTE, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleHiddenBar")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_HIDDEN_BAR, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleQuakeTerminal")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_QUAKE_TERMINAL, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleWorkspaceLayout")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT, 0, 0, 0);
    if (std.mem.eql(u8, binding_id, "toggleOverview")) return command(abi.OMNI_CONTROLLER_COMMAND_TOGGLE_OVERVIEW, 0, 0, 0);

    return null;
}

fn expectKnownId(id: []const u8, total: *usize) !void {
    try std.testing.expect(commandForBindingId(id) != null);
    total.* += 1;
}

test "keybinding mapping covers current default bindings" {
    var total: usize = 0;

    inline for (0..9) |idx| {
        var switch_id: [32]u8 = undefined;
        const switch_slice = try std.fmt.bufPrint(&switch_id, "switchWorkspace.{d}", .{idx});
        try expectKnownId(switch_slice, &total);

        var move_to_id: [32]u8 = undefined;
        const move_to_slice = try std.fmt.bufPrint(&move_to_id, "moveToWorkspace.{d}", .{idx});
        try expectKnownId(move_to_slice, &total);

        var move_col_id: [40]u8 = undefined;
        const move_col_slice = try std.fmt.bufPrint(&move_col_id, "moveColumnToWorkspace.{d}", .{idx});
        try expectKnownId(move_col_slice, &total);

        var focus_col_id: [28]u8 = undefined;
        const focus_col_slice = try std.fmt.bufPrint(&focus_col_id, "focusColumn.{d}", .{idx});
        try expectKnownId(focus_col_slice, &total);

        var summon_id: [34]u8 = undefined;
        const summon_slice = try std.fmt.bufPrint(&summon_id, "summonWorkspace.{d}", .{idx});
        try expectKnownId(summon_slice, &total);
    }

    const directional = [_][]const u8{ "left", "right", "up", "down" };
    inline for (directional) |dir| {
        var focus_id: [20]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&focus_id, "focus.{s}", .{dir}), &total);

        var move_id: [20]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&move_id, "move.{s}", .{dir}), &total);

        var swap_id: [20]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&swap_id, "swap.{s}", .{dir}), &total);

        var move_monitor_id: [32]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&move_monitor_id, "moveToMonitor.{s}", .{dir}), &total);

        var focus_monitor_id: [34]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&focus_monitor_id, "focusMonitor.{s}", .{dir}), &total);

        var move_col_monitor_id: [40]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&move_col_monitor_id, "moveColumnToMonitor.{s}", .{dir}), &total);

        var move_workspace_monitor_id: [44]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&move_workspace_monitor_id, "moveWorkspaceToMonitor.{s}", .{dir}), &total);

        var resize_grow_id: [28]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&resize_grow_id, "resizeGrow.{s}", .{dir}), &total);

        var resize_shrink_id: [32]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&resize_shrink_id, "resizeShrink.{s}", .{dir}), &total);

        var preselect_id: [24]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&preselect_id, "preselect.{s}", .{dir}), &total);
    }

    const two_directional = [_][]const u8{ "left", "right" };
    inline for (two_directional) |dir| {
        var move_col_id: [28]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&move_col_id, "moveColumn.{s}", .{dir}), &total);

        var consume_id: [28]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&consume_id, "consumeWindow.{s}", .{dir}), &total);

        var expel_id: [26]u8 = undefined;
        try expectKnownId(try std.fmt.bufPrint(&expel_id, "expelWindow.{s}", .{dir}), &total);
    }

    const singleton_ids = [_][]const u8{
        "workspaceBackAndForth",
        "switchWorkspace.next",
        "switchWorkspace.previous",
        "focusPrevious",
        "focusDownOrLeft",
        "focusUpOrRight",
        "moveWindowToWorkspaceUp",
        "moveWindowToWorkspaceDown",
        "moveColumnToWorkspaceUp",
        "moveColumnToWorkspaceDown",
        "focusMonitorNext",
        "focusMonitorPrevious",
        "focusMonitorLast",
        "moveWorkspaceToMonitor.next",
        "moveWorkspaceToMonitor.previous",
        "toggleFullscreen",
        "toggleNativeFullscreen",
        "toggleColumnTabbed",
        "focusColumnFirst",
        "focusColumnLast",
        "focusWindowTop",
        "focusWindowBottom",
        "cycleColumnWidthForward",
        "cycleColumnWidthBackward",
        "toggleColumnFullWidth",
        "balanceSizes",
        "moveToRoot",
        "toggleSplit",
        "swapSplit",
        "preselectClear",
        "openWindowFinder",
        "raiseAllFloatingWindows",
        "openMenuAnywhere",
        "openMenuPalette",
        "toggleHiddenBar",
        "toggleQuakeTerminal",
        "toggleWorkspaceLayout",
        "toggleOverview",
    };

    for (singleton_ids) |id| {
        try expectKnownId(id, &total);
    }

    try std.testing.expectEqual(@as(usize, 129), total);
}

test "unknown id returns null" {
    try std.testing.expect(commandForBindingId("focusWorkspaceAnywhere.0") == null);
    try std.testing.expect(commandForBindingId("not-a-binding") == null);
    try std.testing.expect(commandForBindingId("switchWorkspace.19") == null);
}
