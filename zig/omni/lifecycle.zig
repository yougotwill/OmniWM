const types = @import("controller_types.zig");

pub fn applySecureInput(state: *types.RuntimeState, enabled: bool) void {
    state.secure_input_active = enabled;
}

pub fn applyLockScreen(state: *types.RuntimeState, enabled: bool) void {
    state.lock_screen_active = enabled;
}
