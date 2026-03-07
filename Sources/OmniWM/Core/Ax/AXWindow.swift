import AppKit
import ApplicationServices
import Foundation

struct AXWindowRef: Hashable, @unchecked Sendable {
    let pid: pid_t
    let windowId: Int

    init(pid: pid_t, windowId: Int) {
        self.pid = pid
        self.windowId = windowId
    }

    init(element: AXUIElement) throws {
        var resolvedPid: pid_t = 0
        guard AXUIElementGetPid(element, &resolvedPid) == .success,
              let value = getWindowId(from: element) else {
            throw AXErrorWrapper.cannotGetWindowId
        }
        self.pid = resolvedPid
        self.windowId = Int(value)
    }

    var element: AXUIElement {
        AXWindowService.axElement(for: self) ?? AXUIElementCreateApplication(pid)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(windowId)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && lhs.windowId == rhs.windowId
    }
}

enum AXErrorWrapper: Error {
    case cannotSetFrame
    case cannotGetAttribute
    case cannotGetWindowId
}

enum AXWindowService {
    @MainActor
    static func titlePreferFast(windowId: UInt32) -> String? {
        SkyLight.shared.getWindowTitle(windowId)
    }

    static func windowId(_ window: AXWindowRef) -> Int {
        window.windowId
    }

    static func frame(_ window: AXWindowRef) throws(AXErrorWrapper) -> CGRect {
        guard let wsFrame = AXRuntimeBridge.shared.getWindowFrame(pid: window.pid, windowId: window.windowId) else {
            throw .cannotGetAttribute
        }
        return convertFromAX(wsFrame)
    }

    @MainActor
    static func fastFrame(_ window: AXWindowRef) -> CGRect? {
        guard let frame = SkyLight.shared.getWindowBounds(UInt32(windowId(window))) else { return nil }
        return ScreenCoordinateSpace.toAppKit(rect: frame)
    }

    @MainActor
    static func framePreferFast(_ window: AXWindowRef) -> CGRect? {
        fastFrame(window) ?? (try? frame(window))
    }

    static func setFrame(_ window: AXWindowRef, frame: CGRect) throws(AXErrorWrapper) {
        let wsFrame = convertToAX(frame)
        let ok = AXRuntimeBridge.shared.setWindowFrame(pid: window.pid, windowId: window.windowId, frame: wsFrame)
        guard ok else { throw .cannotSetFrame }
    }

    private static func convertFromAX(_ rect: CGRect) -> CGRect {
        ScreenCoordinateSpace.toAppKit(rect: rect)
    }

    private static func convertToAX(_ rect: CGRect) -> CGRect {
        ScreenCoordinateSpace.toWindowServer(rect: rect)
    }

    static func subrole(_ window: AXWindowRef) -> String? {
        guard let element = axElement(for: window) else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        guard result == .success, let subrole = value as? String else { return nil }
        return subrole
    }

    static func isFullscreen(_ window: AXWindowRef) -> Bool {
        if let subrole = subrole(window), subrole == "AXFullScreenWindow" {
            return true
        }
        return AXRuntimeBridge.shared.isWindowFullscreen(pid: window.pid, windowId: window.windowId)
    }

    static func setNativeFullscreen(_ window: AXWindowRef, fullscreen: Bool) -> Bool {
        AXRuntimeBridge.shared.setWindowFullscreen(pid: window.pid, windowId: window.windowId, fullscreen: fullscreen)
    }

    private static func isFullscreenFrame(_ frame: CGRect) -> Bool {
        let center = frame.center
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) else {
            return false
        }
        return frame.approximatelyEqual(to: screen.frame, tolerance: 2.0)
    }

    static func windowType(
        _ window: AXWindowRef,
        appPolicy: NSApplication.ActivationPolicy?,
        bundleId: String? = nil
    ) -> AXWindowType {
        let forceFloating = DefaultFloatingApps.shouldFloat(bundleId)
        return AXRuntimeBridge.shared.getWindowType(
            pid: window.pid,
            windowId: window.windowId,
            appPolicy: appPolicy,
            forceFloating: forceFloating
        )
    }

    static func sizeConstraints(_ window: AXWindowRef, currentSize: CGSize? = nil) -> WindowSizeConstraints {
        guard let raw = AXRuntimeBridge.shared.getWindowConstraints(pid: window.pid, windowId: window.windowId) else {
            if let size = currentSize {
                return .fixed(size: size)
            }
            return .unconstrained
        }

        var constraints = WindowSizeConstraints(
            minSize: CGSize(width: raw.min_width, height: raw.min_height),
            maxSize: CGSize(width: raw.max_width, height: raw.max_height),
            isFixed: raw.is_fixed == 1
        )

        if raw.has_max_width != 1 {
            constraints.maxSize.width = 0
        }
        if raw.has_max_height != 1 {
            constraints.maxSize.height = 0
        }

        return constraints
    }

    static func axWindowRef(for windowId: UInt32, pid: pid_t) -> AXWindowRef? {
        guard axElement(pid: pid, windowId: Int(windowId)) != nil else { return nil }
        return AXWindowRef(pid: pid, windowId: Int(windowId))
    }

    static func axElement(for window: AXWindowRef) -> AXUIElement? {
        axElement(pid: window.pid, windowId: window.windowId)
    }

    static func axElement(pid: pid_t, windowId: Int) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            if let winId = getWindowId(from: window), Int(winId) == windowId {
                return window
            }
        }

        return nil
    }
}

enum AXWindowType {
    case tiling
    case floating
}
