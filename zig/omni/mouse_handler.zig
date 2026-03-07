const std = @import("std");
const abi = @import("abi_types.zig");

pub const GesturePhase = enum(u8) {
    idle = 0,
    armed = 1,
    committed = 2,
};

pub const MouseHandlerConfig = struct {
    focus_follows_mouse_debounce_ms: u32 = 120,
    drag_threshold_points: f64 = 6.0,
};

pub const MouseAction = union(enum) {
    none,
    focus_follows_mouse,
    begin_drag,
    update_drag,
    end_drag,
    scroll,
    gesture,
};

pub fn earlyExitAction(phase: GesturePhase) MouseAction {
    return switch (phase) {
        .idle => .none,
        .armed => .none,
        .committed => .end_drag,
    };
}

pub const MouseHandler = struct {
    config: MouseHandlerConfig,
    phase: GesturePhase = .idle,
    last_move_millis: u64 = 0,
    drag_origin_x: f64 = 0,
    drag_origin_y: f64 = 0,
    dragging: bool = false,

    pub fn init(config: MouseHandlerConfig) MouseHandler {
        return .{ .config = config };
    }

    pub fn reset(self: *MouseHandler) void {
        self.phase = .idle;
        self.dragging = false;
        self.drag_origin_x = 0;
        self.drag_origin_y = 0;
        self.last_move_millis = 0;
    }

    pub fn handleInputEvent(self: *MouseHandler, event: abi.OmniInputEvent, now_millis: u64) MouseAction {
        switch (event.kind) {
            abi.OMNI_INPUT_EVENT_MOUSE_MOVED => {
                return self.handleMove(now_millis);
            },
            abi.OMNI_INPUT_EVENT_LEFT_MOUSE_DOWN => {
                self.phase = .armed;
                self.drag_origin_x = event.location_x;
                self.drag_origin_y = event.location_y;
                self.dragging = false;
                return .none;
            },
            abi.OMNI_INPUT_EVENT_LEFT_MOUSE_DRAGGED => {
                if (self.phase == .idle) return .none;
                const dx = event.location_x - self.drag_origin_x;
                const dy = event.location_y - self.drag_origin_y;
                const distance = std.math.sqrt((dx * dx) + (dy * dy));

                if (!self.dragging and distance >= self.config.drag_threshold_points) {
                    self.dragging = true;
                    self.phase = .committed;
                    return .begin_drag;
                }
                return if (self.dragging) .update_drag else .none;
            },
            abi.OMNI_INPUT_EVENT_LEFT_MOUSE_UP => {
                const was_dragging = self.dragging;
                self.phase = .idle;
                self.dragging = false;
                return if (was_dragging) .end_drag else .none;
            },
            abi.OMNI_INPUT_EVENT_SCROLL_WHEEL => {
                return .scroll;
            },
            abi.OMNI_INPUT_EVENT_GESTURE => {
                return .gesture;
            },
            else => return .none,
        }
    }

    fn handleMove(self: *MouseHandler, now_millis: u64) MouseAction {
        const debounce = @as(u64, self.config.focus_follows_mouse_debounce_ms);
        if (self.last_move_millis == 0 or now_millis - self.last_move_millis >= debounce) {
            self.last_move_millis = now_millis;
            return .focus_follows_mouse;
        }
        self.last_move_millis = now_millis;
        return .none;
    }
};

test "mouse handler debounces focus-follows-mouse" {
    var handler = MouseHandler.init(.{ .focus_follows_mouse_debounce_ms = 100 });
    var event = std.mem.zeroes(abi.OmniInputEvent);
    event.kind = abi.OMNI_INPUT_EVENT_MOUSE_MOVED;

    try std.testing.expectEqual(MouseAction.focus_follows_mouse, handler.handleInputEvent(event, 10));
    try std.testing.expectEqual(MouseAction.none, handler.handleInputEvent(event, 50));
    try std.testing.expectEqual(MouseAction.focus_follows_mouse, handler.handleInputEvent(event, 200));
}

test "mouse handler drag lifecycle" {
    var handler = MouseHandler.init(.{ .drag_threshold_points = 5.0 });

    var down = std.mem.zeroes(abi.OmniInputEvent);
    down.kind = abi.OMNI_INPUT_EVENT_LEFT_MOUSE_DOWN;
    down.location_x = 100;
    down.location_y = 100;

    _ = handler.handleInputEvent(down, 0);

    var drag = std.mem.zeroes(abi.OmniInputEvent);
    drag.kind = abi.OMNI_INPUT_EVENT_LEFT_MOUSE_DRAGGED;
    drag.location_x = 108;
    drag.location_y = 100;

    try std.testing.expectEqual(MouseAction.begin_drag, handler.handleInputEvent(drag, 1));
    try std.testing.expectEqual(MouseAction.update_drag, handler.handleInputEvent(drag, 2));

    var up = std.mem.zeroes(abi.OmniInputEvent);
    up.kind = abi.OMNI_INPUT_EVENT_LEFT_MOUSE_UP;
    try std.testing.expectEqual(MouseAction.end_drag, handler.handleInputEvent(up, 3));
}

test "early exit only emits action for committed phase" {
    try std.testing.expectEqual(MouseAction.none, earlyExitAction(.idle));
    try std.testing.expectEqual(MouseAction.none, earlyExitAction(.armed));
    try std.testing.expectEqual(MouseAction.end_drag, earlyExitAction(.committed));
}
