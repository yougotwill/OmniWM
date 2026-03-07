import AppKit
import Foundation

@MainActor
protocol WorkspaceEventSource: AnyObject {
    func start(handler: @escaping @MainActor (WorkspaceEventHub.Event) -> Void) -> Bool
    func stop()
}

@MainActor
final class RuntimeWorkspaceEventSource: WorkspaceEventSource {
    private var token: UUID?

    func start(handler: @escaping @MainActor (WorkspaceEventHub.Event) -> Void) -> Bool {
        guard OmniWorkspaceObserverRuntimeAdapter.shared.start() else {
            return false
        }

        guard let token = OmniWorkspaceObserverRuntimeAdapter.shared.subscribe({ event in
            switch event {
            case let .launched(pid):
                handler(.launched(pid))
            case let .terminated(pid):
                handler(.terminated(pid))
            case let .activated(pid):
                handler(.activated(pid))
            case let .hidden(pid):
                handler(.hidden(pid))
            case let .unhidden(pid):
                handler(.unhidden(pid))
            case .activeSpaceChanged:
                handler(.activeSpaceChanged)
            }
        }) else {
            OmniWorkspaceObserverRuntimeAdapter.shared.stop()
            return false
        }

        self.token = token
        return true
    }

    func stop() {
        if let token {
            OmniWorkspaceObserverRuntimeAdapter.shared.unsubscribe(token)
            self.token = nil
        }
        OmniWorkspaceObserverRuntimeAdapter.shared.stop()
    }
}

@MainActor
final class LegacyWorkspaceEventSource: WorkspaceEventSource {
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var hideObserver: NSObjectProtocol?
    private var unhideObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?

    func start(handler: @escaping @MainActor (WorkspaceEventHub.Event) -> Void) -> Bool {
        stop()

        let nc = NSWorkspace.shared.notificationCenter
        launchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let pid = Self.pid(from: notification) else { return }
            Task { @MainActor in
                handler(.launched(pid))
            }
        }
        terminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let pid = Self.pid(from: notification) else { return }
            Task { @MainActor in
                handler(.terminated(pid))
            }
        }
        activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let pid = Self.pid(from: notification) else { return }
            Task { @MainActor in
                handler(.activated(pid))
            }
        }
        hideObserver = nc.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let pid = Self.pid(from: notification) else { return }
            Task { @MainActor in
                handler(.hidden(pid))
            }
        }
        unhideObserver = nc.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let pid = Self.pid(from: notification) else { return }
            Task { @MainActor in
                handler(.unhidden(pid))
            }
        }
        activeSpaceObserver = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler(.activeSpaceChanged)
            }
        }

        return true
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        if let launchObserver {
            nc.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        if let terminateObserver {
            nc.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        if let activateObserver {
            nc.removeObserver(activateObserver)
            self.activateObserver = nil
        }
        if let hideObserver {
            nc.removeObserver(hideObserver)
            self.hideObserver = nil
        }
        if let unhideObserver {
            nc.removeObserver(unhideObserver)
            self.unhideObserver = nil
        }
        if let activeSpaceObserver {
            nc.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
    }

    nonisolated private static func pid(from notification: Notification) -> pid_t? {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return nil
        }
        let pid = app.processIdentifier
        return pid > 0 ? pid : nil
    }
}

@MainActor
final class WorkspaceEventHub {
    enum Event: Sendable {
        case launched(pid_t)
        case terminated(pid_t)
        case activated(pid_t)
        case hidden(pid_t)
        case unhidden(pid_t)
        case activeSpaceChanged
    }

    typealias EventHandler = @MainActor (Event) -> Void

    static let shared = WorkspaceEventHub()

    private let runtimeSource: WorkspaceEventSource
    private let legacySource: WorkspaceEventSource
    private var activeSource: WorkspaceEventSource?
    private var handlers: [UUID: EventHandler] = [:]

    init(
        runtimeSource: WorkspaceEventSource = RuntimeWorkspaceEventSource(),
        legacySource: WorkspaceEventSource = LegacyWorkspaceEventSource()
    ) {
        self.runtimeSource = runtimeSource
        self.legacySource = legacySource
    }

    func subscribe(_ handler: @escaping EventHandler) -> UUID {
        if activeSource == nil {
            activateSource()
        }
        let token = UUID()
        handlers[token] = handler
        return token
    }

    func unsubscribe(_ token: UUID) {
        handlers.removeValue(forKey: token)
        if handlers.isEmpty {
            deactivateSource()
        }
    }

    private func activateSource() {
        let forward: @MainActor (Event) -> Void = { [weak self] event in
            self?.emit(event)
        }

        if runtimeSource.start(handler: forward) {
            activeSource = runtimeSource
            return
        }

        _ = legacySource.start(handler: forward)
        activeSource = legacySource
    }

    private func deactivateSource() {
        activeSource?.stop()
        activeSource = nil
    }

    private func emit(_ event: Event) {
        for handler in handlers.values {
            handler(event)
        }
    }
}
