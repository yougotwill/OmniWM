import CoreGraphics
import Foundation

enum BorderUpdateMode {
    case coalesced
    case realtime
}

extension WMController {
    func syncBorderConfigFromSettings() {
        refreshBorderPresentation()
    }

    func refreshBorderPresentation(
        focusedFrame _: CGRect? = nil,
        windowId _: Int? = nil,
        forceHide _: Bool = false,
        updateMode _: BorderUpdateMode = .coalesced
    ) {}

    func invalidateBorderDisplays() {}

    func cleanupBorderRuntime() {}

    func resetBorderRuntimeHealth() {}
}
