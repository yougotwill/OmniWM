const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const accessibility = @import("accessibility.zig");
const ax_context = @import("ax_context.zig");

const c = accessibility.c;

pub const OmniAXRuntime = abi.OmniAXRuntime;

fn asNonnullPtr(comptime T: type, ptr: [*c]T) *T {
    return @ptrFromInt(@intFromPtr(ptr));
}

const RuntimeImpl = struct {
    const pending_context_wait_ms: usize = 500;

    host: abi.OmniAXHostVTable,
    started: bool = false,
    contexts: std.AutoHashMapUnmanaged(i32, *ax_context.AXContext) = .{},
    creating_pids: std.AutoHashMapUnmanaged(i32, void) = .{},
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},

    fn start(self: *RuntimeImpl) i32 {
        if (self.started) return abi.OMNI_OK;
        self.started = true;
        return abi.OMNI_OK;
    }

    fn stop(self: *RuntimeImpl) i32 {
        if (!self.started) return abi.OMNI_OK;

        self.mutex.lock();
        var it = self.contexts.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.contexts.clearAndFree(std.heap.c_allocator);
        self.creating_pids.clearAndFree(std.heap.c_allocator);
        self.started = false;
        self.mutex.unlock();

        return abi.OMNI_OK;
    }

    fn trackApp(self: *RuntimeImpl, pid: i32, app_policy: i32, bundle_id: [*c]const u8, force_floating: u8) i32 {
        if (pid <= 0) return abi.OMNI_ERR_INVALID_ARGS;

        self.mutex.lock();
        if (self.contexts.contains(pid)) {
            self.mutex.unlock();
            return abi.OMNI_OK;
        }
        if (self.creating_pids.contains(pid)) {
            var waited_ms: usize = 0;
            while (!self.contexts.contains(pid) and self.creating_pids.contains(pid) and waited_ms < pending_context_wait_ms) : (waited_ms += 10) {
                self.condition.timedWait(&self.mutex, 10 * std.time.ns_per_ms) catch {};
            }
            if (self.contexts.contains(pid)) {
                self.mutex.unlock();
                return abi.OMNI_OK;
            }
            if (self.creating_pids.contains(pid)) {
                self.mutex.unlock();
                return abi.OMNI_OK;
            }
        }
        self.creating_pids.put(std.heap.c_allocator, pid, {}) catch {
            self.mutex.unlock();
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };
        self.mutex.unlock();

        var bundle_slice: ?[]const u8 = null;
        if (bundle_id != null) {
            bundle_slice = std.mem.span(bundle_id);
        }

        const ctx = ax_context.AXContext.init(
            std.heap.c_allocator,
            pid,
            app_policy,
            bundle_slice,
            force_floating == 1,
            self.host,
        ) catch {
            self.mutex.lock();
            _ = self.creating_pids.remove(pid);
            self.condition.broadcast();
            self.mutex.unlock();
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };

        const start_rc = ctx.start();
        if (start_rc != abi.OMNI_OK) {
            ctx.deinit();
            self.mutex.lock();
            _ = self.creating_pids.remove(pid);
            self.condition.broadcast();
            self.mutex.unlock();
            return start_rc;
        }

        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.creating_pids.remove(pid);
        self.contexts.put(std.heap.c_allocator, pid, ctx) catch {
            self.condition.broadcast();
            ctx.deinit();
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };
        self.condition.broadcast();
        return abi.OMNI_OK;
    }

    fn untrackApp(self: *RuntimeImpl, pid: i32) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ctx = self.contexts.get(pid) orelse return abi.OMNI_OK;
        _ = self.contexts.remove(pid);
        ctx.deinit();
        return abi.OMNI_OK;
    }

    fn enumerateWindows(
        self: *RuntimeImpl,
        out_windows: [*c]abi.OmniAXWindowRecord,
        out_capacity: usize,
        out_written: [*c]usize,
    ) i32 {
        if (out_written == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (out_capacity > 0 and out_windows == null) return abi.OMNI_ERR_INVALID_ARGS;

        out_written[0] = 0;

        var collected = std.ArrayListUnmanaged(abi.OmniAXWindowRecord){};
        defer collected.deinit(std.heap.c_allocator);

        self.mutex.lock();
        var it = self.contexts.iterator();
        while (it.next()) |entry| {
            const rc = entry.value_ptr.*.enumerate(&collected);
            if (rc != abi.OMNI_OK) {
                self.mutex.unlock();
                return rc;
            }
        }
        self.mutex.unlock();

        var written: usize = 0;
        for (collected.items) |record| {
            if (written < out_capacity) {
                out_windows[written] = record;
            }
            written += 1;
        }

        out_written[0] = written;
        return abi.OMNI_OK;
    }

    fn withContext(self: *RuntimeImpl, pid: i32, callback: *const fn (*ax_context.AXContext) i32) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ctx = self.contexts.get(pid) orelse return abi.OMNI_ERR_PLATFORM;
        return callback(ctx);
    }

    fn applyFramesBatch(self: *RuntimeImpl, requests: [*c]const abi.OmniAXFrameRequest, request_count: usize) i32 {
        if (request_count == 0) return abi.OMNI_OK;
        if (requests == null) return abi.OMNI_ERR_INVALID_ARGS;

        var idx: usize = 0;
        while (idx < request_count) : (idx += 1) {
            const request = requests[idx];
            const rc = self.setWindowFrame(request.pid, request.window_id, &request.frame);
            if (rc != abi.OMNI_OK) return rc;
        }

        return abi.OMNI_OK;
    }

    fn cancelFrameJobs(self: *RuntimeImpl, keys: [*c]const abi.OmniAXWindowKey, key_count: usize) i32 {
        if (key_count == 0) return abi.OMNI_OK;
        if (keys == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.mutex.lock();
        defer self.mutex.unlock();

        var idx: usize = 0;
        while (idx < key_count) : (idx += 1) {
            const key = keys[idx];
            if (self.contexts.get(key.pid)) |ctx| {
                ctx.cancel(key.window_id);
            }
        }
        return abi.OMNI_OK;
    }

    fn suppressFrameWrites(self: *RuntimeImpl, keys: [*c]const abi.OmniAXWindowKey, key_count: usize) i32 {
        if (key_count == 0) return abi.OMNI_OK;
        if (keys == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.mutex.lock();
        defer self.mutex.unlock();

        var idx: usize = 0;
        while (idx < key_count) : (idx += 1) {
            const key = keys[idx];
            if (self.contexts.get(key.pid)) |ctx| {
                ctx.suppress(key.window_id);
            }
        }
        return abi.OMNI_OK;
    }

    fn unsuppressFrameWrites(self: *RuntimeImpl, keys: [*c]const abi.OmniAXWindowKey, key_count: usize) i32 {
        if (key_count == 0) return abi.OMNI_OK;
        if (keys == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.mutex.lock();
        defer self.mutex.unlock();

        var idx: usize = 0;
        while (idx < key_count) : (idx += 1) {
            const key = keys[idx];
            if (self.contexts.get(key.pid)) |ctx| {
                ctx.unsuppress(key.window_id);
            }
        }
        return abi.OMNI_OK;
    }

    fn getWindowFrame(self: *RuntimeImpl, pid: i32, window_id: u32, out_rect: [*c]abi.OmniBorderRect) i32 {
        if (out_rect == null) return abi.OMNI_ERR_INVALID_ARGS;

        const Ctx = struct {
            out_rect: *abi.OmniBorderRect,
        };

        var ctx = Ctx{ .out_rect = asNonnullPtr(abi.OmniBorderRect, out_rect) };
        const callback = struct {
            fn run(element: accessibility.AXElementRef, userdata: ?*anyopaque) i32 {
                const op: *Ctx = @ptrCast(@alignCast(userdata.?));
                return accessibility.getFrameWindowServer(element, op.out_rect);
            }
        }.run;

        _ = self;
        return accessibility.withWindowElementById(pid, window_id, callback, @ptrCast(&ctx));
    }

    fn setWindowFrame(self: *RuntimeImpl, pid: i32, window_id: u32, frame: [*c]const abi.OmniBorderRect) i32 {
        if (frame == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.mutex.lock();
        const maybe_ctx = self.contexts.get(pid);
        self.mutex.unlock();

        if (maybe_ctx) |ctx_ref| {
            if (ctx_ref.shouldSkipFrameApply(window_id)) return abi.OMNI_OK;
        }

        const Ctx = struct {
            rect: abi.OmniBorderRect,
        };

        var op_ctx = Ctx{ .rect = frame[0] };
        const callback = struct {
            fn run(element: accessibility.AXElementRef, userdata: ?*anyopaque) i32 {
                const op: *Ctx = @ptrCast(@alignCast(userdata.?));
                return accessibility.setFrameWindowServer(element, op.rect);
            }
        }.run;

        return accessibility.withWindowElementById(pid, window_id, callback, @ptrCast(&op_ctx));
    }

    fn getWindowType(self: *RuntimeImpl, request: [*c]const abi.OmniAXWindowTypeRequest, out_type: [*c]u8) i32 {
        if (request == null or out_type == null) return abi.OMNI_ERR_INVALID_ARGS;

        const Ctx = struct {
            app_policy: i32,
            force_floating: bool,
            out_type: *u8,
        };

        var op_ctx = Ctx{
            .app_policy = request[0].app_policy,
            .force_floating = request[0].force_floating == 1,
            .out_type = asNonnullPtr(u8, out_type),
        };

        const callback = struct {
            fn run(element: accessibility.AXElementRef, userdata: ?*anyopaque) i32 {
                const op: *Ctx = @ptrCast(@alignCast(userdata.?));
                op.out_type.* = accessibility.classifyWindow(element, op.app_policy, op.force_floating);
                return abi.OMNI_OK;
            }
        }.run;

        _ = self;
        return accessibility.withWindowElementById(request[0].pid, request[0].window_id, callback, @ptrCast(&op_ctx));
    }

    fn isWindowFullscreen(self: *RuntimeImpl, pid: i32, window_id: u32, out_fullscreen: [*c]u8) i32 {
        if (out_fullscreen == null) return abi.OMNI_ERR_INVALID_ARGS;

        const Ctx = struct {
            out_fullscreen: *u8,
        };

        var op_ctx = Ctx{ .out_fullscreen = asNonnullPtr(u8, out_fullscreen) };
        const callback = struct {
            fn run(element: accessibility.AXElementRef, userdata: ?*anyopaque) i32 {
                const op: *Ctx = @ptrCast(@alignCast(userdata.?));
                return accessibility.isFullscreen(element, op.out_fullscreen);
            }
        }.run;

        _ = self;
        return accessibility.withWindowElementById(pid, window_id, callback, @ptrCast(&op_ctx));
    }

    fn setWindowFullscreen(self: *RuntimeImpl, pid: i32, window_id: u32, fullscreen: u8) i32 {
        const Ctx = struct {
            fullscreen: bool,
        };

        var op_ctx = Ctx{ .fullscreen = fullscreen == 1 };
        const callback = struct {
            fn run(element: accessibility.AXElementRef, userdata: ?*anyopaque) i32 {
                const op: *Ctx = @ptrCast(@alignCast(userdata.?));
                return accessibility.setFullscreen(element, op.fullscreen);
            }
        }.run;

        _ = self;
        return accessibility.withWindowElementById(pid, window_id, callback, @ptrCast(&op_ctx));
    }

    fn getWindowConstraints(self: *RuntimeImpl, pid: i32, window_id: u32, out_constraints: [*c]abi.OmniAXWindowConstraints) i32 {
        if (out_constraints == null) return abi.OMNI_ERR_INVALID_ARGS;

        const Ctx = struct {
            out_constraints: *abi.OmniAXWindowConstraints,
        };

        var op_ctx = Ctx{ .out_constraints = asNonnullPtr(abi.OmniAXWindowConstraints, out_constraints) };
        const callback = struct {
            fn run(element: accessibility.AXElementRef, userdata: ?*anyopaque) i32 {
                const op: *Ctx = @ptrCast(@alignCast(userdata.?));
                return accessibility.getConstraints(element, op.out_constraints);
            }
        }.run;

        _ = self;
        return accessibility.withWindowElementById(pid, window_id, callback, @ptrCast(&op_ctx));
    }
};

fn asImpl(runtime: [*c]OmniAXRuntime) ?*RuntimeImpl {
    if (runtime == null) return null;
    return @ptrCast(@alignCast(runtime));
}

pub fn omni_ax_runtime_create_impl(
    config: ?*const abi.OmniAXRuntimeConfig,
    host_vtable: ?*const abi.OmniAXHostVTable,
) [*c]OmniAXRuntime {
    const host = host_vtable orelse return null;

    var resolved_config = abi.OmniAXRuntimeConfig{
        .abi_version = abi.OMNI_AX_RUNTIME_ABI_VERSION,
        .reserved = 0,
    };
    if (config) |raw| {
        resolved_config = raw.*;
    }
    if (resolved_config.abi_version != abi.OMNI_AX_RUNTIME_ABI_VERSION) return null;

    const runtime = std.heap.c_allocator.create(RuntimeImpl) catch return null;
    runtime.* = .{ .host = host.* };
    return @ptrCast(runtime);
}

pub fn omni_ax_runtime_destroy_impl(runtime: [*c]OmniAXRuntime) void {
    const impl = asImpl(runtime) orelse return;
    _ = impl.stop();
    std.heap.c_allocator.destroy(impl);
}

pub fn omni_ax_runtime_start_impl(runtime: [*c]OmniAXRuntime) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.start();
}

pub fn omni_ax_runtime_stop_impl(runtime: [*c]OmniAXRuntime) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.stop();
}

pub fn omni_ax_runtime_track_app_impl(runtime: [*c]OmniAXRuntime, pid: i32, app_policy: i32, bundle_id: [*c]const u8, force_floating: u8) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.trackApp(pid, app_policy, bundle_id, force_floating);
}

pub fn omni_ax_runtime_untrack_app_impl(runtime: [*c]OmniAXRuntime, pid: i32) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.untrackApp(pid);
}

pub fn omni_ax_runtime_enumerate_windows_impl(
    runtime: [*c]OmniAXRuntime,
    out_windows: [*c]abi.OmniAXWindowRecord,
    out_capacity: usize,
    out_written: [*c]usize,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.enumerateWindows(out_windows, out_capacity, out_written);
}

pub fn omni_ax_runtime_apply_frames_batch_impl(
    runtime: [*c]OmniAXRuntime,
    requests: [*c]const abi.OmniAXFrameRequest,
    request_count: usize,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.applyFramesBatch(requests, request_count);
}

pub fn omni_ax_runtime_cancel_frame_jobs_impl(
    runtime: [*c]OmniAXRuntime,
    keys: [*c]const abi.OmniAXWindowKey,
    key_count: usize,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.cancelFrameJobs(keys, key_count);
}

pub fn omni_ax_runtime_suppress_frame_writes_impl(
    runtime: [*c]OmniAXRuntime,
    keys: [*c]const abi.OmniAXWindowKey,
    key_count: usize,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.suppressFrameWrites(keys, key_count);
}

pub fn omni_ax_runtime_unsuppress_frame_writes_impl(
    runtime: [*c]OmniAXRuntime,
    keys: [*c]const abi.OmniAXWindowKey,
    key_count: usize,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.unsuppressFrameWrites(keys, key_count);
}

pub fn omni_ax_runtime_get_window_frame_impl(
    runtime: [*c]OmniAXRuntime,
    pid: i32,
    window_id: u32,
    out_rect: [*c]abi.OmniBorderRect,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.getWindowFrame(pid, window_id, out_rect);
}

pub fn omni_ax_runtime_set_window_frame_impl(
    runtime: [*c]OmniAXRuntime,
    pid: i32,
    window_id: u32,
    frame: [*c]const abi.OmniBorderRect,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.setWindowFrame(pid, window_id, frame);
}

pub fn omni_ax_runtime_get_window_type_impl(
    runtime: [*c]OmniAXRuntime,
    request: [*c]const abi.OmniAXWindowTypeRequest,
    out_type: [*c]u8,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.getWindowType(request, out_type);
}

pub fn omni_ax_runtime_is_window_fullscreen_impl(
    runtime: [*c]OmniAXRuntime,
    pid: i32,
    window_id: u32,
    out_fullscreen: [*c]u8,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.isWindowFullscreen(pid, window_id, out_fullscreen);
}

pub fn omni_ax_runtime_set_window_fullscreen_impl(
    runtime: [*c]OmniAXRuntime,
    pid: i32,
    window_id: u32,
    fullscreen: u8,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.setWindowFullscreen(pid, window_id, fullscreen);
}

pub fn omni_ax_runtime_get_window_constraints_impl(
    runtime: [*c]OmniAXRuntime,
    pid: i32,
    window_id: u32,
    out_constraints: [*c]abi.OmniAXWindowConstraints,
) i32 {
    const impl = asImpl(runtime) orelse return abi.OMNI_ERR_INVALID_ARGS;
    return impl.getWindowConstraints(pid, window_id, out_constraints);
}
