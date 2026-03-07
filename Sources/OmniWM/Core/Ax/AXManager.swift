import AppKit
import CZigLayout
import Foundation

@MainActor
final class AXManager {
    private static let systemUIBundleIds: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight"
    ]

    private var workspaceEventToken: UUID?

    var onAppLaunched: ((NSRunningApplication) -> Void)?
    var onAppTerminated: ((pid_t) -> Void)?
    var onWindowDestroyed: ((pid_t, Int) -> Void)?
    var onWindowDestroyedUnknown: (() -> Void)?
    var onFocusedWindowChanged: ((pid_t) -> Void)?

    private var framesByPidBuffer: [pid_t: [(windowId: Int, frame: CGRect)]] = [:]
    private var lastAppliedFrames: [Int: CGRect] = [:]
    private var forceApplyWindowIds: Set<Int> = []
    private(set) var inactiveWorkspaceWindowIds: Set<Int> = []

    init() {
        AXRuntimeBridge.shared.setCallbacks(
            onWindowDestroyed: { [weak self] pid, windowId in
                self?.onWindowDestroyed?(pid, windowId)
            },
            onWindowDestroyedUnknown: { [weak self] in
                self?.onWindowDestroyedUnknown?()
            },
            onFocusedWindowChanged: { [weak self] pid in
                self?.onFocusedWindowChanged?(pid)
            }
        )
    }

    func startLifecycleObservation() {
        guard workspaceEventToken == nil else { return }
        workspaceEventToken = WorkspaceEventHub.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case let .launched(pid):
                guard let app = NSRunningApplication(processIdentifier: pid) else { return }
                guard self.shouldTrack(app) else { return }
                AXRuntimeBridge.shared.track(app: app)
                self.onAppLaunched?(app)
            case let .terminated(pid):
                AXRuntimeBridge.shared.untrack(pid: pid)
                self.onAppTerminated?(pid)
            case .activated, .hidden, .unhidden, .activeSpaceChanged:
                break
            }
        }
    }

    func stopLifecycleObservation() {
        if let token = workspaceEventToken {
            WorkspaceEventHub.shared.unsubscribe(token)
            workspaceEventToken = nil
        }
    }

    func updateInactiveWorkspaceWindows(
        allEntries: [(workspaceId: WorkspaceDescriptor.ID, windowId: Int)],
        activeWorkspaceIds: Set<WorkspaceDescriptor.ID>
    ) {
        inactiveWorkspaceWindowIds.removeAll(keepingCapacity: true)
        for (wsId, windowId) in allEntries {
            if !activeWorkspaceIds.contains(wsId) {
                inactiveWorkspaceWindowIds.insert(windowId)
            }
        }
    }

    func markWindowActive(_ windowId: Int) {
        inactiveWorkspaceWindowIds.remove(windowId)
    }

    func markWindowInactive(_ windowId: Int) {
        inactiveWorkspaceWindowIds.insert(windowId)
    }

    func forceApplyNextFrame(for windowId: Int) {
        forceApplyWindowIds.insert(windowId)
        lastAppliedFrames.removeValue(forKey: windowId)
    }

    func clearInactiveWorkspaceWindows() {
        inactiveWorkspaceWindowIds.removeAll()
    }

    func cleanup() {
        stopLifecycleObservation()
        AXRuntimeBridge.shared.setCallbacks(
            onWindowDestroyed: nil,
            onWindowDestroyedUnknown: nil,
            onFocusedWindowChanged: nil
        )
    }

    func windowsForApp(_ app: NSRunningApplication) async -> [(AXWindowRef, pid_t, Int)] {
        guard shouldTrack(app) else { return [] }
        AXRuntimeBridge.shared.track(app: app)
        let records = AXRuntimeBridge.shared.enumerateWindows().filter {
            $0.pid == app.processIdentifier && $0.window_type == AXRuntimeBridge.tilingWindowTypeRaw
        }
        return records.map { record in
            let ref = AXWindowRef(pid: pid_t(record.pid), windowId: Int(record.window_id))
            return (ref, pid_t(record.pid), Int(record.window_id))
        }
    }

    func requestPermission() -> Bool {
        if AccessibilityPermissionMonitor.shared.refreshNow() { return true }
        _ = omni_ax_permission_request_prompt()
        return AccessibilityPermissionMonitor.shared.refreshNow()
    }

    func currentWindowsAsync() async -> [(AXWindowRef, pid_t, Int)] {
        let visibleWindows = SkyLight.shared.queryAllVisibleWindows()
        let pidsWithWindows = Set(visibleWindows.map { $0.pid })

        let apps = NSWorkspace.shared.runningApplications.filter {
            shouldTrack($0) && pidsWithWindows.contains($0.processIdentifier)
        }

        for app in apps {
            AXRuntimeBridge.shared.track(app: app)
        }

        let tilingRecords = AXRuntimeBridge.shared.enumerateWindows().filter {
            pidsWithWindows.contains($0.pid) && $0.window_type == AXRuntimeBridge.tilingWindowTypeRaw
        }

        return tilingRecords.map { record in
            let ref = AXWindowRef(pid: pid_t(record.pid), windowId: Int(record.window_id))
            return (ref, pid_t(record.pid), Int(record.window_id))
        }
    }

    func applyFramesParallel(_ frames: [(pid: pid_t, windowId: Int, frame: CGRect)]) {
        for key in framesByPidBuffer.keys {
            framesByPidBuffer[key]?.removeAll(keepingCapacity: true)
        }

        for (pid, windowId, frame) in frames {
            if inactiveWorkspaceWindowIds.contains(windowId) {
                continue
            }

            let shouldForceApply = forceApplyWindowIds.remove(windowId) != nil
            if let cached = lastAppliedFrames[windowId],
               abs(cached.origin.x - frame.origin.x) < 0.5,
               abs(cached.origin.y - frame.origin.y) < 0.5,
               abs(cached.size.width - frame.size.width) < 0.5,
               abs(cached.size.height - frame.size.height) < 0.5,
               !shouldForceApply {
                continue
            }

            lastAppliedFrames[windowId] = frame
            if framesByPidBuffer[pid] == nil {
                framesByPidBuffer[pid] = []
                framesByPidBuffer[pid]?.reserveCapacity(8)
            }
            framesByPidBuffer[pid]?.append((windowId, frame))
        }

        var requests: [OmniAXFrameRequest] = []
        requests.reserveCapacity(frames.count)

        for (pid, appFrames) in framesByPidBuffer where !appFrames.isEmpty {
            for (windowId, frame) in appFrames {
                let wsFrame = ScreenCoordinateSpace.toWindowServer(rect: frame)
                requests.append(
                    OmniAXFrameRequest(
                        pid: Int32(pid),
                        window_id: UInt32(windowId),
                        frame: OmniBorderRect(
                            x: wsFrame.origin.x,
                            y: wsFrame.origin.y,
                            width: wsFrame.size.width,
                            height: wsFrame.size.height
                        )
                    )
                )
            }
        }

        AXRuntimeBridge.shared.applyFrames(requests)
    }

    func cancelPendingFrameJobs(_ entries: [(pid: pid_t, windowId: Int)]) {
        let keys = entries.map {
            OmniAXWindowKey(pid: Int32($0.pid), window_id: UInt32($0.windowId))
        }
        AXRuntimeBridge.shared.cancelFrameJobs(keys)
    }

    func suppressFrameWrites(_ entries: [(pid: pid_t, windowId: Int)]) {
        for (_, windowId) in entries {
            lastAppliedFrames.removeValue(forKey: windowId)
        }
        let keys = entries.map {
            OmniAXWindowKey(pid: Int32($0.pid), window_id: UInt32($0.windowId))
        }
        AXRuntimeBridge.shared.suppressFrameWrites(keys)
    }

    func unsuppressFrameWrites(_ entries: [(pid: pid_t, windowId: Int)]) {
        let keys = entries.map {
            OmniAXWindowKey(pid: Int32($0.pid), window_id: UInt32($0.windowId))
        }
        AXRuntimeBridge.shared.unsuppressFrameWrites(keys)
    }

    func applyPositionsViaSkyLight(
        _ positions: [(windowId: Int, origin: CGPoint)],
        allowInactive: Bool = false
    ) {
        let filtered = allowInactive
            ? positions
            : positions.filter { !inactiveWorkspaceWindowIds.contains($0.windowId) }
        guard !filtered.isEmpty else { return }
        let batchPositions = filtered.map {
            (windowId: UInt32($0.windowId), origin: ScreenCoordinateSpace.toWindowServer(point: $0.origin))
        }
        SkyLight.shared.batchMoveWindows(batchPositions)
    }

    private func shouldTrack(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, app.activationPolicy != .prohibited else { return false }
        if let bundleId = app.bundleIdentifier, Self.systemUIBundleIds.contains(bundleId) {
            return false
        }
        return true
    }
}
