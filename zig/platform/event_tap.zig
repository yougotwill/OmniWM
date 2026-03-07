const std = @import("std");
const abi = @import("../omni/abi_types.zig");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("Carbon/Carbon.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

const gesture_event_type: c.CGEventType = @intCast(29);
const secure_poll_interval_seconds: f64 = 2.0;

pub const EventHost = struct {
    userdata: ?*anyopaque = null,
    on_secure_input_changed: ?*const fn (?*anyopaque, bool) void = null,
    on_input_event: ?*const fn (?*anyopaque, abi.OmniInputEvent) void = null,
    on_tap_health: ?*const fn (?*anyopaque, u8, u8) void = null,
};

pub const EventTapManager = struct {
    host: EventHost,
    options: abi.OmniInputOptions = .{
        .hotkeys_enabled = 1,
        .mouse_enabled = 1,
        .gestures_enabled = 1,
        .secure_input_enabled = 1,
    },
    started: bool = false,
    secure_input_active: bool = false,

    secure_tap: c.CFMachPortRef = null,
    secure_source: c.CFRunLoopSourceRef = null,

    mouse_tap: c.CFMachPortRef = null,
    mouse_source: c.CFRunLoopSourceRef = null,

    gesture_tap: c.CFMachPortRef = null,
    gesture_source: c.CFRunLoopSourceRef = null,

    secure_timer: c.CFRunLoopTimerRef = null,

    pub fn init(host: EventHost) EventTapManager {
        return .{ .host = host };
    }

    pub fn deinit(self: *EventTapManager) void {
        _ = self.stop();
    }

    pub fn start(self: *EventTapManager, options: abi.OmniInputOptions) i32 {
        if (self.started) return abi.OMNI_OK;

        self.options = options;

        if (self.options.mouse_enabled != 0) {
            if (!self.startMouseTap()) {
                _ = self.stop();
                return abi.OMNI_ERR_PLATFORM;
            }
        }

        if (self.options.gestures_enabled != 0) {
            if (!self.startGestureTap()) {
                _ = self.stop();
                return abi.OMNI_ERR_PLATFORM;
            }
        }

        if (self.options.secure_input_enabled != 0) {
            if (!self.startSecureTap()) {
                _ = self.stop();
                return abi.OMNI_ERR_PLATFORM;
            }

            self.updateSecureInputState(c.IsSecureEventInputEnabled() != 0);
        }

        self.started = true;
        return abi.OMNI_OK;
    }

    pub fn stop(self: *EventTapManager) i32 {
        if (!self.started and self.secure_tap == null and self.mouse_tap == null and self.gesture_tap == null) {
            return abi.OMNI_OK;
        }

        self.stopSecureTimer();
        self.removeTap(&self.secure_tap, &self.secure_source);
        self.removeTap(&self.mouse_tap, &self.mouse_source);
        self.removeTap(&self.gesture_tap, &self.gesture_source);

        self.started = false;
        self.secure_input_active = false;
        return abi.OMNI_OK;
    }

    pub fn setOptions(self: *EventTapManager, options: abi.OmniInputOptions) i32 {
        if (!self.started) {
            self.options = options;
            return abi.OMNI_OK;
        }

        _ = self.stop();
        return self.start(options);
    }

    pub fn submitEvent(self: *EventTapManager, event: abi.OmniInputEvent) i32 {
        switch (event.kind) {
            abi.OMNI_INPUT_EVENT_SECURE_INPUT_CHANGED => {
                self.updateSecureInputState(event.phase != 0);
            },
            else => {
                if (self.host.on_input_event) |callback| {
                    callback(self.host.userdata, event);
                }
            },
        }
        return abi.OMNI_OK;
    }

    fn startSecureTap(self: *EventTapManager) bool {
        const mask: c.CGEventMask = (@as(c.CGEventMask, 1) << @intCast(c.kCGEventKeyDown));
        return self.createTap(
            c.kCGSessionEventTap,
            c.kCGHeadInsertEventTap,
            c.kCGEventTapOptionListenOnly,
            mask,
            secureTapCallback,
            &self.secure_tap,
            &self.secure_source,
        );
    }

    fn startMouseTap(self: *EventTapManager) bool {
        const mask: c.CGEventMask =
            (@as(c.CGEventMask, 1) << @intCast(c.kCGEventMouseMoved)) |
            (@as(c.CGEventMask, 1) << @intCast(c.kCGEventLeftMouseDown)) |
            (@as(c.CGEventMask, 1) << @intCast(c.kCGEventLeftMouseDragged)) |
            (@as(c.CGEventMask, 1) << @intCast(c.kCGEventLeftMouseUp)) |
            (@as(c.CGEventMask, 1) << @intCast(c.kCGEventScrollWheel));

        return self.createTap(
            c.kCGSessionEventTap,
            c.kCGHeadInsertEventTap,
            c.kCGEventTapOptionListenOnly,
            mask,
            mouseTapCallback,
            &self.mouse_tap,
            &self.mouse_source,
        );
    }

    fn startGestureTap(self: *EventTapManager) bool {
        const mask: c.CGEventMask = (@as(c.CGEventMask, 1) << @intCast(gesture_event_type));
        return self.createTap(
            c.kCGHIDEventTap,
            c.kCGHeadInsertEventTap,
            c.kCGEventTapOptionListenOnly,
            mask,
            gestureTapCallback,
            &self.gesture_tap,
            &self.gesture_source,
        );
    }

    fn createTap(
        self: *EventTapManager,
        tap: c.CGEventTapLocation,
        place: c.CGEventTapPlacement,
        options: c.CGEventTapOptions,
        mask: c.CGEventMask,
        callback: c.CGEventTapCallBack,
        out_tap: *c.CFMachPortRef,
        out_source: *c.CFRunLoopSourceRef,
    ) bool {
        const created_tap = c.CGEventTapCreate(
            tap,
            place,
            options,
            mask,
            callback,
            @ptrCast(self),
        );
        if (created_tap == null) {
            return false;
        }

        const source = c.CFMachPortCreateRunLoopSource(c.kCFAllocatorDefault, created_tap, 0);
        if (source == null) {
            c.CFRelease(created_tap);
            return false;
        }

        c.CFRunLoopAddSource(c.CFRunLoopGetMain(), source, c.kCFRunLoopCommonModes);
        c.CGEventTapEnable(created_tap, true);

        out_tap.* = created_tap;
        out_source.* = source;
        return true;
    }

    fn removeTap(
        self: *EventTapManager,
        tap: *c.CFMachPortRef,
        source: *c.CFRunLoopSourceRef,
    ) void {
        _ = self;
        if (source.* != null) {
            c.CFRunLoopRemoveSource(c.CFRunLoopGetMain(), source.*, c.kCFRunLoopCommonModes);
            c.CFRelease(source.*);
            source.* = null;
        }
        if (tap.* != null) {
            c.CGEventTapEnable(tap.*, false);
            c.CFMachPortInvalidate(tap.*);
            c.CFRelease(tap.*);
            tap.* = null;
        }
    }

    fn onTapDisabled(self: *EventTapManager, tap_kind: u8, reason: u8, tap: c.CFMachPortRef) void {
        if (self.host.on_tap_health) |callback| {
            callback(self.host.userdata, tap_kind, reason);
        }
        if (tap != null) {
            c.CGEventTapEnable(tap, true);
        }

        if (tap_kind == abi.OMNI_INPUT_TAP_KIND_SECURE_INPUT and reason == abi.OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT) {
            self.updateSecureInputState(c.IsSecureEventInputEnabled() != 0);
        }
    }

    fn updateSecureInputState(self: *EventTapManager, is_active: bool) void {
        if (self.secure_input_active == is_active) return;
        self.secure_input_active = is_active;

        if (self.host.on_secure_input_changed) |callback| {
            callback(self.host.userdata, is_active);
        }

        if (is_active) {
            self.startSecureTimer();
        } else {
            self.stopSecureTimer();
        }
    }

    fn startSecureTimer(self: *EventTapManager) void {
        if (self.secure_timer != null) return;

        var context = c.CFRunLoopTimerContext{
            .version = 0,
            .info = @ptrCast(self),
            .retain = null,
            .release = null,
            .copyDescription = null,
        };

        const start_time = c.CFAbsoluteTimeGetCurrent() + secure_poll_interval_seconds;
        self.secure_timer = c.CFRunLoopTimerCreate(
            c.kCFAllocatorDefault,
            start_time,
            secure_poll_interval_seconds,
            0,
            0,
            secureTimerCallback,
            &context,
        );
        if (self.secure_timer != null) {
            c.CFRunLoopAddTimer(c.CFRunLoopGetMain(), self.secure_timer, c.kCFRunLoopCommonModes);
        }
    }

    fn stopSecureTimer(self: *EventTapManager) void {
        if (self.secure_timer == null) return;
        c.CFRunLoopRemoveTimer(c.CFRunLoopGetMain(), self.secure_timer, c.kCFRunLoopCommonModes);
        c.CFRelease(self.secure_timer);
        self.secure_timer = null;
    }

    fn processSecureTapEvent(self: *EventTapManager, type_: c.CGEventType) void {
        switch (type_) {
            c.kCGEventTapDisabledByTimeout => self.onTapDisabled(
                abi.OMNI_INPUT_TAP_KIND_SECURE_INPUT,
                abi.OMNI_INPUT_TAP_HEALTH_DISABLED_TIMEOUT,
                self.secure_tap,
            ),
            c.kCGEventTapDisabledByUserInput => self.onTapDisabled(
                abi.OMNI_INPUT_TAP_KIND_SECURE_INPUT,
                abi.OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT,
                self.secure_tap,
            ),
            else => {
                if (self.secure_input_active and c.IsSecureEventInputEnabled() == 0) {
                    self.updateSecureInputState(false);
                }
            },
        }
    }

    fn processMouseTapEvent(self: *EventTapManager, type_: c.CGEventType, event: c.CGEventRef) void {
        if (type_ == c.kCGEventTapDisabledByTimeout) {
            self.onTapDisabled(abi.OMNI_INPUT_TAP_KIND_MOUSE, abi.OMNI_INPUT_TAP_HEALTH_DISABLED_TIMEOUT, self.mouse_tap);
            return;
        }
        if (type_ == c.kCGEventTapDisabledByUserInput) {
            self.onTapDisabled(abi.OMNI_INPUT_TAP_KIND_MOUSE, abi.OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT, self.mouse_tap);
            return;
        }

        var input = std.mem.zeroes(abi.OmniInputEvent);
        switch (type_) {
            c.kCGEventMouseMoved => input.kind = abi.OMNI_INPUT_EVENT_MOUSE_MOVED,
            c.kCGEventLeftMouseDown => input.kind = abi.OMNI_INPUT_EVENT_LEFT_MOUSE_DOWN,
            c.kCGEventLeftMouseDragged => input.kind = abi.OMNI_INPUT_EVENT_LEFT_MOUSE_DRAGGED,
            c.kCGEventLeftMouseUp => input.kind = abi.OMNI_INPUT_EVENT_LEFT_MOUSE_UP,
            c.kCGEventScrollWheel => input.kind = abi.OMNI_INPUT_EVENT_SCROLL_WHEEL,
            else => return,
        }

        const location = c.CGEventGetLocation(event);
        input.location_x = location.x;
        input.location_y = location.y;
        input.modifiers = @intCast(c.CGEventGetFlags(event));

        if (type_ == c.kCGEventScrollWheel) {
            input.delta_x = c.CGEventGetDoubleValueField(event, c.kCGScrollWheelEventPointDeltaAxis2);
            input.delta_y = c.CGEventGetDoubleValueField(event, c.kCGScrollWheelEventPointDeltaAxis1);
            input.momentum_phase = @intCast(c.CGEventGetIntegerValueField(event, c.kCGScrollWheelEventMomentumPhase));
            input.phase = @intCast(c.CGEventGetIntegerValueField(event, c.kCGScrollWheelEventScrollPhase));
        }

        if (self.host.on_input_event) |callback| {
            callback(self.host.userdata, input);
        }
    }

    fn processGestureTapEvent(self: *EventTapManager, type_: c.CGEventType, event: c.CGEventRef) void {
        if (type_ == c.kCGEventTapDisabledByTimeout) {
            self.onTapDisabled(abi.OMNI_INPUT_TAP_KIND_GESTURE, abi.OMNI_INPUT_TAP_HEALTH_DISABLED_TIMEOUT, self.gesture_tap);
            return;
        }
        if (type_ == c.kCGEventTapDisabledByUserInput) {
            self.onTapDisabled(abi.OMNI_INPUT_TAP_KIND_GESTURE, abi.OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT, self.gesture_tap);
            return;
        }
        if (type_ != gesture_event_type) return;

        const copied = c.CGEventCreateCopy(event);

        var input = std.mem.zeroes(abi.OmniInputEvent);
        input.kind = abi.OMNI_INPUT_EVENT_GESTURE;
        const location = c.CGEventGetLocation(event);
        input.location_x = location.x;
        input.location_y = location.y;
        input.phase = @intCast(c.CGEventGetIntegerValueField(event, c.kCGScrollWheelEventScrollPhase));
        input.modifiers = @intCast(c.CGEventGetFlags(event));
        input.event_ref = if (copied == null) null else @ptrCast(copied);

        if (self.host.on_input_event) |callback| {
            callback(self.host.userdata, input);
        } else if (copied != null) {
            c.CFRelease(copied);
        }
    }
};

fn secureTapCallback(
    proxy: c.CGEventTapProxy,
    type_: c.CGEventType,
    event: c.CGEventRef,
    user_info: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    _ = proxy;
    const ptr = user_info orelse return event;
    const manager: *EventTapManager = @ptrCast(@alignCast(ptr));
    manager.processSecureTapEvent(type_);
    return event;
}

fn mouseTapCallback(
    proxy: c.CGEventTapProxy,
    type_: c.CGEventType,
    event: c.CGEventRef,
    user_info: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    _ = proxy;
    const ptr = user_info orelse return event;
    const manager: *EventTapManager = @ptrCast(@alignCast(ptr));
    manager.processMouseTapEvent(type_, event);
    return event;
}

fn gestureTapCallback(
    proxy: c.CGEventTapProxy,
    type_: c.CGEventType,
    event: c.CGEventRef,
    user_info: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    _ = proxy;
    const ptr = user_info orelse return event;
    const manager: *EventTapManager = @ptrCast(@alignCast(ptr));
    manager.processGestureTapEvent(type_, event);
    return event;
}

fn secureTimerCallback(timer: c.CFRunLoopTimerRef, info: ?*anyopaque) callconv(.c) void {
    _ = timer;
    const ptr = info orelse return;
    const manager: *EventTapManager = @ptrCast(@alignCast(ptr));
    if (manager.secure_input_active and c.IsSecureEventInputEnabled() == 0) {
        manager.updateSecureInputState(false);
    }
}
