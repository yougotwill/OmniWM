const std = @import("std");
const abi = @import("../omni/abi_types.zig");
const keybindings = @import("../omni/keybindings.zig");

const c = @cImport({
    @cInclude("Carbon/Carbon.h");
});

const hotkey_signature: c.OSType = 0x4F4D4E49; // 'OMNI'

const RegisteredHotkey = struct {
    id: u32,
    ref: c.EventHotKeyRef,
    command: abi.OmniControllerCommand,
};

pub const HotkeyManager = struct {
    host: abi.OmniInputHostVTable,
    handler: c.EventHandlerRef = null,
    running: bool = false,
    bindings: std.ArrayListUnmanaged(abi.OmniInputBinding) = .{},
    registered: std.ArrayListUnmanaged(RegisteredHotkey) = .{},
    failures: std.ArrayListUnmanaged(abi.OmniInputRegistrationFailure) = .{},

    pub fn init(host: abi.OmniInputHostVTable) HotkeyManager {
        return .{ .host = host };
    }

    pub fn deinit(self: *HotkeyManager) void {
        _ = self.stop();
        self.bindings.deinit(std.heap.c_allocator);
        self.registered.deinit(std.heap.c_allocator);
        self.failures.deinit(std.heap.c_allocator);
    }

    pub fn start(self: *HotkeyManager) i32 {
        if (self.running) return abi.OMNI_OK;

        var event_spec = c.EventTypeSpec{
            .eventClass = @intCast(c.kEventClassKeyboard),
            .eventKind = @intCast(c.kEventHotKeyPressed),
        };

        const install_status = c.InstallEventHandler(
            c.GetApplicationEventTarget(),
            eventHandler,
            1,
            &event_spec,
            @ptrCast(self),
            &self.handler,
        );
        if (install_status != c.noErr or self.handler == null) {
            self.handler = null;
            return abi.OMNI_ERR_PLATFORM;
        }

        self.running = true;
        return self.registerBindings();
    }

    pub fn stop(self: *HotkeyManager) i32 {
        if (!self.running) return abi.OMNI_OK;

        self.unregisterAllHotkeys();
        if (self.handler) |handler| {
            _ = c.RemoveEventHandler(handler);
        }
        self.handler = null;
        self.running = false;
        return abi.OMNI_OK;
    }

    pub fn setBindings(
        self: *HotkeyManager,
        bindings: [*c]const abi.OmniInputBinding,
        binding_count: usize,
    ) i32 {
        if (binding_count > 0 and bindings == null) return abi.OMNI_ERR_INVALID_ARGS;

        self.bindings.clearRetainingCapacity();
        self.bindings.ensureTotalCapacityPrecise(std.heap.c_allocator, binding_count) catch {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        };

        var idx: usize = 0;
        while (idx < binding_count) : (idx += 1) {
            self.bindings.appendAssumeCapacity(bindings[idx]);
        }

        if (self.running) {
            return self.registerBindings();
        }

        self.clearFailures();
        return abi.OMNI_OK;
    }

    pub fn queryRegistrationFailures(
        self: *const HotkeyManager,
        out_failures: [*c]abi.OmniInputRegistrationFailure,
        out_capacity: usize,
        out_written: [*c]usize,
    ) i32 {
        if (out_written == null) return abi.OMNI_ERR_INVALID_ARGS;
        if (out_capacity > 0 and out_failures == null) return abi.OMNI_ERR_INVALID_ARGS;

        const count = self.failures.items.len;
        out_written[0] = count;

        const copy_count = @min(count, out_capacity);
        var idx: usize = 0;
        while (idx < copy_count) : (idx += 1) {
            out_failures[idx] = self.failures.items[idx];
        }

        return abi.OMNI_OK;
    }

    fn registerBindings(self: *HotkeyManager) i32 {
        self.unregisterAllHotkeys();
        self.clearFailures();

        var next_id: u32 = 1;
        for (self.bindings.items) |binding| {
            const enabled = binding.enabled != 0 and binding.key_code != std.math.maxInt(u32);
            if (!enabled) {
                continue;
            }

            const binding_id = bindingIdSlice(binding.binding_id);
            const mapped = keybindings.commandForBindingId(binding_id) orelse {
                self.appendFailure(binding.binding_id);
                continue;
            };

            var hotkey_ref: c.EventHotKeyRef = null;
            const hotkey_id = c.EventHotKeyID{
                .signature = hotkey_signature,
                .id = next_id,
            };
            const status = c.RegisterEventHotKey(
                binding.key_code,
                binding.modifiers,
                hotkey_id,
                c.GetApplicationEventTarget(),
                0,
                &hotkey_ref,
            );
            if (status != c.noErr or hotkey_ref == null) {
                self.appendFailure(binding.binding_id);
                next_id += 1;
                continue;
            }

            self.registered.append(std.heap.c_allocator, .{
                .id = next_id,
                .ref = hotkey_ref,
                .command = mapped,
            }) catch {
                _ = c.UnregisterEventHotKey(hotkey_ref);
                self.appendFailure(binding.binding_id);
                next_id += 1;
                continue;
            };

            next_id += 1;
        }

        return abi.OMNI_OK;
    }

    fn dispatch(self: *HotkeyManager, hotkey_id: u32) void {
        const callback = self.host.on_hotkey_command orelse return;
        for (self.registered.items) |entry| {
            if (entry.id != hotkey_id) continue;
            _ = callback(self.host.userdata, entry.command);
            return;
        }
    }

    fn unregisterAllHotkeys(self: *HotkeyManager) void {
        for (self.registered.items) |entry| {
            _ = c.UnregisterEventHotKey(entry.ref);
        }
        self.registered.clearRetainingCapacity();
    }

    fn clearFailures(self: *HotkeyManager) void {
        self.failures.clearRetainingCapacity();
    }

    fn appendFailure(self: *HotkeyManager, binding_id: abi.OmniInputBindingId) void {
        self.failures.append(std.heap.c_allocator, .{ .binding_id = binding_id }) catch {};
    }
};

fn bindingIdSlice(raw: abi.OmniInputBindingId) []const u8 {
    const len = @min(@as(usize, raw.length), abi.OMNI_INPUT_BINDING_ID_CAP);
    return raw.bytes[0..len];
}

fn eventHandler(
    next_handler: c.EventHandlerCallRef,
    event: c.EventRef,
    user_data: ?*anyopaque,
) callconv(.c) c.OSStatus {
    _ = next_handler;
    const instance_ptr = user_data orelse return c.noErr;
    const resolved_event = event orelse return c.noErr;

    const manager: *HotkeyManager = @ptrCast(@alignCast(instance_ptr));

    var hotkey_id: c.EventHotKeyID = undefined;
    const status = c.GetEventParameter(
        resolved_event,
        c.kEventParamDirectObject,
        c.typeEventHotKeyID,
        null,
        @sizeOf(c.EventHotKeyID),
        null,
        &hotkey_id,
    );
    if (status != c.noErr) return c.noErr;

    manager.dispatch(hotkey_id.id);
    return c.noErr;
}

test "hotkey manager validates failure query arguments" {
    var manager = HotkeyManager.init(.{
        .userdata = null,
        .on_hotkey_command = null,
        .on_secure_input_state_changed = null,
        .on_mouse_effect_batch = null,
        .on_tap_health_notification = null,
    });
    defer manager.deinit();
    try std.testing.expectEqual(
        @as(i32, abi.OMNI_ERR_INVALID_ARGS),
        manager.queryRegistrationFailures(null, 0, null),
    );
}
