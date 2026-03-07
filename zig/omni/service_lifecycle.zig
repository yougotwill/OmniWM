const std = @import("std");
const abi = @import("abi_types.zig");
const ax_permission = @import("../platform/ax_permission.zig");
const ax_manager = @import("../platform/ax_manager.zig");
const input_runtime = @import("../platform/input_runtime.zig");
const lock_observer = @import("../platform/lock_observer.zig");
const monitor_discovery = @import("../platform/monitor_discovery.zig");
const platform_runtime = @import("../platform/platform_runtime.zig");
const workspace_observer = @import("../platform/workspace_observer.zig");
const wm_controller = @import("wm_controller.zig");

pub const OmniServiceLifecycle = abi.OmniServiceLifecycle;

const RuntimeImpl = struct {
    config: abi.OmniServiceLifecycleConfig,
    handles: abi.OmniServiceLifecycleHandles,
    host: abi.OmniServiceLifecycleHostVTable,
    owned_platform_runtime: [*c]platform_runtime.OmniPlatformRuntime = null,
    owned_workspace_observer_runtime: [*c]workspace_observer.OmniWorkspaceObserverRuntime = null,
    owned_lock_observer_runtime: [*c]lock_observer.OmniLockObserverRuntime = null,
    owned_monitor_runtime: [*c]monitor_discovery.OmniMonitorRuntime = null,

    state: u8 = abi.OMNI_SERVICE_LIFECYCLE_STATE_STOPPED,
    started_wm_controller: bool = false,
    started_ax_runtime: bool = false,
    started_input_runtime: bool = false,
    started_platform_runtime: bool = false,
    started_workspace_observer: bool = false,
    started_lock_observer: bool = false,
    started_monitor_runtime: bool = false,

    fn start(self: *RuntimeImpl) i32 {
        if (self.state == abi.OMNI_SERVICE_LIFECYCLE_STATE_RUNNING) return abi.OMNI_OK;

        self.transitionState(abi.OMNI_SERVICE_LIFECYCLE_STATE_STARTING);

        if (!self.ensureAccessibilityPermission()) {
            self.failWith(abi.OMNI_ERR_PLATFORM, "accessibility permission is required");
            return abi.OMNI_ERR_PLATFORM;
        }

        const owned_rc = self.ensureOwnedRuntimes();
        if (owned_rc != abi.OMNI_OK) return self.failStart(owned_rc, "failed to create owned runtimes");

        const resolved_ax_runtime = self.handles.ax_runtime;
        const resolved_input_runtime = self.handles.input_runtime;
        const resolved_platform_runtime = self.resolvePlatformRuntime();
        const resolved_workspace_observer_runtime = self.resolveWorkspaceObserverRuntime();
        const resolved_lock_observer_runtime = self.resolveLockObserverRuntime();
        const resolved_monitor_runtime = self.resolveMonitorRuntime();

        if (resolved_ax_runtime != null) {
            const rc = ax_manager.omni_ax_runtime_start_impl(resolved_ax_runtime);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start AX runtime");
            self.started_ax_runtime = true;
        }

        if (resolved_input_runtime != null) {
            const rc = input_runtime.omni_input_runtime_start_impl(resolved_input_runtime);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start input runtime");
            self.started_input_runtime = true;
        }

        if (self.handles.wm_controller != null) {
            const rc = wm_controller.omni_wm_controller_start_impl(self.handles.wm_controller);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start WM controller");
            self.started_wm_controller = true;
        }

        if (resolved_platform_runtime != null) {
            const rc = platform_runtime.omni_platform_runtime_start_impl(resolved_platform_runtime);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start platform runtime");
            self.started_platform_runtime = true;
        }

        if (resolved_workspace_observer_runtime != null) {
            const rc = workspace_observer.omni_workspace_observer_runtime_start_impl(resolved_workspace_observer_runtime);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start workspace observer runtime");
            self.started_workspace_observer = true;
        }

        if (resolved_lock_observer_runtime != null) {
            const rc = lock_observer.omni_lock_observer_runtime_start_impl(resolved_lock_observer_runtime);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start lock observer runtime");
            self.started_lock_observer = true;
        }

        if (resolved_monitor_runtime != null) {
            const rc = monitor_discovery.omni_monitor_runtime_start_impl(resolved_monitor_runtime);
            if (rc != abi.OMNI_OK) return self.failStart(rc, "failed to start monitor runtime");
            self.started_monitor_runtime = true;
        }

        self.transitionState(abi.OMNI_SERVICE_LIFECYCLE_STATE_RUNNING);
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (self.state == abi.OMNI_SERVICE_LIFECYCLE_STATE_STOPPED) return abi.OMNI_OK;

        self.transitionState(abi.OMNI_SERVICE_LIFECYCLE_STATE_STOPPING);
        self.stopStartedServices();
        self.transitionState(abi.OMNI_SERVICE_LIFECYCLE_STATE_STOPPED);
        return abi.OMNI_OK;
    }

    fn resolvePlatformRuntime(self: *RuntimeImpl) [*c]platform_runtime.OmniPlatformRuntime {
        return if (self.handles.platform_runtime != null) self.handles.platform_runtime else self.owned_platform_runtime;
    }

    fn resolveWorkspaceObserverRuntime(self: *RuntimeImpl) [*c]workspace_observer.OmniWorkspaceObserverRuntime {
        return if (self.handles.workspace_observer_runtime != null)
            self.handles.workspace_observer_runtime
        else
            self.owned_workspace_observer_runtime;
    }

    fn resolveLockObserverRuntime(self: *RuntimeImpl) [*c]lock_observer.OmniLockObserverRuntime {
        return if (self.handles.lock_observer_runtime != null)
            self.handles.lock_observer_runtime
        else
            self.owned_lock_observer_runtime;
    }

    fn resolveMonitorRuntime(self: *RuntimeImpl) [*c]monitor_discovery.OmniMonitorRuntime {
        return if (self.handles.monitor_runtime != null) self.handles.monitor_runtime else self.owned_monitor_runtime;
    }

    fn ensureOwnedRuntimes(self: *RuntimeImpl) i32 {
        if (self.handles.platform_runtime == null and self.owned_platform_runtime == null) {
            var config = abi.OmniPlatformRuntimeConfig{
                .abi_version = abi.OMNI_PLATFORM_RUNTIME_ABI_VERSION,
                .reserved = 0,
            };
            var host = abi.OmniPlatformHostVTable{
                .userdata = @ptrCast(self),
                .on_window_created = serviceLifecyclePlatformWindowCreatedBridge,
                .on_window_destroyed = serviceLifecyclePlatformWindowDestroyedBridge,
                .on_window_closed = serviceLifecyclePlatformWindowClosedBridge,
                .on_window_moved = serviceLifecyclePlatformWindowMovedBridge,
                .on_window_resized = serviceLifecyclePlatformWindowResizedBridge,
                .on_front_app_changed = serviceLifecyclePlatformFrontAppChangedBridge,
                .on_window_title_changed = serviceLifecyclePlatformWindowTitleChangedBridge,
            };
            self.owned_platform_runtime = platform_runtime.omni_platform_runtime_create_impl(&config, &host);
            if (self.owned_platform_runtime == null) return abi.OMNI_ERR_PLATFORM;
        }

        if (self.handles.workspace_observer_runtime == null and self.owned_workspace_observer_runtime == null) {
            var config = abi.OmniWorkspaceObserverRuntimeConfig{
                .abi_version = abi.OMNI_WORKSPACE_OBSERVER_RUNTIME_ABI_VERSION,
                .reserved = 0,
            };
            var host = abi.OmniWorkspaceObserverHostVTable{
                .userdata = @ptrCast(self),
                .on_app_launched = serviceLifecycleWorkspaceAppLaunchedBridge,
                .on_app_terminated = serviceLifecycleWorkspaceAppTerminatedBridge,
                .on_app_activated = serviceLifecycleWorkspaceAppActivatedBridge,
                .on_app_hidden = serviceLifecycleWorkspaceAppHiddenBridge,
                .on_app_unhidden = serviceLifecycleWorkspaceAppUnhiddenBridge,
                .on_active_space_changed = serviceLifecycleWorkspaceActiveSpaceChangedBridge,
            };
            self.owned_workspace_observer_runtime = workspace_observer.omni_workspace_observer_runtime_create_impl(&config, &host);
            if (self.owned_workspace_observer_runtime == null) return abi.OMNI_ERR_PLATFORM;
        }

        if (self.handles.lock_observer_runtime == null and self.owned_lock_observer_runtime == null) {
            var config = abi.OmniLockObserverRuntimeConfig{
                .abi_version = abi.OMNI_LOCK_OBSERVER_RUNTIME_ABI_VERSION,
                .reserved = 0,
            };
            var host = abi.OmniLockObserverHostVTable{
                .userdata = @ptrCast(self),
                .on_locked = serviceLifecycleLockObserverLockedBridge,
                .on_unlocked = serviceLifecycleLockObserverUnlockedBridge,
            };
            self.owned_lock_observer_runtime = lock_observer.omni_lock_observer_runtime_create_impl(&config, &host);
            if (self.owned_lock_observer_runtime == null) return abi.OMNI_ERR_PLATFORM;
        }

        if (self.handles.monitor_runtime == null and self.owned_monitor_runtime == null) {
            var config = abi.OmniMonitorRuntimeConfig{
                .abi_version = abi.OMNI_MONITOR_RUNTIME_ABI_VERSION,
                .reserved = 0,
            };
            var host = abi.OmniMonitorHostVTable{
                .userdata = @ptrCast(self),
                .on_displays_changed = serviceLifecycleMonitorDisplaysChangedBridge,
            };
            self.owned_monitor_runtime = monitor_discovery.omni_monitor_runtime_create_impl(&config, &host);
            if (self.owned_monitor_runtime == null) return abi.OMNI_ERR_PLATFORM;
        }

        return abi.OMNI_OK;
    }

    fn destroyOwnedRuntimes(self: *RuntimeImpl) void {
        if (self.owned_monitor_runtime != null) {
            monitor_discovery.omni_monitor_runtime_destroy_impl(self.owned_monitor_runtime);
            self.owned_monitor_runtime = null;
        }
        if (self.owned_lock_observer_runtime != null) {
            lock_observer.omni_lock_observer_runtime_destroy_impl(self.owned_lock_observer_runtime);
            self.owned_lock_observer_runtime = null;
        }
        if (self.owned_workspace_observer_runtime != null) {
            workspace_observer.omni_workspace_observer_runtime_destroy_impl(self.owned_workspace_observer_runtime);
            self.owned_workspace_observer_runtime = null;
        }
        if (self.owned_platform_runtime != null) {
            platform_runtime.omni_platform_runtime_destroy_impl(self.owned_platform_runtime);
            self.owned_platform_runtime = null;
        }
    }

    fn submitControllerEvent(self: *RuntimeImpl, event: abi.OmniControllerEvent) void {
        if (self.handles.wm_controller == null) return;
        var mutable_event = event;
        _ = wm_controller.omni_wm_controller_submit_os_event_impl(self.handles.wm_controller, &mutable_event);
    }

    fn emitRefresh(self: *RuntimeImpl, reason: u8) void {
        self.submitControllerEvent(.{
            .kind = abi.OMNI_CONTROLLER_EVENT_REFRESH_SESSION,
            .enabled = 0,
            .refresh_reason = reason,
            .has_display_id = 0,
            .display_id = 0,
            .pid = 0,
            .has_window_handle_id = 0,
            .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_workspace_id = 0,
            .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        });
    }

    fn emitAppEvent(self: *RuntimeImpl, kind: u8, pid: i32) void {
        self.submitControllerEvent(.{
            .kind = kind,
            .enabled = 0,
            .refresh_reason = abi.OMNI_CONTROLLER_REFRESH_REASON_TIMER,
            .has_display_id = 0,
            .display_id = 0,
            .pid = pid,
            .has_window_handle_id = 0,
            .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_workspace_id = 0,
            .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        });
    }

    fn emitLockState(self: *RuntimeImpl, locked: bool) void {
        self.submitControllerEvent(.{
            .kind = abi.OMNI_CONTROLLER_EVENT_LOCK_SCREEN_CHANGED,
            .enabled = if (locked) 1 else 0,
            .refresh_reason = abi.OMNI_CONTROLLER_REFRESH_REASON_TIMER,
            .has_display_id = 0,
            .display_id = 0,
            .pid = 0,
            .has_window_handle_id = 0,
            .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_workspace_id = 0,
            .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        });
    }

    fn emitMonitorReconfigured(self: *RuntimeImpl, display_id: u32) void {
        self.submitControllerEvent(.{
            .kind = abi.OMNI_CONTROLLER_EVENT_MONITOR_RECONFIGURED,
            .enabled = 0,
            .refresh_reason = abi.OMNI_CONTROLLER_REFRESH_REASON_MONITOR_RECONFIGURED,
            .has_display_id = 1,
            .display_id = display_id,
            .pid = 0,
            .has_window_handle_id = 0,
            .window_handle_id = .{ .bytes = [_]u8{0} ** 16 },
            .has_workspace_id = 0,
            .workspace_id = .{ .bytes = [_]u8{0} ** 16 },
        });
    }

    fn ensureAccessibilityPermission(self: *RuntimeImpl) bool {
        if (self.config.request_ax_prompt != 0) {
            _ = ax_permission.omni_ax_permission_request_prompt_impl();
        }

        if (self.config.poll_ax_permission == 0) {
            return ax_permission.omni_ax_permission_is_trusted_impl() != 0;
        }

        return ax_permission.omni_ax_permission_poll_until_trusted_impl(
            self.config.ax_poll_timeout_millis,
            self.config.ax_poll_interval_millis,
        ) != 0;
    }

    fn failStart(self: *RuntimeImpl, code: i32, message: []const u8) i32 {
        self.stopStartedServices();
        self.failWith(code, message);
        return code;
    }

    fn failWith(self: *RuntimeImpl, code: i32, message: []const u8) void {
        self.transitionState(abi.OMNI_SERVICE_LIFECYCLE_STATE_FAILED);
        if (self.host.on_error) |callback| {
            _ = callback(self.host.userdata, code, encodeControllerName(message));
        }
    }

    fn transitionState(self: *RuntimeImpl, state: u8) void {
        self.state = state;
        if (self.host.on_state_changed) |callback| {
            _ = callback(self.host.userdata, state);
        }
    }

    fn stopStartedServices(self: *RuntimeImpl) void {
        const resolved_ax_runtime = self.handles.ax_runtime;
        const resolved_input_runtime = self.handles.input_runtime;
        const resolved_platform_runtime = self.resolvePlatformRuntime();
        const resolved_workspace_observer_runtime = self.resolveWorkspaceObserverRuntime();
        const resolved_lock_observer_runtime = self.resolveLockObserverRuntime();
        const resolved_monitor_runtime = self.resolveMonitorRuntime();

        if (self.started_monitor_runtime) {
            _ = monitor_discovery.omni_monitor_runtime_stop_impl(resolved_monitor_runtime);
            self.started_monitor_runtime = false;
        }
        if (self.started_lock_observer) {
            _ = lock_observer.omni_lock_observer_runtime_stop_impl(resolved_lock_observer_runtime);
            self.started_lock_observer = false;
        }
        if (self.started_workspace_observer) {
            _ = workspace_observer.omni_workspace_observer_runtime_stop_impl(resolved_workspace_observer_runtime);
            self.started_workspace_observer = false;
        }
        if (self.started_platform_runtime) {
            _ = platform_runtime.omni_platform_runtime_stop_impl(resolved_platform_runtime);
            self.started_platform_runtime = false;
        }
        if (self.started_wm_controller) {
            _ = wm_controller.omni_wm_controller_stop_impl(self.handles.wm_controller);
            self.started_wm_controller = false;
        }
        if (self.started_input_runtime) {
            _ = input_runtime.omni_input_runtime_stop_impl(resolved_input_runtime);
            self.started_input_runtime = false;
        }
        if (self.started_ax_runtime) {
            _ = ax_manager.omni_ax_runtime_stop_impl(resolved_ax_runtime);
            self.started_ax_runtime = false;
        }
    }
};

fn encodeControllerName(value: []const u8) abi.OmniControllerName {
    var result = abi.OmniControllerName{
        .length = @intCast(@min(value.len, abi.OMNI_CONTROLLER_NAME_CAP)),
        .bytes = [_]u8{0} ** abi.OMNI_CONTROLLER_NAME_CAP,
    };
    std.mem.copyForwards(u8, result.bytes[0..result.length], value[0..result.length]);
    return result;
}

fn runtimeFromHandle(runtime: [*c]OmniServiceLifecycle) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

fn runtimeFromUserdata(userdata: ?*anyopaque) ?*RuntimeImpl {
    const ptr = userdata orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn serviceLifecyclePlatformWindowCreatedBridge(userdata: ?*anyopaque, _: u32, _: u64) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CREATED);
    return abi.OMNI_OK;
}

fn serviceLifecyclePlatformWindowDestroyedBridge(userdata: ?*anyopaque, _: u32, _: u64) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecyclePlatformWindowClosedBridge(userdata: ?*anyopaque, _: u32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecyclePlatformWindowMovedBridge(userdata: ?*anyopaque, _: u32) callconv(.c) i32 {
    _ = userdata;
    return abi.OMNI_OK;
}

fn serviceLifecyclePlatformWindowResizedBridge(userdata: ?*anyopaque, _: u32) callconv(.c) i32 {
    _ = userdata;
    return abi.OMNI_OK;
}

fn serviceLifecyclePlatformWindowTitleChangedBridge(userdata: ?*anyopaque, _: u32) callconv(.c) i32 {
    _ = userdata;
    return abi.OMNI_OK;
}

fn serviceLifecyclePlatformFrontAppChangedBridge(userdata: ?*anyopaque, pid: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (pid > 0) {
        runtime.emitAppEvent(abi.OMNI_CONTROLLER_EVENT_APP_ACTIVATED, pid);
    }
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecycleWorkspaceAppLaunchedBridge(userdata: ?*anyopaque, _: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CREATED);
    return abi.OMNI_OK;
}

fn serviceLifecycleWorkspaceAppTerminatedBridge(userdata: ?*anyopaque, _: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecycleWorkspaceAppActivatedBridge(userdata: ?*anyopaque, pid: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (pid > 0) {
        runtime.emitAppEvent(abi.OMNI_CONTROLLER_EVENT_APP_ACTIVATED, pid);
    }
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecycleWorkspaceAppHiddenBridge(userdata: ?*anyopaque, pid: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (pid > 0) {
        runtime.emitAppEvent(abi.OMNI_CONTROLLER_EVENT_APP_HIDDEN, pid);
    }
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_APP_HIDDEN);
    return abi.OMNI_OK;
}

fn serviceLifecycleWorkspaceAppUnhiddenBridge(userdata: ?*anyopaque, pid: i32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (pid > 0) {
        runtime.emitAppEvent(abi.OMNI_CONTROLLER_EVENT_APP_UNHIDDEN, pid);
    }
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_APP_UNHIDDEN);
    return abi.OMNI_OK;
}

fn serviceLifecycleWorkspaceActiveSpaceChangedBridge(userdata: ?*anyopaque) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecycleLockObserverLockedBridge(userdata: ?*anyopaque) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitLockState(true);
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecycleLockObserverUnlockedBridge(userdata: ?*anyopaque) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitLockState(false);
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_WINDOW_CHANGED);
    return abi.OMNI_OK;
}

fn serviceLifecycleMonitorDisplaysChangedBridge(userdata: ?*anyopaque, display_id: u32, _: u32) callconv(.c) i32 {
    const runtime = runtimeFromUserdata(userdata) orelse return abi.OMNI_ERR_INVALID_ARGS;
    runtime.emitMonitorReconfigured(display_id);
    runtime.emitRefresh(abi.OMNI_CONTROLLER_REFRESH_REASON_MONITOR_RECONFIGURED);
    return abi.OMNI_OK;
}

pub fn omni_service_lifecycle_create_impl(
    config: ?*const abi.OmniServiceLifecycleConfig,
    handles: ?*const abi.OmniServiceLifecycleHandles,
    host_vtable: ?*const abi.OmniServiceLifecycleHostVTable,
) [*c]OmniServiceLifecycle {
    const resolved_handles = handles orelse return null;

    var resolved_config = abi.OmniServiceLifecycleConfig{
        .abi_version = abi.OMNI_SERVICE_LIFECYCLE_ABI_VERSION,
        .poll_ax_permission = 1,
        .request_ax_prompt = 0,
        .reserved = [_]u8{0} ** 2,
        .ax_poll_timeout_millis = 0,
        .ax_poll_interval_millis = 250,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_SERVICE_LIFECYCLE_ABI_VERSION) return null;

    const resolved_host = if (host_vtable) |raw|
        raw.*
    else
        abi.OmniServiceLifecycleHostVTable{
            .userdata = null,
            .on_state_changed = null,
            .on_error = null,
        };

    const impl = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    impl.* = .{
        .config = resolved_config,
        .handles = resolved_handles.*,
        .host = resolved_host,
    };

    return @ptrCast(impl);
}

pub fn omni_service_lifecycle_destroy_impl(runtime: [*c]OmniServiceLifecycle) void {
    const impl = runtimeFromHandle(runtime) orelse return;
    _ = impl.stop();
    impl.destroyOwnedRuntimes();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_service_lifecycle_start_impl(runtime: [*c]OmniServiceLifecycle) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.start();
}

pub fn omni_service_lifecycle_stop_impl(runtime: [*c]OmniServiceLifecycle) i32 {
    const impl = runtimeFromHandle(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}

pub fn omni_service_lifecycle_query_state_impl(
    runtime: [*c]const OmniServiceLifecycle,
    out_state: [*c]u8,
) i32 {
    if (runtime == null or out_state == null) return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *const RuntimeImpl = @ptrCast(@alignCast(runtime));
    out_state[0] = impl.state;
    return abi.OMNI_OK;
}

test "service lifecycle validates handles" {
    const runtime = omni_service_lifecycle_create_impl(null, null, null);
    try std.testing.expect(runtime == null);
}
