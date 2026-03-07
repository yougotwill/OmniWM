import AppKit
import CZigLayout
import Foundation

private func omniMonitorDisplayChangedBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ displayId: UInt32,
    _ changeFlags: UInt32
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniMonitorRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatchDisplayChanged(displayId: displayId, changeFlags: changeFlags)
    }
    return Int32(OMNI_OK)
}

enum OmniMonitorQueryBridge {
    typealias QueryFunction = (
        UnsafeMutablePointer<OmniMonitorRecord>?,
        Int,
        UnsafeMutablePointer<Int>
    ) -> Int32

    nonisolated(unsafe) static var queryFunction: QueryFunction = { outMonitors, outCapacity, outWritten in
        omni_monitor_query_current(outMonitors, outCapacity, outWritten)
    }

    static func queryCurrentMonitors() -> [Monitor]? {
        var requiredCount = 0
        let probeRc = queryFunction(nil, 0, &requiredCount)
        guard probeRc == Int32(OMNI_OK) || probeRc == Int32(OMNI_ERR_OUT_OF_RANGE) else {
            return nil
        }
        guard requiredCount > 0 else {
            return []
        }

        var capacity = max(requiredCount, 1)
        for _ in 0 ..< 3 {
            var records = Array(repeating: OmniMonitorRecord(), count: capacity)
            var written = 0
            let rc = records.withUnsafeMutableBufferPointer { buffer in
                queryFunction(buffer.baseAddress, buffer.count, &written)
            }
            if rc == Int32(OMNI_OK) {
                return Array(records.prefix(max(0, min(written, records.count))).map(monitor(from:)))
            }
            if rc != Int32(OMNI_ERR_OUT_OF_RANGE) {
                return nil
            }
            capacity = max(written, capacity * 2)
        }
        return nil
    }

    static func monitor(from raw: OmniMonitorRecord) -> Monitor {
        Monitor(
            id: .init(displayId: raw.display_id),
            displayId: raw.display_id,
            frame: CGRect(
                x: raw.frame_x,
                y: raw.frame_y,
                width: raw.frame_width,
                height: raw.frame_height
            ),
            visibleFrame: CGRect(
                x: raw.visible_x,
                y: raw.visible_y,
                width: raw.visible_width,
                height: raw.visible_height
            ),
            hasNotch: raw.has_notch != 0,
            name: string(from: raw.name),
            scale: normalizedScale(raw.backing_scale)
        )
    }

    private static func string(from raw: OmniWorkspaceRuntimeName) -> String {
        let length = min(Int(raw.length), Int(OMNI_WORKSPACE_RUNTIME_NAME_CAP))
        let bytes: [UInt8] = withUnsafeBytes(of: raw.bytes) { rawBuffer in
            Array(rawBuffer.prefix(length))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func normalizedScale(_ value: Double) -> CGFloat {
        guard value.isFinite, value > 0 else { return 2.0 }
        return CGFloat(value)
    }
}

@MainActor
final class OmniMonitorRuntimeAdapter {
    struct DisplayChangeEvent: Sendable {
        let displayId: CGDirectDisplayID
        let changeFlags: UInt32
    }

    typealias EventHandler = @MainActor (DisplayChangeEvent) -> Void

    static let shared = OmniMonitorRuntimeAdapter()

    private var runtime: OpaquePointer?
    private var started = false
    private var handlers: [UUID: EventHandler] = [:]

    private init() {
        createAndStartRuntime()
    }

    func subscribe(_ handler: @escaping EventHandler) -> UUID? {
        guard started else { return nil }
        let token = UUID()
        handlers[token] = handler
        return token
    }

    func unsubscribe(_ token: UUID) {
        handlers.removeValue(forKey: token)
    }

    private func createAndStartRuntime() {
        var config = OmniMonitorRuntimeConfig(
            abi_version: UInt32(OMNI_MONITOR_RUNTIME_ABI_VERSION),
            reserved: 0
        )
        var host = OmniMonitorHostVTable(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            on_displays_changed: omniMonitorDisplayChangedBridge
        )
        runtime = withUnsafePointer(to: &config) { configPtr in
            withUnsafePointer(to: &host) { hostPtr in
                omni_monitor_runtime_create(configPtr, hostPtr)
            }
        }
        guard let runtime else { return }
        if omni_monitor_runtime_start(runtime) == Int32(OMNI_OK) {
            started = true
            return
        }
        omni_monitor_runtime_destroy(runtime)
        self.runtime = nil
        started = false
    }

    fileprivate func dispatchDisplayChanged(displayId: CGDirectDisplayID, changeFlags: UInt32) {
        let event = DisplayChangeEvent(displayId: displayId, changeFlags: changeFlags)
        for handler in handlers.values {
            handler(event)
        }
    }
}
