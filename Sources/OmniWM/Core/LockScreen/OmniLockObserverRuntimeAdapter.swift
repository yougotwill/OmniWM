import CZigLayout
import Foundation

private func omniLockObserverLockedBridge(_ userdata: UnsafeMutableRawPointer?) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniLockObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.locked)
    }
    return Int32(OMNI_OK)
}

private func omniLockObserverUnlockedBridge(_ userdata: UnsafeMutableRawPointer?) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniLockObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.unlocked)
    }
    return Int32(OMNI_OK)
}

@MainActor
final class OmniLockObserverRuntimeAdapter {
    enum Event: Sendable {
        case locked
        case unlocked
    }

    typealias EventHandler = @MainActor (Event) -> Void

    static let shared = OmniLockObserverRuntimeAdapter()

    private var runtime: OpaquePointer?
    private(set) var started = false
    private var handlers: [UUID: EventHandler] = [:]

    private init() {}

    @discardableResult
    func start() -> Bool {
        if started {
            return true
        }

        var config = OmniLockObserverRuntimeConfig(
            abi_version: UInt32(OMNI_LOCK_OBSERVER_RUNTIME_ABI_VERSION),
            reserved: 0
        )
        var host = OmniLockObserverHostVTable(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            on_locked: omniLockObserverLockedBridge,
            on_unlocked: omniLockObserverUnlockedBridge
        )

        runtime = withUnsafePointer(to: &config) { configPtr in
            withUnsafePointer(to: &host) { hostPtr in
                omni_lock_observer_runtime_create(configPtr, hostPtr)
            }
        }

        guard let runtime else {
            started = false
            return false
        }

        if omni_lock_observer_runtime_start(runtime) == Int32(OMNI_OK) {
            started = true
            return true
        }

        omni_lock_observer_runtime_destroy(runtime)
        self.runtime = nil
        started = false
        return false
    }

    func stop() {
        handlers.removeAll(keepingCapacity: false)

        guard let runtime else {
            started = false
            return
        }

        if started {
            _ = omni_lock_observer_runtime_stop(runtime)
        }
        omni_lock_observer_runtime_destroy(runtime)
        self.runtime = nil
        started = false
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

    fileprivate func dispatch(_ event: Event) {
        guard started else { return }
        for handler in handlers.values {
            handler(event)
        }
    }
}
