import ApplicationServices
import CZigLayout
import Foundation

typealias SLPSMode = UInt32
let kCPSUserGenerated: SLPSMode = 0x200

@discardableResult
func _SLPSSetFrontProcessWithOptions(
    _: inout ProcessSerialNumber,
    _: UInt32,
    _: SLPSMode
) -> OSStatus {
    -1
}

@discardableResult
func SLPSPostEventRecordTo(
    _: inout ProcessSerialNumber,
    _: UnsafeMutablePointer<UInt8>
) -> OSStatus {
    -1
}

@discardableResult
func GetProcessForPID(_: pid_t, _: inout ProcessSerialNumber) -> OSStatus {
    -1
}

func getWindowId(from windowRef: AXUIElement) -> CGWindowID? {
    var windowId: UInt32 = 0
    let rawElement = unsafeBitCast(windowRef, to: UnsafeMutableRawPointer.self)
    let rc = omni_private_get_ax_window_id(rawElement, &windowId)
    return rc == Int32(OMNI_OK) ? CGWindowID(windowId) : nil
}

func makeKeyWindow(psn _: inout ProcessSerialNumber, windowId _: UInt32) {
    // Runtime-owned private API path handles key-window event posting in Zig.
}

func focusWindow(pid: pid_t, windowId: UInt32, windowRef _: AXUIElement) {
    _ = omni_private_focus_window(Int32(pid), windowId)
}
