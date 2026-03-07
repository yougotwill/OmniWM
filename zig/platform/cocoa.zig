const std = @import("std");
const objc = @import("objc_platform");
const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
});

pub const NSApplicationActivationPolicyAccessory: isize = 1;
const NSVariableStatusItemLength: c.CGFloat = -1;
const NSFixedStatusItemLength: c.CGFloat = 28;

pub fn nsString(c_string: [*:0]const u8) objc.Id {
    const ns_string = objc.getClass("NSString") orelse return null;
    return objc.msgSend1(objc.Id, ns_string, objc.sel("stringWithUTF8String:"), c_string);
}

pub const App = struct {
    object: objc.Id,

    pub fn shared() App {
        const cls = objc.getClass("NSApplication") orelse return .{ .object = null };
        return .{ .object = objc.msgSend0(objc.Id, cls, objc.sel("sharedApplication")) };
    }

    pub fn setActivationPolicyAccessory(self: App) void {
        if (self.object == null) return;
        _ = objc.msgSend1(bool, self.object, objc.sel("setActivationPolicy:"), NSApplicationActivationPolicyAccessory);
    }

    pub fn setDelegate(self: App, delegate: objc.Id) void {
        if (self.object == null) return;
        _ = objc.msgSend1(void, self.object, objc.sel("setDelegate:"), delegate);
    }

    pub fn run(self: App) void {
        if (self.object == null) return;
        _ = objc.msgSend0(void, self.object, objc.sel("run"));
    }

    pub fn terminate(self: App) void {
        if (self.object == null) return;
        _ = objc.msgSend1(void, self.object, objc.sel("terminate:"), @as(objc.Id, null));
    }
};

pub const Menu = struct {
    object: objc.Id,

    pub fn init() Menu {
        const cls = objc.getClass("NSMenu") orelse return .{ .object = null };
        const allocated = objc.msgSend0(objc.Id, cls, objc.sel("alloc"));
        const initialized = objc.msgSend0(objc.Id, allocated, objc.sel("init"));
        _ = objc.msgSend1(void, initialized, objc.sel("setAutoenablesItems:"), false);
        return .{ .object = initialized };
    }

    pub fn addItem(self: Menu, title: [*:0]const u8, action: objc.Sel, key_equivalent: [*:0]const u8) objc.Id {
        if (self.object == null) return null;
        return objc.msgSend3(
            objc.Id,
            self.object,
            objc.sel("addItemWithTitle:action:keyEquivalent:"),
            nsString(title),
            action,
            nsString(key_equivalent),
        );
    }
};

pub const StatusItem = struct {
    object: objc.Id,

    pub fn create() StatusItem {
        const status_bar_cls = objc.getClass("NSStatusBar") orelse return .{ .object = null };
        const system_status_bar = objc.msgSend0(objc.Id, status_bar_cls, objc.sel("systemStatusBar"));
        return .{
            .object = objc.msgSend1(
                objc.Id,
                system_status_bar,
                objc.sel("statusItemWithLength:"),
                NSFixedStatusItemLength,
            ),
        };
    }

    pub fn remove(self: StatusItem) void {
        if (self.object == null) return;
        const status_bar_cls = objc.getClass("NSStatusBar") orelse return;
        const system_status_bar = objc.msgSend0(objc.Id, status_bar_cls, objc.sel("systemStatusBar"));
        _ = objc.msgSend1(void, system_status_bar, objc.sel("removeStatusItem:"), self.object);
    }

    pub fn button(self: StatusItem) objc.Id {
        if (self.object == null) return null;
        return objc.msgSend0(objc.Id, self.object, objc.sel("button"));
    }

    pub fn setMenu(self: StatusItem, menu: Menu) void {
        if (self.object == null or menu.object == null) return;
        _ = objc.msgSend1(void, self.object, objc.sel("setMenu:"), menu.object);
    }

    pub fn setButtonTitle(self: StatusItem, title: [*:0]const u8) void {
        const button_object = self.button();
        if (button_object == null) return;
        _ = objc.msgSend1(void, button_object, objc.sel("setTitle:"), nsString(title));
    }

    pub fn setTitle(self: StatusItem, title: [*:0]const u8) void {
        if (self.object == null) return;
        _ = objc.msgSend1(void, self.object, objc.sel("setTitle:"), nsString(title));
    }
};

pub fn mainScreen() objc.Id {
    const cls = objc.getClass("NSScreen") orelse return null;
    return objc.msgSend0(objc.Id, cls, objc.sel("mainScreen"));
}

pub fn sharedWorkspace() objc.Id {
    const cls = objc.getClass("NSWorkspace") orelse return null;
    return objc.msgSend0(objc.Id, cls, objc.sel("sharedWorkspace"));
}

pub fn openURL(url_string: [*:0]const u8) bool {
    const workspace = sharedWorkspace();
    if (workspace == null) return false;

    const ns_url_cls = objc.getClass("NSURL") orelse return false;
    const url = objc.msgSend1(objc.Id, ns_url_cls, objc.sel("URLWithString:"), nsString(url_string));
    if (url == null) return false;

    return objc.msgSend1(bool, workspace, objc.sel("openURL:"), url);
}
