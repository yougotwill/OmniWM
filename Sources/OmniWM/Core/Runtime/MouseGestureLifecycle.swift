import Foundation

struct MouseGestureLifecyclePolicy {
    enum Phase: Equatable {
        case idle
        case armed
        case committed
    }

    enum EarlyExitAction: Equatable {
        case resetOnly
        case cancelAndReset
    }

    enum EndedOrCancelledAction: Equatable {
        case resetOnly
        case finalizeThenReset
        case cancelAndReset
    }

    static func earlyExitAction(phase: Phase) -> EarlyExitAction {
        switch phase {
        case .idle, .armed:
            .resetOnly
        case .committed:
            .cancelAndReset
        }
    }

    static func endedOrCancelledAction(
        phase: Phase,
        hasLockedContext: Bool
    ) -> EndedOrCancelledAction {
        switch phase {
        case .idle, .armed:
            .resetOnly
        case .committed:
            hasLockedContext ? .finalizeThenReset : .cancelAndReset
        }
    }
}

struct MouseGestureLifecycleExecutor {
    static func executeEarlyExit(
        action: MouseGestureLifecyclePolicy.EarlyExitAction,
        cancel: () -> Void,
        reset: () -> Void
    ) {
        switch action {
        case .resetOnly:
            reset()
        case .cancelAndReset:
            cancel()
            reset()
        }
    }

    static func executeEndedOrCancelled(
        action: MouseGestureLifecyclePolicy.EndedOrCancelledAction,
        cancel: () -> Void,
        finalize: () -> Void,
        reset: () -> Void
    ) {
        switch action {
        case .resetOnly:
            reset()
        case .finalizeThenReset:
            finalize()
            reset()
        case .cancelAndReset:
            cancel()
            reset()
        }
    }

    static func executeFinalizeResult(
        didEndGesture: Bool,
        startAnimation: () -> Void,
        cancel: () -> Void
    ) {
        if didEndGesture {
            startAnimation()
        } else {
            cancel()
        }
    }
}

struct MouseGestureRefreshCoalescer {
    enum Action: Equatable {
        case refreshNow
        case scheduleAfter(TimeInterval)
        case none
    }

    static func minimumInterval(refreshRate: Double) -> TimeInterval {
        let clampedRate = max(1.0, refreshRate)
        return 1.0 / clampedRate
    }

    static func action(
        now: TimeInterval,
        lastRefreshTime: TimeInterval?,
        hasPendingTask: Bool,
        refreshRate: Double
    ) -> Action {
        guard let lastRefreshTime else {
            return .refreshNow
        }

        let minInterval = minimumInterval(refreshRate: refreshRate)
        let elapsed = now - lastRefreshTime
        if elapsed >= minInterval {
            return .refreshNow
        }
        if hasPendingTask {
            return .none
        }
        return .scheduleAfter(minInterval - elapsed)
    }
}
