const std = @import("std");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

fn isTrusted(prompt: bool) bool {
    if (!prompt) {
        return c.AXIsProcessTrusted() != 0;
    }

    const options = c.CFDictionaryCreateMutable(
        c.kCFAllocatorDefault,
        1,
        &c.kCFTypeDictionaryKeyCallBacks,
        &c.kCFTypeDictionaryValueCallBacks,
    );
    if (options == null) {
        return c.AXIsProcessTrusted() != 0;
    }
    defer c.CFRelease(options);

    c.CFDictionarySetValue(
        options,
        @ptrCast(c.kAXTrustedCheckOptionPrompt),
        @ptrCast(c.kCFBooleanTrue),
    );

    return c.AXIsProcessTrustedWithOptions(options) != 0;
}

pub fn omni_ax_permission_is_trusted_impl() u8 {
    return if (isTrusted(false)) 1 else 0;
}

pub fn omni_ax_permission_request_prompt_impl() u8 {
    return if (isTrusted(true)) 1 else 0;
}

pub fn omni_ax_permission_poll_until_trusted_impl(max_wait_millis: u32, poll_interval_millis: u32) u8 {
    const interval_ms: u64 = if (poll_interval_millis == 0) 250 else poll_interval_millis;
    const max_wait_ms: u64 = max_wait_millis;
    const has_deadline = max_wait_ms > 0;

    var waited_ms: u64 = 0;
    while (true) {
        if (isTrusted(false)) return 1;
        if (has_deadline and waited_ms >= max_wait_ms) return 0;

        const sleep_ms: u64 = if (has_deadline)
            @min(interval_ms, max_wait_ms - waited_ms)
        else
            interval_ms;
        if (sleep_ms == 0) return 0;

        std.Thread.sleep(sleep_ms * std.time.ns_per_ms);
        waited_ms += sleep_ms;
    }
}
