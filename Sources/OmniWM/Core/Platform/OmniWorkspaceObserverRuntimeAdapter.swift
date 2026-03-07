import CZigLayout
import Foundation

private func omniWorkspaceObserverLaunchBridge(_ userdata: UnsafeMutableRawPointer?, _ pid: Int32) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniWorkspaceObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.launched(pid_t(pid)))
    }
    return Int32(OMNI_OK)
}

private func omniWorkspaceObserverTerminateBridge(_ userdata: UnsafeMutableRawPointer?, _ pid: Int32) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniWorkspaceObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.terminated(pid_t(pid)))
    }
    return Int32(OMNI_OK)
}

private func omniWorkspaceObserverActivateBridge(_ userdata: UnsafeMutableRawPointer?, _ pid: Int32) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniWorkspaceObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.activated(pid_t(pid)))
    }
    return Int32(OMNI_OK)
}

private func omniWorkspaceObserverHideBridge(_ userdata: UnsafeMutableRawPointer?, _ pid: Int32) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniWorkspaceObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.hidden(pid_t(pid)))
    }
    return Int32(OMNI_OK)
}

private func omniWorkspaceObserverUnhideBridge(_ userdata: UnsafeMutableRawPointer?, _ pid: Int32) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniWorkspaceObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.unhidden(pid_t(pid)))
    }
    return Int32(OMNI_OK)
}

private func omniWorkspaceObserverActiveSpaceBridge(_ userdata: UnsafeMutableRawPointer?) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let adapter = Unmanaged<OmniWorkspaceObserverRuntimeAdapter>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        adapter.dispatch(.activeSpaceChanged)
    }
    return Int32(OMNI_OK)
}

@MainActor
final class OmniWorkspaceObserverRuntimeAdapter {
    enum Event: Sendable {
        case launched(pid_t)
        case terminated(pid_t)
        case activated(pid_t)
        case hidden(pid_t)
        case unhidden(pid_t)
        case activeSpaceChanged
    }

    typealias EventHandler = @MainActor (Event) -> Void

    static let shared = OmniWorkspaceObserverRuntimeAdapter()

    private var runtime: OpaquePointer?
    private(set) var started = false
    private var handlers: [UUID: EventHandler] = [:]

    private init() {}

    @discardableResult
    func start() -> Bool {
        if started {
            return true
        }

        var config = OmniWorkspaceObserverRuntimeConfig(
            abi_version: UInt32(OMNI_WORKSPACE_OBSERVER_RUNTIME_ABI_VERSION),
            reserved: 0
        )
        var host = OmniWorkspaceObserverHostVTable(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            on_app_launched: omniWorkspaceObserverLaunchBridge,
            on_app_terminated: omniWorkspaceObserverTerminateBridge,
            on_app_activated: omniWorkspaceObserverActivateBridge,
            on_app_hidden: omniWorkspaceObserverHideBridge,
            on_app_unhidden: omniWorkspaceObserverUnhideBridge,
            on_active_space_changed: omniWorkspaceObserverActiveSpaceBridge
        )

        runtime = withUnsafePointer(to: &config) { configPtr in
            withUnsafePointer(to: &host) { hostPtr in
                omni_workspace_observer_runtime_create(configPtr, hostPtr)
            }
        }

        guard let runtime else {
            started = false
            return false
        }

        if omni_workspace_observer_runtime_start(runtime) == Int32(OMNI_OK) {
            started = true
            return true
        }

        omni_workspace_observer_runtime_destroy(runtime)
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
            _ = omni_workspace_observer_runtime_stop(runtime)
        }
        omni_workspace_observer_runtime_destroy(runtime)
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

        switch event {
        case let .launched(pid),
             let .terminated(pid),
             let .activated(pid),
             let .hidden(pid),
             let .unhidden(pid):
            guard pid > 0 else { return }
        case .activeSpaceChanged:
            break
        }

        for handler in handlers.values {
            handler(event)
        }
    }
}
