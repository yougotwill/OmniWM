import CZigLayout
import CoreGraphics
import Foundation

enum SkyLightWindowOrder: Int32 {
    case above = 0
    case below = -1
}

@MainActor
final class SkyLight {
    static let shared = SkyLight()

    private init() {
        var capabilities = OmniSkyLightCapabilities()
        _ = omni_skylight_get_capabilities(&capabilities)
    }

    func getMainConnectionID() -> Int32 {
        omni_skylight_get_main_connection_id()
    }

    func cornerRadius(forWindowId _: Int) -> CGFloat? {
        nil
    }

    func orderWindow(_ wid: UInt32, relativeTo targetWid: UInt32, order: SkyLightWindowOrder = .above) {
        _ = omni_skylight_order_window(wid, targetWid, order.rawValue)
    }

    @discardableResult
    func moveWindow(_ wid: UInt32, to point: CGPoint) -> Bool {
        omni_skylight_move_window(wid, point.x, point.y) == Int32(OMNI_OK)
    }

    func getWindowBounds(_ wid: UInt32) -> CGRect? {
        var rect = OmniBorderRect()
        guard omni_skylight_get_window_bounds(wid, &rect) == Int32(OMNI_OK) else { return nil }
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    func batchMoveWindows(_ positions: [(windowId: UInt32, origin: CGPoint)]) {
        guard !positions.isEmpty else { return }
        var requests = positions.map { position in
            OmniSkyLightMoveRequest(window_id: position.windowId, origin_x: position.origin.x, origin_y: position.origin.y)
        }
        requests.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = omni_skylight_batch_move_windows(baseAddress, buffer.count)
        }
    }

    func queryAllVisibleWindows() -> [WindowServerInfo] {
        let infos = queryVisibleWindowsRaw()
        return infos.compactMap { info in
            let parentId = info.parent_id
            guard parentId == 0 else { return nil }

            let level = info.level
            guard level == 0 || level == 3 || level == 8 else { return nil }

            let tags = info.tags
            let attributes = info.attributes
            let hasVisibleAttribute = (attributes & 0x2) != 0
            let hasTagBit54 = (tags & 0x0040_0000_0000_0000) != 0
            guard hasVisibleAttribute || hasTagBit54 else { return nil }

            let isDocument = (tags & 0x1) != 0
            let isFloating = (tags & 0x2) != 0
            let isModal = (tags & 0x8000_0000) != 0
            guard isDocument || (isFloating && isModal) else { return nil }

            return Self.makeWindowServerInfo(info)
        }
    }

    func queryWindowInfo(_ windowId: UInt32) -> WindowServerInfo? {
        var info = OmniSkyLightWindowInfo()
        guard omni_skylight_query_window_info(windowId, &info) == Int32(OMNI_OK) else { return nil }
        return Self.makeWindowServerInfo(info)
    }

    @discardableResult
    func subscribeToWindowNotifications(_ windowIds: [UInt32]) -> Bool {
        guard !windowIds.isEmpty else { return true }
        return windowIds.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return omni_skylight_subscribe_window_notifications(baseAddress, buffer.count) == Int32(OMNI_OK)
        }
    }

    func getWindowTitle(_ windowId: UInt32) -> String? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let windowList = CGWindowListCopyWindowInfo(options, CGWindowID(windowId)) as? [[String: Any]],
              let windowInfo = windowList.first,
              let title = windowInfo[kCGWindowName as String] as? String
        else { return nil }
        return title
    }

    private func queryVisibleWindowsRaw() -> [OmniSkyLightWindowInfo] {
        var total: Int = 0
        guard omni_skylight_query_visible_windows(nil, 0, &total) == Int32(OMNI_OK), total > 0 else {
            return []
        }

        var buffer = Array(repeating: OmniSkyLightWindowInfo(), count: total)
        var written: Int = 0
        let rc = buffer.withUnsafeMutableBufferPointer { buf in
            omni_skylight_query_visible_windows(buf.baseAddress, buf.count, &written)
        }
        guard rc == Int32(OMNI_OK), written > 0 else { return [] }

        let count = min(written, buffer.count)
        return Array(buffer.prefix(count))
    }

    private static func makeWindowServerInfo(_ info: OmniSkyLightWindowInfo) -> WindowServerInfo {
        WindowServerInfo(
            id: info.id,
            pid: info.pid,
            level: info.level,
            frame: CGRect(
                x: info.frame.x,
                y: info.frame.y,
                width: info.frame.width,
                height: info.frame.height
            ),
            tags: info.tags,
            attributes: info.attributes,
            parentId: info.parent_id
        )
    }
}

struct WindowServerInfo {
    let id: UInt32
    let pid: Int32
    let level: Int32
    let frame: CGRect
    var tags: UInt64 = 0
    var attributes: UInt32 = 0
    var parentId: UInt32 = 0
    var title: String?
}
