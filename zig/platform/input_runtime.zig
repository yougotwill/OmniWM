const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const hotkeys = @import("hotkeys.zig");
const event_tap = @import("event_tap.zig");

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
});

pub const OmniInputRuntime = abi.OmniInputRuntime;

const RuntimeImpl = struct {
    host: abi.OmniInputHostVTable,
    options: abi.OmniInputOptions = defaultOptions(),
    started: bool = false,
    hotkeys: hotkeys.HotkeyManager,
    taps: event_tap.EventTapManager,

    fn init(host: abi.OmniInputHostVTable) RuntimeImpl {
        var impl = RuntimeImpl{
            .host = host,
            .hotkeys = hotkeys.HotkeyManager.init(host),
            .taps = event_tap.EventTapManager.init(.{}),
        };
        impl.taps.host = .{
            .userdata = null,
            .on_secure_input_changed = onSecureInputChanged,
            .on_input_event = onInputEvent,
            .on_tap_health = onTapHealth,
        };
        return impl;
    }

    fn deinit(self: *RuntimeImpl) void {
        _ = self.stop();
        self.hotkeys.deinit();
        self.taps.deinit();
    }

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;

        if (self.options.hotkeys_enabled != 0) {
            const hotkey_rc = self.hotkeys.start();
            if (hotkey_rc != abi.OMNI_OK) return hotkey_rc;
        }

        const tap_rc = self.taps.start(self.options);
        if (tap_rc != abi.OMNI_OK) {
            _ = self.hotkeys.stop();
            return tap_rc;
        }

        self.started = true;
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        _ = self.taps.stop();
        _ = self.hotkeys.stop();
        self.started = false;
        return abi.OMNI_OK;
    }

    fn setBindings(
        self: *RuntimeImpl,
        bindings: [*c]const abi.OmniInputBinding,
        binding_count: usize,
    ) i32 {
        return self.hotkeys.setBindings(bindings, binding_count);
    }

    fn setOptions(self: *RuntimeImpl, options: abi.OmniInputOptions) i32 {
        const old = self.options;
        self.options = options;

        if (!self.started) return abi.OMNI_OK;

        if (old.hotkeys_enabled != self.options.hotkeys_enabled) {
            if (self.options.hotkeys_enabled != 0) {
                const rc = self.hotkeys.start();
                if (rc != abi.OMNI_OK) return rc;
            } else {
                _ = self.hotkeys.stop();
            }
        }

        return self.taps.setOptions(self.options);
    }

    fn submitEvent(self: *RuntimeImpl, event: abi.OmniInputEvent) i32 {
        return self.taps.submitEvent(event);
    }

    fn queryRegistrationFailures(
        self: *RuntimeImpl,
        out_failures: [*c]abi.OmniInputRegistrationFailure,
        out_capacity: usize,
        out_written: [*c]usize,
    ) i32 {
        return self.hotkeys.queryRegistrationFailures(out_failures, out_capacity, out_written);
    }

    fn emitInputEffect(self: *RuntimeImpl, event: abi.OmniInputEvent) void {
        const callback = self.host.on_mouse_effect_batch;
        if (callback == null) {
            releaseEventRefIfNeeded(event);
            return;
        }

        var effect = abi.OmniInputEffect{
            .kind = abi.OMNI_INPUT_EFFECT_DISPATCH_EVENT,
            .reserved = [_]u8{0} ** 7,
            .event = event,
        };
        var effect_export = abi.OmniInputEffectExport{
            .effects = &effect,
            .effect_count = 1,
        };
        _ = callback.?(self.host.userdata, &effect_export);
    }
};

fn defaultOptions() abi.OmniInputOptions {
    return .{
        .hotkeys_enabled = 1,
        .mouse_enabled = 1,
        .gestures_enabled = 1,
        .secure_input_enabled = 1,
    };
}

fn releaseEventRefIfNeeded(event: abi.OmniInputEvent) void {
    if (event.event_ref) |ref| {
        c.CFRelease(@ptrCast(ref));
    }
}

fn implFromRuntime(runtime: [*c]OmniInputRuntime) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

fn onSecureInputChanged(userdata: ?*anyopaque, active: bool) void {
    const ptr = userdata orelse return;
    const runtime: *RuntimeImpl = @ptrCast(@alignCast(ptr));
    if (runtime.host.on_secure_input_state_changed) |callback| {
        _ = callback(runtime.host.userdata, if (active) 1 else 0);
    }
}

fn onInputEvent(userdata: ?*anyopaque, event: abi.OmniInputEvent) void {
    const ptr = userdata orelse {
        releaseEventRefIfNeeded(event);
        return;
    };
    const runtime: *RuntimeImpl = @ptrCast(@alignCast(ptr));
    runtime.emitInputEffect(event);
}

fn onTapHealth(userdata: ?*anyopaque, tap_kind: u8, reason: u8) void {
    const ptr = userdata orelse return;
    const runtime: *RuntimeImpl = @ptrCast(@alignCast(ptr));
    if (runtime.host.on_tap_health_notification) |callback| {
        _ = callback(runtime.host.userdata, tap_kind, reason);
    }
}

pub fn omni_input_runtime_create_impl(
    config: ?*const abi.OmniInputRuntimeConfig,
    host_vtable: ?*const abi.OmniInputHostVTable,
) [*c]OmniInputRuntime {
    const resolved_host = host_vtable orelse return null;

    var resolved_config = abi.OmniInputRuntimeConfig{
        .abi_version = abi.OMNI_INPUT_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }

    if (resolved_config.abi_version != abi.OMNI_INPUT_RUNTIME_ABI_VERSION) {
        return null;
    }

    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = RuntimeImpl.init(resolved_host.*);
    runtime.taps.host.userdata = @ptrCast(runtime);
    return @ptrCast(runtime);
}

pub fn omni_input_runtime_destroy_impl(runtime: [*c]OmniInputRuntime) void {
    const impl = implFromRuntime(runtime) orelse return;
    impl.deinit();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_input_runtime_start_impl(runtime: [*c]OmniInputRuntime) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.start();
}

pub fn omni_input_runtime_stop_impl(runtime: [*c]OmniInputRuntime) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}

pub fn omni_input_runtime_set_bindings_impl(
    runtime: [*c]OmniInputRuntime,
    bindings: [*c]const abi.OmniInputBinding,
    binding_count: usize,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.setBindings(bindings, binding_count);
}

pub fn omni_input_runtime_set_options_impl(
    runtime: [*c]OmniInputRuntime,
    options: ?*const abi.OmniInputOptions,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved = options orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.setOptions(resolved.*);
}

pub fn omni_input_runtime_submit_event_impl(
    runtime: [*c]OmniInputRuntime,
    event: ?*const abi.OmniInputEvent,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const resolved = event orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.submitEvent(resolved.*);
}

pub fn omni_input_runtime_query_registration_failures_impl(
    runtime: [*c]OmniInputRuntime,
    out_failures: [*c]abi.OmniInputRegistrationFailure,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    const impl = implFromRuntime(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.queryRegistrationFailures(out_failures, out_capacity, out_written);
}
