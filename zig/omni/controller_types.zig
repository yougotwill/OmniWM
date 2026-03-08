const std = @import("std");
const abi = @import("abi_types.zig");

pub const Uuid = [16]u8;
pub const NameBytes = [abi.OMNI_CONTROLLER_NAME_CAP]u8;

pub const LayoutKind = enum(u8) {
    default_layout = abi.OMNI_CONTROLLER_LAYOUT_DEFAULT,
    niri = abi.OMNI_CONTROLLER_LAYOUT_NIRI,
    dwindle = abi.OMNI_CONTROLLER_LAYOUT_DWINDLE,
};

pub const Monitor = struct {
    display_id: u32,
    is_main: bool,
    frame_x: f64,
    frame_y: f64,
    frame_width: f64,
    frame_height: f64,
    visible_x: f64,
    visible_y: f64,
    visible_width: f64,
    visible_height: f64,
    name: abi.OmniControllerName,
};

pub const Workspace = struct {
    workspace_id: Uuid,
    assigned_display_id: ?u32,
    is_visible: bool,
    is_previous_visible: bool,
    layout_kind: LayoutKind,
    name: abi.OmniControllerName,
    selected_node_id: ?Uuid,
    last_focused_window_id: ?Uuid,
};

pub const Window = struct {
    handle_id: Uuid,
    pid: i32,
    window_id: i64,
    workspace_id: Uuid,
    layout_kind: LayoutKind,
    is_hidden: bool,
    is_focused: bool,
    is_managed: bool,
    node_id: ?Uuid,
    column_id: ?Uuid,
    order_index: i64,
    column_index: i64,
    row_index: i64,
};

pub const ControllerEffects = struct {
    focus_exports: std.ArrayListUnmanaged(abi.OmniControllerFocusExport) = .{},
    route_plans: std.ArrayListUnmanaged(abi.OmniControllerRoutePlan) = .{},
    transfer_plans: std.ArrayListUnmanaged(abi.OmniControllerTransferPlan) = .{},
    refresh_plans: std.ArrayListUnmanaged(abi.OmniControllerRefreshPlan) = .{},
    ui_actions: std.ArrayListUnmanaged(abi.OmniControllerUiAction) = .{},
    layout_actions: std.ArrayListUnmanaged(abi.OmniControllerLayoutAction) = .{},

    pub fn deinit(self: *ControllerEffects, allocator: std.mem.Allocator) void {
        self.focus_exports.deinit(allocator);
        self.route_plans.deinit(allocator);
        self.transfer_plans.deinit(allocator);
        self.refresh_plans.deinit(allocator);
        self.ui_actions.deinit(allocator);
        self.layout_actions.deinit(allocator);
        self.* = .{};
    }

    pub fn clear(self: *ControllerEffects) void {
        self.focus_exports.items.len = 0;
        self.route_plans.items.len = 0;
        self.transfer_plans.items.len = 0;
        self.refresh_plans.items.len = 0;
        self.ui_actions.items.len = 0;
        self.layout_actions.items.len = 0;
    }
};

pub const RuntimeState = struct {
    allocator: std.mem.Allocator,
    monitors: std.ArrayListUnmanaged(Monitor) = .{},
    workspaces: std.ArrayListUnmanaged(Workspace) = .{},
    windows: std.ArrayListUnmanaged(Window) = .{},
    last_focused_by_workspace: std.AutoHashMap(Uuid, Uuid),
    selected_node_by_workspace: std.AutoHashMap(Uuid, Uuid),
    focus_history_by_workspace: std.AutoHashMap(Uuid, std.ArrayListUnmanaged(Uuid)),
    focused_window: ?Uuid = null,
    active_monitor: ?u32 = null,
    previous_monitor: ?u32 = null,
    secure_input_active: bool = false,
    lock_screen_active: bool = false,
    non_managed_focus_active: bool = false,
    app_fullscreen_active: bool = false,
    focus_follows_window_to_monitor: bool = false,
    move_mouse_to_focused_window: bool = false,
    layout_light_session_active: bool = false,
    layout_immediate_in_progress: bool = false,
    layout_incremental_in_progress: bool = false,
    layout_full_enumeration_in_progress: bool = false,
    layout_animation_active: bool = false,
    layout_has_completed_initial_refresh: bool = false,
    effects: ControllerEffects = .{},

    pub fn init(allocator: std.mem.Allocator) RuntimeState {
        return .{
            .allocator = allocator,
            .last_focused_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
            .selected_node_by_workspace = std.AutoHashMap(Uuid, Uuid).init(allocator),
            .focus_history_by_workspace = std.AutoHashMap(Uuid, std.ArrayListUnmanaged(Uuid)).init(allocator),
        };
    }

    pub fn deinit(self: *RuntimeState) void {
        self.monitors.deinit(self.allocator);
        self.workspaces.deinit(self.allocator);
        self.windows.deinit(self.allocator);
        self.last_focused_by_workspace.deinit();
        self.selected_node_by_workspace.deinit();

        var history_iter = self.focus_history_by_workspace.iterator();
        while (history_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.focus_history_by_workspace.deinit();
        self.effects.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clearSnapshot(self: *RuntimeState) void {
        self.monitors.items.len = 0;
        self.workspaces.items.len = 0;
        self.windows.items.len = 0;
        self.selected_node_by_workspace.clearRetainingCapacity();
    }

    pub fn clearEffects(self: *RuntimeState) void {
        self.effects.clear();
    }
};

pub fn uuid(raw: abi.OmniUuid128) Uuid {
    return raw.bytes;
}

pub fn rawUuid(value: Uuid) abi.OmniUuid128 {
    return .{ .bytes = value };
}

pub fn optionalUuid(has_value: u8, raw: abi.OmniUuid128) ?Uuid {
    if (has_value == 0) {
        return null;
    }
    return uuid(raw);
}

pub fn writeOptionalUuid(has_field: *u8, out_field: *abi.OmniUuid128, value: ?Uuid) void {
    if (value) |resolved| {
        has_field.* = 1;
        out_field.* = rawUuid(resolved);
    } else {
        has_field.* = 0;
        out_field.* = .{ .bytes = [_]u8{0} ** 16 };
    }
}

pub fn optionalDisplayId(has_value: u8, display_id: u32) ?u32 {
    if (has_value == 0) {
        return null;
    }
    return display_id;
}

pub fn writeOptionalDisplayId(has_field: *u8, out_field: *u32, value: ?u32) void {
    if (value) |resolved| {
        has_field.* = 1;
        out_field.* = resolved;
    } else {
        has_field.* = 0;
        out_field.* = 0;
    }
}

fn normalizedNameLen(name: abi.OmniControllerName) usize {
    const clamped_len = @min(@as(usize, name.length), abi.OMNI_CONTROLLER_NAME_CAP);
    var len: usize = 0;
    while (len < clamped_len and name.bytes[len] != 0) : (len += 1) {}
    return len;
}

pub fn nameSlice(name: abi.OmniControllerName) []const u8 {
    return name.bytes[0..normalizedNameLen(name)];
}

pub fn nameEquals(name: abi.OmniControllerName, value: []const u8) bool {
    const lhs_len = normalizedNameLen(name);
    if (lhs_len != value.len) {
        return false;
    }
    var idx: usize = 0;
    while (idx < lhs_len) : (idx += 1) {
        if (name.bytes[idx] != value[idx]) {
            return false;
        }
    }
    return true;
}

pub fn parseWorkspaceOrdinal(name: abi.OmniControllerName) ?usize {
    const slice = nameSlice(name);
    if (slice.len == 0) {
        return null;
    }
    var value: usize = 0;
    for (slice) |byte| {
        if (byte < '0' or byte > '9') {
            return null;
        }
        value = (value * 10) + @as(usize, byte - '0');
    }
    return value;
}

pub fn logicalWorkspaceLessThan(lhs: abi.OmniControllerName, rhs: abi.OmniControllerName) bool {
    const lhs_num = parseWorkspaceOrdinal(lhs);
    const rhs_num = parseWorkspaceOrdinal(rhs);
    if (lhs_num != null and rhs_num != null and lhs_num.? != rhs_num.?) {
        return lhs_num.? < rhs_num.?;
    }
    return std.mem.order(u8, nameSlice(lhs), nameSlice(rhs)) == .lt;
}

pub fn encodeName(value: []const u8) abi.OmniControllerName {
    var result = abi.OmniControllerName{
        .length = @intCast(@min(value.len, abi.OMNI_CONTROLLER_NAME_CAP)),
        .bytes = [_]u8{0} ** abi.OMNI_CONTROLLER_NAME_CAP,
    };
    std.mem.copyForwards(u8, result.bytes[0..result.length], value[0..result.length]);
    return result;
}

pub fn workspaceLayoutName(kind: LayoutKind) []const u8 {
    return switch (kind) {
        .default_layout, .niri => "niri",
        .dwindle => "dwindle",
    };
}

pub fn optionalBool(has_value: u8) bool {
    return has_value != 0;
}
