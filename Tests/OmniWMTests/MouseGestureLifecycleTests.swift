import XCTest
@testable import OmniWM

final class MouseGestureLifecycleTests: XCTestCase {
    func testEarlyExitActions() {
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.earlyExitAction(phase: .idle),
            .resetOnly
        )
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.earlyExitAction(phase: .armed),
            .resetOnly
        )
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.earlyExitAction(phase: .committed),
            .cancelAndReset
        )
    }

    func testEndedOrCancelledActions() {
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.endedOrCancelledAction(
                phase: .idle,
                hasLockedContext: false
            ),
            .resetOnly
        )
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.endedOrCancelledAction(
                phase: .armed,
                hasLockedContext: true
            ),
            .resetOnly
        )
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.endedOrCancelledAction(
                phase: .committed,
                hasLockedContext: true
            ),
            .finalizeThenReset
        )
        XCTAssertEqual(
            MouseGestureLifecyclePolicy.endedOrCancelledAction(
                phase: .committed,
                hasLockedContext: false
            ),
            .cancelAndReset
        )
    }

    func testExecutorEarlyExitCommittedCallsCancelThenReset() {
        var effects: [String] = []
        MouseGestureLifecycleExecutor.executeEarlyExit(
            action: .cancelAndReset,
            cancel: { effects.append("cancel") },
            reset: { effects.append("reset") }
        )
        XCTAssertEqual(effects, ["cancel", "reset"])
    }

    func testExecutorEndedCancelledCommittedWithContextCallsFinalizeThenReset() {
        var effects: [String] = []
        MouseGestureLifecycleExecutor.executeEndedOrCancelled(
            action: .finalizeThenReset,
            cancel: { effects.append("cancel") },
            finalize: { effects.append("finalize") },
            reset: { effects.append("reset") }
        )
        XCTAssertEqual(effects, ["finalize", "reset"])
    }

    func testExecutorEndedCancelledCommittedWithoutContextCallsCancelThenReset() {
        var effects: [String] = []
        MouseGestureLifecycleExecutor.executeEndedOrCancelled(
            action: .cancelAndReset,
            cancel: { effects.append("cancel") },
            finalize: { effects.append("finalize") },
            reset: { effects.append("reset") }
        )
        XCTAssertEqual(effects, ["cancel", "reset"])
    }

    func testExecutorFinalizeFailureCancelsOnly() {
        var effects: [String] = []
        MouseGestureLifecycleExecutor.executeFinalizeResult(
            didEndGesture: false,
            startAnimation: { effects.append("start") },
            cancel: { effects.append("cancel") }
        )
        XCTAssertEqual(effects, ["cancel"])
    }

    func testCoalescerFirstEventRefreshesImmediately() {
        XCTAssertEqual(
            MouseGestureRefreshCoalescer.action(
                now: 1.0,
                lastRefreshTime: nil,
                hasPendingTask: false,
                refreshRate: 120
            ),
            .refreshNow
        )
    }

    func testCoalescerSubsequentEventWithinFrameSchedulesDeferredRefresh() {
        let refreshRate = 120.0
        let minInterval = MouseGestureRefreshCoalescer.minimumInterval(refreshRate: refreshRate)
        let now = 1.003
        let last = 1.0
        let action = MouseGestureRefreshCoalescer.action(
            now: now,
            lastRefreshTime: last,
            hasPendingTask: false,
            refreshRate: refreshRate
        )
        guard case let .scheduleAfter(delay) = action else {
            return XCTFail("Expected deferred scheduling, got \(action)")
        }
        XCTAssertEqual(delay, minInterval - (now - last), accuracy: 0.000_001)
        let fireAt = now + delay
        XCTAssertEqual(fireAt, last + minInterval, accuracy: 0.000_001)
    }

    func testCoalescerPendingTaskSuppressesDuplicatesUntilBoundary() {
        XCTAssertEqual(
            MouseGestureRefreshCoalescer.action(
                now: 1.004,
                lastRefreshTime: 1.0,
                hasPendingTask: true,
                refreshRate: 120
            ),
            .none
        )
    }

    func testCoalescerRefreshReopensOnNextFrame() {
        let refreshRate = 120.0
        let minInterval = MouseGestureRefreshCoalescer.minimumInterval(refreshRate: refreshRate)
        let boundary = 1.0 + minInterval
        XCTAssertEqual(
            MouseGestureRefreshCoalescer.action(
                now: boundary + minInterval + 0.000_1,
                lastRefreshTime: boundary,
                hasPendingTask: false,
                refreshRate: refreshRate
            ),
            .refreshNow
        )
    }
}
