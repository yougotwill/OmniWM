import AppKit
import CZigLayout
import Foundation

final class AXRuntimeBridge: @unchecked Sendable {
    static let shared = AXRuntimeBridge()
    static let tilingWindowTypeRaw: UInt8 = 0
    static let floatingWindowTypeRaw: UInt8 = 1

    var onWindowDestroyed: ((pid_t, Int) -> Void)?
    var onWindowDestroyedUnknown: (() -> Void)?
    var onFocusedWindowChanged: ((pid_t) -> Void)?

    private var runtime: OpaquePointer?

    private init() {
        var config = OmniAXRuntimeConfig(
            abi_version: UInt32(OMNI_AX_RUNTIME_ABI_VERSION),
            reserved: 0
        )
        var host = OmniAXHostVTable(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            on_window_destroyed: { userdata, pid, windowId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let bridge = Unmanaged<AXRuntimeBridge>.fromOpaque(userdata).takeUnretainedValue()
                Task { @MainActor in
                    bridge.onWindowDestroyed?(pid_t(pid), Int(windowId))
                }
                return Int32(OMNI_OK)
            },
            on_window_destroyed_unknown: { userdata in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let bridge = Unmanaged<AXRuntimeBridge>.fromOpaque(userdata).takeUnretainedValue()
                Task { @MainActor in
                    bridge.onWindowDestroyedUnknown?()
                }
                return Int32(OMNI_OK)
            },
            on_focused_window_changed: { userdata, pid in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let bridge = Unmanaged<AXRuntimeBridge>.fromOpaque(userdata).takeUnretainedValue()
                Task { @MainActor in
                    bridge.onFocusedWindowChanged?(pid_t(pid))
                }
                return Int32(OMNI_OK)
            }
        )

        runtime = withUnsafePointer(to: &config) { configPtr in
            withUnsafePointer(to: &host) { hostPtr in
                omni_ax_runtime_create(configPtr, hostPtr)
            }
        }

        if let runtime {
            _ = omni_ax_runtime_start(runtime)
        }
    }

    deinit {
        guard let runtime else { return }
        _ = omni_ax_runtime_stop(runtime)
        omni_ax_runtime_destroy(runtime)
        self.runtime = nil
    }

    func setCallbacks(
        onWindowDestroyed: ((pid_t, Int) -> Void)?,
        onWindowDestroyedUnknown: (() -> Void)?,
        onFocusedWindowChanged: ((pid_t) -> Void)?
    ) {
        self.onWindowDestroyed = onWindowDestroyed
        self.onWindowDestroyedUnknown = onWindowDestroyedUnknown
        self.onFocusedWindowChanged = onFocusedWindowChanged
    }

    func track(app: NSRunningApplication, forceFloating: Bool = false) {
        guard let runtime else { return }
        let pid = app.processIdentifier
        let appPolicy = Int32(app.activationPolicy.rawValue)
        let forceFloatingRaw: UInt8 = forceFloating ? 1 : 0

        if let bundleId = app.bundleIdentifier {
            bundleId.withCString { cString in
                _ = omni_ax_runtime_track_app(runtime, Int32(pid), appPolicy, cString, forceFloatingRaw)
            }
        } else {
            _ = omni_ax_runtime_track_app(runtime, Int32(pid), appPolicy, nil, forceFloatingRaw)
        }
    }

    func untrack(pid: pid_t) {
        guard let runtime else { return }
        _ = omni_ax_runtime_untrack_app(runtime, Int32(pid))
    }

    func enumerateWindows() -> [OmniAXWindowRecord] {
        guard let runtime else { return [] }

        var total = 0
        _ = omni_ax_runtime_enumerate_windows(runtime, nil, 0, &total)
        guard total > 0 else { return [] }

        var buffer = Array(repeating: OmniAXWindowRecord(), count: total)
        var written = 0
        let rc = buffer.withUnsafeMutableBufferPointer { ptr in
            omni_ax_runtime_enumerate_windows(runtime, ptr.baseAddress, ptr.count, &written)
        }
        guard rc == Int32(OMNI_OK), written > 0 else { return [] }
        return Array(buffer.prefix(min(written, buffer.count)))
    }

    func applyFrames(_ requests: [OmniAXFrameRequest]) {
        guard let runtime else { return }
        guard !requests.isEmpty else { return }
        var mutable = requests
        mutable.withUnsafeMutableBufferPointer { ptr in
            _ = omni_ax_runtime_apply_frames_batch(runtime, ptr.baseAddress, ptr.count)
        }
    }

    func cancelFrameJobs(_ keys: [OmniAXWindowKey]) {
        guard let runtime else { return }
        guard !keys.isEmpty else { return }
        var mutable = keys
        mutable.withUnsafeMutableBufferPointer { ptr in
            _ = omni_ax_runtime_cancel_frame_jobs(runtime, ptr.baseAddress, ptr.count)
        }
    }

    func suppressFrameWrites(_ keys: [OmniAXWindowKey]) {
        guard let runtime else { return }
        guard !keys.isEmpty else { return }
        var mutable = keys
        mutable.withUnsafeMutableBufferPointer { ptr in
            _ = omni_ax_runtime_suppress_frame_writes(runtime, ptr.baseAddress, ptr.count)
        }
    }

    func unsuppressFrameWrites(_ keys: [OmniAXWindowKey]) {
        guard let runtime else { return }
        guard !keys.isEmpty else { return }
        var mutable = keys
        mutable.withUnsafeMutableBufferPointer { ptr in
            _ = omni_ax_runtime_unsuppress_frame_writes(runtime, ptr.baseAddress, ptr.count)
        }
    }

    func getWindowFrame(pid: pid_t, windowId: Int) -> CGRect? {
        guard let runtime else { return nil }
        var rect = OmniBorderRect()
        let rc = omni_ax_runtime_get_window_frame(runtime, Int32(pid), UInt32(windowId), &rect)
        guard rc == Int32(OMNI_OK) else { return nil }
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    func setWindowFrame(pid: pid_t, windowId: Int, frame: CGRect) -> Bool {
        guard let runtime else { return false }
        var rect = OmniBorderRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height)
        return omni_ax_runtime_set_window_frame(runtime, Int32(pid), UInt32(windowId), &rect) == Int32(OMNI_OK)
    }

    func getWindowType(
        pid: pid_t,
        windowId: Int,
        appPolicy: NSApplication.ActivationPolicy?,
        forceFloating: Bool
    ) -> AXWindowType {
        guard let runtime else { return .floating }
        var request = OmniAXWindowTypeRequest(
            pid: Int32(pid),
            window_id: UInt32(windowId),
            app_policy: Int32(appPolicy?.rawValue ?? -1),
            force_floating: forceFloating ? 1 : 0
        )
        var outType: UInt8 = Self.floatingWindowTypeRaw
        let rc = withUnsafePointer(to: &request) { requestPtr in
            omni_ax_runtime_get_window_type(runtime, requestPtr, &outType)
        }
        guard rc == Int32(OMNI_OK) else { return .floating }
        return outType == Self.tilingWindowTypeRaw ? .tiling : .floating
    }

    func isWindowFullscreen(pid: pid_t, windowId: Int) -> Bool {
        guard let runtime else { return false }
        var fullscreen: UInt8 = 0
        let rc = omni_ax_runtime_is_window_fullscreen(runtime, Int32(pid), UInt32(windowId), &fullscreen)
        guard rc == Int32(OMNI_OK) else { return false }
        return fullscreen == 1
    }

    func setWindowFullscreen(pid: pid_t, windowId: Int, fullscreen: Bool) -> Bool {
        guard let runtime else { return false }
        return omni_ax_runtime_set_window_fullscreen(runtime, Int32(pid), UInt32(windowId), fullscreen ? 1 : 0) == Int32(OMNI_OK)
    }

    func getWindowConstraints(pid: pid_t, windowId: Int) -> OmniAXWindowConstraints? {
        guard let runtime else { return nil }
        var constraints = OmniAXWindowConstraints()
        let rc = omni_ax_runtime_get_window_constraints(runtime, Int32(pid), UInt32(windowId), &constraints)
        guard rc == Int32(OMNI_OK) else { return nil }
        return constraints
    }
}
