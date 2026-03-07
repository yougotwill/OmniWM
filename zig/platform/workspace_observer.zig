const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const objc = @import("objc.zig");

pub const OmniWorkspaceObserverRuntime = abi.OmniWorkspaceObserverRuntime;

const NotificationKind = enum {
    app_launched,
    app_terminated,
    app_activated,
    app_hidden,
    app_unhidden,
};

const RuntimeImpl = struct {
    host: abi.OmniWorkspaceObserverHostVTable,
    started: bool = false,
    notification_center: objc.Id = null,
    observer: objc.Id = null,

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;

        const notification_center = workspaceNotificationCenter() orelse return abi.OMNI_ERR_PLATFORM;
        const observer_class = ensureObserverClass() orelse return abi.OMNI_ERR_PLATFORM;

        const allocated = objc.msgSend0(objc.Id, observer_class, objc.sel("alloc"));
        const observer = objc.msgSend0(objc.Id, allocated, objc.sel("init"));
        if (observer == null) return abi.OMNI_ERR_PLATFORM;

        registerObserver(notification_center, observer, "handleDidLaunchApplication:", "NSWorkspaceDidLaunchApplicationNotification");
        registerObserver(notification_center, observer, "handleDidTerminateApplication:", "NSWorkspaceDidTerminateApplicationNotification");
        registerObserver(notification_center, observer, "handleDidActivateApplication:", "NSWorkspaceDidActivateApplicationNotification");
        registerObserver(notification_center, observer, "handleDidHideApplication:", "NSWorkspaceDidHideApplicationNotification");
        registerObserver(notification_center, observer, "handleDidUnhideApplication:", "NSWorkspaceDidUnhideApplicationNotification");
        registerObserver(notification_center, observer, "handleActiveSpaceDidChange:", "NSWorkspaceActiveSpaceDidChangeNotification");

        const register_rc = registerRuntimeObserver(observer, self);
        if (register_rc != abi.OMNI_OK) {
            _ = objc.msgSend1(void, notification_center, objc.sel("removeObserver:"), observer);
            objc.release(observer);
            return register_rc;
        }

        self.notification_center = notification_center;
        self.observer = observer;
        self.started = true;
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_OK;

        unregisterRuntimeObserver(self.observer);

        if (self.notification_center != null and self.observer != null) {
            _ = objc.msgSend1(
                void,
                self.notification_center,
                objc.sel("removeObserver:"),
                self.observer,
            );
        }
        objc.release(self.observer);
        self.observer = null;
        self.notification_center = null;
        self.started = false;
        return abi.OMNI_OK;
    }

    fn dispatchPidEvent(self: *RuntimeImpl, kind: NotificationKind, pid: i32) void {
        if (!self.started or pid <= 0) return;

        switch (kind) {
            .app_launched => {
                if (self.host.on_app_launched) |callback| {
                    _ = callback(self.host.userdata, pid);
                }
            },
            .app_terminated => {
                if (self.host.on_app_terminated) |callback| {
                    _ = callback(self.host.userdata, pid);
                }
            },
            .app_activated => {
                if (self.host.on_app_activated) |callback| {
                    _ = callback(self.host.userdata, pid);
                }
            },
            .app_hidden => {
                if (self.host.on_app_hidden) |callback| {
                    _ = callback(self.host.userdata, pid);
                }
            },
            .app_unhidden => {
                if (self.host.on_app_unhidden) |callback| {
                    _ = callback(self.host.userdata, pid);
                }
            },
        }
    }

    fn dispatchActiveSpaceChanged(self: *RuntimeImpl) void {
        if (!self.started) return;
        if (self.host.on_active_space_changed) |callback| {
            _ = callback(self.host.userdata);
        }
    }
};

var g_observer_class: objc.Class = null;
var g_runtime_by_observer = std.AutoHashMapUnmanaged(usize, *RuntimeImpl){};
var g_runtime_by_observer_mutex: std.Thread.Mutex = .{};

fn ensureObserverClass() objc.Class {
    if (g_observer_class) |existing| return existing;

    const existing = objc.getClass("OmniWorkspaceObserverBridge");
    if (existing != null) {
        g_observer_class = existing;
        return existing;
    }

    const ns_object = objc.getClass("NSObject") orelse return null;
    const cls = objc.allocateClassPair(ns_object, "OmniWorkspaceObserverBridge") orelse return null;

    _ = objc.classAddMethod(
        cls,
        objc.sel("handleDidLaunchApplication:"),
        objc.toImp(handleDidLaunchApplication),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleDidTerminateApplication:"),
        objc.toImp(handleDidTerminateApplication),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleDidActivateApplication:"),
        objc.toImp(handleDidActivateApplication),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleDidHideApplication:"),
        objc.toImp(handleDidHideApplication),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleDidUnhideApplication:"),
        objc.toImp(handleDidUnhideApplication),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleActiveSpaceDidChange:"),
        objc.toImp(handleActiveSpaceDidChange),
        "v@:@",
    );

    objc.registerClassPair(cls);
    g_observer_class = cls;
    return cls;
}

fn workspaceNotificationCenter() objc.Id {
    const workspace_class = objc.getClass("NSWorkspace") orelse return null;
    const workspace = objc.msgSend0(objc.Id, workspace_class, objc.sel("sharedWorkspace"));
    if (workspace == null) return null;
    return objc.msgSend0(objc.Id, workspace, objc.sel("notificationCenter"));
}

fn registerObserver(
    notification_center: objc.Id,
    observer: objc.Id,
    selector_name: [*:0]const u8,
    notification_name: [*:0]const u8,
) void {
    if (notification_center == null or observer == null) return;
    const name = nsString(notification_name) orelse return;
    _ = objc.msgSend4(
        void,
        notification_center,
        objc.sel("addObserver:selector:name:object:"),
        observer,
        objc.sel(selector_name),
        name,
        @as(objc.Id, null),
    );
}

fn nsString(c_string: [*:0]const u8) objc.Id {
    const cls = objc.getClass("NSString") orelse return null;
    return objc.msgSend1(objc.Id, cls, objc.sel("stringWithUTF8String:"), c_string);
}

fn respondsToSelector(object: objc.Id, selector_name: [*:0]const u8) bool {
    if (object == null) return false;
    return objc.msgSend1(
        bool,
        object,
        objc.sel("respondsToSelector:"),
        objc.sel(selector_name),
    );
}

fn observerKey(observer: objc.Id) ?usize {
    if (observer == null) return null;
    return @intFromPtr(observer.?);
}

fn registerRuntimeObserver(observer: objc.Id, runtime: *RuntimeImpl) i32 {
    const key = observerKey(observer) orelse return abi.OMNI_ERR_INVALID_ARGS;
    g_runtime_by_observer_mutex.lock();
    defer g_runtime_by_observer_mutex.unlock();
    g_runtime_by_observer.put(std.heap.c_allocator, key, runtime) catch return abi.OMNI_ERR_OUT_OF_RANGE;
    return abi.OMNI_OK;
}

fn unregisterRuntimeObserver(observer: objc.Id) void {
    const key = observerKey(observer) orelse return;
    g_runtime_by_observer_mutex.lock();
    defer g_runtime_by_observer_mutex.unlock();
    _ = g_runtime_by_observer.remove(key);
}

fn runtimeForObserver(observer: objc.Id) ?*RuntimeImpl {
    const key = observerKey(observer) orelse return null;
    g_runtime_by_observer_mutex.lock();
    defer g_runtime_by_observer_mutex.unlock();
    return g_runtime_by_observer.get(key);
}

fn workspaceAppFromNotification(notification: objc.Id) objc.Id {
    if (notification == null) return null;
    const user_info = objc.msgSend0(objc.Id, notification, objc.sel("userInfo"));
    if (user_info == null) return null;
    if (!respondsToSelector(user_info, "objectForKey:")) return null;

    const app_key = nsString("NSWorkspaceApplicationKey") orelse return null;
    return objc.msgSend1(objc.Id, user_info, objc.sel("objectForKey:"), app_key);
}

fn pidFromNotification(notification: objc.Id) ?i32 {
    const app = workspaceAppFromNotification(notification);
    if (app == null) return null;
    if (!respondsToSelector(app, "processIdentifier")) return null;

    const pid = objc.msgSend0(i32, app, objc.sel("processIdentifier"));
    if (pid <= 0) return null;
    return pid;
}

fn dispatchPidEvent(kind: NotificationKind, observer: objc.Id, notification: objc.Id) void {
    const runtime = runtimeForObserver(observer) orelse return;
    const pid = pidFromNotification(notification) orelse return;
    runtime.dispatchPidEvent(kind, pid);
}

fn handleDidLaunchApplication(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    dispatchPidEvent(.app_launched, self, notification);
}

fn handleDidTerminateApplication(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    dispatchPidEvent(.app_terminated, self, notification);
}

fn handleDidActivateApplication(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    dispatchPidEvent(.app_activated, self, notification);
}

fn handleDidHideApplication(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    dispatchPidEvent(.app_hidden, self, notification);
}

fn handleDidUnhideApplication(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    dispatchPidEvent(.app_unhidden, self, notification);
}

fn handleActiveSpaceDidChange(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    _ = notification;
    const runtime = runtimeForObserver(self) orelse return;
    runtime.dispatchActiveSpaceChanged();
}

fn asImpl(runtime: [*c]OmniWorkspaceObserverRuntime) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

pub fn omni_workspace_observer_runtime_create_impl(
    config: ?*const abi.OmniWorkspaceObserverRuntimeConfig,
    host_vtable: ?*const abi.OmniWorkspaceObserverHostVTable,
) [*c]OmniWorkspaceObserverRuntime {
    const host = host_vtable orelse return null;

    var resolved_config = abi.OmniWorkspaceObserverRuntimeConfig{
        .abi_version = abi.OMNI_WORKSPACE_OBSERVER_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_WORKSPACE_OBSERVER_RUNTIME_ABI_VERSION) {
        return null;
    }

    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = .{ .host = host.* };
    return @ptrCast(runtime);
}

pub fn omni_workspace_observer_runtime_destroy_impl(runtime: [*c]OmniWorkspaceObserverRuntime) void {
    const impl = asImpl(runtime) orelse return;
    _ = impl.stop();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_workspace_observer_runtime_start_impl(runtime: [*c]OmniWorkspaceObserverRuntime) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.start();
}

pub fn omni_workspace_observer_runtime_stop_impl(runtime: [*c]OmniWorkspaceObserverRuntime) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}
