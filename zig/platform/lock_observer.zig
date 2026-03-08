const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const objc = @import("objc.zig");

pub const OmniLockObserverRuntime = abi.OmniLockObserverRuntime;

const lock_screen_bundle_id = "com.apple.loginwindow";

const RuntimeImpl = struct {
    host: abi.OmniLockObserverHostVTable,
    started: bool = false,
    lock_active: bool = false,
    distributed_notification_center: objc.Id = null,
    workspace_notification_center: objc.Id = null,
    observer: objc.Id = null,

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;

        const distributed_center = distributedNotificationCenter() orelse return abi.OMNI_ERR_PLATFORM;
        const workspace_center = workspaceNotificationCenter() orelse return abi.OMNI_ERR_PLATFORM;
        const observer_class = ensureObserverClass() orelse return abi.OMNI_ERR_PLATFORM;

        const allocated = objc.msgSend0(objc.Id, observer_class, objc.sel("alloc"));
        const observer = objc.msgSend0(objc.Id, allocated, objc.sel("init"));
        if (observer == null) return abi.OMNI_ERR_PLATFORM;

        registerObserver(distributed_center, observer, "handleScreenLocked:", "com.apple.screenIsLocked");
        registerObserver(distributed_center, observer, "handleScreenUnlocked:", "com.apple.screenIsUnlocked");
        registerObserver(workspace_center, observer, "handleDidActivateApplication:", "NSWorkspaceDidActivateApplicationNotification");

        const register_rc = registerRuntimeObserver(observer, self);
        if (register_rc != abi.OMNI_OK) {
            _ = objc.msgSend1(void, distributed_center, objc.sel("removeObserver:"), observer);
            _ = objc.msgSend1(void, workspace_center, objc.sel("removeObserver:"), observer);
            objc.release(observer);
            return register_rc;
        }

        self.distributed_notification_center = distributed_center;
        self.workspace_notification_center = workspace_center;
        self.observer = observer;
        self.lock_active = isFrontmostLockScreen();
        self.started = true;
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_OK;

        unregisterRuntimeObserver(self.observer);

        if (self.distributed_notification_center != null and self.observer != null) {
            _ = objc.msgSend1(
                void,
                self.distributed_notification_center,
                objc.sel("removeObserver:"),
                self.observer,
            );
        }
        if (self.workspace_notification_center != null and self.observer != null) {
            _ = objc.msgSend1(
                void,
                self.workspace_notification_center,
                objc.sel("removeObserver:"),
                self.observer,
            );
        }

        objc.release(self.observer);
        self.observer = null;
        self.distributed_notification_center = null;
        self.workspace_notification_center = null;
        self.started = false;
        self.lock_active = false;
        return abi.OMNI_OK;
    }

    fn applyLockState(self: *RuntimeImpl, locked: bool) void {
        if (!self.started) return;
        if (self.lock_active == locked) return;

        self.lock_active = locked;
        if (locked) {
            if (self.host.on_locked) |callback| {
                _ = callback(self.host.userdata);
            }
        } else {
            if (self.host.on_unlocked) |callback| {
                _ = callback(self.host.userdata);
            }
        }
    }

    fn handleLockHint(self: *RuntimeImpl) void {
        if (isFrontmostLockScreen()) {
            self.applyLockState(true);
        }
    }

    fn handleUnlockHint(self: *RuntimeImpl) void {
        if (!isFrontmostLockScreen()) {
            self.applyLockState(false);
        }
    }

    fn reconcileActivation(self: *RuntimeImpl, bundle_id: ?[]const u8) void {
        if (bundle_id) |bundle| {
            if (std.mem.eql(u8, bundle, lock_screen_bundle_id)) {
                self.applyLockState(true);
                return;
            }
        }
        if (self.lock_active) {
            self.applyLockState(false);
        }
    }
};

var g_observer_class: objc.Class = null;
var g_runtime_by_observer = std.AutoHashMapUnmanaged(usize, *RuntimeImpl){};
var g_runtime_by_observer_mutex: std.Thread.Mutex = .{};

fn ensureObserverClass() objc.Class {
    if (g_observer_class) |existing| return existing;

    const existing = objc.getClass("OmniLockObserverBridge");
    if (existing != null) {
        g_observer_class = existing;
        return existing;
    }

    const ns_object = objc.getClass("NSObject") orelse return null;
    const cls = objc.allocateClassPair(ns_object, "OmniLockObserverBridge") orelse return null;

    _ = objc.classAddMethod(
        cls,
        objc.sel("handleScreenLocked:"),
        objc.toImp(handleScreenLocked),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleScreenUnlocked:"),
        objc.toImp(handleScreenUnlocked),
        "v@:@",
    );
    _ = objc.classAddMethod(
        cls,
        objc.sel("handleDidActivateApplication:"),
        objc.toImp(handleDidActivateApplication),
        "v@:@",
    );

    objc.registerClassPair(cls);
    g_observer_class = cls;
    return cls;
}

fn distributedNotificationCenter() objc.Id {
    const cls = objc.getClass("NSDistributedNotificationCenter") orelse return null;
    return objc.msgSend0(objc.Id, cls, objc.sel("defaultCenter"));
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

fn utf8Slice(ns_string: objc.Id) ?[]const u8 {
    if (ns_string == null) return null;
    if (!respondsToSelector(ns_string, "UTF8String")) return null;

    const utf8_ptr_opt = objc.msgSend0(?[*:0]const u8, ns_string, objc.sel("UTF8String"));
    const utf8_ptr = utf8_ptr_opt orelse return null;
    return std.mem.span(utf8_ptr);
}

fn workspaceAppFromNotification(notification: objc.Id) objc.Id {
    if (notification == null) return null;

    const user_info = objc.msgSend0(objc.Id, notification, objc.sel("userInfo"));
    if (user_info == null) return null;
    if (!respondsToSelector(user_info, "objectForKey:")) return null;

    const app_key = nsString("NSWorkspaceApplicationKey") orelse return null;
    return objc.msgSend1(objc.Id, user_info, objc.sel("objectForKey:"), app_key);
}

fn bundleIdFromNotification(notification: objc.Id) ?[]const u8 {
    const app = workspaceAppFromNotification(notification);
    if (app == null) return null;
    if (!respondsToSelector(app, "bundleIdentifier")) return null;

    const bundle_id_obj = objc.msgSend0(objc.Id, app, objc.sel("bundleIdentifier"));
    return utf8Slice(bundle_id_obj);
}

fn isFrontmostLockScreen() bool {
    const workspace_class = objc.getClass("NSWorkspace") orelse return false;
    const workspace = objc.msgSend0(objc.Id, workspace_class, objc.sel("sharedWorkspace"));
    if (workspace == null) return false;
    if (!respondsToSelector(workspace, "frontmostApplication")) return false;

    const app = objc.msgSend0(objc.Id, workspace, objc.sel("frontmostApplication"));
    if (app == null) return false;
    if (!respondsToSelector(app, "bundleIdentifier")) return false;

    const bundle_id_obj = objc.msgSend0(objc.Id, app, objc.sel("bundleIdentifier"));
    const bundle = utf8Slice(bundle_id_obj) orelse return false;
    return std.mem.eql(u8, bundle, lock_screen_bundle_id);
}

fn handleScreenLocked(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    _ = notification;
    const runtime = runtimeForObserver(self) orelse return;
    runtime.handleLockHint();
}

fn handleScreenUnlocked(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    _ = notification;
    const runtime = runtimeForObserver(self) orelse return;
    runtime.handleUnlockHint();
}

fn handleDidActivateApplication(self: objc.Id, _: objc.Sel, notification: objc.Id) callconv(.c) void {
    const runtime = runtimeForObserver(self) orelse return;
    runtime.reconcileActivation(bundleIdFromNotification(notification));
}

fn asImpl(runtime: [*c]OmniLockObserverRuntime) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

pub fn omni_lock_observer_runtime_create_impl(
    config: ?*const abi.OmniLockObserverRuntimeConfig,
    host_vtable: ?*const abi.OmniLockObserverHostVTable,
) [*c]OmniLockObserverRuntime {
    const host = host_vtable orelse return null;

    var resolved_config = abi.OmniLockObserverRuntimeConfig{
        .abi_version = abi.OMNI_LOCK_OBSERVER_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_LOCK_OBSERVER_RUNTIME_ABI_VERSION) {
        return null;
    }

    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = .{ .host = host.* };
    return @ptrCast(runtime);
}

pub fn omni_lock_observer_runtime_destroy_impl(runtime: [*c]OmniLockObserverRuntime) void {
    const impl = asImpl(runtime) orelse return;
    _ = impl.stop();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_lock_observer_runtime_start_impl(runtime: [*c]OmniLockObserverRuntime) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.start();
}

pub fn omni_lock_observer_runtime_stop_impl(runtime: [*c]OmniLockObserverRuntime) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}

pub fn omni_lock_observer_runtime_query_locked_impl(
    runtime: [*c]const OmniLockObserverRuntime,
    out_locked: ?*u8,
) i32 {
    if (runtime == null) return abi.OMNI_ERR_INVALID_ARGS;
    const resolved_out = out_locked orelse return abi.OMNI_ERR_INVALID_ARGS;
    const impl: *const RuntimeImpl = @ptrCast(@alignCast(runtime));
    resolved_out.* = if (impl.lock_active) 1 else 0;
    return abi.OMNI_OK;
}
