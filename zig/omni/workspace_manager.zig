const std = @import("std");
const abi = @import("abi_types.zig");
const monitor = @import("monitor.zig");
const window_model = @import("window_model.zig");

pub const Workspace = struct {
    id: abi.OmniUuid128,
    name: abi.OmniWorkspaceRuntimeName,
    assigned_anchor: ?monitor.Point,
};

const Assignment = struct {
    workspace_name: abi.OmniWorkspaceRuntimeName,
    kind: u8,
    sequence_number: i32,
    pattern: abi.OmniWorkspaceRuntimeName,
};

const MonitorWorkspacePair = struct {
    monitor_id: u32,
    workspace_id: abi.OmniUuid128,
};

pub const WorkspaceManager = struct {
    allocator: std.mem.Allocator,
    monitors: std.ArrayListUnmanaged(monitor.Monitor) = .{},
    workspaces: std.ArrayListUnmanaged(Workspace) = .{},
    persistent_names: std.ArrayListUnmanaged(abi.OmniWorkspaceRuntimeName) = .{},
    assignments: std.ArrayListUnmanaged(Assignment) = .{},
    visible_by_monitor: std.AutoHashMapUnmanaged(u32, abi.OmniUuid128) = .{},
    visible_by_workspace: std.AutoHashMapUnmanaged(abi.OmniUuid128, u32) = .{},
    previous_visible_by_monitor: std.AutoHashMapUnmanaged(u32, abi.OmniUuid128) = .{},
    active_monitor: ?u32 = null,
    previous_monitor: ?u32 = null,
    next_workspace_serial: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) !WorkspaceManager {
        var result = WorkspaceManager{
            .allocator = allocator,
        };
        try result.monitors.append(allocator, monitor.fallbackMonitor());
        var empty_windows = window_model.WindowModel.init(allocator);
        defer empty_windows.deinit();
        try result.ensureVisibleWorkspaces(result.monitors.items, &empty_windows);
        return result;
    }

    pub fn deinit(self: *WorkspaceManager) void {
        self.monitors.deinit(self.allocator);
        self.workspaces.deinit(self.allocator);
        self.persistent_names.deinit(self.allocator);
        self.assignments.deinit(self.allocator);
        self.visible_by_monitor.deinit(self.allocator);
        self.visible_by_workspace.deinit(self.allocator);
        self.previous_visible_by_monitor.deinit(self.allocator);
        self.* = undefined;
    }

    fn uuidEqual(lhs: abi.OmniUuid128, rhs: abi.OmniUuid128) bool {
        return std.mem.eql(u8, lhs.bytes[0..], rhs.bytes[0..]);
    }

    pub fn nameSlice(name: abi.OmniWorkspaceRuntimeName) []const u8 {
        return monitor.nameSlice(name);
    }

    fn nameEquals(lhs: abi.OmniWorkspaceRuntimeName, rhs: []const u8) bool {
        return std.mem.eql(u8, nameSlice(lhs), rhs);
    }

    fn workspaceNameEquals(lhs: abi.OmniWorkspaceRuntimeName, rhs: abi.OmniWorkspaceRuntimeName) bool {
        return std.mem.eql(u8, nameSlice(lhs), nameSlice(rhs));
    }

    fn asciiLower(byte: u8) u8 {
        return std.ascii.toLower(byte);
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) {
            return true;
        }
        if (needle.len > haystack.len) {
            return false;
        }
        var start: usize = 0;
        while (start + needle.len <= haystack.len) : (start += 1) {
            var matches = true;
            var idx: usize = 0;
            while (idx < needle.len) : (idx += 1) {
                if (asciiLower(haystack[start + idx]) != asciiLower(needle[idx])) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                return true;
            }
        }
        return false;
    }

    fn isReservedWorkspaceName(raw: []const u8) bool {
        const reserved = [_][]const u8{
            "focused",
            "non-focused",
            "visible",
            "invisible",
            "non-visible",
            "active",
            "non-active",
            "inactive",
            "back-and-forth",
            "back_and_forth",
            "previous",
            "prev",
            "next",
            "monitor",
            "workspace",
            "monitors",
            "workspaces",
            "all",
            "none",
            "mouse",
            "target",
        };
        for (reserved) |entry| {
            if (std.mem.eql(u8, raw, entry)) {
                return true;
            }
        }
        return false;
    }

    fn isValidWorkspaceName(raw: []const u8) bool {
        if (raw.len == 0) {
            return false;
        }
        if (isReservedWorkspaceName(raw)) {
            return false;
        }
        if (raw[0] == '_' or raw[0] == '-') {
            return false;
        }
        for (raw) |byte| {
            if (byte == ',') {
                return false;
            }
            if (std.ascii.isWhitespace(byte)) {
                return false;
            }
        }
        return true;
    }

    fn generateWorkspaceId(self: *WorkspaceManager) abi.OmniUuid128 {
        var bytes = [_]u8{0} ** 16;
        std.mem.writeInt(u64, bytes[0..8], self.next_workspace_serial, .little);
        bytes[8] = 0x77;
        bytes[9] = 0x73;
        bytes[10] = 0x70;
        bytes[11] = 0x63;
        self.next_workspace_serial += 1;
        return .{ .bytes = bytes };
    }

    fn findWorkspaceIndexById(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128) ?usize {
        for (self.workspaces.items, 0..) |workspace, idx| {
            if (uuidEqual(workspace.id, workspace_id)) {
                return idx;
            }
        }
        return null;
    }

    fn findWorkspaceIndexByName(self: *const WorkspaceManager, name: []const u8) ?usize {
        for (self.workspaces.items, 0..) |workspace, idx| {
            if (nameEquals(workspace.name, name)) {
                return idx;
            }
        }
        return null;
    }

    fn monitorExists(self: *const WorkspaceManager, monitor_id: u32) bool {
        return monitor.findByDisplayId(self.monitors.items, monitor_id) != null;
    }

    fn setWorkspaceAnchor(self: *WorkspaceManager, workspace_id: abi.OmniUuid128, anchor: ?monitor.Point) void {
        const index = self.findWorkspaceIndexById(workspace_id) orelse return;
        self.workspaces.items[index].assigned_anchor = anchor;
    }

    fn createWorkspace(self: *WorkspaceManager, name: []const u8) !?abi.OmniUuid128 {
        if (name.len == 0 or name.len > abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP) {
            return null;
        }
        if (!isValidWorkspaceName(name)) {
            return null;
        }
        if (self.findWorkspaceIndexByName(name)) |existing| {
            return self.workspaces.items[existing].id;
        }

        const workspace = Workspace{
            .id = self.generateWorkspaceId(),
            .name = monitor.encodeName(name),
            .assigned_anchor = null,
        };
        try self.workspaces.append(self.allocator, workspace);
        return workspace.id;
    }

    fn hasPersistentName(self: *const WorkspaceManager, name: abi.OmniWorkspaceRuntimeName) bool {
        for (self.persistent_names.items) |value| {
            if (workspaceNameEquals(value, name)) {
                return true;
            }
        }
        return false;
    }

    pub fn isPersistentWorkspaceName(self: *const WorkspaceManager, name: abi.OmniWorkspaceRuntimeName) bool {
        return self.hasPersistentName(name);
    }

    fn hasAssignment(self: *const WorkspaceManager, assignment: Assignment) bool {
        for (self.assignments.items) |value| {
            if (!workspaceNameEquals(value.workspace_name, assignment.workspace_name)) {
                continue;
            }
            if (value.kind != assignment.kind) {
                continue;
            }
            if (value.sequence_number != assignment.sequence_number) {
                continue;
            }
            if (!workspaceNameEquals(value.pattern, assignment.pattern)) {
                continue;
            }
            return true;
        }
        return false;
    }

    fn ensurePersistentWorkspaces(self: *WorkspaceManager) !void {
        for (self.persistent_names.items) |name| {
            _ = try self.workspaceIdByName(nameSlice(name), true);
        }
    }

    fn applyForcedAssignments(self: *WorkspaceManager) !void {
        for (self.assignments.items) |assignment| {
            _ = try self.workspaceIdByName(nameSlice(assignment.workspace_name), true);
        }
    }

    fn resolveAssignmentMonitor(self: *const WorkspaceManager, assignment: Assignment) ?monitor.Monitor {
        return switch (assignment.kind) {
            abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_ANY => null,
            abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_MAIN => monitor.mainOrFirst(self.monitors.items),
            abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SECONDARY => blk: {
                if (self.monitors.items.len < 2) {
                    break :blk null;
                }
                for (self.monitors.items) |value| {
                    if (!value.is_main) {
                        break :blk value;
                    }
                }
                break :blk self.monitors.items[1];
            },
            abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SEQUENCE_NUMBER => blk: {
                if (assignment.sequence_number < 1) {
                    break :blk null;
                }
                const index: usize = @intCast(assignment.sequence_number - 1);
                if (index >= self.monitors.items.len) {
                    break :blk null;
                }
                break :blk self.monitors.items[index];
            },
            abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_NAME_PATTERN => blk: {
                const pattern = nameSlice(assignment.pattern);
                if (pattern.len == 0) {
                    break :blk null;
                }
                for (self.monitors.items) |candidate| {
                    if (containsIgnoreCase(monitor.nameSlice(candidate.name), pattern)) {
                        break :blk candidate;
                    }
                }
                break :blk null;
            },
            else => null,
        };
    }

    fn forceAssignedMonitorForName(self: *const WorkspaceManager, workspace_name: abi.OmniWorkspaceRuntimeName) ?monitor.Monitor {
        for (self.assignments.items) |assignment| {
            if (!workspaceNameEquals(assignment.workspace_name, workspace_name)) {
                continue;
            }
            if (self.resolveAssignmentMonitor(assignment)) |target| {
                return target;
            }
        }
        return null;
    }

    fn forceAssignedMonitorForSlice(self: *const WorkspaceManager, workspace_name: []const u8) ?monitor.Monitor {
        for (self.assignments.items) |assignment| {
            if (!std.mem.eql(u8, nameSlice(assignment.workspace_name), workspace_name)) {
                continue;
            }
            if (self.resolveAssignmentMonitor(assignment)) |target| {
                return target;
            }
        }
        return null;
    }

    fn isValidAssignment(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128, monitor_id: u32) bool {
        const workspace_idx = self.findWorkspaceIndexById(workspace_id) orelse return false;
        if (self.forceAssignedMonitorForName(self.workspaces.items[workspace_idx].name)) |forced| {
            return forced.display_id == monitor_id;
        }
        return true;
    }

    pub fn workspaceMonitorId(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128) ?u32 {
        const workspace_idx = self.findWorkspaceIndexById(workspace_id) orelse return null;
        const workspace = self.workspaces.items[workspace_idx];

        if (self.forceAssignedMonitorForName(workspace.name)) |forced| {
            return forced.display_id;
        }
        if (self.visible_by_workspace.get(workspace_id)) |visible_monitor| {
            return visible_monitor;
        }
        if (workspace.assigned_anchor) |anchor| {
            for (self.monitors.items) |value| {
                const value_anchor = monitor.anchorPoint(value);
                if (value_anchor.x == anchor.x and value_anchor.y == anchor.y) {
                    return value.display_id;
                }
            }
            if (monitor.approximateByAnchor(self.monitors.items, anchor)) |approx| {
                return approx.display_id;
            }
        }
        if (monitor.mainOrFirst(self.monitors.items)) |fallback| {
            return fallback.display_id;
        }
        return null;
    }

    pub fn monitorForWorkspace(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128) ?monitor.Monitor {
        const monitor_id = self.workspaceMonitorId(workspace_id) orelse return null;
        return monitor.findByDisplayId(self.monitors.items, monitor_id);
    }

    fn currentMonitorIdsMatchVisibleMapping(self: *const WorkspaceManager) bool {
        if (self.visible_by_monitor.count() != self.monitors.items.len) {
            return false;
        }
        for (self.monitors.items) |value| {
            if (!self.visible_by_monitor.contains(value.display_id)) {
                return false;
            }
        }
        return true;
    }

    fn prunePreviousVisible(self: *WorkspaceManager) void {
        var removed = std.ArrayListUnmanaged(u32){};
        defer removed.deinit(self.allocator);

        var it = self.previous_visible_by_monitor.iterator();
        while (it.next()) |entry| {
            if (self.monitorExists(entry.key_ptr.*)) {
                continue;
            }
            removed.append(self.allocator, entry.key_ptr.*) catch {};
        }
        for (removed.items) |monitor_id| {
            _ = self.previous_visible_by_monitor.remove(monitor_id);
        }
    }

    fn clearVisibleMappings(self: *WorkspaceManager) void {
        self.visible_by_monitor.clearRetainingCapacity();
        self.visible_by_workspace.clearRetainingCapacity();
    }

    fn oldWorkspaceForMonitor(
        old_pairs: []const MonitorWorkspacePair,
        monitor_id: u32,
    ) ?abi.OmniUuid128 {
        for (old_pairs) |pair| {
            if (pair.monitor_id == monitor_id) {
                return pair.workspace_id;
            }
        }
        return null;
    }

    fn previousMonitorById(monitors: []const monitor.Monitor, monitor_id: u32) ?monitor.Monitor {
        return monitor.findByDisplayId(monitors, monitor_id);
    }

    fn listContains(values: []const u32, needle: u32) bool {
        for (values) |value| {
            if (value == needle) {
                return true;
            }
        }
        return false;
    }

    fn listRemove(values: *std.ArrayListUnmanaged(u32), needle: u32) void {
        for (values.items, 0..) |value, idx| {
            if (value == needle) {
                _ = values.swapRemove(idx);
                return;
            }
        }
    }

    fn rearrangeWorkspacesOnMonitors(
        self: *WorkspaceManager,
        previous_monitors: []const monitor.Monitor,
        windows: *const window_model.WindowModel,
    ) !void {
        var old_pairs = std.ArrayListUnmanaged(MonitorWorkspacePair){};
        defer old_pairs.deinit(self.allocator);

        var old_it = self.visible_by_monitor.iterator();
        while (old_it.next()) |entry| {
            try old_pairs.append(self.allocator, .{
                .monitor_id = entry.key_ptr.*,
                .workspace_id = entry.value_ptr.*,
            });
        }

        var remaining_old_monitor_ids = std.ArrayListUnmanaged(u32){};
        defer remaining_old_monitor_ids.deinit(self.allocator);
        for (old_pairs.items) |pair| {
            if (previousMonitorById(previous_monitors, pair.monitor_id) != null) {
                if (!listContains(remaining_old_monitor_ids.items, pair.monitor_id)) {
                    try remaining_old_monitor_ids.append(self.allocator, pair.monitor_id);
                }
            }
        }

        var new_to_old = std.AutoHashMapUnmanaged(u32, u32){};
        defer new_to_old.deinit(self.allocator);

        for (self.monitors.items) |new_monitor| {
            if (listContains(remaining_old_monitor_ids.items, new_monitor.display_id)) {
                try new_to_old.put(self.allocator, new_monitor.display_id, new_monitor.display_id);
                listRemove(&remaining_old_monitor_ids, new_monitor.display_id);
            }
        }

        for (self.monitors.items) |new_monitor| {
            if (new_to_old.contains(new_monitor.display_id)) {
                continue;
            }

            var best_old_id: ?u32 = null;
            var best_distance = std.math.inf(f64);
            var best_sort: ?monitor.Monitor = null;

            for (remaining_old_monitor_ids.items) |candidate_old_id| {
                const old_monitor = previousMonitorById(previous_monitors, candidate_old_id) orelse continue;
                const dx = (old_monitor.frame_x + (old_monitor.frame_width / 2.0)) -
                    (new_monitor.frame_x + (new_monitor.frame_width / 2.0));
                const dy = (old_monitor.frame_y + (old_monitor.frame_height / 2.0)) -
                    (new_monitor.frame_y + (new_monitor.frame_height / 2.0));
                const distance = (dx * dx) + (dy * dy);

                if (best_old_id == null or distance < best_distance) {
                    best_old_id = candidate_old_id;
                    best_distance = distance;
                    best_sort = old_monitor;
                    continue;
                }

                if (distance == best_distance and best_sort != null and monitor.sortLessThan(old_monitor, best_sort.?)) {
                    best_old_id = candidate_old_id;
                    best_sort = old_monitor;
                }
            }

            if (best_old_id) |resolved_old_id| {
                try new_to_old.put(self.allocator, new_monitor.display_id, resolved_old_id);
                listRemove(&remaining_old_monitor_ids, resolved_old_id);
            }
        }

        self.clearVisibleMappings();

        for (self.monitors.items) |new_monitor| {
            var restored = false;
            if (new_to_old.get(new_monitor.display_id)) |old_id| {
                if (oldWorkspaceForMonitor(old_pairs.items, old_id)) |workspace_id| {
                    if (self.setActiveWorkspaceInternal(workspace_id, new_monitor.display_id, monitor.anchorPoint(new_monitor))) {
                        restored = true;
                    }
                }
            }

            if (!restored) {
                const stub_id = try self.getStubWorkspaceId(new_monitor.display_id, windows);
                _ = self.setActiveWorkspaceInternal(stub_id, new_monitor.display_id, monitor.anchorPoint(new_monitor));
            }
        }
    }

    fn ensureVisibleWorkspaces(
        self: *WorkspaceManager,
        previous_monitors: []const monitor.Monitor,
        windows: *const window_model.WindowModel,
    ) !void {
        self.prunePreviousVisible();
        if (!self.currentMonitorIdsMatchVisibleMapping()) {
            try self.rearrangeWorkspacesOnMonitors(previous_monitors, windows);
        }
    }

    fn reconcileForcedVisibleWorkspaces(self: *WorkspaceManager) void {
        var forced_targets = std.ArrayListUnmanaged(struct {
            workspace_id: abi.OmniUuid128,
            monitor_id: u32,
        }){};
        defer forced_targets.deinit(self.allocator);

        for (self.assignments.items) |assignment| {
            const workspace_index = self.findWorkspaceIndexByName(nameSlice(assignment.workspace_name)) orelse continue;
            const workspace_id = self.workspaces.items[workspace_index].id;

            var already_present = false;
            for (forced_targets.items) |target| {
                if (uuidEqual(target.workspace_id, workspace_id)) {
                    already_present = true;
                    break;
                }
            }
            if (already_present) {
                continue;
            }

            const resolved_monitor = self.resolveAssignmentMonitor(assignment) orelse continue;
            forced_targets.append(self.allocator, .{
                .workspace_id = workspace_id,
                .monitor_id = resolved_monitor.display_id,
            }) catch continue;
        }

        for (forced_targets.items) |target| {
            if (self.visible_by_workspace.get(target.workspace_id)) |current_monitor| {
                if (current_monitor != target.monitor_id) {
                    _ = self.setActiveWorkspaceInternal(target.workspace_id, target.monitor_id, null);
                }
            } else {
                _ = self.setActiveWorkspaceInternal(target.workspace_id, target.monitor_id, null);
            }
        }
    }

    fn getFallbackWorkspaceId(self: *WorkspaceManager) !abi.OmniUuid128 {
        if (self.workspaces.items.len > 0) {
            return self.workspaces.items[0].id;
        }

        if (try self.createWorkspace("1")) |fallback| {
            return fallback;
        }

        const workspace = Workspace{
            .id = self.generateWorkspaceId(),
            .name = monitor.encodeName("fallback"),
            .assigned_anchor = null,
        };
        try self.workspaces.append(self.allocator, workspace);
        return workspace.id;
    }

    fn logicalNumberCompare(lhs: []const u8, rhs: []const u8) std.math.Order {
        var lhs_start: usize = 0;
        while (lhs_start < lhs.len and lhs[lhs_start] == '0') : (lhs_start += 1) {}

        var rhs_start: usize = 0;
        while (rhs_start < rhs.len and rhs[rhs_start] == '0') : (rhs_start += 1) {}

        const lhs_trimmed = lhs[lhs_start..];
        const rhs_trimmed = rhs[rhs_start..];

        if (lhs_trimmed.len != rhs_trimmed.len) {
            return if (lhs_trimmed.len < rhs_trimmed.len) .lt else .gt;
        }

        const order = std.mem.order(u8, lhs_trimmed, rhs_trimmed);
        if (order != .eq) {
            return order;
        }
        return .eq;
    }

    fn logicalWorkspaceLessThan(lhs: abi.OmniWorkspaceRuntimeName, rhs: abi.OmniWorkspaceRuntimeName) bool {
        const a = nameSlice(lhs);
        const b = nameSlice(rhs);

        var ia: usize = 0;
        var ib: usize = 0;
        while (ia < a.len and ib < b.len) {
            const a_is_num = std.ascii.isDigit(a[ia]);
            const b_is_num = std.ascii.isDigit(b[ib]);

            var a_end = ia;
            while (a_end < a.len and std.ascii.isDigit(a[a_end]) == a_is_num) : (a_end += 1) {}

            var b_end = ib;
            while (b_end < b.len and std.ascii.isDigit(b[b_end]) == b_is_num) : (b_end += 1) {}

            const a_seg = a[ia..a_end];
            const b_seg = b[ib..b_end];

            if (a_is_num and b_is_num) {
                const order = logicalNumberCompare(a_seg, b_seg);
                if (order != .eq) {
                    return order == .lt;
                }
            } else if (a_is_num != b_is_num) {
                return a_is_num;
            } else {
                const order = std.mem.order(u8, a_seg, b_seg);
                if (order != .eq) {
                    return order == .lt;
                }
            }

            ia = a_end;
            ib = b_end;
        }

        if (a.len != b.len) {
            return a.len < b.len;
        }
        return false;
    }

    fn sortedWorkspaceIndices(self: *const WorkspaceManager) !std.ArrayListUnmanaged(usize) {
        var indices = std.ArrayListUnmanaged(usize){};
        for (self.workspaces.items, 0..) |_, idx| {
            try indices.append(self.allocator, idx);
        }

        std.sort.insertion(usize, indices.items, self, struct {
            fn lessThan(ctx: *const WorkspaceManager, lhs_idx: usize, rhs_idx: usize) bool {
                const lhs = ctx.workspaces.items[lhs_idx];
                const rhs = ctx.workspaces.items[rhs_idx];
                return logicalWorkspaceLessThan(lhs.name, rhs.name);
            }
        }.lessThan);

        return indices;
    }

    fn getStubWorkspaceId(
        self: *WorkspaceManager,
        monitor_id: u32,
        windows: *const window_model.WindowModel,
    ) !abi.OmniUuid128 {
        if (!self.monitorExists(monitor_id)) {
            return try self.getFallbackWorkspaceId();
        }

        if (self.previous_visible_by_monitor.get(monitor_id)) |prev_workspace_id| {
            if (self.findWorkspaceIndexById(prev_workspace_id)) |prev_idx| {
                const prev_workspace = self.workspaces.items[prev_idx];
                if (!self.visible_by_workspace.contains(prev_workspace_id) and
                    self.forceAssignedMonitorForName(prev_workspace.name) == null)
                {
                    if (self.workspaceMonitorId(prev_workspace_id)) |resolved_monitor_id| {
                        if (resolved_monitor_id == monitor_id) {
                            return prev_workspace_id;
                        }
                    }
                }
            }
        }

        var sorted_indices = try self.sortedWorkspaceIndices();
        defer sorted_indices.deinit(self.allocator);

        for (sorted_indices.items) |workspace_idx| {
            const workspace = self.workspaces.items[workspace_idx];
            if (self.visible_by_workspace.contains(workspace.id)) {
                continue;
            }
            if (self.forceAssignedMonitorForName(workspace.name) != null) {
                continue;
            }
            const candidate_monitor_id = self.workspaceMonitorId(workspace.id) orelse continue;
            if (candidate_monitor_id == monitor_id) {
                return workspace.id;
            }
        }

        var numeric_idx: usize = 1;
        while (numeric_idx < 10000) : (numeric_idx += 1) {
            var name_buf: [32]u8 = undefined;
            const candidate_name = std.fmt.bufPrint(&name_buf, "{d}", .{numeric_idx}) catch continue;
            const candidate_encoded = monitor.encodeName(candidate_name);

            if (self.hasPersistentName(candidate_encoded)) {
                continue;
            }
            if (self.forceAssignedMonitorForSlice(candidate_name)) |forced| {
                if (forced.display_id != monitor_id) {
                    continue;
                }
            }

            if (self.findWorkspaceIndexByName(candidate_name)) |existing_idx| {
                const existing_id = self.workspaces.items[existing_idx].id;
                if (!self.visible_by_workspace.contains(existing_id) and !windows.hasWindowsInWorkspace(existing_id)) {
                    return existing_id;
                }
            } else if (try self.createWorkspace(candidate_name)) |new_id| {
                return new_id;
            }
        }

        var auto_buf: [64]u8 = undefined;
        const auto_name = std.fmt.bufPrint(&auto_buf, "auto-{d}", .{self.next_workspace_serial}) catch null;
        if (auto_name) |name| {
            if (try self.createWorkspace(name)) |new_id| {
                return new_id;
            }
        }

        return try self.getFallbackWorkspaceId();
    }

    fn setActiveWorkspaceInternal(
        self: *WorkspaceManager,
        workspace_id: abi.OmniUuid128,
        monitor_id: u32,
        anchor_point: ?monitor.Point,
    ) bool {
        if (!self.isValidAssignment(workspace_id, monitor_id)) {
            return false;
        }

        const effective_anchor: ?monitor.Point = blk: {
            if (anchor_point) |resolved| {
                break :blk resolved;
            }
            if (monitor.findByDisplayId(self.monitors.items, monitor_id)) |target| {
                break :blk monitor.anchorPoint(target);
            }
            break :blk null;
        };

        if (self.visible_by_workspace.get(workspace_id)) |previous_monitor_id| {
            _ = self.visible_by_workspace.remove(workspace_id);
            _ = self.visible_by_monitor.remove(previous_monitor_id);
            self.previous_visible_by_monitor.put(self.allocator, previous_monitor_id, workspace_id) catch {};
        }

        if (self.visible_by_monitor.get(monitor_id)) |previous_workspace_id| {
            self.previous_visible_by_monitor.put(self.allocator, monitor_id, previous_workspace_id) catch {};
            _ = self.visible_by_monitor.remove(monitor_id);
            _ = self.visible_by_workspace.remove(previous_workspace_id);
        }

        self.visible_by_monitor.put(self.allocator, monitor_id, workspace_id) catch return false;
        self.visible_by_workspace.put(self.allocator, workspace_id, monitor_id) catch {
            _ = self.visible_by_monitor.remove(monitor_id);
            return false;
        };
        self.setWorkspaceAnchor(workspace_id, effective_anchor);

        if (self.active_monitor == null or self.active_monitor.? != monitor_id) {
            self.previous_monitor = self.active_monitor;
            self.active_monitor = monitor_id;
        }
        return true;
    }

    pub fn workspaceIdByName(self: *WorkspaceManager, name: []const u8, create_if_missing: bool) !?abi.OmniUuid128 {
        if (self.findWorkspaceIndexByName(name)) |idx| {
            return self.workspaces.items[idx].id;
        }
        if (!create_if_missing) {
            return null;
        }
        return try self.createWorkspace(name);
    }

    pub fn workspaceExists(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128) bool {
        return self.findWorkspaceIndexById(workspace_id) != null;
    }

    pub fn setActiveWorkspace(self: *WorkspaceManager, workspace_id: abi.OmniUuid128, monitor_id: u32) bool {
        const target_monitor = monitor.findByDisplayId(self.monitors.items, monitor_id) orelse return false;
        return self.setActiveWorkspaceInternal(workspace_id, target_monitor.display_id, monitor.anchorPoint(target_monitor));
    }

    pub fn summonWorkspaceByName(
        self: *WorkspaceManager,
        workspace_name: []const u8,
        target_monitor_id: u32,
    ) ?abi.OmniUuid128 {
        const workspace_idx = self.findWorkspaceIndexByName(workspace_name) orelse return null;
        if (!self.monitorExists(target_monitor_id)) {
            return null;
        }
        const workspace_id = self.workspaces.items[workspace_idx].id;
        if (self.visible_by_monitor.get(target_monitor_id)) |visible_workspace_id| {
            if (uuidEqual(visible_workspace_id, workspace_id)) {
                return null;
            }
        }
        if (!self.setActiveWorkspaceInternal(workspace_id, target_monitor_id, null)) {
            return null;
        }
        return workspace_id;
    }

    pub fn moveWorkspaceToMonitor(
        self: *WorkspaceManager,
        workspace_id: abi.OmniUuid128,
        target_monitor_id: u32,
        windows: *const window_model.WindowModel,
    ) !bool {
        const target_monitor = monitor.findByDisplayId(self.monitors.items, target_monitor_id) orelse return false;
        const source_monitor = self.monitorForWorkspace(workspace_id) orelse return false;
        if (source_monitor.display_id == target_monitor.display_id) {
            return false;
        }
        if (!self.isValidAssignment(workspace_id, target_monitor.display_id)) {
            return false;
        }
        if (!self.setActiveWorkspaceInternal(workspace_id, target_monitor.display_id, monitor.anchorPoint(target_monitor))) {
            return false;
        }

        const stub_workspace_id = try self.getStubWorkspaceId(source_monitor.display_id, windows);
        _ = self.setActiveWorkspaceInternal(stub_workspace_id, source_monitor.display_id, monitor.anchorPoint(source_monitor));
        return true;
    }

    pub fn swapWorkspaces(
        self: *WorkspaceManager,
        workspace_1_id: abi.OmniUuid128,
        monitor_1_id: u32,
        workspace_2_id: abi.OmniUuid128,
        monitor_2_id: u32,
    ) bool {
        const monitor_1 = monitor.findByDisplayId(self.monitors.items, monitor_1_id) orelse return false;
        const monitor_2 = monitor.findByDisplayId(self.monitors.items, monitor_2_id) orelse return false;
        if (monitor_1.display_id == monitor_2.display_id) {
            return false;
        }
        if (!self.isValidAssignment(workspace_1_id, monitor_2.display_id) or
            !self.isValidAssignment(workspace_2_id, monitor_1.display_id))
        {
            return false;
        }

        if (self.visible_by_monitor.get(monitor_1.display_id)) |previous_1| {
            self.previous_visible_by_monitor.put(self.allocator, monitor_1.display_id, previous_1) catch {};
        }
        if (self.visible_by_monitor.get(monitor_2.display_id)) |previous_2| {
            self.previous_visible_by_monitor.put(self.allocator, monitor_2.display_id, previous_2) catch {};
        }

        _ = self.visible_by_workspace.remove(workspace_1_id);
        _ = self.visible_by_workspace.remove(workspace_2_id);
        _ = self.visible_by_monitor.remove(monitor_1.display_id);
        _ = self.visible_by_monitor.remove(monitor_2.display_id);

        self.visible_by_monitor.put(self.allocator, monitor_1.display_id, workspace_2_id) catch return false;
        self.visible_by_workspace.put(self.allocator, workspace_2_id, monitor_1.display_id) catch return false;
        self.visible_by_monitor.put(self.allocator, monitor_2.display_id, workspace_1_id) catch return false;
        self.visible_by_workspace.put(self.allocator, workspace_1_id, monitor_2.display_id) catch return false;

        self.setWorkspaceAnchor(workspace_2_id, monitor.anchorPoint(monitor_1));
        self.setWorkspaceAnchor(workspace_1_id, monitor.anchorPoint(monitor_2));
        self.previous_monitor = self.active_monitor;
        self.active_monitor = monitor_1.display_id;
        return true;
    }

    pub fn adjacentMonitor(self: *const WorkspaceManager, from_monitor_id: u32, direction: u8, wrap: bool) ?monitor.Monitor {
        return monitor.adjacentMonitor(self.monitors.items, from_monitor_id, direction, wrap);
    }

    pub fn visibleWorkspaceOnMonitor(self: *const WorkspaceManager, monitor_id: u32) ?abi.OmniUuid128 {
        return self.visible_by_monitor.get(monitor_id);
    }

    pub fn visibleMonitorForWorkspace(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128) ?u32 {
        return self.visible_by_workspace.get(workspace_id);
    }

    pub fn previousWorkspaceOnMonitor(self: *const WorkspaceManager, monitor_id: u32) ?abi.OmniUuid128 {
        return self.previous_visible_by_monitor.get(monitor_id);
    }

    pub fn isWorkspacePreviousVisible(self: *const WorkspaceManager, workspace_id: abi.OmniUuid128) bool {
        var it = self.previous_visible_by_monitor.iterator();
        while (it.next()) |entry| {
            if (uuidEqual(entry.value_ptr.*, workspace_id)) {
                return true;
            }
        }
        return false;
    }

    pub fn importMonitors(
        self: *WorkspaceManager,
        snapshots: []const abi.OmniWorkspaceRuntimeMonitorSnapshot,
        windows: *const window_model.WindowModel,
    ) !void {
        var previous_monitors = std.ArrayListUnmanaged(monitor.Monitor){};
        defer previous_monitors.deinit(self.allocator);
        for (self.monitors.items) |value| {
            try previous_monitors.append(self.allocator, value);
        }

        self.monitors.items.len = 0;

        if (snapshots.len == 0) {
            try self.monitors.append(self.allocator, monitor.fallbackMonitor());
        } else {
            var seen = std.AutoHashMapUnmanaged(u32, void){};
            defer seen.deinit(self.allocator);

            for (snapshots) |snapshot| {
                if (seen.contains(snapshot.display_id)) {
                    continue;
                }
                try seen.put(self.allocator, snapshot.display_id, {});
                try self.monitors.append(self.allocator, monitor.fromSnapshot(snapshot));
            }
            if (self.monitors.items.len == 0) {
                try self.monitors.append(self.allocator, monitor.fallbackMonitor());
            }
        }

        monitor.sortByPosition(self.monitors.items);
        try self.ensureVisibleWorkspaces(previous_monitors.items, windows);
        self.reconcileForcedVisibleWorkspaces();
    }

    pub fn importSettings(
        self: *WorkspaceManager,
        settings: abi.OmniWorkspaceRuntimeSettingsImport,
        windows: *const window_model.WindowModel,
    ) !void {
        self.persistent_names.items.len = 0;
        self.assignments.items.len = 0;

        for (0..settings.persistent_name_count) |idx| {
            const name = settings.persistent_names[idx];
            const raw = nameSlice(name);
            if (!isValidWorkspaceName(raw)) {
                continue;
            }
            if (!self.hasPersistentName(name)) {
                try self.persistent_names.append(self.allocator, name);
            }
            _ = try self.workspaceIdByName(raw, true);
        }

        for (0..settings.monitor_assignment_count) |idx| {
            const raw_assignment = settings.monitor_assignments[idx];
            const workspace_raw = nameSlice(raw_assignment.workspace_name);
            if (!isValidWorkspaceName(workspace_raw)) {
                continue;
            }

            if (raw_assignment.assignment_kind == abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SEQUENCE_NUMBER and
                raw_assignment.sequence_number < 1)
            {
                continue;
            }

            if (raw_assignment.assignment_kind == abi.OMNI_WORKSPACE_MONITOR_ASSIGNMENT_NAME_PATTERN and
                nameSlice(raw_assignment.monitor_pattern).len == 0)
            {
                continue;
            }

            const assignment = Assignment{
                .workspace_name = raw_assignment.workspace_name,
                .kind = raw_assignment.assignment_kind,
                .sequence_number = raw_assignment.sequence_number,
                .pattern = raw_assignment.monitor_pattern,
            };
            if (!self.hasAssignment(assignment)) {
                try self.assignments.append(self.allocator, assignment);
            }
            _ = try self.workspaceIdByName(workspace_raw, true);
        }

        try self.ensurePersistentWorkspaces();
        try self.applyForcedAssignments();
        try self.ensureVisibleWorkspaces(self.monitors.items, windows);
        self.reconcileForcedVisibleWorkspaces();
    }
};

fn testMonitorSnapshot(id: u32, is_main: bool, x: f64, y: f64, width: f64, height: f64, name: []const u8) abi.OmniWorkspaceRuntimeMonitorSnapshot {
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
        .name = monitor.encodeName(name),
    };
}

test "workspace visibility transitions keep previous mapping" {
    var windows = window_model.WindowModel.init(std.testing.allocator);
    defer windows.deinit();

    var manager = try WorkspaceManager.init(std.testing.allocator);
    defer manager.deinit();

    const snapshots = [_]abi.OmniWorkspaceRuntimeMonitorSnapshot{
        testMonitorSnapshot(11, true, 0.0, 0.0, 100.0, 100.0, "Main"),
        testMonitorSnapshot(22, false, 120.0, 0.0, 100.0, 100.0, "Side"),
    };
    try manager.importMonitors(snapshots[0..], &windows);

    const one = (try manager.workspaceIdByName("1", true)).?;
    const two = (try manager.workspaceIdByName("2", true)).?;

    try std.testing.expect(manager.setActiveWorkspace(one, 11));
    try std.testing.expect(manager.setActiveWorkspace(two, 11));

    const visible = manager.visibleWorkspaceOnMonitor(11).?;
    try std.testing.expect(std.mem.eql(u8, visible.bytes[0..], two.bytes[0..]));

    const previous = manager.previousWorkspaceOnMonitor(11).?;
    try std.testing.expect(std.mem.eql(u8, previous.bytes[0..], one.bytes[0..]));

    try std.testing.expect(manager.visibleMonitorForWorkspace(one) == null);
}
