import AppKit
import CoreGraphics
import CZigLayout
import Foundation

enum BorderPresentationUpdateMode {
    case coalesced
    case realtime

    var abiValue: UInt8 {
        switch self {
        case .coalesced:
            return 0
        case .realtime:
            return 1
        }
    }
}

@MainActor
extension WMController {
    func syncBorderConfigFromSettings() {
        refreshBorderPresentation()
    }

    func refreshBorderPresentation(
        focusedFrame: CGRect? = nil,
        windowId: Int? = nil,
        forceHide: Bool = false,
        updateMode: BorderPresentationUpdateMode = .coalesced
    ) {
        let displayInfos = currentBorderDisplays()
        var snapshot = buildBorderSnapshotInput(
            focusedFrame: focusedFrame,
            windowId: windowId,
            displays: displayInfos,
            forceHide: forceHide,
            updateMode: updateMode
        )
        focusManager.setAppFullscreen(active: snapshot.is_native_fullscreen_active != 0)
        let shouldCreateRuntime = snapshot.force_hide == 0 && snapshot.config.enabled != 0

        let rc = submitBorderSnapshot(
            &snapshot,
            displays: displayInfos,
            createIfMissing: shouldCreateRuntime
        )
        guard let rc else { return }
        handleBorderRuntimeResult(rc, operation: "omni_border_runtime_submit_snapshot")
    }

    func invalidateBorderDisplays() {
        borderDisplayCache.removeAll(keepingCapacity: false)
        borderDisplayCacheValid = false
        guard let rc = callBorderRuntime(
            operation: "omni_border_runtime_invalidate_displays",
            createIfMissing: false,
            invoke: { runtime in
                omni_border_runtime_invalidate_displays(runtime)
            }
        ) else { return }
        handleBorderRuntimeResult(rc, operation: "omni_border_runtime_invalidate_displays")
    }

    func cleanupBorderRuntime() {
        borderRuntimeStorage.destroy()
        clearBorderRuntimeFailures()
    }

    func resetBorderRuntimeHealth() {
        borderRuntimeStorage.destroy()
        clearBorderRuntimeFailures()
    }

    private func currentBorderConfig() -> OmniBorderConfig {
        let width = normalizedBorderWidth(settings.borderWidth)
        return OmniBorderConfig(
            enabled: settings.bordersEnabled ? 1 : 0,
            width: width,
            color: OmniBorderColor(
                red: normalizedColorComponent(settings.borderColorRed),
                green: normalizedColorComponent(settings.borderColorGreen),
                blue: normalizedColorComponent(settings.borderColorBlue),
                alpha: normalizedColorComponent(settings.borderColorAlpha)
            )
        )
    }

    private func buildBorderSnapshotInput(
        focusedFrame: CGRect?,
        windowId: Int?,
        displays: [OmniBorderDisplayInfo],
        forceHide: Bool,
        updateMode: BorderPresentationUpdateMode
    ) -> OmniBorderSnapshotInput {
        let config = currentBorderConfig()
        let snapshot = latestControllerSnapshot
        let isNonManagedFocusActive = snapshot?.nonManagedFocusActive ?? focusManager.isNonManagedFocusActive
        let currentFocusedHandle = isNonManagedFocusActive ? nil : self.focusedHandle
        let focusedEntry = currentFocusedHandle.flatMap { workspaceManager.entry(for: $0) }
        let focusedSnapshotWindow = currentFocusedHandle.flatMap { handle in
            snapshot?.window(handleId: handle.id)
        }
        let focusedWorkspaceId =
            focusedEntry?.workspaceId
            ?? currentFocusedHandle.flatMap(runtimeWorkspaceId(for:))
            ?? focusedSnapshotWindow?.workspaceId
        let activeWorkspaceId = activeWorkspace()?.id
        let activeWorkspaceMatch = activeWorkspaceId == focusedWorkspaceId
        let resolvedFrame = sanitizeBorderFrame(
            focusedFrame ?? focusedEntry.flatMap { try? AXWindowService.frame($0.axRef) }
        )
        let resolvedWindowId = normalizeWindowId(windowId ?? focusedEntry?.windowId ?? focusedSnapshotWindow?.windowId)
        let nativeFullscreen: Bool
        if focusedFrame != nil, windowId != nil {
            nativeFullscreen = focusManager.isAppFullscreenActive
        } else if let focusedEntry {
            nativeFullscreen = AXWindowService.isFullscreen(focusedEntry.axRef)
        } else {
            nativeFullscreen = snapshot?.appFullscreenActive ?? focusManager.isAppFullscreenActive
        }
        let managedFullscreen = currentFocusedHandle.map(isManagedBorderWindowFullscreen(_:)) ?? false
        let layoutAnimationActive = snapshot?.layoutAnimationActive
            ?? activeWorkspaceId.map { isLayoutAnimationActive(for: $0) }
            ?? false

        return OmniBorderSnapshotInput(
            config: config,
            has_focused_window_id: resolvedWindowId == nil ? 0 : 1,
            focused_window_id: Int64(resolvedWindowId ?? 0),
            has_focused_frame: resolvedFrame == nil ? 0 : 1,
            focused_frame: makeBorderRect(resolvedFrame ?? .zero),
            is_focused_window_in_active_workspace: activeWorkspaceMatch ? 1 : 0,
            is_non_managed_focus_active: isNonManagedFocusActive ? 1 : 0,
            is_native_fullscreen_active: nativeFullscreen ? 1 : 0,
            is_managed_fullscreen_active: managedFullscreen ? 1 : 0,
            defer_updates: 0,
            update_mode: updateMode.abiValue,
            layout_animation_active: layoutAnimationActive ? 1 : 0,
            force_hide: forceHide ? 1 : 0,
            displays: nil,
            display_count: displays.count
        )
    }

    private func currentBorderDisplays() -> [OmniBorderDisplayInfo] {
        if borderDisplayCacheValid {
            return borderDisplayCache
        }

        let screens = NSScreen.screens
        var displayInfos: [OmniBorderDisplayInfo] = []
        displayInfos.reserveCapacity(screens.count)

        for (index, screen) in screens.enumerated() {
            guard let appKitFrame = sanitizeBorderFrame(screen.frame) else { continue }
            let resolvedDisplayId = screen.displayId ?? fallbackDisplayId(for: index)
            let windowServerFrame = if let displayId = screen.displayId {
                sanitizeBorderFrame(CGDisplayBounds(displayId)) ?? appKitFrame
            } else {
                sanitizeBorderFrame(ScreenCoordinateSpace.toWindowServer(rect: appKitFrame)) ?? appKitFrame
            }
            displayInfos.append(OmniBorderDisplayInfo(
                display_id: resolvedDisplayId,
                appkit_frame: makeBorderRect(appKitFrame),
                window_server_frame: makeBorderRect(windowServerFrame),
                backing_scale: normalizedBackingScale(screen.backingScaleFactor)
            ))
        }

        if displayInfos.isEmpty, let primary = screens.first, let primaryFrame = sanitizeBorderFrame(primary.frame) {
            let fallbackId = primary.displayId ?? CGMainDisplayID()
            let wsFrame = sanitizeBorderFrame(ScreenCoordinateSpace.toWindowServer(rect: primaryFrame)) ?? primaryFrame
            displayInfos = [OmniBorderDisplayInfo(
                display_id: fallbackId,
                appkit_frame: makeBorderRect(primaryFrame),
                window_server_frame: makeBorderRect(wsFrame),
                backing_scale: normalizedBackingScale(primary.backingScaleFactor)
            )]
        }

        borderDisplayCache = displayInfos
        borderDisplayCacheValid = true
        return displayInfos
    }

    private func makeBorderRect(_ rect: CGRect) -> OmniBorderRect {
        OmniBorderRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    func isLayoutAnimationActive(for workspaceId: WorkspaceDescriptor.ID) -> Bool {
        if zigNiriEngine?.hasActiveAnimation(in: workspaceId) == true {
            return true
        }

        if layoutRefreshController.hasDwindleAnimationRunning(in: workspaceId) {
            return true
        }

        return false
    }

    private func isManagedBorderWindowFullscreen(_ handle: WindowHandle) -> Bool {
        guard let workspaceId = workspaceManager.workspace(for: handle),
              let workspaceView = zigNiriEngine?.workspaceView(for: workspaceId),
              let nodeId = zigNiriEngine?.nodeId(for: handle),
              let windowView = workspaceView.windowsById[nodeId]
        else {
            return false
        }
        return windowView.sizingMode == .fullscreen
    }

    private func callBorderRuntime(
        operation: String,
        createIfMissing: Bool = true,
        invoke: (OpaquePointer) -> Int32
    ) -> Int32? {
        let now = Date().timeIntervalSince1970
        if borderRuntimeDegraded, !shouldRetryBorderRuntime(at: now) {
            return nil
        }

        let runtime: OpaquePointer
        if let borderRuntime {
            runtime = borderRuntime
        } else {
            guard createIfMissing, let createdRuntime = ensureBorderRuntime(operation: operation, now: now) else {
                return nil
            }
            runtime = createdRuntime
        }

        return invoke(runtime)
    }

    private func ensureBorderRuntime(operation: String, now: TimeInterval) -> OpaquePointer? {
        if let borderRuntime {
            return borderRuntime
        }
        if borderRuntimeDegraded, !shouldRetryBorderRuntime(at: now) {
            return nil
        }
        guard let runtime = borderRuntimeFactory() else {
            recordBorderRuntimeCreationFailure(operation: operation, now: now)
            return nil
        }
        borderRuntimeStorage.store(runtime)
        clearBorderRuntimeFailures()
        return runtime
    }

    private func submitBorderSnapshot(
        _ snapshot: inout OmniBorderSnapshotInput,
        displays: [OmniBorderDisplayInfo],
        createIfMissing: Bool
    ) -> Int32? {
        func performSubmit() -> Int32? {
            displays.withUnsafeBufferPointer { displayBuffer -> Int32? in
                snapshot.displays = displayBuffer.baseAddress
                snapshot.display_count = displayBuffer.count
                return withUnsafePointer(to: &snapshot) { snapshotPtr in
                    callBorderRuntime(
                        operation: "omni_border_runtime_submit_snapshot",
                        createIfMissing: createIfMissing,
                        invoke: { runtime in
                            omni_border_runtime_submit_snapshot(runtime, snapshotPtr)
                        }
                    )
                }
            }
        }

        guard let rc = performSubmit() else { return nil }
        guard rc == Int32(OMNI_ERR_PLATFORM) else { return rc }

        // Retry once with a fresh runtime before considering backoff.
        borderRuntimeStorage.destroy()
        return performSubmit() ?? rc
    }

    private func handleBorderRuntimeResult(_ rc: Int32, operation: String) {
        if rc == Int32(OMNI_OK) {
            clearBorderRuntimeFailures()
            return
        }

        if rc == Int32(OMNI_ERR_INVALID_ARGS) || rc == Int32(OMNI_ERR_OUT_OF_RANGE) {
            NSLog("OmniWM: \(operation) rejected invalid border snapshot (rc=\(rc)); skipping update.")
            return
        }

        borderRuntimeFailureCount += 1
        if rc == Int32(OMNI_ERR_PLATFORM) {
            borderRuntimePlatformFailureStreak += 1
        } else {
            borderRuntimePlatformFailureStreak = 0
        }
        NSLog("OmniWM: \(operation) failed with rc=\(rc).")

        let shouldEnterBackoff = borderRuntimePlatformFailureStreak >= 3 || borderRuntimeFailureCount >= 5
        if shouldEnterBackoff {
            enterBorderRuntimeBackoff(reason: "\(operation) rc=\(rc)", now: Date().timeIntervalSince1970)
        }
    }

    private func recordBorderRuntimeCreationFailure(operation: String, now: TimeInterval) {
        borderRuntimeFailureCount += 1
        borderRuntimePlatformFailureStreak = 0
        enterBorderRuntimeBackoff(
            reason: "\(operation) runtime creation failed",
            now: now
        )
    }

    private func enterBorderRuntimeBackoff(reason: String, now: TimeInterval) {
        borderRuntimeStorage.destroy()
        borderRuntimeDegraded = true
        borderRuntimeRetryNotBefore = now + runtimeRetryDelaySeconds(for: borderRuntimeFailureCount)
        NSLog("OmniWM: border runtime unavailable (\(reason)); retrying after backoff.")
    }

    private func shouldRetryBorderRuntime(at now: TimeInterval) -> Bool {
        now >= borderRuntimeRetryNotBefore
    }

    private func runtimeRetryDelaySeconds(for failureCount: Int) -> TimeInterval {
        let clampedFailures = max(1, min(failureCount, 6))
        let multiplier = Double(1 << (clampedFailures - 1))
        return min(0.25 * multiplier, 4.0)
    }

    private func clearBorderRuntimeFailures() {
        borderRuntimeDegraded = false
        borderRuntimeFailureCount = 0
        borderRuntimePlatformFailureStreak = 0
        borderRuntimeRetryNotBefore = 0
    }

    private func normalizeWindowId(_ windowId: Int?) -> Int? {
        guard let windowId, windowId >= 0 else { return nil }
        return windowId
    }

    private func sanitizeBorderFrame(_ frame: CGRect?) -> CGRect? {
        guard let frame else { return nil }
        let normalized = frame.standardized
        guard normalized.origin.x.isFinite,
              normalized.origin.y.isFinite,
              normalized.size.width.isFinite,
              normalized.size.height.isFinite,
              normalized.size.width > 0,
              normalized.size.height > 0
        else {
            return nil
        }

        let maxAbsCoordinate = 1_000_000.0
        let values = [
            normalized.minX,
            normalized.minY,
            normalized.maxX,
            normalized.maxY
        ]
        guard values.allSatisfy({ abs($0) <= maxAbsCoordinate }) else {
            return nil
        }
        return normalized
    }

    private func normalizedBorderWidth(_ width: Double) -> Double {
        guard width.isFinite else { return 0 }
        return min(max(width, 0), 64)
    }

    private func normalizedColorComponent(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }

    private func normalizedBackingScale(_ scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else { return 2.0 }
        return scale
    }

    private func fallbackDisplayId(for index: Int) -> CGDirectDisplayID {
        CGMainDisplayID() &+ CGDirectDisplayID(index)
    }
}
