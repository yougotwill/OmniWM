const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const skylight = @import("skylight.zig");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("Carbon/Carbon.h");
    @cInclude("dlfcn.h");
});

pub const SLPSMode = u32;
pub const kCPSUserGenerated: SLPSMode = 0x200;

const SetFrontProcessWithOptionsFn = *const fn (*c.ProcessSerialNumber, u32, SLPSMode) callconv(.c) c.OSStatus;
const PostEventRecordToFn = *const fn (*c.ProcessSerialNumber, [*]u8) callconv(.c) c.OSStatus;
const GetProcessForPIDFn = *const fn (c.pid_t, *c.ProcessSerialNumber) callconv(.c) c.OSStatus;
const AXGetWindowFn = *const fn (c.AXUIElementRef, *c.CGWindowID) callconv(.c) c.AXError;

const application_services_path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";

const Shared = struct {
    capabilities: abi.OmniPrivateCapabilities = std.mem.zeroes(abi.OmniPrivateCapabilities),
    app_services_handle: ?*anyopaque = null,
    set_front_process_with_options: ?SetFrontProcessWithOptionsFn = null,
    post_event_record_to: ?PostEventRecordToFn = null,
    get_process_for_pid: ?GetProcessForPIDFn = null,
    ax_get_window: ?AXGetWindowFn = null,
};

var mutex = std.Thread.Mutex{};
var g_shared: Shared = .{};
var is_initialized = false;
var is_available = false;
var logged_capabilities = false;

pub fn shared() ?*Shared {
    mutex.lock();
    defer mutex.unlock();

    if (!is_initialized) {
        const loaded = loadShared();
        if (loaded) |value| {
            g_shared = value;
            is_available = true;
            if (!logged_capabilities) {
                logged_capabilities = true;
                std.log.info(
                    "private api capabilities: set_front={d} post_event={d} get_psn={d} ax_get_window={d}",
                    .{
                        value.capabilities.has_set_front_process_with_options,
                        value.capabilities.has_post_event_record_to,
                        value.capabilities.has_get_process_for_pid,
                        value.capabilities.has_ax_get_window,
                    },
                );
            }
        } else {
            is_available = false;
        }
        is_initialized = true;
    }

    if (!is_available) return null;
    return &g_shared;
}

fn loadShared() ?Shared {
    var value = Shared{};

    value.app_services_handle = c.dlopen(application_services_path, c.RTLD_LAZY);

    if (skylight.shared()) |sky| {
        value.set_front_process_with_options = resolveOptional(SetFrontProcessWithOptionsFn, sky.skylight_handle, "_SLPSSetFrontProcessWithOptions");
        value.post_event_record_to = resolveOptional(PostEventRecordToFn, sky.skylight_handle, "SLPSPostEventRecordTo");
    }

    if (value.app_services_handle) |handle| {
        value.ax_get_window = resolveOptional(AXGetWindowFn, handle, "_AXUIElementGetWindow");
        value.get_process_for_pid = resolveOptional(GetProcessForPIDFn, handle, "GetProcessForPID");
    }

    value.capabilities = .{
        .has_set_front_process_with_options = flag(value.set_front_process_with_options != null),
        .has_post_event_record_to = flag(value.post_event_record_to != null),
        .has_get_process_for_pid = flag(value.get_process_for_pid != null),
        .has_ax_get_window = flag(value.ax_get_window != null),
    };

    return value;
}

fn flag(value: bool) u8 {
    return if (value) 1 else 0;
}

fn resolveOptional(comptime T: type, handle: ?*anyopaque, symbol: [*:0]const u8) ?T {
    const raw_symbol = c.dlsym(handle, symbol);
    if (raw_symbol == null) return null;
    return @ptrCast(@alignCast(raw_symbol));
}

pub fn getCapabilities(out_capabilities: [*c]abi.OmniPrivateCapabilities) i32 {
    if (out_capabilities == null) return abi.OMNI_ERR_INVALID_ARGS;
    const private_shared = shared() orelse {
        out_capabilities[0] = std.mem.zeroes(abi.OmniPrivateCapabilities);
        return abi.OMNI_ERR_PLATFORM;
    };
    out_capabilities[0] = private_shared.capabilities;
    return abi.OMNI_OK;
}

pub fn getAXWindowId(ax_element: ?*anyopaque, out_window_id: [*c]u32) i32 {
    if (ax_element == null or out_window_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    const private_shared = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const ax_get_window = private_shared.ax_get_window orelse return abi.OMNI_ERR_PLATFORM;

    var window_id: c.CGWindowID = 0;
    const ax_element_ref: c.AXUIElementRef = @ptrCast(ax_element);
    const rc = ax_get_window(ax_element_ref, &window_id);
    if (rc != c.kAXErrorSuccess) return abi.OMNI_ERR_PLATFORM;

    out_window_id[0] = @intCast(window_id);
    return abi.OMNI_OK;
}

fn postKeyWindowEvents(post_event_record_to: PostEventRecordToFn, psn: *c.ProcessSerialNumber, window_id: u32) void {
    var event_bytes = [_]u8{0} ** 0xF8;
    event_bytes[0x04] = 0xF8;
    event_bytes[0x08] = 0x01;
    event_bytes[0x3A] = 0x10;

    const wid = window_id;
    event_bytes[0x3C] = @truncate(wid & 0xff);
    event_bytes[0x3D] = @truncate((wid >> 8) & 0xff);
    event_bytes[0x3E] = @truncate((wid >> 16) & 0xff);
    event_bytes[0x3F] = @truncate((wid >> 24) & 0xff);

    var i: usize = 0x20;
    while (i < 0x30) : (i += 1) {
        event_bytes[i] = 0xff;
    }

    _ = post_event_record_to(psn, &event_bytes);
    event_bytes[0x08] = 0x02;
    _ = post_event_record_to(psn, &event_bytes);
}

pub fn focusWindow(pid: i32, window_id: u32) i32 {
    const private_shared = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const set_front_process_with_options = private_shared.set_front_process_with_options orelse return abi.OMNI_ERR_PLATFORM;
    const post_event_record_to = private_shared.post_event_record_to orelse return abi.OMNI_ERR_PLATFORM;
    const get_process_for_pid = private_shared.get_process_for_pid orelse return abi.OMNI_ERR_PLATFORM;

    var psn = std.mem.zeroes(c.ProcessSerialNumber);
    if (get_process_for_pid(@intCast(pid), &psn) != c.noErr) return abi.OMNI_ERR_PLATFORM;

    _ = set_front_process_with_options(&psn, window_id, kCPSUserGenerated);
    postKeyWindowEvents(post_event_record_to, &psn, window_id);
    return abi.OMNI_OK;
}
