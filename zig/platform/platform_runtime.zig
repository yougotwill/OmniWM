const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const skylight = @import("skylight.zig");

const ConnectionEvent = enum(u32) {
    window_moved = 806,
    window_resized = 807,
    window_title_changed = 1322,
    space_window_created = 1325,
    space_window_destroyed = 1326,
    frontmost_application_changed = 1508,
};

const NotifyEvent = enum(u32) {
    window_closed = 804,
};

const connection_events = [_]ConnectionEvent{
    .space_window_created,
    .space_window_destroyed,
    .window_moved,
    .window_resized,
    .window_title_changed,
    .frontmost_application_changed,
};

pub const OmniPlatformRuntime = abi.OmniPlatformRuntime;

const RuntimeImpl = struct {
    host: abi.OmniPlatformHostVTable,
    started: bool = false,
    registered_connection_events: [connection_events.len]bool = [_]bool{false} ** connection_events.len,
    window_closed_registered: bool = false,
    notify_context: ?*anyopaque = null,

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;

        var registered_count: usize = 0;
        for (connection_events, 0..) |event, index| {
            if (skylight.registerConnectionNotify(connectionCallback, @intFromEnum(event), self) == abi.OMNI_OK) {
                self.registered_connection_events[index] = true;
                registered_count += 1;
            }
        }

        const cid = skylight.mainConnectionId();
        if (cid > 0) {
            self.notify_context = @ptrFromInt(@as(usize, @intCast(cid)));
        } else {
            self.notify_context = null;
        }

        if (skylight.registerNotifyProc(notifyCallback, @intFromEnum(NotifyEvent.window_closed), self.notify_context) == abi.OMNI_OK) {
            self.window_closed_registered = true;
            registered_count += 1;
            g_notify_runtime = self;
        }

        self.started = registered_count > 0;
        if (!self.started) return abi.OMNI_ERR_PLATFORM;

        self.subscribeAllVisibleWindows();
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_OK;

        for (connection_events, 0..) |event, index| {
            if (!self.registered_connection_events[index]) continue;
            _ = skylight.unregisterConnectionNotify(connectionCallback, @intFromEnum(event));
            self.registered_connection_events[index] = false;
        }

        if (self.window_closed_registered) {
            _ = skylight.unregisterNotifyProc(notifyCallback, @intFromEnum(NotifyEvent.window_closed), self.notify_context);
            self.window_closed_registered = false;
        }
        if (g_notify_runtime == self) {
            g_notify_runtime = null;
        }

        self.started = false;
        return abi.OMNI_OK;
    }

    fn subscribeWindows(self: *RuntimeImpl, window_ids: [*c]const u32, window_count: usize) i32 {
        _ = self;
        return skylight.subscribeWindowNotifications(window_ids, window_count);
    }

    fn subscribeAllVisibleWindows(self: *RuntimeImpl) void {
        _ = self;
        var buffer: [1024]abi.OmniSkyLightWindowInfo = undefined;
        var written: usize = 0;
        if (skylight.queryVisibleWindows(&buffer, buffer.len, &written) != abi.OMNI_OK) return;

        const count = @min(written, buffer.len);
        if (count == 0) return;

        var ids: [1024]u32 = undefined;
        var id_count: usize = 0;
        for (buffer[0..count]) |entry| {
            ids[id_count] = entry.id;
            id_count += 1;
        }
        _ = skylight.subscribeWindowNotifications(&ids, id_count);
    }

    fn dispatchConnectionEvent(self: *RuntimeImpl, event: u32, data: ?*anyopaque, length: usize) void {
        if (!self.started) return;

        switch (event) {
            @intFromEnum(ConnectionEvent.space_window_created) => {
                const space_id = readU64(data, length, 0) orelse return;
                const window_id = readU32(data, length, 8) orelse return;
                if (self.host.on_window_created) |callback| {
                    _ = callback(self.host.userdata, window_id, space_id);
                }
                _ = skylight.subscribeWindowNotifications(&[_]u32{window_id}, 1);
            },
            @intFromEnum(ConnectionEvent.space_window_destroyed) => {
                const space_id = readU64(data, length, 0) orelse return;
                const window_id = readU32(data, length, 8) orelse return;
                if (self.host.on_window_destroyed) |callback| {
                    _ = callback(self.host.userdata, window_id, space_id);
                }
            },
            @intFromEnum(ConnectionEvent.window_moved) => {
                const window_id = readU32(data, length, 0) orelse return;
                if (self.host.on_window_moved) |callback| {
                    _ = callback(self.host.userdata, window_id);
                }
            },
            @intFromEnum(ConnectionEvent.window_resized) => {
                const window_id = readU32(data, length, 0) orelse return;
                if (self.host.on_window_resized) |callback| {
                    _ = callback(self.host.userdata, window_id);
                }
            },
            @intFromEnum(ConnectionEvent.window_title_changed) => {
                const window_id = readU32(data, length, 0) orelse return;
                if (self.host.on_window_title_changed) |callback| {
                    _ = callback(self.host.userdata, window_id);
                }
            },
            @intFromEnum(ConnectionEvent.frontmost_application_changed) => {
                const pid = readI32(data, length, 0) orelse return;
                if (self.host.on_front_app_changed) |callback| {
                    _ = callback(self.host.userdata, pid);
                }
            },
            else => {},
        }
    }

    fn dispatchNotifyEvent(self: *RuntimeImpl, event: u32, data: ?*anyopaque, length: usize) void {
        if (!self.started) return;
        if (event != @intFromEnum(NotifyEvent.window_closed)) return;

        const window_id = readU32(data, length, 0) orelse return;
        if (self.host.on_window_closed) |callback| {
            _ = callback(self.host.userdata, window_id);
        }
    }
};

var g_notify_runtime: ?*RuntimeImpl = null;

fn connectionCallback(
    event: u32,
    data: ?*anyopaque,
    length: usize,
    context: ?*anyopaque,
    cid: i32,
) callconv(.c) void {
    _ = cid;
    const context_ptr = context orelse return;
    const runtime: *RuntimeImpl = @ptrCast(@alignCast(context_ptr));
    runtime.dispatchConnectionEvent(event, data, length);
}

fn notifyCallback(
    event: u32,
    data: ?*anyopaque,
    length: usize,
    cid: i32,
) callconv(.c) void {
    _ = cid;
    const runtime = g_notify_runtime orelse return;
    runtime.dispatchNotifyEvent(event, data, length);
}

fn payload(data: ?*anyopaque, length: usize) ?[]const u8 {
    if (data == null or length == 0) return null;
    const bytes: [*]const u8 = @ptrCast(data.?);
    return bytes[0..length];
}

fn readU32(data: ?*anyopaque, length: usize, offset: usize) ?u32 {
    const bytes = payload(data, length) orelse return null;
    if (bytes.len < offset + 4) return null;
    const raw: *const [4]u8 = @ptrCast(bytes[offset .. offset + 4].ptr);
    return std.mem.readInt(u32, raw, .little);
}

fn readU64(data: ?*anyopaque, length: usize, offset: usize) ?u64 {
    const bytes = payload(data, length) orelse return null;
    if (bytes.len < offset + 8) return null;
    const raw: *const [8]u8 = @ptrCast(bytes[offset .. offset + 8].ptr);
    return std.mem.readInt(u64, raw, .little);
}

fn readI32(data: ?*anyopaque, length: usize, offset: usize) ?i32 {
    const raw = readU32(data, length, offset) orelse return null;
    return @bitCast(raw);
}

pub fn omni_platform_runtime_create_impl(
    config: ?*const abi.OmniPlatformRuntimeConfig,
    host_vtable: ?*const abi.OmniPlatformHostVTable,
) [*c]OmniPlatformRuntime {
    const resolved_host = host_vtable orelse return null;
    var resolved_config = abi.OmniPlatformRuntimeConfig{
        .abi_version = abi.OMNI_PLATFORM_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_PLATFORM_RUNTIME_ABI_VERSION) return null;

    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = .{
        .host = resolved_host.*,
    };
    return @ptrCast(runtime);
}

pub fn omni_platform_runtime_destroy_impl(runtime: [*c]OmniPlatformRuntime) void {
    if (runtime == null) return;
    const impl: *RuntimeImpl = @ptrCast(@alignCast(runtime));
    _ = impl.stop();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_platform_runtime_start_impl(runtime: [*c]OmniPlatformRuntime) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *RuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.start();
}

pub fn omni_platform_runtime_stop_impl(runtime: [*c]OmniPlatformRuntime) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *RuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.stop();
}

pub fn omni_platform_runtime_subscribe_windows_impl(
    runtime: [*c]OmniPlatformRuntime,
    window_ids: [*c]const u32,
    window_count: usize,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *RuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.subscribeWindows(window_ids, window_count);
}
