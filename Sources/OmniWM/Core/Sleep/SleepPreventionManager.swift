import AppKit
import CZigLayout

@MainActor
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    private var sleepAssertionID: UInt32?
    private var isUserSessionActive = true
    private var isPreventionEnabled = false

    private init() {
        setupWorkspaceNotifications()
    }

    func preventSleep() {
        isPreventionEnabled = true
        reconcileAssertionOwnership()
    }

    func allowSleep() {
        isPreventionEnabled = false
        reconcileAssertionOwnership()
    }

    private func reconcileAssertionOwnership() {
        let shouldHoldAssertion = isPreventionEnabled && isUserSessionActive

        if shouldHoldAssertion {
            acquireAssertionIfNeeded()
        } else {
            releaseSleepAssertion()
        }
    }

    private func acquireAssertionIfNeeded() {
        guard sleepAssertionID == nil else { return }

        var assertionID: UInt32 = 0
        if omni_sleep_prevention_create_assertion(&assertionID) == Int32(OMNI_OK) {
            sleepAssertionID = assertionID
        }
    }

    private func releaseSleepAssertion() {
        guard let assertionID = sleepAssertionID else { return }
        _ = omni_sleep_prevention_release_assertion(assertionID)
        sleepAssertionID = nil
    }

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func sessionDidResignActive() {
        isUserSessionActive = false
        reconcileAssertionOwnership()
    }

    @objc private func sessionDidBecomeActive() {
        isUserSessionActive = true
        reconcileAssertionOwnership()
    }
}
