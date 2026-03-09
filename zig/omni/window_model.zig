const std = @import("std");
const abi = @import("abi_types.zig");

pub const WindowKey = struct {
    pid: i32,
    window_id: i64,
};

pub const HiddenState = struct {
    proportional_x: f64,
    proportional_y: f64,
    reference_display_id: ?u32,
    workspace_inactive: bool,
};

pub const Entry = struct {
    handle_id: abi.OmniUuid128,
    key: WindowKey,
    workspace_id: abi.OmniUuid128,
    hidden_state: ?HiddenState = null,
    layout_reason: u8 = abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD,
};

pub const WindowModel = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    index_by_key: std.AutoHashMapUnmanaged(WindowKey, usize) = .{},
    index_by_handle: std.AutoHashMapUnmanaged(abi.OmniUuid128, usize) = .{},
    workspace_counts: std.AutoHashMapUnmanaged(abi.OmniUuid128, usize) = .{},
    missing_counts: std.AutoHashMapUnmanaged(WindowKey, u32) = .{},
    next_handle_serial: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) WindowModel {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WindowModel) void {
        self.entries.deinit(self.allocator);
        self.index_by_key.deinit(self.allocator);
        self.index_by_handle.deinit(self.allocator);
        self.workspace_counts.deinit(self.allocator);
        self.missing_counts.deinit(self.allocator);
        self.* = undefined;
    }

    fn uuidEqual(lhs: abi.OmniUuid128, rhs: abi.OmniUuid128) bool {
        return std.mem.eql(u8, lhs.bytes[0..], rhs.bytes[0..]);
    }

    fn incrementWorkspaceCount(self: *WindowModel, workspace_id: abi.OmniUuid128) !void {
        const current = self.workspace_counts.get(workspace_id) orelse 0;
        try self.workspace_counts.put(self.allocator, workspace_id, current + 1);
    }

    fn decrementWorkspaceCount(self: *WindowModel, workspace_id: abi.OmniUuid128) void {
        const current = self.workspace_counts.get(workspace_id) orelse return;
        if (current <= 1) {
            _ = self.workspace_counts.remove(workspace_id);
            return;
        }
        self.workspace_counts.put(self.allocator, workspace_id, current - 1) catch {};
    }

    fn generateHandleId(self: *WindowModel) abi.OmniUuid128 {
        var bytes = [_]u8{0} ** 16;
        std.mem.writeInt(u64, bytes[0..8], self.next_handle_serial, .little);
        bytes[8] = 0x77;
        bytes[9] = 0x6d;
        bytes[10] = 0x68;
        bytes[11] = 0x64;
        self.next_handle_serial += 1;
        return .{ .bytes = bytes };
    }

    fn removeAt(self: *WindowModel, index: usize) void {
        if (index >= self.entries.items.len) {
            return;
        }
        const removed = self.entries.swapRemove(index);
        _ = self.index_by_key.remove(removed.key);
        _ = self.index_by_handle.remove(removed.handle_id);
        _ = self.missing_counts.remove(removed.key);
        self.decrementWorkspaceCount(removed.workspace_id);

        if (index < self.entries.items.len) {
            const moved = self.entries.items[index];
            self.index_by_key.put(self.allocator, moved.key, index) catch {};
            self.index_by_handle.put(self.allocator, moved.handle_id, index) catch {};
        }
    }

    fn findIndexByKey(self: *const WindowModel, key: WindowKey) ?usize {
        return self.index_by_key.get(key);
    }

    fn findIndexByHandle(self: *const WindowModel, handle_id: abi.OmniUuid128) ?usize {
        return self.index_by_handle.get(handle_id);
    }

    pub fn upsert(
        self: *WindowModel,
        request: abi.OmniWorkspaceRuntimeWindowUpsert,
    ) !abi.OmniUuid128 {
        const key = WindowKey{
            .pid = request.pid,
            .window_id = request.window_id,
        };

        if (self.findIndexByKey(key)) |index| {
            _ = self.missing_counts.remove(key);
            return self.entries.items[index].handle_id;
        }

        var handle_id = request.handle_id;
        if (request.has_handle_id == 0 or self.findIndexByHandle(handle_id) != null) {
            handle_id = self.generateHandleId();
            while (self.findIndexByHandle(handle_id) != null) {
                handle_id = self.generateHandleId();
            }
        }

        try self.entries.append(self.allocator, .{
            .handle_id = handle_id,
            .key = key,
            .workspace_id = request.workspace_id,
            .hidden_state = null,
            .layout_reason = abi.OMNI_WORKSPACE_LAYOUT_REASON_STANDARD,
        });
        const index = self.entries.items.len - 1;
        try self.index_by_key.put(self.allocator, key, index);
        try self.index_by_handle.put(self.allocator, handle_id, index);
        try self.incrementWorkspaceCount(request.workspace_id);
        _ = self.missing_counts.remove(key);
        return handle_id;
    }

    pub fn removeWindow(self: *WindowModel, key: WindowKey) bool {
        const index = self.findIndexByKey(key) orelse return false;
        self.removeAt(index);
        return true;
    }

    pub fn setWorkspace(self: *WindowModel, handle_id: abi.OmniUuid128, workspace_id: abi.OmniUuid128) bool {
        const index = self.findIndexByHandle(handle_id) orelse return false;
        var entry = &self.entries.items[index];
        if (uuidEqual(entry.workspace_id, workspace_id)) {
            return true;
        }
        self.decrementWorkspaceCount(entry.workspace_id);
        self.incrementWorkspaceCount(workspace_id) catch return false;
        entry.workspace_id = workspace_id;
        return true;
    }

    pub fn setHiddenState(self: *WindowModel, handle_id: abi.OmniUuid128, state: ?HiddenState) bool {
        const index = self.findIndexByHandle(handle_id) orelse return false;
        self.entries.items[index].hidden_state = state;
        return true;
    }

    pub fn setLayoutReason(self: *WindowModel, handle_id: abi.OmniUuid128, reason: u8) bool {
        const index = self.findIndexByHandle(handle_id) orelse return false;
        self.entries.items[index].layout_reason = reason;
        return true;
    }

    pub fn removeMissing(
        self: *WindowModel,
        active_keys: []const abi.OmniWorkspaceRuntimeWindowKey,
        required_consecutive_misses: u32,
    ) !void {
        const threshold = @max(@as(u32, 1), required_consecutive_misses);

        var active = std.AutoHashMapUnmanaged(WindowKey, void){};
        defer active.deinit(self.allocator);
        for (active_keys) |raw| {
            const key = WindowKey{ .pid = raw.pid, .window_id = raw.window_id };
            try active.put(self.allocator, key, {});
        }

        var missing = std.ArrayListUnmanaged(WindowKey){};
        defer missing.deinit(self.allocator);

        var key_it = self.index_by_key.iterator();
        while (key_it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (active.contains(key)) {
                _ = self.missing_counts.remove(key);
                continue;
            }

            const misses = (self.missing_counts.get(key) orelse 0) + 1;
            if (misses >= threshold) {
                _ = self.missing_counts.remove(key);
                try missing.append(self.allocator, key);
            } else {
                try self.missing_counts.put(self.allocator, key, misses);
            }
        }

        for (missing.items) |key| {
            _ = self.removeWindow(key);
        }

        var stale = std.ArrayListUnmanaged(WindowKey){};
        defer stale.deinit(self.allocator);
        var missing_it = self.missing_counts.iterator();
        while (missing_it.next()) |entry| {
            if (!self.index_by_key.contains(entry.key_ptr.*)) {
                try stale.append(self.allocator, entry.key_ptr.*);
            }
        }
        for (stale.items) |key| {
            _ = self.missing_counts.remove(key);
        }
    }

    pub fn hasWindowsInWorkspace(self: *const WindowModel, workspace_id: abi.OmniUuid128) bool {
        return (self.workspace_counts.get(workspace_id) orelse 0) > 0;
    }

    pub fn workspaceForHandle(self: *const WindowModel, handle_id: abi.OmniUuid128) ?abi.OmniUuid128 {
        const index = self.findIndexByHandle(handle_id) orelse return null;
        return self.entries.items[index].workspace_id;
    }

    pub fn validateInvariants(self: *const WindowModel) !void {
        if (self.index_by_key.count() != self.entries.items.len) {
            std.log.warn(
                "window model validation failed reason=index_by_key_count_mismatch expected={d} actual={d}",
                .{ self.entries.items.len, self.index_by_key.count() },
            );
            return error.InvariantViolation;
        }
        if (self.index_by_handle.count() != self.entries.items.len) {
            std.log.warn(
                "window model validation failed reason=index_by_handle_count_mismatch expected={d} actual={d}",
                .{ self.entries.items.len, self.index_by_handle.count() },
            );
            return error.InvariantViolation;
        }

        var expected_workspace_counts = std.AutoHashMapUnmanaged(abi.OmniUuid128, usize){};
        defer expected_workspace_counts.deinit(self.allocator);

        for (self.entries.items, 0..) |entry, index| {
            const key_index = self.index_by_key.get(entry.key) orelse {
                std.log.warn(
                    "window model validation failed reason=missing_key_index pid={d} window_id={d}",
                    .{ entry.key.pid, entry.key.window_id },
                );
                return error.InvariantViolation;
            };
            if (key_index != index) {
                std.log.warn(
                    "window model validation failed reason=key_index_mismatch pid={d} window_id={d} expected={d} actual={d}",
                    .{ entry.key.pid, entry.key.window_id, index, key_index },
                );
                return error.InvariantViolation;
            }

            const handle_index = self.index_by_handle.get(entry.handle_id) orelse {
                std.log.warn("window model validation failed reason=missing_handle_index index={d}", .{index});
                return error.InvariantViolation;
            };
            if (handle_index != index) {
                std.log.warn(
                    "window model validation failed reason=handle_index_mismatch expected={d} actual={d}",
                    .{ index, handle_index },
                );
                return error.InvariantViolation;
            }

            const current = expected_workspace_counts.get(entry.workspace_id) orelse 0;
            try expected_workspace_counts.put(self.allocator, entry.workspace_id, current + 1);
        }

        if (expected_workspace_counts.count() != self.workspace_counts.count()) {
            std.log.warn(
                "window model validation failed reason=workspace_count_size_mismatch expected={d} actual={d}",
                .{ expected_workspace_counts.count(), self.workspace_counts.count() },
            );
            return error.InvariantViolation;
        }

        var expected_it = expected_workspace_counts.iterator();
        while (expected_it.next()) |entry| {
            const actual = self.workspace_counts.get(entry.key_ptr.*) orelse {
                std.log.warn("window model validation failed reason=missing_workspace_count", .{});
                return error.InvariantViolation;
            };
            if (actual != entry.value_ptr.*) {
                std.log.warn(
                    "window model validation failed reason=workspace_count_mismatch expected={d} actual={d}",
                    .{ entry.value_ptr.*, actual },
                );
                return error.InvariantViolation;
            }
        }

        var actual_it = self.workspace_counts.iterator();
        while (actual_it.next()) |entry| {
            const expected = expected_workspace_counts.get(entry.key_ptr.*) orelse {
                std.log.warn("window model validation failed reason=unexpected_workspace_count", .{});
                return error.InvariantViolation;
            };
            if (expected != entry.value_ptr.*) {
                std.log.warn(
                    "window model validation failed reason=workspace_count_reverse_mismatch expected={d} actual={d}",
                    .{ expected, entry.value_ptr.* },
                );
                return error.InvariantViolation;
            }
        }

        var missing_it = self.missing_counts.iterator();
        while (missing_it.next()) |entry| {
            if (!self.index_by_key.contains(entry.key_ptr.*)) {
                std.log.warn(
                    "window model validation failed reason=stale_missing_count pid={d} window_id={d}",
                    .{ entry.key_ptr.*.pid, entry.key_ptr.*.window_id },
                );
                return error.InvariantViolation;
            }
        }
    }
};
