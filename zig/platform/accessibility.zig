const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const private_apis = @import("private_apis.zig");

pub const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("CoreGraphics/CoreGraphics.h");
});

pub const AXElementRef = c.AXUIElementRef;

var g_windows_attr: c.CFStringRef = null;
var g_role_attr: c.CFStringRef = null;
var g_subrole_attr: c.CFStringRef = null;
var g_enabled_attr: c.CFStringRef = null;
var g_focused_window_attr: c.CFStringRef = null;
var g_position_attr: c.CFStringRef = null;
var g_size_attr: c.CFStringRef = null;
var g_close_button_attr: c.CFStringRef = null;
var g_fullscreen_button_attr: c.CFStringRef = null;
var g_zoom_button_attr: c.CFStringRef = null;
var g_minimize_button_attr: c.CFStringRef = null;
var g_fullscreen_attr: c.CFStringRef = null;
var g_grow_area_attr: c.CFStringRef = null;
var g_min_size_attr: c.CFStringRef = null;
var g_max_size_attr: c.CFStringRef = null;
var g_focused_window_changed_notification: c.CFStringRef = null;
var g_ui_element_destroyed_notification: c.CFStringRef = null;

pub fn createApplication(pid: i32) AXElementRef {
    return c.AXUIElementCreateApplication(@intCast(pid));
}

pub fn releaseCF(value: c.CFTypeRef) void {
    if (value == null) return;
    c.CFRelease(value);
}

pub fn getWindowId(element: AXElementRef) ?u32 {
    var window_id: u32 = 0;
    const rc = private_apis.getAXWindowId(@ptrCast(@constCast(element)), &window_id);
    if (rc != abi.OMNI_OK) return null;
    return window_id;
}

pub fn axAttrWindows() c.CFStringRef {
    return cachedAttr(&g_windows_attr, "AXWindows");
}

pub fn axAttrRole() c.CFStringRef {
    return cachedAttr(&g_role_attr, "AXRole");
}

pub fn axAttrSubrole() c.CFStringRef {
    return cachedAttr(&g_subrole_attr, "AXSubrole");
}

pub fn axAttrEnabled() c.CFStringRef {
    return cachedAttr(&g_enabled_attr, "AXEnabled");
}

pub fn axAttrFocusedWindow() c.CFStringRef {
    return cachedAttr(&g_focused_window_attr, "AXFocusedWindow");
}

pub fn axAttrPosition() c.CFStringRef {
    return cachedAttr(&g_position_attr, "AXPosition");
}

pub fn axAttrSize() c.CFStringRef {
    return cachedAttr(&g_size_attr, "AXSize");
}

pub fn axAttrCloseButton() c.CFStringRef {
    return cachedAttr(&g_close_button_attr, "AXCloseButton");
}

pub fn axAttrFullscreenButton() c.CFStringRef {
    return cachedAttr(&g_fullscreen_button_attr, "AXFullScreenButton");
}

pub fn axAttrZoomButton() c.CFStringRef {
    return cachedAttr(&g_zoom_button_attr, "AXZoomButton");
}

pub fn axAttrMinimizeButton() c.CFStringRef {
    return cachedAttr(&g_minimize_button_attr, "AXMinimizeButton");
}

pub fn axNotificationFocusedWindowChanged() c.CFStringRef {
    return cachedAttr(&g_focused_window_changed_notification, "AXFocusedWindowChanged");
}

pub fn axNotificationUIElementDestroyed() c.CFStringRef {
    return cachedAttr(&g_ui_element_destroyed_notification, "AXUIElementDestroyed");
}

fn copyAttributeValue(element: AXElementRef, attribute: c.CFStringRef, out_value: *c.CFTypeRef) bool {
    out_value.* = null;
    return c.AXUIElementCopyAttributeValue(element, attribute, out_value) == c.kAXErrorSuccess;
}

fn boolValueFromCF(raw: c.CFTypeRef) ?bool {
    if (raw == null) return null;
    if (c.CFGetTypeID(raw) == c.CFBooleanGetTypeID()) {
        return c.CFBooleanGetValue(@ptrCast(raw)) != 0;
    }
    return null;
}

fn cfStringEquals(raw: c.CFTypeRef, expected: []const u8) bool {
    if (raw == null) return false;
    if (c.CFGetTypeID(raw) != c.CFStringGetTypeID()) return false;

    var buf: [256]u8 = undefined;
    if (c.CFStringGetCString(@ptrCast(raw), &buf, buf.len, c.kCFStringEncodingUTF8) == 0) {
        return false;
    }

    const c_len = std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len;
    return std.mem.eql(u8, buf[0..c_len], expected);
}

fn hasAttributeElement(element: AXElementRef, attribute: c.CFStringRef) bool {
    var raw: c.CFTypeRef = null;
    defer releaseCF(raw);
    if (!copyAttributeValue(element, attribute, &raw)) return false;
    return raw != null;
}

fn boolAttribute(element: AXElementRef, attribute: c.CFStringRef) ?bool {
    var raw: c.CFTypeRef = null;
    defer releaseCF(raw);
    if (!copyAttributeValue(element, attribute, &raw)) return null;
    return boolValueFromCF(raw);
}

fn subroleIs(element: AXElementRef, expected: []const u8) bool {
    var raw: c.CFTypeRef = null;
    defer releaseCF(raw);
    if (!copyAttributeValue(element, axAttrSubrole(), &raw)) return false;
    return cfStringEquals(raw, expected);
}

pub fn classifyWindow(element: AXElementRef, app_policy: i32, force_floating: bool) u8 {
    if (force_floating) return abi.OMNI_AX_WINDOW_TYPE_FLOATING;

    const has_close_button = hasAttributeElement(element, axAttrCloseButton());
    const has_fullscreen_button = hasAttributeElement(element, axAttrFullscreenButton());
    const has_zoom_button = hasAttributeElement(element, axAttrZoomButton());
    const has_minimize_button = hasAttributeElement(element, axAttrMinimizeButton());

    const has_any_button = has_close_button or has_fullscreen_button or has_zoom_button or has_minimize_button;
    const is_standard_subrole = subroleIs(element, "AXStandardWindow");

    // NSApplication.ActivationPolicy.accessory raw value is 1.
    if (app_policy == 1 and !has_close_button) return abi.OMNI_AX_WINDOW_TYPE_FLOATING;

    if (!has_any_button and !is_standard_subrole) return abi.OMNI_AX_WINDOW_TYPE_FLOATING;
    if (!is_standard_subrole) return abi.OMNI_AX_WINDOW_TYPE_FLOATING;

    if (!has_fullscreen_button) return abi.OMNI_AX_WINDOW_TYPE_FLOATING;

    var fullscreen_button: c.CFTypeRef = null;
    defer releaseCF(fullscreen_button);
    if (!copyAttributeValue(element, axAttrFullscreenButton(), &fullscreen_button) or fullscreen_button == null) {
        return abi.OMNI_AX_WINDOW_TYPE_FLOATING;
    }

    const enabled = boolAttribute(@ptrCast(@constCast(fullscreen_button)), axAttrEnabled());
    if (enabled != true) return abi.OMNI_AX_WINDOW_TYPE_FLOATING;

    return abi.OMNI_AX_WINDOW_TYPE_TILING;
}

pub fn getFrameWindowServer(element: AXElementRef, out_rect: *abi.OmniBorderRect) i32 {
    var position_raw: c.CFTypeRef = null;
    defer releaseCF(position_raw);
    var size_raw: c.CFTypeRef = null;
    defer releaseCF(size_raw);

    if (!copyAttributeValue(element, axAttrPosition(), &position_raw)) return abi.OMNI_ERR_PLATFORM;
    if (!copyAttributeValue(element, axAttrSize(), &size_raw)) return abi.OMNI_ERR_PLATFORM;
    if (position_raw == null or size_raw == null) return abi.OMNI_ERR_PLATFORM;

    if (c.CFGetTypeID(position_raw) != c.AXValueGetTypeID()) return abi.OMNI_ERR_PLATFORM;
    if (c.CFGetTypeID(size_raw) != c.AXValueGetTypeID()) return abi.OMNI_ERR_PLATFORM;

    var pos = c.CGPointZero;
    var size = c.CGSizeZero;
    if (c.AXValueGetValue(@ptrCast(position_raw), c.kAXValueCGPointType, &pos) == 0) return abi.OMNI_ERR_PLATFORM;
    if (c.AXValueGetValue(@ptrCast(size_raw), c.kAXValueCGSizeType, &size) == 0) return abi.OMNI_ERR_PLATFORM;

    out_rect.* = .{
        .x = pos.x,
        .y = pos.y,
        .width = size.width,
        .height = size.height,
    };
    return abi.OMNI_OK;
}

pub fn setFrameWindowServer(element: AXElementRef, rect: abi.OmniBorderRect) i32 {
    var point = c.CGPointMake(rect.x, rect.y);
    var size = c.CGSizeMake(rect.width, rect.height);

    const position_value = c.AXValueCreate(c.kAXValueCGPointType, &point) orelse return abi.OMNI_ERR_PLATFORM;
    defer releaseCF(position_value);
    const size_value = c.AXValueCreate(c.kAXValueCGSizeType, &size) orelse return abi.OMNI_ERR_PLATFORM;
    defer releaseCF(size_value);

    const rc_size = c.AXUIElementSetAttributeValue(element, axAttrSize(), size_value);
    const rc_pos = c.AXUIElementSetAttributeValue(element, axAttrPosition(), position_value);

    if (rc_size != c.kAXErrorSuccess or rc_pos != c.kAXErrorSuccess) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn isFullscreen(element: AXElementRef, out_fullscreen: *u8) i32 {
    if (subroleIs(element, "AXFullScreenWindow")) {
        out_fullscreen.* = 1;
        return abi.OMNI_OK;
    }

    const fullscreen_attr = cachedAttr(&g_fullscreen_attr, "AXFullScreen");
    const maybe_bool = boolAttribute(element, fullscreen_attr);
    if (maybe_bool) |value| {
        out_fullscreen.* = if (value) 1 else 0;
        return abi.OMNI_OK;
    }

    out_fullscreen.* = 0;
    return abi.OMNI_OK;
}

pub fn setFullscreen(element: AXElementRef, fullscreen: bool) i32 {
    const fullscreen_attr = cachedAttr(&g_fullscreen_attr, "AXFullScreen");
    const value = if (fullscreen) c.kCFBooleanTrue else c.kCFBooleanFalse;
    if (c.AXUIElementSetAttributeValue(element, fullscreen_attr, value) != c.kAXErrorSuccess) {
        return abi.OMNI_ERR_PLATFORM;
    }
    return abi.OMNI_OK;
}

pub fn getConstraints(element: AXElementRef, out_constraints: *abi.OmniAXWindowConstraints) i32 {
    var min_width: f64 = 1;
    var min_height: f64 = 1;
    var max_width: f64 = 0;
    var max_height: f64 = 0;
    var has_max_width: u8 = 0;
    var has_max_height: u8 = 0;
    var is_fixed: u8 = 0;

    const has_grow_area = hasAttributeElement(element, cachedAttr(&g_grow_area_attr, "AXGrowArea"));
    const has_zoom_button = hasAttributeElement(element, axAttrZoomButton());
    const is_standard_subrole = subroleIs(element, "AXStandardWindow");
    const resizable = has_grow_area or has_zoom_button or is_standard_subrole;

    var min_raw: c.CFTypeRef = null;
    defer releaseCF(min_raw);
    if (copyAttributeValue(element, cachedAttr(&g_min_size_attr, "AXMinSize"), &min_raw) and min_raw != null and c.CFGetTypeID(min_raw) == c.AXValueGetTypeID()) {
        var min_size = c.CGSizeZero;
        if (c.AXValueGetValue(@ptrCast(min_raw), c.kAXValueCGSizeType, &min_size) != 0) {
            min_width = min_size.width;
            min_height = min_size.height;
        }
    }

    var max_raw: c.CFTypeRef = null;
    defer releaseCF(max_raw);
    if (copyAttributeValue(element, cachedAttr(&g_max_size_attr, "AXMaxSize"), &max_raw) and max_raw != null and c.CFGetTypeID(max_raw) == c.AXValueGetTypeID()) {
        var max_size = c.CGSizeZero;
        if (c.AXValueGetValue(@ptrCast(max_raw), c.kAXValueCGSizeType, &max_size) != 0) {
            max_width = max_size.width;
            max_height = max_size.height;
            if (max_width > 0) has_max_width = 1;
            if (max_height > 0) has_max_height = 1;
        }
    }

    if (!resizable) {
        var rect = abi.OmniBorderRect{ .x = 0, .y = 0, .width = 0, .height = 0 };
        if (getFrameWindowServer(element, &rect) == abi.OMNI_OK) {
            min_width = rect.width;
            min_height = rect.height;
            max_width = rect.width;
            max_height = rect.height;
            has_max_width = 1;
            has_max_height = 1;
            is_fixed = 1;
        }
    }

    out_constraints.* = .{
        .min_width = min_width,
        .min_height = min_height,
        .max_width = max_width,
        .max_height = max_height,
        .has_max_width = has_max_width,
        .has_max_height = has_max_height,
        .is_fixed = is_fixed,
    };

    return abi.OMNI_OK;
}

pub fn getFocusedWindowIdForApp(pid: i32, out_window_id: *u32) i32 {
    const app = createApplication(pid);
    if (app == null) return abi.OMNI_ERR_PLATFORM;

    var focused_raw: c.CFTypeRef = null;
    defer releaseCF(focused_raw);

    if (!copyAttributeValue(app, axAttrFocusedWindow(), &focused_raw)) return abi.OMNI_ERR_PLATFORM;
    if (focused_raw == null) return abi.OMNI_ERR_PLATFORM;
    if (c.CFGetTypeID(focused_raw) != c.AXUIElementGetTypeID()) return abi.OMNI_ERR_PLATFORM;

    const element: AXElementRef = @ptrCast(focused_raw);
    const window_id = getWindowId(element) orelse return abi.OMNI_ERR_PLATFORM;
    out_window_id.* = window_id;
    return abi.OMNI_OK;
}

pub fn withWindowElementById(pid: i32, window_id: u32, callback: *const fn (AXElementRef, ?*anyopaque) i32, userdata: ?*anyopaque) i32 {
    const app = createApplication(pid);
    if (app == null) return abi.OMNI_ERR_PLATFORM;

    var windows_raw: c.CFTypeRef = null;
    defer releaseCF(windows_raw);

    if (!copyAttributeValue(app, axAttrWindows(), &windows_raw) or windows_raw == null) return abi.OMNI_ERR_PLATFORM;
    if (c.CFGetTypeID(windows_raw) != c.CFArrayGetTypeID()) return abi.OMNI_ERR_PLATFORM;

    const windows: c.CFArrayRef = @ptrCast(windows_raw);
    const count = c.CFArrayGetCount(windows);
    var idx: c.CFIndex = 0;
    while (idx < count) : (idx += 1) {
        const item = c.CFArrayGetValueAtIndex(windows, idx);
        if (item == null) continue;
        const element: AXElementRef = @ptrCast(@constCast(item));
        const maybe_id = getWindowId(element) orelse continue;
        if (maybe_id != window_id) continue;
        return callback(element, userdata);
    }

    return abi.OMNI_ERR_PLATFORM;
}

pub fn enumerateWindowsForApp(
    allocator: std.mem.Allocator,
    pid: i32,
    app_policy: i32,
    force_floating: bool,
    out_records: *std.ArrayListUnmanaged(abi.OmniAXWindowRecord),
) i32 {
    const app = createApplication(pid);
    if (app == null) return abi.OMNI_OK;

    var windows_raw: c.CFTypeRef = null;
    defer releaseCF(windows_raw);

    if (!copyAttributeValue(app, axAttrWindows(), &windows_raw) or windows_raw == null) return abi.OMNI_OK;
    if (c.CFGetTypeID(windows_raw) != c.CFArrayGetTypeID()) return abi.OMNI_OK;

    const windows: c.CFArrayRef = @ptrCast(windows_raw);
    const count = c.CFArrayGetCount(windows);
    var idx: c.CFIndex = 0;
    while (idx < count) : (idx += 1) {
        const item = c.CFArrayGetValueAtIndex(windows, idx);
        if (item == null) continue;

        const element: AXElementRef = @ptrCast(@constCast(item));
        const window_id = getWindowId(element) orelse continue;

        var role_raw: c.CFTypeRef = null;
        defer releaseCF(role_raw);
        if (!copyAttributeValue(element, axAttrRole(), &role_raw)) continue;
        if (!cfStringEquals(role_raw, "AXWindow")) continue;

        const window_type = classifyWindow(element, app_policy, force_floating);
        out_records.append(allocator, .{
            .pid = pid,
            .window_id = window_id,
            .window_type = window_type,
        }) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    return abi.OMNI_OK;
}

fn cachedAttr(slot: *c.CFStringRef, value: [*:0]const u8) c.CFStringRef {
    if (slot.* != null) return slot.*;
    slot.* = c.CFStringCreateWithCString(null, value, c.kCFStringEncodingUTF8);
    return slot.*;
}
