const std = @import("std");
const abi = @import("abi_types.zig");
const accessibility = @import("../platform/accessibility.zig");
const objc = @import("../platform/objc.zig");
const private_apis = @import("../platform/private_apis.zig");

const c = accessibility.c;

pub const Hooks = struct {
    private_focus: ?*const fn (i32, u32) i32 = null,
    activate_application: ?*const fn (i32) i32 = null,
    raise_window: ?*const fn (i32, u32) i32 = null,
};

var hooks = Hooks{};
var test_activate_call_count: usize = 0;
var test_raise_call_count: usize = 0;

pub fn replaceHooks(new_hooks: Hooks) Hooks {
    const previous = hooks;
    hooks = new_hooks;
    return previous;
}

pub fn activateApplication(pid: i32) i32 {
    if (pid <= 0) return abi.OMNI_ERR_INVALID_ARGS;
    if (hooks.activate_application) |callback| {
        return callback(pid);
    }

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
    if (hooks.raise_window) |callback| {
        return callback(pid, window_id);
    }

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
    if (pid <= 0 or window_id == 0) return abi.OMNI_ERR_INVALID_ARGS;

    const private_focus_rc = if (hooks.private_focus) |callback|
        callback(pid, window_id)
    else
        private_apis.focusWindow(pid, window_id);
    if (private_focus_rc == abi.OMNI_OK) {
        _ = raiseWindow(pid, window_id);
        return abi.OMNI_OK;
    }

    const activate_rc = activateApplication(pid);
    if (activate_rc != abi.OMNI_OK) return abi.OMNI_ERR_PLATFORM;

    const raise_rc = raiseWindow(pid, window_id);
    if (raise_rc == abi.OMNI_OK) return abi.OMNI_OK;
    return abi.OMNI_ERR_PLATFORM;
}

test "focus manager validates arguments" {
    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_INVALID_ARGS), activateApplication(0));
    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_INVALID_ARGS), raiseWindow(0, 0));
    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_INVALID_ARGS), focusWindow(0, 0));
}

test "focus manager prefers private focus path and skips activation fallback" {
    const private_focus = struct {
        fn run(_: i32, _: u32) i32 {
            return abi.OMNI_OK;
        }
    }.run;
    const activate = struct {
        fn run(_: i32) i32 {
            test_activate_call_count += 1;
            return abi.OMNI_OK;
        }
    }.run;
    const raise = struct {
        fn run(_: i32, _: u32) i32 {
            test_raise_call_count += 1;
            return abi.OMNI_ERR_PLATFORM;
        }
    }.run;

    test_activate_call_count = 0;
    test_raise_call_count = 0;
    const previous = replaceHooks(.{
        .private_focus = private_focus,
        .activate_application = activate,
        .raise_window = raise,
    });
    defer _ = replaceHooks(previous);

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), focusWindow(42, 77));
    try std.testing.expectEqual(@as(usize, 0), test_activate_call_count);
    try std.testing.expectEqual(@as(usize, 1), test_raise_call_count);
}

test "focus manager falls back to activate plus raise when private focus is unavailable" {
    const private_focus = struct {
        fn run(_: i32, _: u32) i32 {
            return abi.OMNI_ERR_PLATFORM;
        }
    }.run;
    const activate = struct {
        fn run(_: i32) i32 {
            test_activate_call_count += 1;
            return abi.OMNI_OK;
        }
    }.run;
    const raise = struct {
        fn run(_: i32, _: u32) i32 {
            test_raise_call_count += 1;
            return abi.OMNI_OK;
        }
    }.run;

    test_activate_call_count = 0;
    test_raise_call_count = 0;
    const previous = replaceHooks(.{
        .private_focus = private_focus,
        .activate_application = activate,
        .raise_window = raise,
    });
    defer _ = replaceHooks(previous);

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), focusWindow(42, 77));
    try std.testing.expectEqual(@as(usize, 1), test_activate_call_count);
    try std.testing.expectEqual(@as(usize, 1), test_raise_call_count);
}

test "focus manager returns platform error when both focus strategies fail" {
    const private_focus = struct {
        fn run(_: i32, _: u32) i32 {
            return abi.OMNI_ERR_PLATFORM;
        }
    }.run;
    const activate = struct {
        fn run(_: i32) i32 {
            return abi.OMNI_OK;
        }
    }.run;
    const raise = struct {
        fn run(_: i32, _: u32) i32 {
            return abi.OMNI_ERR_PLATFORM;
        }
    }.run;

    const previous = replaceHooks(.{
        .private_focus = private_focus,
        .activate_application = activate,
        .raise_window = raise,
    });
    defer _ = replaceHooks(previous);

    try std.testing.expectEqual(@as(i32, abi.OMNI_ERR_PLATFORM), focusWindow(42, 77));
}
