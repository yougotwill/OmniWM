import CZigLayout
import Foundation

@MainActor
final class AccessibilityPermissionMonitor {
    static let shared = AccessibilityPermissionMonitor()

    private var task: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private(set) var isGranted: Bool

    private init() {
        isGranted = omni_ax_permission_is_trusted() != 0
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let status = omni_ax_permission_is_trusted() != 0
                self.yield(status)
                let interval: Duration = status ? .milliseconds(750) : .milliseconds(250)
                try? await Task.sleep(for: interval)
            }
        }
    }

    deinit {
        task?.cancel()
        let currentContinuations = Array(continuations.values)
        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    func stream(initial: Bool = true) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            if initial {
                continuation.yield(isGranted)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func refreshNow() -> Bool {
        let status = omni_ax_permission_is_trusted() != 0
        yield(status)
        return status
    }

    private func yield(_ value: Bool) {
        guard value != isGranted else { return }
        isGranted = value
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }
}
