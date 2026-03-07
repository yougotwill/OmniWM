const builtin = @import("builtin");
const c = @cImport({
    @cInclude("objc/message.h");
    @cInclude("objc/runtime.h");
});

pub const Id = ?*anyopaque;
pub const Class = ?*anyopaque;
pub const Sel = c.SEL;

const objc_msgSend_ptr: *const anyopaque = @extern(*const anyopaque, .{ .name = "objc_msgSend" });

pub fn getClass(name: [*:0]const u8) Class {
    return @ptrCast(c.objc_getClass(name));
}

pub fn allocateClassPair(superclass: Class, name: [*:0]const u8) Class {
    return @ptrCast(c.objc_allocateClassPair(@ptrCast(superclass), name, 0));
}

pub fn registerClassPair(class: Class) void {
    c.objc_registerClassPair(@ptrCast(class));
}

pub fn classAddMethod(class: Class, selector: Sel, imp: c.IMP, types: [*:0]const u8) bool {
    const rc = c.class_addMethod(@ptrCast(class), selector, imp, types);
    if (@TypeOf(rc) == bool) return rc;
    return rc != 0;
}

pub fn sel(name: [*:0]const u8) Sel {
    return c.sel_registerName(name);
}

pub fn msgSend0(comptime Ret: type, target: anytype, selector: Sel) Ret {
    const Fn = *const fn (@TypeOf(target), Sel) callconv(.c) Ret;
    const fn_ptr: Fn = @ptrCast(@alignCast(objc_msgSend_ptr));
    return fn_ptr(target, selector);
}

pub fn msgSend1(comptime Ret: type, target: anytype, selector: Sel, arg0: anytype) Ret {
    const Fn = *const fn (@TypeOf(target), Sel, @TypeOf(arg0)) callconv(.c) Ret;
    const fn_ptr: Fn = @ptrCast(@alignCast(objc_msgSend_ptr));
    return fn_ptr(target, selector, arg0);
}

pub fn msgSend2(comptime Ret: type, target: anytype, selector: Sel, arg0: anytype, arg1: anytype) Ret {
    const Fn = *const fn (@TypeOf(target), Sel, @TypeOf(arg0), @TypeOf(arg1)) callconv(.c) Ret;
    const fn_ptr: Fn = @ptrCast(@alignCast(objc_msgSend_ptr));
    return fn_ptr(target, selector, arg0, arg1);
}

pub fn msgSend3(comptime Ret: type, target: anytype, selector: Sel, arg0: anytype, arg1: anytype, arg2: anytype) Ret {
    const Fn = *const fn (
        @TypeOf(target),
        Sel,
        @TypeOf(arg0),
        @TypeOf(arg1),
        @TypeOf(arg2),
    ) callconv(.c) Ret;
    const fn_ptr: Fn = @ptrCast(@alignCast(objc_msgSend_ptr));
    return fn_ptr(target, selector, arg0, arg1, arg2);
}

pub fn msgSend4(comptime Ret: type, target: anytype, selector: Sel, arg0: anytype, arg1: anytype, arg2: anytype, arg3: anytype) Ret {
    const Fn = *const fn (
        @TypeOf(target),
        Sel,
        @TypeOf(arg0),
        @TypeOf(arg1),
        @TypeOf(arg2),
        @TypeOf(arg3),
    ) callconv(.c) Ret;
    const fn_ptr: Fn = @ptrCast(@alignCast(objc_msgSend_ptr));
    return fn_ptr(target, selector, arg0, arg1, arg2, arg3);
}

fn useStretForReturn(comptime Ret: type) bool {
    return builtin.target.cpu.arch == .x86_64 and @sizeOf(Ret) > 16;
}

pub fn msgSendStruct0(comptime Ret: type, target: anytype, selector: Sel) Ret {
    if (comptime useStretForReturn(Ret)) {
        var result: Ret = undefined;
        const stret_ptr: *const anyopaque = @extern(*const anyopaque, .{ .name = "objc_msgSend_stret" });
        const Fn = *const fn (*Ret, @TypeOf(target), Sel) callconv(.c) void;
        const fn_ptr: Fn = @ptrCast(@alignCast(stret_ptr));
        fn_ptr(&result, target, selector);
        return result;
    }
    return msgSend0(Ret, target, selector);
}

pub fn retain(object: Id) Id {
    if (object == null) return null;
    return msgSend0(Id, object, sel("retain"));
}

pub fn release(object: Id) void {
    if (object == null) return;
    _ = msgSend0(Id, object, sel("release"));
}

pub fn toImp(function: anytype) c.IMP {
    const FnPtr = switch (@typeInfo(@TypeOf(function))) {
        .@"fn" => &function,
        .pointer => function,
        else => @compileError("objc.toImp expects a function or function pointer"),
    };
    return @ptrCast(@constCast(FnPtr));
}

pub const AutoreleasePool = struct {
    object: Id,

    pub fn init() AutoreleasePool {
        const cls = getClass("NSAutoreleasePool") orelse return .{ .object = null };
        const allocated = msgSend0(Id, cls, sel("alloc"));
        const initialized = msgSend0(Id, allocated, sel("init"));
        return .{ .object = initialized };
    }

    pub fn drain(self: *AutoreleasePool) void {
        if (self.object == null) return;
        _ = msgSend0(Id, self.object, sel("drain"));
        self.object = null;
    }
};
