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

    fn refreshExportState(self: *WorkspaceController) !void {
        self.export_monitors.clearRetainingCapacity();
        self.export_workspaces.clearRetainingCapacity();
        self.export_windows.clearRetainingCapacity();

        try self.export_monitors.ensureTotalCapacity(self.allocator, self.manager.monitors.items.len);
        try self.export_workspaces.ensureTotalCapacity(self.allocator, self.manager.workspaces.items.len);
        try self.export_windows.ensureTotalCapacity(self.allocator, self.windows.entries.items.len);

        for (self.manager.monitors.items) |value| {
            self.export_monitors.appendAssumeCapacity(self.monitorRecord(value));
        }

        for (self.manager.workspaces.items) |workspace| {
            const assigned_monitor = self.manager.workspaceMonitorId(workspace.id);
            const visible_monitor = self.manager.visibleMonitorForWorkspace(workspace.id);
            const assigned_anchor = workspace.assigned_anchor orelse monitor_model.Point{ .x = 0, .y = 0 };

            self.export_workspaces.appendAssumeCapacity(.{
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
            self.export_windows.appendAssumeCapacity(.{
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
