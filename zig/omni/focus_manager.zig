const std = @import("std");
const abi = @import("abi_types.zig");
const accessibility = @import("../platform/accessibility.zig");
const objc = @import("../platform/objc.zig");

const c = accessibility.c;

pub fn activateApplication(pid: i32) i32 {
    if (pid <= 0) return abi.OMNI_ERR_INVALID_ARGS;

    const app_class = objc.getClass("NSRunningApplication") orelse return abi.OMNI_ERR_PLATFORM;
    const app = objc.msgSend1(
        objc.Id,
        app_class,
        objc.sel("runningApplicationWithProcessIdentifier:"),
        pid,
    );
    if (app == null) return abi.OMNI_ERR_PLATFORM;

    // NSApplicationActivateIgnoringOtherApps = 1 << 1
    const activated = objc.msgSend1(bool, app, objc.sel("activateWithOptions:"), @as(usize, 2));
    return if (activated) abi.OMNI_OK else abi.OMNI_ERR_PLATFORM;
}

pub fn raiseWindow(pid: i32, window_id: u32) i32 {
    if (pid <= 0 or window_id == 0) return abi.OMNI_ERR_INVALID_ARGS;

    const callback = struct {
        fn run(element: accessibility.AXElementRef, _: ?*anyopaque) i32 {
            const action = c.CFStringCreateWithCString(
                c.kCFAllocatorDefault,
                "AXRaise",
                c.kCFStringEncodingUTF8,
            );
            if (action == null) return abi.OMNI_ERR_PLATFORM;
            defer c.CFRelease(action);

            const rc = c.AXUIElementPerformAction(element, @ptrCast(action));
            return if (rc == c.kAXErrorSuccess) abi.OMNI_OK else abi.OMNI_ERR_PLATFORM;
        }
    }.run;

    return accessibility.withWindowElementById(pid, window_id, callback, null);
}

pub fn focusWindow(pid: i32, window_id: u32) i32 {
    const activate_rc = activateApplication(pid);
    if (activate_rc != abi.OMNI_OK) return activate_rc;
    return raiseWindow(pid, window_id);
}

test "focus manager validates arguments" {
    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_INVALID_ARGS), activateApplication(0));
    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_INVALID_ARGS), raiseWindow(0, 0));
}
