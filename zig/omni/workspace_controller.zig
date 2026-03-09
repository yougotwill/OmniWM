const std = @import("std");
const abi = @import("abi_types.zig");
const monitor_model = @import("monitor.zig");
const window_model = @import("window_model.zig");
const workspace_model = @import("workspace_manager.zig");

pub const WorkspaceController = struct {
    allocator: std.mem.Allocator,
    manager: workspace_model.WorkspaceManager,
    windows: window_model.WindowModel,
    export_monitors: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeMonitorRecord) = .{},
    export_workspaces: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeWorkspaceRecord) = .{},
    export_windows: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeWindowRecord) = .{},

    pub fn init(allocator: std.mem.Allocator) !WorkspaceController {
        var controller = WorkspaceController{
            .allocator = allocator,
            .manager = try workspace_model.WorkspaceManager.init(allocator),
            .windows = window_model.WindowModel.init(allocator),
        };
        try controller.refreshExportState();
        return controller;
    }

    pub fn deinit(self: *WorkspaceController) void {
        self.export_monitors.deinit(self.allocator);
        self.export_workspaces.deinit(self.allocator);
        self.export_windows.deinit(self.allocator);
        self.windows.deinit();
        self.manager.deinit();
        self.* = undefined;
    }

    pub fn importMonitors(self: *WorkspaceController, monitors: []const abi.OmniWorkspaceRuntimeMonitorSnapshot) !void {
        try self.manager.importMonitors(monitors, &self.windows);
        try self.refreshExportState();
    }

    pub fn importSettings(self: *WorkspaceController, settings: abi.OmniWorkspaceRuntimeSettingsImport) !void {
        try self.manager.importSettings(settings, &self.windows);
        try self.refreshExportState();
    }

    pub fn workspaceIdByName(
        self: *WorkspaceController,
        name: abi.OmniWorkspaceRuntimeName,
        create_if_missing: bool,
    ) !?abi.OmniUuid128 {
        const result = try self.manager.workspaceIdByName(monitor_model.nameSlice(name), create_if_missing);
        try self.refreshExportState();
        return result;
    }

    pub fn setActiveWorkspace(
        self: *WorkspaceController,
        workspace_id: abi.OmniUuid128,
        monitor_display_id: u32,
    ) bool {
        if (!self.manager.workspaceExists(workspace_id)) {
            return false;
        }
        if (!self.manager.setActiveWorkspace(workspace_id, monitor_display_id)) {
            return false;
        }
        self.refreshExportState() catch return false;
        return true;
    }

    pub fn switchWorkspaceByName(
        self: *WorkspaceController,
        name: abi.OmniWorkspaceRuntimeName,
    ) !?abi.OmniUuid128 {
        const result = try self.manager.switchWorkspaceByName(monitor_model.nameSlice(name));
        try self.refreshExportState();
        return result;
    }

    pub fn focusWorkspaceAnywhere(
        self: *WorkspaceController,
        workspace_id: abi.OmniUuid128,
    ) ?abi.OmniUuid128 {
        const result = self.manager.focusWorkspaceAnywhere(workspace_id) orelse return null;
        self.refreshExportState() catch return null;
        return result;
    }

    pub fn summonWorkspaceByName(
        self: *WorkspaceController,
        name: abi.OmniWorkspaceRuntimeName,
        monitor_display_id: u32,
    ) ?abi.OmniUuid128 {
        const result = self.manager.summonWorkspaceByName(monitor_model.nameSlice(name), monitor_display_id);
        self.refreshExportState() catch return null;
        return result;
    }

    pub fn moveWorkspaceToMonitor(
        self: *WorkspaceController,
        workspace_id: abi.OmniUuid128,
        target_monitor_display_id: u32,
    ) !bool {
        const moved = try self.manager.moveWorkspaceToMonitor(workspace_id, target_monitor_display_id, &self.windows);
        if (!moved) {
            return false;
        }
        try self.refreshExportState();
        return true;
    }

    pub fn swapWorkspaces(
        self: *WorkspaceController,
        workspace_1_id: abi.OmniUuid128,
        monitor_1_display_id: u32,
        workspace_2_id: abi.OmniUuid128,
        monitor_2_display_id: u32,
    ) bool {
        if (!self.manager.swapWorkspaces(workspace_1_id, monitor_1_display_id, workspace_2_id, monitor_2_display_id)) {
            return false;
        }
        self.refreshExportState() catch return false;
        return true;
    }

    pub fn adjacentMonitorRecord(
        self: *const WorkspaceController,
        from_monitor_display_id: u32,
        direction: u8,
        wrap_around: bool,
    ) ?abi.OmniWorkspaceRuntimeMonitorRecord {
        const monitor = self.manager.adjacentMonitor(from_monitor_display_id, direction, wrap_around) orelse return null;
        return self.monitorRecord(monitor);
    }

    pub fn windowUpsert(
        self: *WorkspaceController,
        request: abi.OmniWorkspaceRuntimeWindowUpsert,
    ) !?abi.OmniUuid128 {
        if (!self.manager.workspaceExists(request.workspace_id)) {
            return null;
        }
        const handle = try self.windows.upsert(request);
        try self.refreshExportState();
        return handle;
    }

    pub fn windowRemove(self: *WorkspaceController, key: abi.OmniWorkspaceRuntimeWindowKey) void {
        _ = self.windows.removeWindow(.{ .pid = key.pid, .window_id = key.window_id });
        self.refreshExportState() catch {};
    }

    pub fn windowSetWorkspace(
        self: *WorkspaceController,
        handle_id: abi.OmniUuid128,
        workspace_id: abi.OmniUuid128,
    ) bool {
        if (!self.manager.workspaceExists(workspace_id)) {
            return false;
        }
        if (!self.windows.setWorkspace(handle_id, workspace_id)) {
            return false;
        }
        self.refreshExportState() catch return false;
        return true;
    }

    pub fn windowSetHiddenState(
        self: *WorkspaceController,
        handle_id: abi.OmniUuid128,
        state: ?window_model.HiddenState,
    ) bool {
        if (!self.windows.setHiddenState(handle_id, state)) {
            return false;
        }
        self.refreshExportState() catch return false;
        return true;
    }

    pub fn windowSetLayoutReason(
        self: *WorkspaceController,
        handle_id: abi.OmniUuid128,
        layout_reason: u8,
    ) bool {
        if (!self.windows.setLayoutReason(handle_id, layout_reason)) {
            return false;
        }
        self.refreshExportState() catch return false;
        return true;
    }

    pub fn windowRemoveMissing(
        self: *WorkspaceController,
        active_keys: []const abi.OmniWorkspaceRuntimeWindowKey,
        required_consecutive_misses: u32,
    ) !void {
        try self.windows.removeMissing(active_keys, required_consecutive_misses);
        try self.refreshExportState();
    }

    pub fn exportState(self: *WorkspaceController, out_export: *abi.OmniWorkspaceRuntimeStateExport) !void {
        try self.refreshExportState();
        out_export.* = .{
            .monitors = if (self.export_monitors.items.len == 0) null else self.export_monitors.items.ptr,
            .monitor_count = self.export_monitors.items.len,
            .workspaces = if (self.export_workspaces.items.len == 0) null else self.export_workspaces.items.ptr,
            .workspace_count = self.export_workspaces.items.len,
            .windows = if (self.export_windows.items.len == 0) null else self.export_windows.items.ptr,
            .window_count = self.export_windows.items.len,
            .has_active_monitor_display_id = if (self.manager.active_monitor == null) 0 else 1,
            .active_monitor_display_id = self.manager.active_monitor orelse 0,
            .has_previous_monitor_display_id = if (self.manager.previous_monitor == null) 0 else 1,
            .previous_monitor_display_id = self.manager.previous_monitor orelse 0,
        };
    }

    pub fn emptyMonitorRecord() abi.OmniWorkspaceRuntimeMonitorRecord {
        return .{
            .display_id = 0,
            .is_main = 0,
            .frame_x = 0,
            .frame_y = 0,
            .frame_width = 0,
            .frame_height = 0,
            .visible_x = 0,
            .visible_y = 0,
            .visible_width = 0,
            .visible_height = 0,
            .name = monitor_model.encodeName(""),
            .has_active_workspace_id = 0,
            .active_workspace_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_previous_workspace_id = 0,
            .previous_workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        };
    }

    fn monitorRecord(self: *const WorkspaceController, value: monitor_model.Monitor) abi.OmniWorkspaceRuntimeMonitorRecord {
        const active_workspace = self.manager.visibleWorkspaceOnMonitor(value.display_id);
        const previous_workspace = self.manager.previousWorkspaceOnMonitor(value.display_id);

        return .{
            .display_id = value.display_id,
            .is_main = if (value.is_main) 1 else 0,
            .frame_x = value.frame_x,
            .frame_y = value.frame_y,
            .frame_width = value.frame_width,
            .frame_height = value.frame_height,
            .visible_x = value.visible_x,
            .visible_y = value.visible_y,
            .visible_width = value.visible_width,
            .visible_height = value.visible_height,
            .name = value.name,
            .has_active_workspace_id = if (active_workspace == null) 0 else 1,
            .active_workspace_id = active_workspace orelse .{ .bytes = [_]u8{0} ** 16 },
            .has_previous_workspace_id = if (previous_workspace == null) 0 else 1,
            .previous_workspace_id = previous_workspace orelse .{ .bytes = [_]u8{0} ** 16 },
        };
    }

    fn validateRuntimeState(self: *const WorkspaceController) !void {
        try self.windows.validateInvariants();

        if (self.manager.visible_by_monitor.count() != self.manager.monitors.items.len) {
            std.log.warn(
                "workspace export validation failed reason=visible_monitor_count_mismatch expected={d} actual={d}",
                .{ self.manager.monitors.items.len, self.manager.visible_by_monitor.count() },
            );
            return error.InvariantViolation;
        }
        if (self.manager.visible_by_workspace.count() != self.manager.visible_by_monitor.count()) {
            std.log.warn(
                "workspace export validation failed reason=visible_workspace_count_mismatch expected={d} actual={d}",
                .{ self.manager.visible_by_monitor.count(), self.manager.visible_by_workspace.count() },
            );
            return error.InvariantViolation;
        }

        if (self.manager.active_monitor) |display_id| {
            if (monitor_model.findByDisplayId(self.manager.monitors.items, display_id) == null) {
                std.log.warn(
                    "workspace export validation failed reason=active_monitor_missing display_id={d}",
                    .{display_id},
                );
                return error.InvariantViolation;
            }
        }
        if (self.manager.previous_monitor) |display_id| {
            if (monitor_model.findByDisplayId(self.manager.monitors.items, display_id) == null) {
                std.log.warn(
                    "workspace export validation failed reason=previous_monitor_missing display_id={d}",
                    .{display_id},
                );
                return error.InvariantViolation;
            }
        }

        for (self.manager.monitors.items) |monitor| {
            const workspace_id = self.manager.visible_by_monitor.get(monitor.display_id) orelse {
                std.log.warn(
                    "workspace export validation failed reason=missing_visible_workspace display_id={d}",
                    .{monitor.display_id},
                );
                return error.InvariantViolation;
            };
            if (!self.manager.workspaceExists(workspace_id)) {
                std.log.warn(
                    "workspace export validation failed reason=visible_workspace_missing display_id={d}",
                    .{monitor.display_id},
                );
                return error.InvariantViolation;
            }
            const mapped_display_id = self.manager.visible_by_workspace.get(workspace_id) orelse {
                std.log.warn(
                    "workspace export validation failed reason=visible_workspace_inverse_missing display_id={d}",
                    .{monitor.display_id},
                );
                return error.InvariantViolation;
            };
            if (mapped_display_id != monitor.display_id) {
                std.log.warn(
                    "workspace export validation failed reason=visible_workspace_inverse_mismatch display_id={d} mapped_display_id={d}",
                    .{ monitor.display_id, mapped_display_id },
                );
                return error.InvariantViolation;
            }
        }

        var visible_it = self.manager.visible_by_workspace.iterator();
        while (visible_it.next()) |entry| {
            if (!self.manager.workspaceExists(entry.key_ptr.*)) {
                std.log.warn("workspace export validation failed reason=unknown_visible_workspace", .{});
                return error.InvariantViolation;
            }
            if (monitor_model.findByDisplayId(self.manager.monitors.items, entry.value_ptr.*) == null) {
                std.log.warn(
                    "workspace export validation failed reason=unknown_visible_monitor display_id={d}",
                    .{entry.value_ptr.*},
                );
                return error.InvariantViolation;
            }
            const workspace_id = self.manager.visible_by_monitor.get(entry.value_ptr.*) orelse {
                std.log.warn(
                    "workspace export validation failed reason=visible_monitor_inverse_missing display_id={d}",
                    .{entry.value_ptr.*},
                );
                return error.InvariantViolation;
            };
            if (!std.mem.eql(u8, workspace_id.bytes[0..], entry.key_ptr.*.bytes[0..])) {
                std.log.warn(
                    "workspace export validation failed reason=visible_monitor_inverse_mismatch display_id={d}",
                    .{entry.value_ptr.*},
                );
                return error.InvariantViolation;
            }
        }

        var previous_it = self.manager.previous_visible_by_monitor.iterator();
        while (previous_it.next()) |entry| {
            if (monitor_model.findByDisplayId(self.manager.monitors.items, entry.key_ptr.*) == null) {
                std.log.warn(
                    "workspace export validation failed reason=unknown_previous_monitor display_id={d}",
                    .{entry.key_ptr.*},
                );
                return error.InvariantViolation;
            }
            if (!self.manager.workspaceExists(entry.value_ptr.*)) {
                std.log.warn("workspace export validation failed reason=unknown_previous_workspace", .{});
                return error.InvariantViolation;
            }
        }

        for (self.windows.entries.items) |entry| {
            if (!self.manager.workspaceExists(entry.workspace_id)) {
                std.log.warn("workspace export validation failed reason=window_workspace_missing", .{});
                return error.InvariantViolation;
            }
        }
    }

    fn refreshExportState(self: *WorkspaceController) !void {
        try self.validateRuntimeState();

        var next_export_monitors: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeMonitorRecord) = .{};
        errdefer next_export_monitors.deinit(self.allocator);
        var next_export_workspaces: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeWorkspaceRecord) = .{};
        errdefer next_export_workspaces.deinit(self.allocator);
        var next_export_windows: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeWindowRecord) = .{};
        errdefer next_export_windows.deinit(self.allocator);

        try next_export_monitors.ensureTotalCapacity(self.allocator, self.manager.monitors.items.len);
        try next_export_workspaces.ensureTotalCapacity(self.allocator, self.manager.workspaces.items.len);
        try next_export_windows.ensureTotalCapacity(self.allocator, self.windows.entries.items.len);

        for (self.manager.monitors.items) |value| {
            try next_export_monitors.append(self.allocator, self.monitorRecord(value));
        }

        for (self.manager.workspaces.items) |workspace| {
            const assigned_monitor = self.manager.workspaceMonitorId(workspace.id);
            const visible_monitor = self.manager.visibleMonitorForWorkspace(workspace.id);
            const assigned_anchor = workspace.assigned_anchor orelse monitor_model.Point{ .x = 0, .y = 0 };

            try next_export_workspaces.append(self.allocator, .{
                .workspace_id = workspace.id,
                .name = workspace.name,
                .has_assigned_monitor_anchor = if (workspace.assigned_anchor == null) 0 else 1,
                .assigned_monitor_anchor_x = assigned_anchor.x,
                .assigned_monitor_anchor_y = assigned_anchor.y,
                .has_assigned_display_id = if (assigned_monitor == null) 0 else 1,
                .assigned_display_id = assigned_monitor orelse 0,
                .is_visible = if (visible_monitor == null) 0 else 1,
                .is_previous_visible = if (self.manager.isWorkspacePreviousVisible(workspace.id)) 1 else 0,
                .is_persistent = if (self.manager.isPersistentWorkspaceName(workspace.name)) 1 else 0,
            });
        }

        for (self.windows.entries.items) |entry| {
            try next_export_windows.append(self.allocator, .{
                .handle_id = entry.handle_id,
                .pid = entry.key.pid,
                .window_id = entry.key.window_id,
                .workspace_id = entry.workspace_id,
                .has_hidden_state = if (entry.hidden_state == null) 0 else 1,
                .hidden_state = if (entry.hidden_state) |hidden|
                    .{
                        .proportional_x = hidden.proportional_x,
                        .proportional_y = hidden.proportional_y,
                        .has_reference_display_id = if (hidden.reference_display_id == null) 0 else 1,
                        .reference_display_id = hidden.reference_display_id orelse 0,
                        .workspace_inactive = if (hidden.workspace_inactive) 1 else 0,
                    }
                else
                    .{
                        .proportional_x = 0,
                        .proportional_y = 0,
                        .has_reference_display_id = 0,
                        .reference_display_id = 0,
                        .workspace_inactive = 0,
                    },
                .layout_reason = entry.layout_reason,
            });
        }

        std.mem.swap(@TypeOf(self.export_monitors), &self.export_monitors, &next_export_monitors);
        std.mem.swap(@TypeOf(self.export_workspaces), &self.export_workspaces, &next_export_workspaces);
        std.mem.swap(@TypeOf(self.export_windows), &self.export_windows, &next_export_windows);

        next_export_monitors.deinit(self.allocator);
        next_export_workspaces.deinit(self.allocator);
        next_export_windows.deinit(self.allocator);
    }
};

test "workspace controller exports seeded state" {
    var controller = try WorkspaceController.init(std.testing.allocator);
    defer controller.deinit();

    var state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try controller.exportState(&state_export);

    try std.testing.expect(state_export.monitor_count >= 1);
    try std.testing.expect(state_export.workspace_count >= 1);
}

test "workspace controller tracks window lifecycle" {
    var controller = try WorkspaceController.init(std.testing.allocator);
    defer controller.deinit();

    const first_monitor = controller.manager.monitors.items[0];
    const workspace_id = (try controller.workspaceIdByName(monitor_model.encodeName("1"), true)).?;

    try std.testing.expect(controller.setActiveWorkspace(workspace_id, first_monitor.display_id));

    const handle = (try controller.windowUpsert(.{
        .pid = 99,
        .window_id = 101,
        .workspace_id = workspace_id,
        .has_handle_id = 0,
        .handle_id = .{ .bytes = [_]u8{0} ** 16 },
    })).?;

    try std.testing.expect(controller.windowSetLayoutReason(handle, abi.OMNI_WORKSPACE_LAYOUT_REASON_MACOS_HIDDEN_APP));

    try controller.windowRemoveMissing(&[_]abi.OmniWorkspaceRuntimeWindowKey{}, 1);

    var state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try controller.exportState(&state_export);
    try std.testing.expectEqual(@as(usize, 0), state_export.window_count);
}

test "workspace controller preserves previous export when validation fails" {
    var controller = try WorkspaceController.init(std.testing.allocator);
    defer controller.deinit();

    const first_monitor = controller.manager.monitors.items[0];
    const workspace_id = (try controller.workspaceIdByName(monitor_model.encodeName("1"), true)).?;
    try std.testing.expect(controller.setActiveWorkspace(workspace_id, first_monitor.display_id));

    _ = (try controller.windowUpsert(.{
        .pid = 777,
        .window_id = 888,
        .workspace_id = workspace_id,
        .has_handle_id = 0,
        .handle_id = .{ .bytes = [_]u8{0} ** 16 },
    })).?;

    try std.testing.expectEqual(@as(usize, 1), controller.export_windows.items.len);
    _ = controller.windows.index_by_key.remove(.{ .pid = 777, .window_id = 888 });

    try std.testing.expectError(error.InvariantViolation, controller.refreshExportState());
    try std.testing.expectEqual(@as(usize, 1), controller.export_windows.items.len);
}

fn testMonitorSnapshot(
    id: u32,
    is_main: bool,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    name: []const u8,
) abi.OmniWorkspaceRuntimeMonitorSnapshot {
    return .{
        .display_id = id,
        .is_main = if (is_main) 1 else 0,
        .frame_x = x,
        .frame_y = y,
        .frame_width = width,
        .frame_height = height,
        .visible_x = x,
        .visible_y = y,
        .visible_width = width,
        .visible_height = height,
        .name = monitor_model.encodeName(name),
    };
}

test "workspace controller switchWorkspaceByName follows the existing workspace monitor" {
    var controller = try WorkspaceController.init(std.testing.allocator);
    defer controller.deinit();

    const snapshots = [_]abi.OmniWorkspaceRuntimeMonitorSnapshot{
        testMonitorSnapshot(11, true, 0.0, 0.0, 100.0, 100.0, "Main"),
        testMonitorSnapshot(22, false, 120.0, 0.0, 100.0, 100.0, "Side"),
    };
    try controller.importMonitors(snapshots[0..]);

    const one = (try controller.workspaceIdByName(monitor_model.encodeName("1"), true)).?;
    const two = (try controller.workspaceIdByName(monitor_model.encodeName("2"), true)).?;

    try std.testing.expect(controller.setActiveWorkspace(one, 11));
    try std.testing.expect(controller.setActiveWorkspace(two, 22));
    try std.testing.expect(controller.setActiveWorkspace(one, 11));

    const resolved = (try controller.switchWorkspaceByName(monitor_model.encodeName("2"))).?;
    try std.testing.expectEqual(two, resolved);
    try std.testing.expectEqual(two, controller.manager.visibleWorkspaceOnMonitor(22).?);
    try std.testing.expectEqual(one, controller.manager.visibleWorkspaceOnMonitor(11).?);

    var state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try controller.exportState(&state_export);
    try std.testing.expectEqual(@as(u8, 1), state_export.has_active_monitor_display_id);
    try std.testing.expectEqual(@as(u32, 22), state_export.active_monitor_display_id);
    try std.testing.expectEqual(@as(u8, 1), state_export.has_previous_monitor_display_id);
    try std.testing.expectEqual(@as(u32, 11), state_export.previous_monitor_display_id);
}

test "workspace controller switchWorkspaceByName creates a missing workspace on the main monitor" {
    var controller = try WorkspaceController.init(std.testing.allocator);
    defer controller.deinit();

    const snapshots = [_]abi.OmniWorkspaceRuntimeMonitorSnapshot{
        testMonitorSnapshot(11, true, 0.0, 0.0, 100.0, 100.0, "Main"),
        testMonitorSnapshot(22, false, 120.0, 0.0, 100.0, 100.0, "Side"),
    };
    try controller.importMonitors(snapshots[0..]);

    const two = (try controller.workspaceIdByName(monitor_model.encodeName("2"), true)).?;
    try std.testing.expect(controller.setActiveWorkspace(two, 22));

    const created = (try controller.switchWorkspaceByName(monitor_model.encodeName("3"))).?;
    try std.testing.expectEqual(created, controller.manager.visibleWorkspaceOnMonitor(11).?);

    var state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try controller.exportState(&state_export);
    try std.testing.expectEqual(@as(u8, 1), state_export.has_active_monitor_display_id);
    try std.testing.expectEqual(@as(u32, 11), state_export.active_monitor_display_id);
    try std.testing.expectEqual(@as(u8, 1), state_export.has_previous_monitor_display_id);
    try std.testing.expectEqual(@as(u32, 22), state_export.previous_monitor_display_id);
}

test "workspace controller focusWorkspaceAnywhere updates export state to the workspace monitor" {
    var controller = try WorkspaceController.init(std.testing.allocator);
    defer controller.deinit();

    const snapshots = [_]abi.OmniWorkspaceRuntimeMonitorSnapshot{
        testMonitorSnapshot(11, true, 0.0, 0.0, 100.0, 100.0, "Main"),
        testMonitorSnapshot(22, false, 120.0, 0.0, 100.0, 100.0, "Side"),
    };
    try controller.importMonitors(snapshots[0..]);

    const one = (try controller.workspaceIdByName(monitor_model.encodeName("1"), true)).?;
    const two = (try controller.workspaceIdByName(monitor_model.encodeName("2"), true)).?;

    try std.testing.expect(controller.setActiveWorkspace(one, 11));
    try std.testing.expect(controller.setActiveWorkspace(two, 22));

    const resolved = controller.focusWorkspaceAnywhere(one).?;
    try std.testing.expectEqual(one, resolved);

    var state_export: abi.OmniWorkspaceRuntimeStateExport = std.mem.zeroes(abi.OmniWorkspaceRuntimeStateExport);
    try controller.exportState(&state_export);
    try std.testing.expectEqual(@as(u8, 1), state_export.has_active_monitor_display_id);
    try std.testing.expectEqual(@as(u32, 11), state_export.active_monitor_display_id);
    try std.testing.expectEqual(@as(u8, 1), state_export.has_previous_monitor_display_id);
    try std.testing.expectEqual(@as(u32, 22), state_export.previous_monitor_display_id);
}
