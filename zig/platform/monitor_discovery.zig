const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const objc = @import("objc.zig");

const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
});

const NSPoint = extern struct {
    x: f64,
    y: f64,
};

const NSSize = extern struct {
    width: f64,
    height: f64,
};

const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

const NSEdgeInsets = extern struct {
    top: f64,
    left: f64,
    bottom: f64,
    right: f64,
};

pub const OmniMonitorRuntime = abi.OmniMonitorRuntime;

const RuntimeImpl = struct {
    host: abi.OmniMonitorHostVTable,
    started: bool = false,

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;
        const rc = c.CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, self);
        if (rc != c.kCGErrorSuccess) return abi.OMNI_ERR_PLATFORM;
        self.started = true;
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_OK;
        _ = c.CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, self);
        self.started = false;
        return abi.OMNI_OK;
    }

    fn dispatchDisplayChange(self: *RuntimeImpl, display_id: u32, change_flags: u32) void {
        if (!self.started) return;
        if (self.host.on_displays_changed) |callback| {
            _ = callback(self.host.userdata, display_id, change_flags);
        }
    }
};

fn runtimeFromHandle(runtime: [*c]OmniMonitorRuntime) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

fn encodeName(value: []const u8) abi.OmniWorkspaceRuntimeName {
    const clamped_len = @min(value.len, abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP);
    var result = abi.OmniWorkspaceRuntimeName{
        .length = @intCast(clamped_len),
        .bytes = [_]u8{0} ** abi.OMNI_WORKSPACE_RUNTIME_NAME_CAP,
    };
    std.mem.copyForwards(u8, result.bytes[0..clamped_len], value[0..clamped_len]);
    return result;
}

fn nsString(c_string: [*:0]const u8) objc.Id {
    const cls = objc.getClass("NSString") orelse return null;
    return objc.msgSend1(objc.Id, cls, objc.sel("stringWithUTF8String:"), c_string);
}

fn rectSortLessThan(lhs: abi.OmniMonitorRecord, rhs: abi.OmniMonitorRecord) bool {
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

fn collectCurrentMonitors(
    allocator: std.mem.Allocator,
    records: *std.ArrayListUnmanaged(abi.OmniMonitorRecord),
) !void {
    records.clearRetainingCapacity();
    var pool = objc.AutoreleasePool.init();
    defer pool.drain();

    const screen_class = objc.getClass("NSScreen") orelse return;
    const screens = objc.msgSend0(objc.Id, screen_class, objc.sel("screens"));
    if (screens == null) return;

    const count = objc.msgSend0(usize, screens, objc.sel("count"));
    try records.ensureTotalCapacity(allocator, count);

    const ns_screen_number_key = nsString("NSScreenNumber");
    const main_display_id: u32 = @intCast(c.CGMainDisplayID());

    var index: usize = 0;
    while (index < count) : (index += 1) {
        const screen = objc.msgSend1(objc.Id, screens, objc.sel("objectAtIndex:"), index);
        if (screen == null) continue;

        const device_description = objc.msgSend0(objc.Id, screen, objc.sel("deviceDescription"));
        if (device_description == null) continue;
        const screen_number = objc.msgSend1(objc.Id, device_description, objc.sel("objectForKey:"), ns_screen_number_key);
        if (screen_number == null) continue;

        const display_id = objc.msgSend0(u32, screen_number, objc.sel("unsignedIntValue"));
        if (display_id == 0) continue;

        const frame = objc.msgSendStruct0(NSRect, screen, objc.sel("frame"));
        const visible = objc.msgSendStruct0(NSRect, screen, objc.sel("visibleFrame"));
        const localized_name = objc.msgSend0(objc.Id, screen, objc.sel("localizedName"));
        const utf8_name = if (localized_name != null)
            objc.msgSend0([*:0]const u8, localized_name, objc.sel("UTF8String"))
        else
            "";
        const backing_scale = objc.msgSend0(f64, screen, objc.sel("backingScaleFactor"));

        var has_notch: u8 = 0;
        if (objc.msgSend1(bool, screen, objc.sel("respondsToSelector:"), objc.sel("safeAreaInsets"))) {
            const safe_area = objc.msgSendStruct0(NSEdgeInsets, screen, objc.sel("safeAreaInsets"));
            has_notch = if (safe_area.top > 0) 1 else 0;
        }

        records.appendAssumeCapacity(.{
            .display_id = display_id,
            .is_main = if (display_id == main_display_id) 1 else 0,
            .frame_x = frame.origin.x,
            .frame_y = frame.origin.y,
            .frame_width = frame.size.width,
            .frame_height = frame.size.height,
            .visible_x = visible.origin.x,
            .visible_y = visible.origin.y,
            .visible_width = visible.size.width,
            .visible_height = visible.size.height,
            .has_notch = has_notch,
            .backing_scale = if (std.math.isFinite(backing_scale) and backing_scale > 0) backing_scale else 2.0,
            .name = encodeName(std.mem.span(utf8_name)),
        });
    }

    if (records.items.len > 1) {
        std.sort.insertion(abi.OmniMonitorRecord, records.items, {}, struct {
            fn lessThan(_: void, lhs: abi.OmniMonitorRecord, rhs: abi.OmniMonitorRecord) bool {
                return rectSortLessThan(lhs, rhs);
            }
        }.lessThan);
    }
}

fn displayReconfigurationCallback(
    display: c.CGDirectDisplayID,
    flags: c.CGDisplayChangeSummaryFlags,
    user_info: ?*anyopaque,
) callconv(.c) void {
    const raw_ctx = user_info orelse return;
    const ctx: *RuntimeImpl = @ptrCast(@alignCast(raw_ctx));
    const display_id: u32 = @intCast(display);
    const change_flags: u32 = @truncate(@as(u64, @intCast(flags)));
    ctx.dispatchDisplayChange(display_id, change_flags);
}

pub fn omni_monitor_query_current_impl(
    out_monitors: [*c]abi.OmniMonitorRecord,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    if (out_written == null) return abi.OMNI_ERR_INVALID_ARGS;

    var records = std.ArrayListUnmanaged(abi.OmniMonitorRecord){};
    defer records.deinit(std.heap.c_allocator);
    collectCurrentMonitors(std.heap.c_allocator, &records) catch return abi.OMNI_ERR_OUT_OF_RANGE;

    out_written[0] = records.items.len;
    if (out_capacity == 0 and out_monitors == null) {
        return abi.OMNI_OK;
    }
    if (records.items.len > out_capacity) {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }
    if (records.items.len > 0 and out_monitors == null) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }

    if (records.items.len > 0) {
        std.mem.copyForwards(
            abi.OmniMonitorRecord,
            out_monitors[0..records.items.len],
            records.items,
        );
    }
    return abi.OMNI_OK;
}

pub fn omni_monitor_runtime_create_impl(
    config: ?*const abi.OmniMonitorRuntimeConfig,
    host_vtable: ?*const abi.OmniMonitorHostVTable,
) [*c]OmniMonitorRuntime {
    const resolved_host = host_vtable orelse return null;
    var resolved_config = abi.OmniMonitorRuntimeConfig{
        .abi_version = abi.OMNI_MONITOR_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_MONITOR_RUNTIME_ABI_VERSION) return null;

    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = .{
        .host = resolved_host.*,
    };
    return @ptrCast(runtime);
}

pub fn omni_monitor_runtime_destroy_impl(runtime: [*c]OmniMonitorRuntime) void {
    const impl = runtimeFromHandle(runtime) orelse return;
    _ = impl.stop();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_monitor_runtime_start_impl(runtime: [*c]OmniMonitorRuntime) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.start();
}

pub fn omni_monitor_runtime_stop_impl(runtime: [*c]OmniMonitorRuntime) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}
