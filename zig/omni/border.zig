const std = @import("std");
const abi = @import("abi_types.zig");
const skylight = @import("../platform/skylight.zig");
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("CoreGraphics/CoreGraphics.h");
});
const Allocator = std.mem.Allocator;
const CFTypeRef = ?*anyopaque;
const CGContextRef = ?*c.CGContext;
const BorderConstants = struct {
    const padding: f64 = 8.0;
    const corner_radius: f64 = 9.0;
    const approximate_tolerance: f64 = 0.5;
    const max_display_count: usize = 32;
    const window_kind: i32 = 2;
    const sentinel_coordinate: f32 = -9999.0;
    const window_tags: u64 = (@as(u64, 1) << 1) | (@as(u64, 1) << 9);
    const window_level: i32 = 3;
    const order_below: i32 = -1;
    const order_out: i32 = 0;
};
const BorderPresentRequest = struct {
    local_frame: abi.OmniBorderRect,
    drawing_bounds: abi.OmniBorderRect,
    origin_x: f64,
    origin_y: f64,
    target_window_id: u32,
    backing_scale: f64,
};
pub const BorderRuntimeCreateStatus = enum(u8) {
    success = 0,
    out_of_memory,
    missing_skylight,
    missing_symbol,
    connection_unavailable,
    missing_move_primitive,
};
var last_create_status: BorderRuntimeCreateStatus = .success;
const BorderMacOSApi = struct {
    const CFReleaseFn = *const fn (CFTypeRef) callconv(.c) void;
    const MainConnectionIDFn = *const fn () callconv(.c) i32;
    const TransactionCreateFn = *const fn (i32) callconv(.c) CFTypeRef;
    const TransactionCommitFn = *const fn (CFTypeRef, i32) callconv(.c) i32;
    const TransactionOrderWindowFn = *const fn (CFTypeRef, u32, i32, u32) callconv(.c) void;
    const TransactionMoveWindowWithGroupFn = *const fn (CFTypeRef, u32, c.CGPoint) callconv(.c) i32;
    const TransactionSetWindowLevelFn = *const fn (CFTypeRef, u32, i32) callconv(.c) i32;
    const MoveWindowFn = *const fn (i32, u32, *c.CGPoint) callconv(.c) i32;
    const DisableUpdateFn = *const fn (i32) callconv(.c) void;
    const ReenableUpdateFn = *const fn (i32) callconv(.c) void;
    const NewWindowFn = *const fn (i32, i32, f32, f32, CFTypeRef, *u32) callconv(.c) i32;
    const ReleaseWindowFn = *const fn (i32, u32) callconv(.c) i32;
    const WindowContextCreateFn = *const fn (i32, u32, ?*anyopaque) callconv(.c) CGContextRef;
    const SetWindowShapeFn = *const fn (i32, u32, f32, f32, CFTypeRef) callconv(.c) i32;
    const SetWindowResolutionFn = *const fn (i32, u32, f32) callconv(.c) i32;
    const SetWindowOpacityFn = *const fn (i32, u32, i32) callconv(.c) i32;
    const SetWindowTagsFn = *const fn (i32, u32, *u64, i32) callconv(.c) i32;
    const FlushWindowContentRegionFn = *const fn (i32, u32, CFTypeRef) callconv(.c) i32;
    const NewRegionWithRectFn = *const fn (*const c.CGRect, *CFTypeRef) callconv(.c) i32;
    shared: *skylight.Shared,
    cf_release: CFReleaseFn,
    main_connection_id: MainConnectionIDFn,
    transaction_create: TransactionCreateFn,
    transaction_commit: TransactionCommitFn,
    transaction_order_window: TransactionOrderWindowFn,
    transaction_move_window_with_group: ?TransactionMoveWindowWithGroupFn,
    transaction_set_window_level: ?TransactionSetWindowLevelFn,
    move_window: ?MoveWindowFn,
    disable_update: DisableUpdateFn,
    reenable_update: ReenableUpdateFn,
    new_window: NewWindowFn,
    release_window: ReleaseWindowFn,
    window_context_create: WindowContextCreateFn,
    set_window_shape: SetWindowShapeFn,
    set_window_resolution: ?SetWindowResolutionFn,
    set_window_opacity: ?SetWindowOpacityFn,
    set_window_tags: ?SetWindowTagsFn,
    flush_window_content_region: ?FlushWindowContentRegionFn,
    new_region_with_rect: NewRegionWithRectFn,
    fn init() !BorderMacOSApi {
        const shared_api = skylight.shared() orelse return error.MissingSkyLight;
        return .{
            .shared = shared_api,
            .cf_release = @ptrCast(shared_api.cf_release orelse return error.MissingSymbol),
            .main_connection_id = @ptrCast(shared_api.main_connection_id orelse return error.MissingSymbol),
            .transaction_create = @ptrCast(shared_api.transaction_create orelse return error.MissingSymbol),
            .transaction_commit = @ptrCast(shared_api.transaction_commit orelse return error.MissingSymbol),
            .transaction_order_window = @ptrCast(shared_api.transaction_order_window orelse return error.MissingSymbol),
            .transaction_move_window_with_group = if (shared_api.transaction_move_window_with_group) |callback| @ptrCast(callback) else null,
            .transaction_set_window_level = if (shared_api.transaction_set_window_level) |callback| @ptrCast(callback) else null,
            .move_window = if (shared_api.move_window) |callback| @ptrCast(callback) else null,
            .disable_update = @ptrCast(shared_api.disable_update orelse return error.MissingSymbol),
            .reenable_update = @ptrCast(shared_api.reenable_update orelse return error.MissingSymbol),
            .new_window = @ptrCast(shared_api.new_window orelse return error.MissingSymbol),
            .release_window = @ptrCast(shared_api.release_window orelse return error.MissingSymbol),
            .window_context_create = @ptrCast(shared_api.window_context_create orelse return error.MissingSymbol),
            .set_window_shape = @ptrCast(shared_api.set_window_shape orelse return error.MissingSymbol),
            .set_window_resolution = if (shared_api.set_window_resolution) |callback| @ptrCast(callback) else null,
            .set_window_opacity = if (shared_api.set_window_opacity) |callback| @ptrCast(callback) else null,
            .set_window_tags = if (shared_api.set_window_tags) |callback| @ptrCast(callback) else null,
            .flush_window_content_region = if (shared_api.flush_window_content_region) |callback| @ptrCast(callback) else null,
            .new_region_with_rect = @ptrCast(shared_api.new_region_with_rect orelse return error.MissingSymbol),
        };
    }
    fn deinit(self: *BorderMacOSApi) void {
        _ = self;
    }
    fn connectionId(self: BorderMacOSApi) i32 {
        return self.main_connection_id();
    }
    fn createRegion(self: BorderMacOSApi, rect: abi.OmniBorderRect) CFTypeRef {
        var cg_rect = makeCGRect(rect);
        var region: CFTypeRef = null;
        if (self.new_region_with_rect(&cg_rect, &region) != 0) {
            return null;
        }
        return region;
    }
    fn createBorderWindow(self: BorderMacOSApi, frame: abi.OmniBorderRect) u32 {
        const region = self.createRegion(frame) orelse return 0;
        defer self.cf_release(region);
        const cid = self.connectionId();
        if (cid <= 0) return 0;
        var wid: u32 = 0;
        _ = self.new_window(
            cid,
            BorderConstants.window_kind,
            BorderConstants.sentinel_coordinate,
            BorderConstants.sentinel_coordinate,
            region,
            &wid,
        );
        return wid;
    }
    fn releaseBorderWindow(self: BorderMacOSApi, wid: u32) void {
        if (wid == 0) return;
        const cid = self.connectionId();
        if (cid <= 0) return;
        _ = self.release_window(cid, wid);
    }
    fn createWindowContext(self: BorderMacOSApi, wid: u32) CGContextRef {
        const cid = self.connectionId();
        if (cid <= 0) return null;
        return self.window_context_create(cid, wid, null);
    }
    fn setWindowShape(self: BorderMacOSApi, wid: u32, frame: abi.OmniBorderRect) i32 {
        const region = self.createRegion(frame) orelse return abi.OMNI_ERR_PLATFORM;
        defer self.cf_release(region);
        const cid = self.connectionId();
        if (cid <= 0) return abi.OMNI_ERR_PLATFORM;
        self.disable_update(cid);
        const rc = self.set_window_shape(
            cid,
            wid,
            BorderConstants.sentinel_coordinate,
            BorderConstants.sentinel_coordinate,
            region,
        );
        self.reenable_update(cid);
        if (rc != 0) return abi.OMNI_ERR_PLATFORM;
        return abi.OMNI_OK;
    }
    fn configureWindow(self: BorderMacOSApi, wid: u32, resolution: f64, is_opaque: bool) void {
        const cid = self.connectionId();
        if (cid <= 0) return;
        if (self.set_window_resolution) |set_window_resolution| {
            _ = set_window_resolution(cid, wid, @floatCast(resolution));
        }
        if (self.set_window_opacity) |set_window_opacity| {
            _ = set_window_opacity(cid, wid, if (is_opaque) 1 else 0);
        }
    }
    fn setWindowTags(self: BorderMacOSApi, wid: u32, tags: u64) void {
        const set_window_tags = self.set_window_tags orelse return;
        const cid = self.connectionId();
        if (cid <= 0) return;
        var mutable_tags = tags;
        _ = set_window_tags(cid, wid, &mutable_tags, 64);
    }
    fn flushWindow(self: BorderMacOSApi, wid: u32) void {
        const flush_window_content_region = self.flush_window_content_region orelse return;
        const cid = self.connectionId();
        if (cid <= 0) return;
        _ = flush_window_content_region(cid, wid, null);
    }
    fn moveAndOrder(self: BorderMacOSApi, wid: u32, origin_x: f64, origin_y: f64, target_wid: u32) i32 {
        const cid = self.connectionId();
        if (cid <= 0) return abi.OMNI_ERR_PLATFORM;
        var moved_with_transaction = false;
        if (self.transaction_move_window_with_group) |transaction_move_window_with_group| {
            const transaction = self.transaction_create(cid) orelse return abi.OMNI_ERR_PLATFORM;
            defer self.cf_release(transaction);
            if (transaction_move_window_with_group(transaction, wid, c.CGPointMake(origin_x, origin_y)) == 0) {
                moved_with_transaction = true;
            }
            if (self.transaction_set_window_level) |transaction_set_window_level| {
                _ = transaction_set_window_level(transaction, wid, BorderConstants.window_level);
            }
            if (target_wid != 0) {
                self.transaction_order_window(transaction, wid, BorderConstants.order_below, target_wid);
            }
            if (self.transaction_commit(transaction, 0) == 0) return abi.OMNI_OK;
        }
        if (!moved_with_transaction) {
            if (self.move_window) |move_window| {
                var point = c.CGPointMake(origin_x, origin_y);
                if (move_window(cid, wid, &point) != 0) {
                    return abi.OMNI_ERR_PLATFORM;
                }
            } else {
                return abi.OMNI_ERR_PLATFORM;
            }
        }
        const fallback_transaction = self.transaction_create(cid) orelse return abi.OMNI_OK;
        defer self.cf_release(fallback_transaction);
        if (self.transaction_set_window_level) |transaction_set_window_level| {
            _ = transaction_set_window_level(fallback_transaction, wid, BorderConstants.window_level);
        }
        if (target_wid != 0) {
            self.transaction_order_window(fallback_transaction, wid, BorderConstants.order_below, target_wid);
        }
        _ = self.transaction_commit(fallback_transaction, 0);
        return abi.OMNI_OK;
    }
    fn hide(self: BorderMacOSApi, wid: u32) i32 {
        if (wid == 0) return abi.OMNI_OK;
        const cid = self.connectionId();
        if (cid <= 0) return abi.OMNI_ERR_PLATFORM;
        const transaction = self.transaction_create(cid) orelse return abi.OMNI_ERR_PLATFORM;
        defer self.cf_release(transaction);
        self.transaction_order_window(transaction, wid, BorderConstants.order_out, 0);
        _ = self.transaction_commit(transaction, 0);
        return abi.OMNI_OK;
    }
};
const BorderMacOSBackend = struct {
    api: BorderMacOSApi,
    wid: u32 = 0,
    context: CGContextRef = null,
    current_frame: abi.OmniBorderRect = zeroRect(),
    current_target_wid: u32 = 0,
    current_backing_scale: f64 = 0.0,
    current_config: abi.OmniBorderConfig = defaultConfig(),
    needs_redraw: bool = true,
    fn init() !BorderMacOSBackend {
        return .{
            .api = try BorderMacOSApi.init(),
        };
    }
    fn destroy(self: *BorderMacOSBackend) void {
        if (self.context) |context| {
            self.api.cf_release(@ptrCast(context));
            self.context = null;
        }
        if (self.wid != 0) {
            self.api.releaseBorderWindow(self.wid);
            self.wid = 0;
        }
        self.api.deinit();
        self.current_frame = zeroRect();
        self.current_target_wid = 0;
        self.current_backing_scale = 0.0;
        self.current_config = defaultConfig();
        self.needs_redraw = true;
    }
    fn hide(self: *BorderMacOSBackend) i32 {
        if (self.wid != 0) {
            const rc = self.api.hide(self.wid);
            if (rc != abi.OMNI_OK) return rc;
        }
        self.current_target_wid = 0;
        return abi.OMNI_OK;
    }
    fn present(self: *BorderMacOSBackend, config: abi.OmniBorderConfig, request: BorderPresentRequest) i32 {
        if (self.wid == 0) {
            const new_wid = self.api.createBorderWindow(request.local_frame);
            if (new_wid == 0) return abi.OMNI_ERR_PLATFORM;
            self.wid = new_wid;
            self.api.configureWindow(self.wid, request.backing_scale, false);
            self.current_backing_scale = request.backing_scale;
            self.api.setWindowTags(self.wid, BorderConstants.window_tags);
            self.context = self.api.createWindowContext(self.wid);
            if (self.context == null) {
                self.api.releaseBorderWindow(self.wid);
                self.wid = 0;
                return abi.OMNI_ERR_PLATFORM;
            }
            c.CGContextSetInterpolationQuality(self.context, c.kCGInterpolationNone);
            self.needs_redraw = true;
        }
        if (self.current_backing_scale != request.backing_scale) {
            self.api.configureWindow(self.wid, request.backing_scale, false);
            self.current_backing_scale = request.backing_scale;
            self.needs_redraw = true;
        }
        if (!sameSize(self.current_frame, request.local_frame)) {
            const shape_rc = self.api.setWindowShape(self.wid, request.local_frame);
            if (shape_rc != abi.OMNI_OK) return shape_rc;
            self.needs_redraw = true;
        }
        if (!borderConfigEqual(self.current_config, config)) {
            self.needs_redraw = true;
        }
        self.current_frame = request.local_frame;
        self.current_target_wid = request.target_window_id;
        self.current_config = config;
        if (self.needs_redraw) {
            const draw_rc = self.draw(config, request.local_frame, request.drawing_bounds);
            if (draw_rc != abi.OMNI_OK) return draw_rc;
        }
        return self.api.moveAndOrder(self.wid, request.origin_x, request.origin_y, request.target_window_id);
    }
    fn draw(
        self: *BorderMacOSBackend,
        config: abi.OmniBorderConfig,
        frame: abi.OmniBorderRect,
        drawing_bounds: abi.OmniBorderRect,
    ) i32 {
        const context = self.context orelse return abi.OMNI_ERR_PLATFORM;
        self.needs_redraw = false;
        const border_width = config.width;
        const outer_radius = BorderConstants.corner_radius + border_width;
        const inner_rect = insetRect(drawing_bounds, border_width, border_width);
        const frame_rect = makeCGRect(frame);
        const inner_path = c.CGPathCreateWithRoundedRect(
            makeCGRect(inner_rect),
            BorderConstants.corner_radius,
            BorderConstants.corner_radius,
            null,
        );
        defer c.CGPathRelease(inner_path);
        const outer_path = c.CGPathCreateWithRoundedRect(
            makeCGRect(drawing_bounds),
            outer_radius,
            outer_radius,
            null,
        );
        defer c.CGPathRelease(outer_path);
        c.CGContextSaveGState(context);
        c.CGContextClearRect(context, frame_rect);
        c.CGContextSetRGBFillColor(context, config.color.red, config.color.green, config.color.blue, config.color.alpha);
        c.CGContextAddPath(context, outer_path);
        c.CGContextAddPath(context, inner_path);
        c.CGContextEOFillPath(context);
        c.CGContextRestoreGState(context);
        c.CGContextFlush(context);
        self.api.flushWindow(self.wid);
        return abi.OMNI_OK;
    }
};
const BorderPresentationState = struct {
    is_focused_window_in_active_workspace: u8 = 0,
    is_non_managed_focus_active: u8 = 0,
    is_native_fullscreen_active: u8 = 0,
    is_managed_fullscreen_active: u8 = 0,

    fn fromSnapshot(snapshot: abi.OmniBorderSnapshotInput) BorderPresentationState {
        return .{
            .is_focused_window_in_active_workspace = snapshot.is_focused_window_in_active_workspace,
            .is_non_managed_focus_active = snapshot.is_non_managed_focus_active,
            .is_native_fullscreen_active = snapshot.is_native_fullscreen_active,
            .is_managed_fullscreen_active = snapshot.is_managed_fullscreen_active,
        };
    }
};
const BorderState = struct {
    config: abi.OmniBorderConfig = defaultConfig(),
    presentation_state: BorderPresentationState = .{},
    force_hide_active: bool = false,
    last_applied_frame: abi.OmniBorderRect = zeroRect(),
    last_applied_window_id: i64 = 0,
    last_applied_config: abi.OmniBorderConfig = defaultConfig(),
    has_last_applied: bool = false,
    fn submitSnapshot(self: *BorderState, backend: anytype, snapshot: abi.OmniBorderSnapshotInput) i32 {
        if (!isDisplayPayloadValid(snapshot.displays, snapshot.display_count)) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        self.config = snapshot.config;
        self.presentation_state = BorderPresentationState.fromSnapshot(snapshot);
        self.force_hide_active = snapshot.force_hide != 0;
        if (snapshot.force_hide != 0) {
            return self.hide(backend);
        }
        return self.applyPresentation(backend, makePresentationInput(snapshot));
    }
    fn applyConfig(self: *BorderState, backend: anytype, config: abi.OmniBorderConfig) i32 {
        self.config = config;
        if (config.enabled == 0) {
            return self.hide(backend);
        }
        return abi.OMNI_OK;
    }
    fn applyMotion(self: *BorderState, backend: anytype, input: abi.OmniBorderMotionInput) i32 {
        if (!isDisplayPayloadValid(input.displays, input.display_count)) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (!isMotionInputSane(input)) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (self.force_hide_active) {
            return self.hide(backend);
        }
        return self.applyPresentation(backend, makeMotionPresentationInput(self.*, input));
    }
    fn applyPresentation(self: *BorderState, backend: anytype, input: abi.OmniBorderPresentationInput) i32 {
        if (!isDisplayPayloadValid(input.displays, input.display_count)) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (!isPresentationPayloadSane(input)) {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        self.config = input.config;
        if (shouldHideBorder(input)) {
            return self.hide(backend);
        }
        if (shouldDeferPresentation(input)) {
            return abi.OMNI_OK;
        }
        const displays = sliceDisplays(input);
        const display = if (displays.len > 0) selectDisplay(displays, input.focused_frame) else null;
        const target_window_id = castWindowId(input.focused_window_id) orelse return self.hide(backend);
        if (self.has_last_applied and
            self.last_applied_window_id == input.focused_window_id and
            rectApproximatelyEqual(self.last_applied_frame, input.focused_frame, BorderConstants.approximate_tolerance) and
            borderConfigEqual(self.last_applied_config, self.config))
        {
            return abi.OMNI_OK;
        }
        const scale = normalizedScale(if (display) |resolved_display| resolved_display.backing_scale else 2.0);
        const inflated_frame = roundRectToPhysicalPixels(
            inflateFrame(input.focused_frame, self.config.width + BorderConstants.padding),
            scale,
        );
        const focused_frame = roundRectToPhysicalPixels(input.focused_frame, scale);
        const window_server_frame = if (display) |resolved_display|
            appKitToWindowServerRect(inflated_frame, resolved_display)
        else
            inflated_frame;
        const focused_window_server_frame = if (display) |resolved_display|
            appKitToWindowServerRect(focused_frame, resolved_display)
        else
            focused_frame;
        const local_frame = abi.OmniBorderRect{
            .x = 0.0,
            .y = 0.0,
            .width = window_server_frame.width,
            .height = window_server_frame.height,
        };
        const drawing_bounds = abi.OmniBorderRect{
            .x = focused_window_server_frame.x - window_server_frame.x,
            .y = focused_window_server_frame.y - window_server_frame.y,
            .width = focused_window_server_frame.width,
            .height = focused_window_server_frame.height,
        };
        const rc = backend.present(self.config, .{
            .local_frame = local_frame,
            .drawing_bounds = drawing_bounds,
            .origin_x = window_server_frame.x,
            .origin_y = window_server_frame.y,
            .target_window_id = target_window_id,
            .backing_scale = scale,
        });
        if (rc == abi.OMNI_ERR_PLATFORM) {
            self.clearApplied();
            return abi.OMNI_OK;
        }
        if (rc != abi.OMNI_OK) return rc;
        self.last_applied_frame = input.focused_frame;
        self.last_applied_window_id = input.focused_window_id;
        self.last_applied_config = self.config;
        self.has_last_applied = true;
        return abi.OMNI_OK;
    }
    fn invalidateDisplays(self: *BorderState, backend: anytype) i32 {
        return self.hide(backend);
    }
    fn hide(self: *BorderState, backend: anytype) i32 {
        const rc = backend.hide();
        self.clearApplied();
        return rc;
    }
    fn clearApplied(self: *BorderState) void {
        self.last_applied_frame = zeroRect();
        self.last_applied_window_id = 0;
        self.last_applied_config = self.config;
        self.has_last_applied = false;
    }
};
pub const OmniBorderRuntime = extern struct {
    _opaque: u8 = 0,
};
const BorderRuntimeImpl = struct {
    state: BorderState = .{},
    backend: BorderMacOSBackend,
};
pub fn omni_border_runtime_create_impl() [*c]OmniBorderRuntime {
    const runtime = std.heap.c_allocator.create(BorderRuntimeImpl) catch {
        last_create_status = .out_of_memory;
        return null;
    };
    var backend = BorderMacOSBackend.init() catch |err| {
        last_create_status = switch (err) {
            error.MissingSkyLight => .missing_skylight,
            error.MissingSymbol => .missing_symbol,
        };
        std.heap.c_allocator.destroy(runtime);
        return null;
    };
    errdefer backend.destroy();
    if (backend.api.connectionId() <= 0) {
        last_create_status = .connection_unavailable;
        std.heap.c_allocator.destroy(runtime);
        return null;
    }
    if (backend.api.transaction_move_window_with_group == null and backend.api.move_window == null) {
        last_create_status = .missing_move_primitive;
        std.heap.c_allocator.destroy(runtime);
        return null;
    }
    last_create_status = .success;
    runtime.* = .{
        .state = .{},
        .backend = backend,
    };
    return @ptrCast(runtime);
}
pub fn omni_border_runtime_last_create_status_impl() BorderRuntimeCreateStatus {
    return last_create_status;
}
pub fn omni_border_runtime_destroy_impl(runtime: [*c]OmniBorderRuntime) void {
    if (runtime == null) return;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    impl.backend.destroy();
    std.heap.c_allocator.destroy(impl);
}
pub fn omni_border_runtime_apply_config_impl(
    runtime: [*c]OmniBorderRuntime,
    config: [*c]const abi.OmniBorderConfig,
) i32 {
    if (runtime == null or config == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.state.applyConfig(&impl.backend, config[0]);
}
pub fn omni_border_runtime_apply_presentation_impl(
    runtime: [*c]OmniBorderRuntime,
    input: [*c]const abi.OmniBorderPresentationInput,
) i32 {
    if (runtime == null or input == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.state.applyPresentation(&impl.backend, input[0]);
}
pub fn omni_border_runtime_submit_snapshot_impl(
    runtime: [*c]OmniBorderRuntime,
    snapshot: [*c]const abi.OmniBorderSnapshotInput,
) i32 {
    if (runtime == null or snapshot == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.state.submitSnapshot(&impl.backend, snapshot[0]);
}
pub fn omni_border_runtime_apply_motion_impl(
    runtime: [*c]OmniBorderRuntime,
    input: [*c]const abi.OmniBorderMotionInput,
) i32 {
    if (runtime == null or input == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.state.applyMotion(&impl.backend, input[0]);
}
pub fn omni_border_runtime_invalidate_displays_impl(runtime: [*c]OmniBorderRuntime) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.state.invalidateDisplays(&impl.backend);
}
pub fn omni_border_runtime_hide_impl(runtime: [*c]OmniBorderRuntime) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *BorderRuntimeImpl = @ptrCast(@alignCast(runtime));
    return impl.state.hide(&impl.backend);
}
fn defaultConfig() abi.OmniBorderConfig {
    return .{
        .enabled = 0,
        .width = 0.0,
        .color = .{
            .red = 0.0,
            .green = 0.0,
            .blue = 0.0,
            .alpha = 0.0,
        },
    };
}
fn zeroRect() abi.OmniBorderRect {
    return .{ .x = 0.0, .y = 0.0, .width = 0.0, .height = 0.0 };
}
fn sameSize(lhs: abi.OmniBorderRect, rhs: abi.OmniBorderRect) bool {
    return lhs.width == rhs.width and lhs.height == rhs.height;
}
fn borderConfigEqual(lhs: abi.OmniBorderConfig, rhs: abi.OmniBorderConfig) bool {
    return lhs.enabled == rhs.enabled and
        lhs.width == rhs.width and
        lhs.color.red == rhs.color.red and
        lhs.color.green == rhs.color.green and
        lhs.color.blue == rhs.color.blue and
        lhs.color.alpha == rhs.color.alpha;
}
fn isDisplayPayloadValid(displays: [*c]const abi.OmniBorderDisplayInfo, display_count: usize) bool {
    if (display_count > BorderConstants.max_display_count) return false;
    if (display_count > 0 and displays == null) return false;
    return true;
}
fn makePresentationInput(snapshot: abi.OmniBorderSnapshotInput) abi.OmniBorderPresentationInput {
    return .{
        .config = snapshot.config,
        .has_focused_window_id = snapshot.has_focused_window_id,
        .focused_window_id = snapshot.focused_window_id,
        .has_focused_frame = snapshot.has_focused_frame,
        .focused_frame = snapshot.focused_frame,
        .is_focused_window_in_active_workspace = snapshot.is_focused_window_in_active_workspace,
        .is_non_managed_focus_active = snapshot.is_non_managed_focus_active,
        .is_native_fullscreen_active = snapshot.is_native_fullscreen_active,
        .is_managed_fullscreen_active = snapshot.is_managed_fullscreen_active,
        .defer_updates = snapshot.defer_updates,
        .update_mode = snapshot.update_mode,
        .layout_animation_active = snapshot.layout_animation_active,
        .displays = snapshot.displays,
        .display_count = snapshot.display_count,
    };
}
fn makeMotionPresentationInput(state: BorderState, input: abi.OmniBorderMotionInput) abi.OmniBorderPresentationInput {
    return .{
        .config = state.config,
        .has_focused_window_id = 1,
        .focused_window_id = input.focused_window_id,
        .has_focused_frame = 1,
        .focused_frame = input.focused_frame,
        .is_focused_window_in_active_workspace = state.presentation_state.is_focused_window_in_active_workspace,
        .is_non_managed_focus_active = state.presentation_state.is_non_managed_focus_active,
        .is_native_fullscreen_active = state.presentation_state.is_native_fullscreen_active,
        .is_managed_fullscreen_active = state.presentation_state.is_managed_fullscreen_active,
        .defer_updates = 0,
        .update_mode = input.update_mode,
        .layout_animation_active = 0,
        .displays = input.displays,
        .display_count = input.display_count,
    };
}
fn shouldDeferPresentation(input: abi.OmniBorderPresentationInput) bool {
    if (input.defer_updates != 0) return true;
    if (input.update_mode == abi.OMNI_BORDER_UPDATE_MODE_REALTIME) return false;
    return input.layout_animation_active != 0;
}
fn shouldHideBorder(input: abi.OmniBorderPresentationInput) bool {
    if (input.config.enabled == 0) return true;
    if (input.has_focused_window_id == 0 or input.has_focused_frame == 0) return true;
    if (input.focused_frame.width <= 0.0 or input.focused_frame.height <= 0.0) return true;
    if (input.is_focused_window_in_active_workspace == 0) return true;
    if (input.is_non_managed_focus_active != 0) return true;
    if (input.is_native_fullscreen_active != 0) return true;
    if (input.is_managed_fullscreen_active != 0) return true;
    return false;
}
fn isPresentationPayloadSane(input: abi.OmniBorderPresentationInput) bool {
    if (!isBorderConfigSane(input.config)) return false;
    if (input.has_focused_frame != 0 and !isRectSane(input.focused_frame)) return false;
    if (input.display_count == 0 or input.displays == null) {
        return true;
    }
    for (input.displays[0..input.display_count]) |display| {
        if (!isDisplayInfoSane(display)) return false;
    }
    return true;
}
fn isMotionInputSane(input: abi.OmniBorderMotionInput) bool {
    if (castWindowId(input.focused_window_id) == null) return false;
    if (!isRectSane(input.focused_frame)) return false;
    if (input.focused_frame.width <= 0 or input.focused_frame.height <= 0) return false;
    return input.update_mode == abi.OMNI_BORDER_UPDATE_MODE_COALESCED or
        input.update_mode == abi.OMNI_BORDER_UPDATE_MODE_REALTIME;
}
fn isBorderConfigSane(config: abi.OmniBorderConfig) bool {
    if (!std.math.isFinite(config.width) or config.width < 0 or config.width > 128.0) return false;
    return isColorComponentSane(config.color.red) and
        isColorComponentSane(config.color.green) and
        isColorComponentSane(config.color.blue) and
        isColorComponentSane(config.color.alpha);
}
fn isColorComponentSane(value: f64) bool {
    return std.math.isFinite(value) and value >= 0 and value <= 1;
}
fn isRectSane(rect: abi.OmniBorderRect) bool {
    if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y)) return false;
    if (!std.math.isFinite(rect.width) or !std.math.isFinite(rect.height)) return false;
    if (rect.width < 0 or rect.height < 0) return false;
    const max_abs_coordinate = 1_000_000.0;
    const min_x = rect.x;
    const min_y = rect.y;
    const max_x = rect.x + rect.width;
    const max_y = rect.y + rect.height;
    return @abs(min_x) <= max_abs_coordinate and
        @abs(min_y) <= max_abs_coordinate and
        @abs(max_x) <= max_abs_coordinate and
        @abs(max_y) <= max_abs_coordinate;
}
fn isDisplayInfoSane(display: abi.OmniBorderDisplayInfo) bool {
    if (!isRectSane(display.appkit_frame) or !isRectSane(display.window_server_frame)) return false;
    if (display.appkit_frame.width <= 0 or display.appkit_frame.height <= 0) return false;
    if (display.window_server_frame.width <= 0 or display.window_server_frame.height <= 0) return false;
    if (!std.math.isFinite(display.backing_scale) or display.backing_scale <= 0) return false;
    return true;
}
fn sliceDisplays(input: abi.OmniBorderPresentationInput) []const abi.OmniBorderDisplayInfo {
    if (input.displays == null or input.display_count == 0) return &.{};
    return input.displays[0..input.display_count];
}
fn castWindowId(window_id: i64) ?u32 {
    if (window_id < 0 or window_id > std.math.maxInt(u32)) return null;
    return @intCast(window_id);
}
fn normalizedScale(scale: f64) f64 {
    return if (scale > 0.0) scale else 2.0;
}
fn inflateFrame(frame: abi.OmniBorderRect, amount: f64) abi.OmniBorderRect {
    return .{
        .x = frame.x - amount,
        .y = frame.y - amount,
        .width = frame.width + (amount * 2.0),
        .height = frame.height + (amount * 2.0),
    };
}
fn insetRect(rect: abi.OmniBorderRect, dx: f64, dy: f64) abi.OmniBorderRect {
    return .{
        .x = rect.x + dx,
        .y = rect.y + dy,
        .width = rect.width - (dx * 2.0),
        .height = rect.height - (dy * 2.0),
    };
}
fn roundRectToPhysicalPixels(rect: abi.OmniBorderRect, scale: f64) abi.OmniBorderRect {
    return .{
        .x = roundToPhysicalPixel(rect.x, scale),
        .y = roundToPhysicalPixel(rect.y, scale),
        .width = roundToPhysicalPixel(rect.width, scale),
        .height = roundToPhysicalPixel(rect.height, scale),
    };
}
fn roundToPhysicalPixel(value: f64, scale: f64) f64 {
    return @round(value * scale) / scale;
}
fn rectApproximatelyEqual(lhs: abi.OmniBorderRect, rhs: abi.OmniBorderRect, tolerance: f64) bool {
    return @abs(lhs.x - rhs.x) < tolerance and
        @abs(lhs.y - rhs.y) < tolerance and
        @abs(lhs.width - rhs.width) < tolerance and
        @abs(lhs.height - rhs.height) < tolerance;
}
fn selectDisplay(displays: []const abi.OmniBorderDisplayInfo, frame: abi.OmniBorderRect) ?abi.OmniBorderDisplayInfo {
    if (displays.len == 0) return null;
    const center_x = frame.x + (frame.width / 2.0);
    const center_y = frame.y + (frame.height / 2.0);
    for (displays) |display| {
        if (rectContainsPoint(display.appkit_frame, center_x, center_y)) {
            return display;
        }
    }
    var best_display = displays[0];
    var best_distance = rectDistanceSquared(displays[0].appkit_frame, center_x, center_y);
    for (displays[1..]) |display| {
        const distance = rectDistanceSquared(display.appkit_frame, center_x, center_y);
        if (distance < best_distance) {
            best_display = display;
            best_distance = distance;
        }
    }
    return best_display;
}
fn rectContainsPoint(rect: abi.OmniBorderRect, x: f64, y: f64) bool {
    return x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height;
}
fn rectDistanceSquared(rect: abi.OmniBorderRect, x: f64, y: f64) f64 {
    const clamped_x = std.math.clamp(x, rect.x, rect.x + rect.width);
    const clamped_y = std.math.clamp(y, rect.y, rect.y + rect.height);
    const dx = x - clamped_x;
    const dy = y - clamped_y;
    return dx * dx + dy * dy;
}
fn appKitToWindowServerRect(rect: abi.OmniBorderRect, display: abi.OmniBorderDisplayInfo) abi.OmniBorderRect {
    const scale_x = if (display.appkit_frame.width > 0.0)
        display.window_server_frame.width / display.appkit_frame.width
    else
        1.0;
    const scale_y = if (display.appkit_frame.height > 0.0)
        display.window_server_frame.height / display.appkit_frame.height
    else
        1.0;
    const dx = rect.x - display.appkit_frame.x;
    const dy = (display.appkit_frame.y + display.appkit_frame.height) - rect.y - rect.height;
    return .{
        .x = display.window_server_frame.x + (dx * scale_x),
        .y = display.window_server_frame.y + (dy * scale_y),
        .width = rect.width * scale_x,
        .height = rect.height * scale_y,
    };
}
fn makeCGRect(rect: abi.OmniBorderRect) c.CGRect {
    return c.CGRectMake(rect.x, rect.y, rect.width, rect.height);
}
const FakeBackend = struct {
    present_count: usize = 0,
    hide_count: usize = 0,
    next_present_rc: i32 = abi.OMNI_OK,
    last_config: abi.OmniBorderConfig = defaultConfig(),
    last_request: ?BorderPresentRequest = null,
    fn present(self: *FakeBackend, config: abi.OmniBorderConfig, request: BorderPresentRequest) i32 {
        if (self.next_present_rc != abi.OMNI_OK) {
            const rc = self.next_present_rc;
            self.next_present_rc = abi.OMNI_OK;
            return rc;
        }
        self.present_count += 1;
        self.last_config = config;
        self.last_request = request;
        return abi.OMNI_OK;
    }
    fn hide(self: *FakeBackend) i32 {
        self.hide_count += 1;
        return abi.OMNI_OK;
    }
};
fn makeDisplay(
    appkit_x: f64,
    appkit_y: f64,
    appkit_width: f64,
    appkit_height: f64,
    ws_x: f64,
    ws_y: f64,
    ws_width: f64,
    ws_height: f64,
    scale: f64,
) abi.OmniBorderDisplayInfo {
    return .{
        .display_id = 1,
        .appkit_frame = .{
            .x = appkit_x,
            .y = appkit_y,
            .width = appkit_width,
            .height = appkit_height,
        },
        .window_server_frame = .{
            .x = ws_x,
            .y = ws_y,
            .width = ws_width,
            .height = ws_height,
        },
        .backing_scale = scale,
    };
}
fn makeInput(
    config: abi.OmniBorderConfig,
    frame: abi.OmniBorderRect,
    displays: []const abi.OmniBorderDisplayInfo,
) abi.OmniBorderPresentationInput {
    return .{
        .config = config,
        .has_focused_window_id = 1,
        .focused_window_id = 42,
        .has_focused_frame = 1,
        .focused_frame = frame,
        .is_focused_window_in_active_workspace = 1,
        .is_non_managed_focus_active = 0,
        .is_native_fullscreen_active = 0,
        .is_managed_fullscreen_active = 0,
        .defer_updates = 0,
        .update_mode = abi.OMNI_BORDER_UPDATE_MODE_COALESCED,
        .layout_animation_active = 0,
        .displays = if (displays.len == 0) null else displays.ptr,
        .display_count = displays.len,
    };
}
fn makeSnapshotInput(
    config: abi.OmniBorderConfig,
    frame: abi.OmniBorderRect,
    displays: []const abi.OmniBorderDisplayInfo,
) abi.OmniBorderSnapshotInput {
    return .{
        .config = config,
        .has_focused_window_id = 1,
        .focused_window_id = 42,
        .has_focused_frame = 1,
        .focused_frame = frame,
        .is_focused_window_in_active_workspace = 1,
        .is_non_managed_focus_active = 0,
        .is_native_fullscreen_active = 0,
        .is_managed_fullscreen_active = 0,
        .defer_updates = 0,
        .update_mode = abi.OMNI_BORDER_UPDATE_MODE_COALESCED,
        .layout_animation_active = 0,
        .force_hide = 0,
        .displays = if (displays.len == 0) null else displays.ptr,
        .display_count = displays.len,
    };
}
fn makeMotionInput(
    frame: abi.OmniBorderRect,
    displays: []const abi.OmniBorderDisplayInfo,
    update_mode: u8,
) abi.OmniBorderMotionInput {
    return .{
        .focused_window_id = 42,
        .focused_frame = frame,
        .update_mode = update_mode,
        .displays = if (displays.len == 0) null else displays.ptr,
        .display_count = displays.len,
    };
}

test "motion applies immediately after deferred snapshot" {
    var state = BorderState{};
    var backend = FakeBackend{};
    const config = abi.OmniBorderConfig{
        .enabled = 1,
        .width = 4.0,
        .color = .{ .red = 0.0, .green = 0.5, .blue = 1.0, .alpha = 1.0 },
    };
    const displays = [_]abi.OmniBorderDisplayInfo{
        makeDisplay(0.0, 0.0, 1440.0, 900.0, 0.0, 0.0, 2880.0, 1800.0, 2.0),
    };
    var snapshot = makeSnapshotInput(config, .{ .x = 100.0, .y = 120.0, .width = 800.0, .height = 600.0 }, displays[0..]);
    snapshot.layout_animation_active = 1;

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), state.submitSnapshot(&backend, snapshot));
    try std.testing.expectEqual(@as(usize, 0), backend.present_count);

    const motion = makeMotionInput(
        .{ .x = 140.0, .y = 160.0, .width = 800.0, .height = 600.0 },
        displays[0..],
        abi.OMNI_BORDER_UPDATE_MODE_REALTIME,
    );
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), state.applyMotion(&backend, motion));
    try std.testing.expectEqual(@as(usize, 1), backend.present_count);
    try std.testing.expectEqual(@as(i64, 42), state.last_applied_window_id);
    try std.testing.expectEqual(@as(f64, 140.0), state.last_applied_frame.x);
}

test "motion stays hidden after force hide snapshot" {
    var state = BorderState{};
    var backend = FakeBackend{};
    const config = abi.OmniBorderConfig{
        .enabled = 1,
        .width = 4.0,
        .color = .{ .red = 0.0, .green = 0.5, .blue = 1.0, .alpha = 1.0 },
    };
    const displays = [_]abi.OmniBorderDisplayInfo{
        makeDisplay(0.0, 0.0, 1440.0, 900.0, 0.0, 0.0, 2880.0, 1800.0, 2.0),
    };
    var snapshot = makeSnapshotInput(config, .{ .x = 100.0, .y = 120.0, .width = 800.0, .height = 600.0 }, displays[0..]);
    snapshot.force_hide = 1;

    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), state.submitSnapshot(&backend, snapshot));
    try std.testing.expectEqual(@as(usize, 1), backend.hide_count);

    const motion = makeMotionInput(
        .{ .x = 140.0, .y = 160.0, .width = 800.0, .height = 600.0 },
        displays[0..],
        abi.OMNI_BORDER_UPDATE_MODE_REALTIME,
    );
    try std.testing.expectEqual(@as(i32, abi.OMNI_OK), state.applyMotion(&backend, motion));
    try std.testing.expectEqual(@as(usize, 2), backend.hide_count);
    try std.testing.expectEqual(@as(usize, 0), backend.present_count);
}
