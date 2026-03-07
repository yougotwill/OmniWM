const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const accessibility = @import("accessibility.zig");

const c = accessibility.c;

pub const AXContext = struct {
    allocator: std.mem.Allocator,
    pid: i32,
    app_policy: i32,
    force_floating: bool,
    host: abi.OmniAXHostVTable,
    bundle_id: ?[]u8 = null,

    thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    start_mutex: std.Thread.Mutex = .{},
    start_condition: std.Thread.Condition = .{},
    start_ready: bool = false,
    start_failed: bool = false,

    state_mutex: std.Thread.Mutex = .{},
    runloop: c.CFRunLoopRef = null,
    destroy_observer: c.AXObserverRef = null,
    focus_observer: c.AXObserverRef = null,
    subscribed_window_ids: std.AutoHashMapUnmanaged(u32, void) = .{},
    suppressed_window_ids: std.AutoHashMapUnmanaged(u32, void) = .{},
    cancelled_window_ids: std.AutoHashMapUnmanaged(u32, void) = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        pid: i32,
        app_policy: i32,
        bundle_id: ?[]const u8,
        force_floating: bool,
        host: abi.OmniAXHostVTable,
    ) !*AXContext {
        const ctx = try allocator.create(AXContext);
        ctx.* = .{
            .allocator = allocator,
            .pid = pid,
            .app_policy = app_policy,
            .force_floating = force_floating,
            .host = host,
        };

        if (bundle_id) |id| {
            ctx.bundle_id = try allocator.dupe(u8, id);
        }

        return ctx;
    }

    pub fn deinit(self: *AXContext) void {
        self.stop();

        self.state_mutex.lock();
        self.subscribed_window_ids.deinit(self.allocator);
        self.suppressed_window_ids.deinit(self.allocator);
        self.cancelled_window_ids.deinit(self.allocator);
        self.state_mutex.unlock();

        if (self.bundle_id) |id| {
            self.allocator.free(id);
            self.bundle_id = null;
        }

        self.allocator.destroy(self);
    }

    pub fn start(self: *AXContext) i32 {
        if (self.running.load(.acquire)) return abi.OMNI_OK;

        self.start_mutex.lock();
        defer self.start_mutex.unlock();

        self.start_ready = false;
        self.start_failed = false;
        self.running.store(true, .release);

        self.thread = std.Thread.spawn(.{}, runThread, .{self}) catch {
            self.running.store(false, .release);
            return abi.OMNI_ERR_PLATFORM;
        };

        var waited_ms: usize = 0;
        while (!self.start_ready and !self.start_failed and waited_ms < 2000) : (waited_ms += 10) {
            self.start_condition.timedWait(&self.start_mutex, 10 * std.time.ns_per_ms) catch {};
        }

        if (!self.start_ready or self.start_failed) {
            self.running.store(false, .release);
            return abi.OMNI_ERR_PLATFORM;
        }

        return abi.OMNI_OK;
    }

    pub fn stop(self: *AXContext) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);

        self.state_mutex.lock();
        const runloop = self.runloop;
        self.state_mutex.unlock();

        if (runloop != null) {
            c.CFRunLoopStop(runloop);
        }

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    fn runThread(self: *AXContext) void {
        const app = accessibility.createApplication(self.pid);
        if (app == null) {
            self.markStartFailed();
            return;
        }

        var destroy_observer: c.AXObserverRef = null;
        if (c.AXObserverCreate(@intCast(self.pid), onWindowDestroyed, &destroy_observer) != c.kAXErrorSuccess) {
            self.markStartFailed();
            return;
        }

        var focus_observer: c.AXObserverRef = null;
        if (c.AXObserverCreate(@intCast(self.pid), onFocusedWindowChanged, &focus_observer) != c.kAXErrorSuccess) {
            accessibility.releaseCF(@ptrCast(destroy_observer));
            self.markStartFailed();
            return;
        }

        const runloop = c.CFRunLoopGetCurrent();
        c.CFRunLoopAddSource(runloop, c.AXObserverGetRunLoopSource(destroy_observer), c.kCFRunLoopDefaultMode);
        c.CFRunLoopAddSource(runloop, c.AXObserverGetRunLoopSource(focus_observer), c.kCFRunLoopDefaultMode);

        _ = c.AXObserverAddNotification(
            focus_observer,
            app,
            accessibility.axNotificationFocusedWindowChanged(),
            @ptrCast(self),
        );

        self.state_mutex.lock();
        self.runloop = runloop;
        self.destroy_observer = destroy_observer;
        self.focus_observer = focus_observer;
        self.state_mutex.unlock();

        self.markStartReady();

        while (self.running.load(.acquire)) {
            _ = c.CFRunLoopRunInMode(c.kCFRunLoopDefaultMode, 0.05, 1);
        }

        self.state_mutex.lock();
        if (self.destroy_observer != null) {
            c.CFRunLoopRemoveSource(runloop, c.AXObserverGetRunLoopSource(self.destroy_observer), c.kCFRunLoopDefaultMode);
            accessibility.releaseCF(@ptrCast(self.destroy_observer));
            self.destroy_observer = null;
        }
        if (self.focus_observer != null) {
            c.CFRunLoopRemoveSource(runloop, c.AXObserverGetRunLoopSource(self.focus_observer), c.kCFRunLoopDefaultMode);
            accessibility.releaseCF(@ptrCast(self.focus_observer));
            self.focus_observer = null;
        }
        self.runloop = null;
        self.state_mutex.unlock();
    }

    fn markStartReady(self: *AXContext) void {
        self.start_mutex.lock();
        defer self.start_mutex.unlock();
        self.start_ready = true;
        self.start_condition.signal();
    }

    fn markStartFailed(self: *AXContext) void {
        self.start_mutex.lock();
        defer self.start_mutex.unlock();
        self.start_failed = true;
        self.start_condition.signal();
    }

    fn onWindowDestroyed(
        _: c.AXObserverRef,
        element: c.AXUIElementRef,
        _: c.CFStringRef,
        refcon: ?*anyopaque,
    ) callconv(.c) void {
        const raw = refcon orelse return;
        const ctx: *AXContext = @ptrCast(@alignCast(raw));

        var pid: c.pid_t = 0;
        if (c.AXUIElementGetPid(element, &pid) != c.kAXErrorSuccess) return;

        if (ctx.host.on_window_destroyed) |callback| {
            if (accessibility.getWindowId(element)) |window_id| {
                _ = callback(ctx.host.userdata, @intCast(pid), window_id);
                return;
            }
        }

        if (ctx.host.on_window_destroyed_unknown) |callback| {
            _ = callback(ctx.host.userdata);
        }
    }

    fn onFocusedWindowChanged(
        _: c.AXObserverRef,
        element: c.AXUIElementRef,
        _: c.CFStringRef,
        refcon: ?*anyopaque,
    ) callconv(.c) void {
        const raw = refcon orelse return;
        const ctx: *AXContext = @ptrCast(@alignCast(raw));

        var pid: c.pid_t = 0;
        if (c.AXUIElementGetPid(element, &pid) != c.kAXErrorSuccess) return;

        if (ctx.host.on_focused_window_changed) |callback| {
            _ = callback(ctx.host.userdata, @intCast(pid));
        }
    }

    pub fn enumerate(self: *AXContext, out_records: *std.ArrayListUnmanaged(abi.OmniAXWindowRecord)) i32 {
        const rc = accessibility.enumerateWindowsForApp(
            self.allocator,
            self.pid,
            self.app_policy,
            self.force_floating,
            out_records,
        );
        if (rc != abi.OMNI_OK) return rc;
        self.syncDestroyedSubscriptions();
        return abi.OMNI_OK;
    }

    fn syncDestroyedSubscriptions(self: *AXContext) void {
        self.state_mutex.lock();
        const observer = self.destroy_observer;
        self.state_mutex.unlock();
        if (observer == null) return;

        const app = accessibility.createApplication(self.pid);
        if (app == null) return;

        var windows_raw: c.CFTypeRef = null;
        defer accessibility.releaseCF(windows_raw);
        if (c.AXUIElementCopyAttributeValue(app, accessibility.axAttrWindows(), &windows_raw) != c.kAXErrorSuccess) return;
        if (windows_raw == null or c.CFGetTypeID(windows_raw) != c.CFArrayGetTypeID()) return;

        const windows: c.CFArrayRef = @ptrCast(windows_raw);
        const count = c.CFArrayGetCount(windows);
        var idx: c.CFIndex = 0;
        while (idx < count) : (idx += 1) {
            const item = c.CFArrayGetValueAtIndex(windows, idx);
            if (item == null) continue;

            const element: c.AXUIElementRef = @ptrCast(@constCast(item));
            const window_id = accessibility.getWindowId(element) orelse continue;

            self.state_mutex.lock();
            const already = self.subscribed_window_ids.contains(window_id);
            self.state_mutex.unlock();
            if (already) continue;

            const add_rc = c.AXObserverAddNotification(observer, element, accessibility.axNotificationUIElementDestroyed(), @ptrCast(self));
            if (add_rc == c.kAXErrorSuccess or add_rc == c.kAXErrorNotificationAlreadyRegistered) {
                self.state_mutex.lock();
                self.subscribed_window_ids.put(self.allocator, window_id, {}) catch {};
                self.state_mutex.unlock();
            }
        }
    }

    pub fn suppress(self: *AXContext, window_id: u32) void {
        self.state_mutex.lock();
        defer self.state_mutex.unlock();
        self.suppressed_window_ids.put(self.allocator, window_id, {}) catch {};
    }

    pub fn unsuppress(self: *AXContext, window_id: u32) void {
        self.state_mutex.lock();
        defer self.state_mutex.unlock();
        _ = self.suppressed_window_ids.remove(window_id);
    }

    pub fn cancel(self: *AXContext, window_id: u32) void {
        self.state_mutex.lock();
        defer self.state_mutex.unlock();
        self.cancelled_window_ids.put(self.allocator, window_id, {}) catch {};
    }

    pub fn shouldSkipFrameApply(self: *AXContext, window_id: u32) bool {
        self.state_mutex.lock();
        defer self.state_mutex.unlock();
        if (self.suppressed_window_ids.contains(window_id)) return true;
        if (self.cancelled_window_ids.contains(window_id)) {
            _ = self.cancelled_window_ids.remove(window_id);
            return true;
        }
        return false;
    }
};
