const abi = @import("../omni/abi_types.zig");

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("IOKit/pwr_mgt/IOPMLib.h");
});

pub fn omni_sleep_prevention_create_assertion_impl(out_assertion_id: [*c]u32) i32 {
    if (out_assertion_id == null) return abi.OMNI_ERR_INVALID_ARGS;

    const assertion_type = c.CFStringCreateWithCString(
        null,
        "PreventUserIdleDisplaySleep",
        c.kCFStringEncodingUTF8,
    );
    if (assertion_type == null) return abi.OMNI_ERR_PLATFORM;
    defer c.CFRelease(assertion_type);

    const reason = c.CFStringCreateWithCString(null, "OmniWM prevents sleep", c.kCFStringEncodingUTF8);
    if (reason == null) return abi.OMNI_ERR_PLATFORM;
    defer c.CFRelease(reason);

    var assertion_id: c.IOPMAssertionID = 0;
    const rc = c.IOPMAssertionCreateWithDescription(
        assertion_type,
        reason,
        null,
        null,
        null,
        0,
        null,
        &assertion_id,
    );
    if (rc != c.kIOReturnSuccess) return abi.OMNI_ERR_PLATFORM;

    out_assertion_id[0] = assertion_id;
    return abi.OMNI_OK;
}

pub fn omni_sleep_prevention_release_assertion_impl(assertion_id: u32) i32 {
    if (assertion_id == 0) return abi.OMNI_ERR_INVALID_ARGS;
    const rc = c.IOPMAssertionRelease(assertion_id);
    if (rc != c.kIOReturnSuccess) return abi.OMNI_ERR_PLATFORM;
    return abi.OMNI_OK;
}
