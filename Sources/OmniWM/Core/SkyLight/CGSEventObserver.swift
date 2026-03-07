import CZigLayout
import Foundation

enum CGSWindowEvent {
    case created(windowId: UInt32, spaceId: UInt64)
    case destroyed(windowId: UInt32, spaceId: UInt64)
    case moved(windowId: UInt32)
    case resized(windowId: UInt32)
    case closed(windowId: UInt32)
    case frontAppChanged(pid: pid_t)
    case titleChanged(windowId: UInt32)
}

@MainActor
protocol CGSEventDelegate: AnyObject {
    func cgsEventObserver(_ observer: CGSEventObserver, didReceive event: CGSWindowEvent)
}

@MainActor
final class CGSEventObserver {
    static let shared = CGSEventObserver()

    weak var delegate: CGSEventDelegate?

    private var runtime: OpaquePointer?
    private var isRegistered = false

    private init() {}

    func start() {
        guard !isRegistered else { return }

        var config = OmniPlatformRuntimeConfig(
            abi_version: UInt32(OMNI_PLATFORM_RUNTIME_ABI_VERSION),
            reserved: 0
        )

        var host = OmniPlatformHostVTable(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            on_window_created: { userdata, windowId, spaceId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .created(windowId: windowId, spaceId: spaceId))
                }
                return Int32(OMNI_OK)
            },
            on_window_destroyed: { userdata, windowId, spaceId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .destroyed(windowId: windowId, spaceId: spaceId))
                }
                return Int32(OMNI_OK)
            },
            on_window_closed: { userdata, windowId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .closed(windowId: windowId))
                }
                return Int32(OMNI_OK)
            },
            on_window_moved: { userdata, windowId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .moved(windowId: windowId))
                }
                return Int32(OMNI_OK)
            },
            on_window_resized: { userdata, windowId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .resized(windowId: windowId))
                }
                return Int32(OMNI_OK)
            },
            on_front_app_changed: { userdata, pid in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .frontAppChanged(pid: pid))
                }
                return Int32(OMNI_OK)
            },
            on_window_title_changed: { userdata, windowId in
                guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
                let observer = Unmanaged<CGSEventObserver>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async {
                    observer.delegate?.cgsEventObserver(observer, didReceive: .titleChanged(windowId: windowId))
                }
                return Int32(OMNI_OK)
            }
        )

        runtime = withUnsafePointer(to: &config) { configPtr in
            withUnsafePointer(to: &host) { hostPtr in
                omni_platform_runtime_create(configPtr, hostPtr)
            }
        }

        guard let runtime else {
            isRegistered = false
            return
        }

        let rc = omni_platform_runtime_start(runtime)
        isRegistered = (rc == Int32(OMNI_OK))
        if !isRegistered {
            omni_platform_runtime_destroy(runtime)
            self.runtime = nil
        }
    }

    func stop() {
        guard let runtime else {
            isRegistered = false
            return
        }
        _ = omni_platform_runtime_stop(runtime)
        omni_platform_runtime_destroy(runtime)
        self.runtime = nil
        isRegistered = false
    }

    @discardableResult
    func subscribeToWindows(_ windowIds: [UInt32]) -> Bool {
        guard !windowIds.isEmpty else { return true }
        guard let runtime else {
            return SkyLight.shared.subscribeToWindowNotifications(windowIds)
        }
        return windowIds.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            return omni_platform_runtime_subscribe_windows(runtime, baseAddress, buffer.count) == Int32(OMNI_OK)
        }
    }
}
