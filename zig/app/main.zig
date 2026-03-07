const std = @import("std");
const objc = @import("objc_platform");
const cocoa = @import("cocoa_platform");
const cf = @import("cf_platform");

const DelegateClassName = "OmniWMPhase0AppDelegate";
const ActionsClassName = "OmniWMPhase0Actions";

var global_state: ?*AppState = null;

const AppState = struct {
    app: cocoa.App,
    delegate_object: objc.Id = null,
    actions_object: objc.Id = null,
    status_item: ?cocoa.StatusItem = null,
    menu: ?cocoa.Menu = null,
    launch_complete: bool = false,

    fn init() AppState {
        return .{ .app = cocoa.App.shared() };
    }

    fn installLifecycle(self: *AppState) !void {
        const delegate_class = registerAppDelegateClass() orelse return error.RegisterDelegateClassFailed;
        const actions_class = registerActionsClass() orelse return error.RegisterActionsClassFailed;

        const delegate_alloc = objc.msgSend0(objc.Id, delegate_class, objc.sel("alloc"));
        self.delegate_object = objc.msgSend0(objc.Id, delegate_alloc, objc.sel("init"));
        if (self.delegate_object == null) return error.AllocateDelegateFailed;

        const actions_alloc = objc.msgSend0(objc.Id, actions_class, objc.sel("alloc"));
        self.actions_object = objc.msgSend0(objc.Id, actions_alloc, objc.sel("init"));
        if (self.actions_object == null) return error.AllocateActionsFailed;

        self.app.setDelegate(self.delegate_object);
    }

    fn onDidFinishLaunching(self: *AppState) void {
        if (self.launch_complete) return;
        self.app.setActivationPolicyAccessory();
        self.launch_complete = true;
        std.log.info("phase0: did finish launching", .{});

        const status_item = cocoa.StatusItem.create();
        if (status_item.object == null) {
            std.log.err("failed to create status item", .{});
            return;
        }
        status_item.setTitle("OW");
        status_item.setButtonTitle("OW");
        if (status_item.button() == null) {
            std.log.err("phase0: status item button is null (item likely invisible)", .{});
        } else {
            std.log.info("phase0: status item button created", .{});
        }

        const menu = cocoa.Menu.init();
        if (menu.object == null) {
            std.log.err("failed to create status menu", .{});
            status_item.remove();
            return;
        }

        const quit_item = menu.addItem("Quit OmniWM", objc.sel("quitOmniWM:"), "q");
        if (quit_item != null) {
            _ = objc.msgSend1(void, quit_item, objc.sel("setTarget:"), self.actions_object);
        }
        std.log.info("phase0: menu created and quit item attached", .{});

        status_item.setMenu(menu);
        std.log.info("phase0: menu assigned to status item", .{});

        self.status_item = status_item;
        self.menu = menu;

        // Touch CoreFoundation helpers now so phase-0 validates the wrapper import path.
        _ = cf.currentRunLoop();
    }

    fn onWillTerminate(self: *AppState) void {
        self.cleanup();
    }

    fn onQuitAction(self: *AppState) void {
        self.app.terminate();
    }

    fn cleanup(self: *AppState) void {
        if (self.status_item) |item| {
            item.remove();
            self.status_item = null;
        }

        if (self.menu) |menu| {
            objc.release(menu.object);
            self.menu = null;
        }

        if (self.actions_object != null) {
            objc.release(self.actions_object);
            self.actions_object = null;
        }

        if (self.delegate_object != null) {
            objc.release(self.delegate_object);
            self.delegate_object = null;
        }

        self.launch_complete = false;
    }
};

pub fn main() !void {
    var pool = objc.AutoreleasePool.init();
    defer pool.drain();

    var state = AppState.init();
    global_state = &state;
    defer {
        state.cleanup();
        global_state = null;
    }

    try state.installLifecycle();
    // Ensure phase0 menu bootstrap happens even if delegate callbacks are not fired
    // in this standalone executable context.
    state.onDidFinishLaunching();
    state.app.run();
}

fn registerAppDelegateClass() ?objc.Class {
    if (objc.getClass(DelegateClassName)) |existing| return existing;

    const ns_object_class = objc.getClass("NSObject") orelse return null;
    const klass = objc.allocateClassPair(ns_object_class, DelegateClassName) orelse return null;

    const did_finish = objc.classAddMethod(
        klass,
        objc.sel("applicationDidFinishLaunching:"),
        objc.toImp(&applicationDidFinishLaunching),
        "v@:@",
    );
    const will_terminate = objc.classAddMethod(
        klass,
        objc.sel("applicationWillTerminate:"),
        objc.toImp(&applicationWillTerminate),
        "v@:@",
    );

    if (!did_finish or !will_terminate) return null;

    objc.registerClassPair(klass);
    return klass;
}

fn registerActionsClass() ?objc.Class {
    if (objc.getClass(ActionsClassName)) |existing| return existing;

    const ns_object_class = objc.getClass("NSObject") orelse return null;
    const klass = objc.allocateClassPair(ns_object_class, ActionsClassName) orelse return null;

    const added = objc.classAddMethod(
        klass,
        objc.sel("quitOmniWM:"),
        objc.toImp(&quitOmniWM),
        "v@:@",
    );
    if (!added) return null;

    objc.registerClassPair(klass);
    return klass;
}

fn applicationDidFinishLaunching(_: objc.Id, _: objc.Sel, _: objc.Id) callconv(.c) void {
    if (global_state) |state| {
        state.onDidFinishLaunching();
    }
}

fn applicationWillTerminate(_: objc.Id, _: objc.Sel, _: objc.Id) callconv(.c) void {
    if (global_state) |state| {
        state.onWillTerminate();
    }
}

fn quitOmniWM(_: objc.Id, _: objc.Sel, _: objc.Id) callconv(.c) void {
    if (global_state) |state| {
        state.onQuitAction();
    }
}
