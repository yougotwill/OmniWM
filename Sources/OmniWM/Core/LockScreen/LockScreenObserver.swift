import AppKit
import Foundation

@MainActor
enum LockScreenValidation {
    static func shouldApplyLockHint(frontmostBundleId: String?) -> Bool {
        frontmostBundleId == LockScreenObserver.lockScreenAppBundleId
    }

    static func shouldApplyUnlockHint(frontmostBundleId: String?) -> Bool {
        frontmostBundleId != LockScreenObserver.lockScreenAppBundleId
    }
}

@MainActor
final class LockScreenObserver {
    static let lockScreenAppBundleId = "com.apple.loginwindow"

    enum LockState {
        case unlocked
        case locked
        case transitioning
    }

    private(set) var state: LockState = .unlocked
    var onLockDetected: (() -> Void)?
    var onUnlockDetected: (() -> Void)?

    private var runtimeToken: UUID?
    private var activationObserver: NSObjectProtocol?
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?

    init() {}

    func start() {
        guard runtimeToken == nil,
              activationObserver == nil,
              screenLockObserver == nil,
              screenUnlockObserver == nil
        else {
            return
        }

        if OmniLockObserverRuntimeAdapter.shared.start(),
           let token = OmniLockObserverRuntimeAdapter.shared.subscribe({ [weak self] event in
               switch event {
               case .locked:
                   self?.handleLockHint()
               case .unlocked:
                   self?.handleUnlockHint()
               }
           }) {
            runtimeToken = token
            return
        }

        OmniLockObserverRuntimeAdapter.shared.stop()
        setupLegacyObservers()
    }

    func stop() {
        cleanup()
    }

    private func setupLegacyObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        activationObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.handleAppActivation(bundleId: app.bundleIdentifier)
            }
        }

        let dnc = DistributedNotificationCenter.default()
        screenLockObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleLockHint()
            }
        }

        screenUnlockObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleUnlockHint()
            }
        }
    }

    private func handleAppActivation(bundleId: String?) {
        if bundleId == Self.lockScreenAppBundleId {
            handleLockEvent()
        } else if state == .locked || state == .transitioning {
            handleUnlockEvent()
        }
    }

    private func handleLockHint() {
        guard LockScreenValidation.shouldApplyLockHint(frontmostBundleId: frontmostBundleId()) else { return }
        handleLockEvent()
    }

    private func handleUnlockHint() {
        guard LockScreenValidation.shouldApplyUnlockHint(frontmostBundleId: frontmostBundleId()) else { return }
        handleUnlockEvent()
    }

    private func handleLockEvent() {
        guard state != .locked else { return }
        state = .locked
        onLockDetected?()
    }

    private func handleUnlockEvent() {
        guard state != .unlocked else { return }
        state = .transitioning
        onUnlockDetected?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if self.state == .transitioning {
                self.state = .unlocked
            }
        }
    }

    private func frontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func isFrontmostAppLockScreen() -> Bool {
        frontmostBundleId() == Self.lockScreenAppBundleId
    }

    func cleanup() {
        if let token = runtimeToken {
            OmniLockObserverRuntimeAdapter.shared.unsubscribe(token)
            runtimeToken = nil
            OmniLockObserverRuntimeAdapter.shared.stop()
        }

        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }

        let dnc = DistributedNotificationCenter.default()
        if let observer = screenLockObserver {
            dnc.removeObserver(observer)
            screenLockObserver = nil
        }
        if let observer = screenUnlockObserver {
            dnc.removeObserver(observer)
            screenUnlockObserver = nil
        }
    }
}
