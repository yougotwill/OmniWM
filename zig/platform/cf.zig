const std = @import("std");
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
});

pub const CFTypeRef = c.CFTypeRef;
pub const RunLoopRef = c.CFRunLoopRef;
pub const ArrayRef = c.CFArrayRef;
pub const MachPortRef = c.CFMachPortRef;

pub fn asType(comptime T: type, value: CFTypeRef) ?T {
    if (value == null) return null;
    return @ptrCast(@alignCast(value));
}

pub fn retain(value: CFTypeRef) CFTypeRef {
    if (value == null) return null;
    return c.CFRetain(value);
}

pub fn release(value: CFTypeRef) void {
    if (value == null) return;
    c.CFRelease(value);
}

pub fn currentRunLoop() RunLoopRef {
    return c.CFRunLoopGetCurrent();
}

pub fn runLoopRun() void {
    c.CFRunLoopRun();
}

pub fn runLoopStop(loop: RunLoopRef) void {
    if (loop == null) return;
    c.CFRunLoopStop(loop);
}

pub fn arrayCount(array: ArrayRef) usize {
    if (array == null) return 0;
    return @intCast(c.CFArrayGetCount(array));
}

pub fn arrayValueAtIndex(array: ArrayRef, index: usize) ?*const anyopaque {
    if (array == null) return null;
    const idx: c.CFIndex = @intCast(index);
    return c.CFArrayGetValueAtIndex(array, idx);
}

pub fn machPortInvalidate(port: MachPortRef) void {
    if (port == null) return;
    c.CFMachPortInvalidate(port);
}

pub fn cfString(value: []const u8) ?c.CFStringRef {
    if (value.len == 0) {
        return c.CFStringCreateWithCString(null, "", c.kCFStringEncodingUTF8);
    }
    const sentinel = std.heap.c_allocator.dupeZ(u8, value) catch return null;
    defer std.heap.c_allocator.free(sentinel);
    return c.CFStringCreateWithCString(null, sentinel.ptr, c.kCFStringEncodingUTF8);
}

pub fn CFRef(comptime T: type) type {
    return struct {
        value: ?T,

        pub fn init(value: ?T) @This() {
            return .{ .value = value };
        }

        pub fn get(self: @This()) ?T {
            return self.value;
        }

        pub fn retainRef(self: @This()) @This() {
            if (self.value) |raw| {
                _ = retain(@ptrCast(raw));
            }
            return self;
        }

        pub fn releaseRef(self: *@This()) void {
            if (self.value) |raw| {
                release(@ptrCast(raw));
                self.value = null;
            }
        }
    };
}
