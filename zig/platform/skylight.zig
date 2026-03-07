const std = @import("std");
const abi = @import("../omni/abi_types.zig");

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("dlfcn.h");
});

pub const CFTypeRef = ?*anyopaque;
pub const CGContextRef = ?*c.CGContext;

pub const ConnectionNotifyCallback = *const fn (
    u32,
    ?*anyopaque,
    usize,
    ?*anyopaque,
    i32,
) callconv(.c) void;

pub const NotifyCallback = *const fn (
    u32,
    ?*anyopaque,
    usize,
    i32,
) callconv(.c) void;

pub const CFReleaseFn = *const fn (CFTypeRef) callconv(.c) void;
pub const MainConnectionIDFn = *const fn () callconv(.c) i32;
pub const WindowQueryWindowsFn = *const fn (i32, c.CFArrayRef, u32) callconv(.c) CFTypeRef;
pub const WindowQueryResultCopyWindowsFn = *const fn (CFTypeRef) callconv(.c) CFTypeRef;
pub const WindowIteratorGetCountFn = *const fn (CFTypeRef) callconv(.c) i32;
pub const WindowIteratorAdvanceFn = *const fn (CFTypeRef) callconv(.c) bool;
pub const WindowIteratorGetBoundsFn = *const fn (CFTypeRef) callconv(.c) c.CGRect;
pub const WindowIteratorGetWindowIDFn = *const fn (CFTypeRef) callconv(.c) u32;
pub const WindowIteratorGetPIDFn = *const fn (CFTypeRef) callconv(.c) i32;
pub const WindowIteratorGetLevelFn = *const fn (CFTypeRef) callconv(.c) i32;
pub const WindowIteratorGetTagsFn = *const fn (CFTypeRef) callconv(.c) u64;
pub const WindowIteratorGetAttributesFn = *const fn (CFTypeRef) callconv(.c) u32;
pub const WindowIteratorGetParentIDFn = *const fn (CFTypeRef) callconv(.c) u32;
pub const TransactionCreateFn = *const fn (i32) callconv(.c) CFTypeRef;
pub const TransactionCommitFn = *const fn (CFTypeRef, i32) callconv(.c) i32;
pub const TransactionOrderWindowFn = *const fn (CFTypeRef, u32, i32, u32) callconv(.c) void;
pub const TransactionMoveWindowWithGroupFn = *const fn (CFTypeRef, u32, c.CGPoint) callconv(.c) i32;
pub const TransactionSetWindowLevelFn = *const fn (CFTypeRef, u32, i32) callconv(.c) i32;
pub const MoveWindowFn = *const fn (i32, u32, *c.CGPoint) callconv(.c) i32;
pub const GetWindowBoundsFn = *const fn (i32, u32, *c.CGRect) callconv(.c) i32;
pub const DisableUpdateFn = *const fn (i32) callconv(.c) void;
pub const ReenableUpdateFn = *const fn (i32) callconv(.c) void;
pub const NewWindowFn = *const fn (i32, i32, f32, f32, CFTypeRef, *u32) callconv(.c) i32;
pub const ReleaseWindowFn = *const fn (i32, u32) callconv(.c) i32;
pub const WindowContextCreateFn = *const fn (i32, u32, ?*anyopaque) callconv(.c) CGContextRef;
pub const SetWindowShapeFn = *const fn (i32, u32, f32, f32, CFTypeRef) callconv(.c) i32;
pub const SetWindowResolutionFn = *const fn (i32, u32, f32) callconv(.c) i32;
pub const SetWindowOpacityFn = *const fn (i32, u32, i32) callconv(.c) i32;
pub const SetWindowTagsFn = *const fn (i32, u32, *u64, i32) callconv(.c) i32;
pub const FlushWindowContentRegionFn = *const fn (i32, u32, CFTypeRef) callconv(.c) i32;
pub const NewRegionWithRectFn = *const fn (*const c.CGRect, *CFTypeRef) callconv(.c) i32;
pub const RegisterConnectionNotifyProcFn = *const fn (i32, ConnectionNotifyCallback, u32, ?*anyopaque) callconv(.c) i32;
pub const UnregisterConnectionNotifyProcFn = *const fn (i32, ConnectionNotifyCallback, u32) callconv(.c) i32;
pub const RequestNotificationsForWindowsFn = *const fn (i32, [*]const u32, i32) callconv(.c) i32;
pub const RegisterNotifyProcFn = *const fn (NotifyCallback, u32, ?*anyopaque) callconv(.c) i32;
pub const UnregisterNotifyProcFn = *const fn (NotifyCallback, u32, ?*anyopaque) callconv(.c) i32;

pub const Shared = struct {
    skylight_handle: ?*anyopaque = null,
    corefoundation_handle: ?*anyopaque = null,
    capabilities: abi.OmniSkyLightCapabilities = std.mem.zeroes(abi.OmniSkyLightCapabilities),

    cf_release: ?CFReleaseFn = null,
    main_connection_id: ?MainConnectionIDFn = null,

    window_query_windows: ?WindowQueryWindowsFn = null,
    window_query_result_copy_windows: ?WindowQueryResultCopyWindowsFn = null,
    window_iterator_get_count: ?WindowIteratorGetCountFn = null,
    window_iterator_advance: ?WindowIteratorAdvanceFn = null,
    window_iterator_get_bounds: ?WindowIteratorGetBoundsFn = null,
    window_iterator_get_window_id: ?WindowIteratorGetWindowIDFn = null,
    window_iterator_get_pid: ?WindowIteratorGetPIDFn = null,
    window_iterator_get_level: ?WindowIteratorGetLevelFn = null,
    window_iterator_get_tags: ?WindowIteratorGetTagsFn = null,
    window_iterator_get_attributes: ?WindowIteratorGetAttributesFn = null,
    window_iterator_get_parent_id: ?WindowIteratorGetParentIDFn = null,

    transaction_create: ?TransactionCreateFn = null,
    transaction_commit: ?TransactionCommitFn = null,
    transaction_order_window: ?TransactionOrderWindowFn = null,
    transaction_move_window_with_group: ?TransactionMoveWindowWithGroupFn = null,
    transaction_set_window_level: ?TransactionSetWindowLevelFn = null,
    move_window: ?MoveWindowFn = null,
    get_window_bounds: ?GetWindowBoundsFn = null,

    disable_update: ?DisableUpdateFn = null,
    reenable_update: ?ReenableUpdateFn = null,
    new_window: ?NewWindowFn = null,
    release_window: ?ReleaseWindowFn = null,
    window_context_create: ?WindowContextCreateFn = null,
    set_window_shape: ?SetWindowShapeFn = null,
    set_window_resolution: ?SetWindowResolutionFn = null,
    set_window_opacity: ?SetWindowOpacityFn = null,
    set_window_tags: ?SetWindowTagsFn = null,
    flush_window_content_region: ?FlushWindowContentRegionFn = null,
    new_region_with_rect: ?NewRegionWithRectFn = null,

    register_connection_notify_proc: ?RegisterConnectionNotifyProcFn = null,
    unregister_connection_notify_proc: ?UnregisterConnectionNotifyProcFn = null,
    request_notifications_for_windows: ?RequestNotificationsForWindowsFn = null,
    register_notify_proc: ?RegisterNotifyProcFn = null,
    unregister_notify_proc: ?UnregisterNotifyProcFn = null,
};

const skylight_path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight";
const corefoundation_path = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";

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
                    "skylight capabilities: query={d} notify={d} tx_move={d} move={d} bounds={d}",
                    .{
                        value.capabilities.has_window_query_windows,
                        value.capabilities.has_register_connection_notify_proc,
                        value.capabilities.has_transaction_move_window_with_group,
                        value.capabilities.has_move_window,
                        value.capabilities.has_get_window_bounds,
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
    const skylight_handle = c.dlopen(skylight_path, c.RTLD_LAZY);
    if (skylight_handle == null) return null;

    const corefoundation_handle = c.dlopen(corefoundation_path, c.RTLD_LAZY);
    if (corefoundation_handle == null) {
        _ = c.dlclose(skylight_handle);
        return null;
    }

    var value = Shared{
        .skylight_handle = skylight_handle,
        .corefoundation_handle = corefoundation_handle,
    };

    value.cf_release = resolveOptional(CFReleaseFn, corefoundation_handle, "CFRelease");
    value.main_connection_id = resolveOptional(MainConnectionIDFn, skylight_handle, "SLSMainConnectionID");

    value.window_query_windows = resolveOptional(WindowQueryWindowsFn, skylight_handle, "SLSWindowQueryWindows");
    value.window_query_result_copy_windows = resolveOptional(WindowQueryResultCopyWindowsFn, skylight_handle, "SLSWindowQueryResultCopyWindows");
    value.window_iterator_get_count = resolveOptional(WindowIteratorGetCountFn, skylight_handle, "SLSWindowIteratorGetCount");
    value.window_iterator_advance = resolveOptional(WindowIteratorAdvanceFn, skylight_handle, "SLSWindowIteratorAdvance");
    value.window_iterator_get_bounds = resolveOptional(WindowIteratorGetBoundsFn, skylight_handle, "SLSWindowIteratorGetBounds");
    value.window_iterator_get_window_id = resolveOptional(WindowIteratorGetWindowIDFn, skylight_handle, "SLSWindowIteratorGetWindowID");
    value.window_iterator_get_pid = resolveOptional(WindowIteratorGetPIDFn, skylight_handle, "SLSWindowIteratorGetPID");
    value.window_iterator_get_level = resolveOptional(WindowIteratorGetLevelFn, skylight_handle, "SLSWindowIteratorGetLevel");
    value.window_iterator_get_tags = resolveOptional(WindowIteratorGetTagsFn, skylight_handle, "SLSWindowIteratorGetTags");
    value.window_iterator_get_attributes = resolveOptional(WindowIteratorGetAttributesFn, skylight_handle, "SLSWindowIteratorGetAttributes");
    value.window_iterator_get_parent_id = resolveOptional(WindowIteratorGetParentIDFn, skylight_handle, "SLSWindowIteratorGetParentID");

    value.transaction_create = resolveOptional(TransactionCreateFn, skylight_handle, "SLSTransactionCreate");
    value.transaction_commit = resolveOptional(TransactionCommitFn, skylight_handle, "SLSTransactionCommit");
    value.transaction_order_window = resolveOptional(TransactionOrderWindowFn, skylight_handle, "SLSTransactionOrderWindow");
    value.transaction_move_window_with_group = resolveOptional(TransactionMoveWindowWithGroupFn, skylight_handle, "SLSTransactionMoveWindowWithGroup");
    value.transaction_set_window_level = resolveOptional(TransactionSetWindowLevelFn, skylight_handle, "SLSTransactionSetWindowLevel");
    value.move_window = resolveOptional(MoveWindowFn, skylight_handle, "SLSMoveWindow");
    value.get_window_bounds = resolveOptional(GetWindowBoundsFn, skylight_handle, "SLSGetWindowBounds");

    value.disable_update = resolveOptional(DisableUpdateFn, skylight_handle, "SLSDisableUpdate");
    value.reenable_update = resolveOptional(ReenableUpdateFn, skylight_handle, "SLSReenableUpdate");
    value.new_window = resolveOptional(NewWindowFn, skylight_handle, "SLSNewWindow");
    value.release_window = resolveOptional(ReleaseWindowFn, skylight_handle, "SLSReleaseWindow");
    value.window_context_create = resolveOptional(WindowContextCreateFn, skylight_handle, "SLWindowContextCreate");
    value.set_window_shape = resolveOptional(SetWindowShapeFn, skylight_handle, "SLSSetWindowShape");
    value.set_window_resolution = resolveOptional(SetWindowResolutionFn, skylight_handle, "SLSSetWindowResolution");
    value.set_window_opacity = resolveOptional(SetWindowOpacityFn, skylight_handle, "SLSSetWindowOpacity");
    value.set_window_tags = resolveOptional(SetWindowTagsFn, skylight_handle, "SLSSetWindowTags");
    value.flush_window_content_region = resolveOptional(FlushWindowContentRegionFn, skylight_handle, "SLSFlushWindowContentRegion");
    value.new_region_with_rect = resolveOptional(NewRegionWithRectFn, skylight_handle, "CGSNewRegionWithRect");

    value.register_connection_notify_proc = resolveOptional(RegisterConnectionNotifyProcFn, skylight_handle, "SLSRegisterConnectionNotifyProc");
    value.unregister_connection_notify_proc = resolveOptional(UnregisterConnectionNotifyProcFn, skylight_handle, "SLSUnregisterConnectionNotifyProc") orelse
        resolveOptional(UnregisterConnectionNotifyProcFn, skylight_handle, "SLSRemoveConnectionNotifyProc");
    value.request_notifications_for_windows = resolveOptional(RequestNotificationsForWindowsFn, skylight_handle, "SLSRequestNotificationsForWindows");
    value.register_notify_proc = resolveOptional(RegisterNotifyProcFn, skylight_handle, "SLSRegisterNotifyProc");
    value.unregister_notify_proc = resolveOptional(UnregisterNotifyProcFn, skylight_handle, "SLSUnregisterNotifyProc") orelse
        resolveOptional(UnregisterNotifyProcFn, skylight_handle, "SLSRemoveNotifyProc");

    value.capabilities = .{
        .has_main_connection_id = flag(value.main_connection_id != null),
        .has_window_query_windows = flag(value.window_query_windows != null),
        .has_window_query_result_copy_windows = flag(value.window_query_result_copy_windows != null),
        .has_window_iterator_advance = flag(value.window_iterator_advance != null),
        .has_window_iterator_get_bounds = flag(value.window_iterator_get_bounds != null),
        .has_window_iterator_get_window_id = flag(value.window_iterator_get_window_id != null),
        .has_window_iterator_get_pid = flag(value.window_iterator_get_pid != null),
        .has_window_iterator_get_level = flag(value.window_iterator_get_level != null),
        .has_window_iterator_get_tags = flag(value.window_iterator_get_tags != null),
        .has_window_iterator_get_attributes = flag(value.window_iterator_get_attributes != null),
        .has_window_iterator_get_parent_id = flag(value.window_iterator_get_parent_id != null),
        .has_transaction_create = flag(value.transaction_create != null),
        .has_transaction_commit = flag(value.transaction_commit != null),
        .has_transaction_order_window = flag(value.transaction_order_window != null),
        .has_transaction_move_window_with_group = flag(value.transaction_move_window_with_group != null),
        .has_transaction_set_window_level = flag(value.transaction_set_window_level != null),
        .has_move_window = flag(value.move_window != null),
        .has_get_window_bounds = flag(value.get_window_bounds != null),
        .has_disable_update = flag(value.disable_update != null),
        .has_reenable_update = flag(value.reenable_update != null),
        .has_new_window = flag(value.new_window != null),
        .has_release_window = flag(value.release_window != null),
        .has_window_context_create = flag(value.window_context_create != null),
        .has_set_window_shape = flag(value.set_window_shape != null),
        .has_set_window_resolution = flag(value.set_window_resolution != null),
        .has_set_window_opacity = flag(value.set_window_opacity != null),
        .has_set_window_tags = flag(value.set_window_tags != null),
        .has_flush_window_content_region = flag(value.flush_window_content_region != null),
        .has_new_region_with_rect = flag(value.new_region_with_rect != null),
        .has_register_connection_notify_proc = flag(value.register_connection_notify_proc != null),
        .has_unregister_connection_notify_proc = flag(value.unregister_connection_notify_proc != null),
        .has_request_notifications_for_windows = flag(value.request_notifications_for_windows != null),
        .has_register_notify_proc = flag(value.register_notify_proc != null),
        .has_unregister_notify_proc = flag(value.unregister_notify_proc != null),
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

fn releaseCf(shared_api: *const Shared, value: CFTypeRef) void {
    if (value == null) return;
    if (shared_api.cf_release) |cf_release| {
        cf_release(value);
        return;
    }
    c.CFRelease(@ptrCast(value));
}

pub fn mainConnectionId() i32 {
    const shared_api = shared() orelse return 0;
    const main_connection_id = shared_api.main_connection_id orelse return 0;
    return main_connection_id();
}

pub fn getCapabilities(out_capabilities: [*c]abi.OmniSkyLightCapabilities) i32 {
    if (out_capabilities == null) return abi.OMNI_ERR_INVALID_ARGS;
    const shared_api = shared() orelse {
        out_capabilities[0] = std.mem.zeroes(abi.OmniSkyLightCapabilities);
        return abi.OMNI_ERR_PLATFORM;
    };
    out_capabilities[0] = shared_api.capabilities;
    return abi.OMNI_OK;
}

pub fn orderWindow(window_id: u32, relative_to_window_id: u32, order: i32) i32 {
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;
    const transaction_create = shared_api.transaction_create orelse return abi.OMNI_ERR_PLATFORM;
    const transaction_order_window = shared_api.transaction_order_window orelse return abi.OMNI_ERR_PLATFORM;
    const transaction_commit = shared_api.transaction_commit orelse return abi.OMNI_ERR_PLATFORM;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;

    const transaction = transaction_create(cid) orelse return abi.OMNI_ERR_PLATFORM;
    defer releaseCf(shared_api, transaction);

    transaction_order_window(transaction, window_id, order, relative_to_window_id);
    if (transaction_commit(transaction, 0) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn moveWindow(window_id: u32, origin_x: f64, origin_y: f64) i32 {
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;

    if (shared_api.transaction_create) |transaction_create| {
        if (shared_api.transaction_move_window_with_group) |transaction_move_window_with_group| {
            const transaction = transaction_create(cid) orelse return abi.OMNI_ERR_PLATFORM;
            defer releaseCf(shared_api, transaction);
            if (transaction_move_window_with_group(transaction, window_id, c.CGPointMake(origin_x, origin_y)) == 0) {
                if (shared_api.transaction_commit) |transaction_commit| {
                    if (transaction_commit(transaction, 0) == 0) return abi.OMNI_OK;
                }
            }
        }
    }

    const move_window = shared_api.move_window orelse return abi.OMNI_ERR_PLATFORM;
    var point = c.CGPointMake(origin_x, origin_y);
    if (move_window(cid, window_id, &point) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn batchMoveWindows(
    requests: [*c]const abi.OmniSkyLightMoveRequest,
    request_count: usize,
) i32 {
    if (request_count == 0) return abi.OMNI_OK;
    if (requests == null) return abi.OMNI_ERR_INVALID_ARGS;

    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;
    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;

    if (shared_api.transaction_create) |transaction_create| {
        if (shared_api.transaction_move_window_with_group) |transaction_move_window_with_group| {
            const transaction = transaction_create(cid) orelse return abi.OMNI_ERR_PLATFORM;
            defer releaseCf(shared_api, transaction);
            for (requests[0..request_count]) |request| {
                _ = transaction_move_window_with_group(transaction, request.window_id, c.CGPointMake(request.origin_x, request.origin_y));
            }
            if (shared_api.transaction_commit) |transaction_commit| {
                if (transaction_commit(transaction, 0) == 0) return abi.OMNI_OK;
            }
        }
    }

    for (requests[0..request_count]) |request| {
        const rc = moveWindow(request.window_id, request.origin_x, request.origin_y);
        if (rc != abi.OMNI_OK) return rc;
    }
    return abi.OMNI_OK;
}

pub fn getWindowBounds(window_id: u32, out_rect: [*c]abi.OmniBorderRect) i32 {
    if (out_rect == null) return abi.OMNI_ERR_INVALID_ARGS;
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;
    const get_window_bounds = shared_api.get_window_bounds orelse return abi.OMNI_ERR_PLATFORM;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;

    var rect = c.CGRectZero;
    if (get_window_bounds(cid, window_id, &rect) != 0) return abi.OMNI_ERR_PLATFORM;
    out_rect[0] = .{
        .x = rect.origin.x,
        .y = rect.origin.y,
        .width = rect.size.width,
        .height = rect.size.height,
    };
    return abi.OMNI_OK;
}

fn requireWindowQueryFunctions(shared_api: *const Shared) bool {
    return shared_api.main_connection_id != null and
        shared_api.window_query_windows != null and
        shared_api.window_query_result_copy_windows != null and
        shared_api.window_iterator_advance != null and
        shared_api.window_iterator_get_bounds != null and
        shared_api.window_iterator_get_window_id != null and
        shared_api.window_iterator_get_pid != null and
        shared_api.window_iterator_get_level != null and
        shared_api.window_iterator_get_tags != null and
        shared_api.window_iterator_get_attributes != null and
        shared_api.window_iterator_get_parent_id != null;
}

fn createEmptyArray() ?c.CFArrayRef {
    return c.CFArrayCreate(null, null, 0, &c.kCFTypeArrayCallBacks);
}

pub fn queryVisibleWindows(
    out_windows: [*c]abi.OmniSkyLightWindowInfo,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    if (out_written == null) return abi.OMNI_ERR_INVALID_ARGS;
    out_written[0] = 0;

    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    if (!requireWindowQueryFunctions(shared_api)) return abi.OMNI_ERR_PLATFORM;

    if (out_capacity > 0 and out_windows == null) return abi.OMNI_ERR_INVALID_ARGS;

    const main_connection_id = shared_api.main_connection_id.?;
    const window_query_windows = shared_api.window_query_windows.?;
    const window_query_result_copy_windows = shared_api.window_query_result_copy_windows.?;
    const window_iterator_advance = shared_api.window_iterator_advance.?;
    const window_iterator_get_bounds = shared_api.window_iterator_get_bounds.?;
    const window_iterator_get_window_id = shared_api.window_iterator_get_window_id.?;
    const window_iterator_get_pid = shared_api.window_iterator_get_pid.?;
    const window_iterator_get_level = shared_api.window_iterator_get_level.?;
    const window_iterator_get_tags = shared_api.window_iterator_get_tags.?;
    const window_iterator_get_attributes = shared_api.window_iterator_get_attributes.?;
    const window_iterator_get_parent_id = shared_api.window_iterator_get_parent_id.?;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;

    const empty_array = createEmptyArray() orelse return abi.OMNI_ERR_PLATFORM;
    defer releaseCf(shared_api, @constCast(@ptrCast(empty_array)));

    const query = window_query_windows(cid, empty_array, 0) orelse return abi.OMNI_ERR_PLATFORM;
    defer releaseCf(shared_api, query);

    const iterator = window_query_result_copy_windows(query) orelse return abi.OMNI_ERR_PLATFORM;
    defer releaseCf(shared_api, iterator);

    var written: usize = 0;
    while (window_iterator_advance(iterator)) {
        if (written >= out_capacity) {
            written += 1;
            continue;
        }

        const bounds = window_iterator_get_bounds(iterator);
        out_windows[written] = .{
            .id = window_iterator_get_window_id(iterator),
            .pid = window_iterator_get_pid(iterator),
            .level = window_iterator_get_level(iterator),
            .frame = .{
                .x = bounds.origin.x,
                .y = bounds.origin.y,
                .width = bounds.size.width,
                .height = bounds.size.height,
            },
            .tags = window_iterator_get_tags(iterator),
            .attributes = window_iterator_get_attributes(iterator),
            .parent_id = window_iterator_get_parent_id(iterator),
        };
        written += 1;
    }

    out_written[0] = written;
    return abi.OMNI_OK;
}

pub fn queryWindowInfo(window_id: u32, out_info: [*c]abi.OmniSkyLightWindowInfo) i32 {
    if (out_info == null) return abi.OMNI_ERR_INVALID_ARGS;

    var total: usize = 0;
    var rc = queryVisibleWindows(null, 0, &total);
    if (rc != abi.OMNI_OK) return rc;
    if (total == 0) return abi.OMNI_ERR_PLATFORM;

    const buffer = std.heap.c_allocator.alloc(abi.OmniSkyLightWindowInfo, total) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    defer std.heap.c_allocator.free(buffer);

    var written: usize = 0;
    rc = queryVisibleWindows(buffer.ptr, buffer.len, &written);
    if (rc != abi.OMNI_OK) return rc;

    const count = @min(written, buffer.len);
    for (buffer[0..count]) |item| {
        if (item.id == window_id) {
            out_info[0] = item;
            return abi.OMNI_OK;
        }
    }
    return abi.OMNI_ERR_PLATFORM;
}

pub fn subscribeWindowNotifications(window_ids: [*c]const u32, window_count: usize) i32 {
    if (window_count == 0) return abi.OMNI_OK;
    if (window_ids == null) return abi.OMNI_ERR_INVALID_ARGS;

    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;
    const request_notifications_for_windows = shared_api.request_notifications_for_windows orelse return abi.OMNI_ERR_PLATFORM;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;

    if (request_notifications_for_windows(cid, window_ids, @intCast(window_count)) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn registerConnectionNotify(callback: ConnectionNotifyCallback, event_type: u32, context: ?*anyopaque) i32 {
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;
    const register_connection_notify_proc = shared_api.register_connection_notify_proc orelse return abi.OMNI_ERR_PLATFORM;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;
    if (register_connection_notify_proc(cid, callback, event_type, context) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn unregisterConnectionNotify(callback: ConnectionNotifyCallback, event_type: u32) i32 {
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const main_connection_id = shared_api.main_connection_id orelse return abi.OMNI_ERR_PLATFORM;
    const unregister_connection_notify_proc = shared_api.unregister_connection_notify_proc orelse return abi.OMNI_ERR_PLATFORM;

    const cid = main_connection_id();
    if (cid == 0) return abi.OMNI_ERR_PLATFORM;
    if (unregister_connection_notify_proc(cid, callback, event_type) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn registerNotifyProc(callback: NotifyCallback, event_type: u32, context: ?*anyopaque) i32 {
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const register_notify_proc = shared_api.register_notify_proc orelse return abi.OMNI_ERR_PLATFORM;
    if (register_notify_proc(callback, event_type, context) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}

pub fn unregisterNotifyProc(callback: NotifyCallback, event_type: u32, context: ?*anyopaque) i32 {
    const shared_api = shared() orelse return abi.OMNI_ERR_PLATFORM;
    const unregister_notify_proc = shared_api.unregister_notify_proc orelse return abi.OMNI_ERR_PLATFORM;
    if (unregister_notify_proc(callback, event_type, context) != 0) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}
