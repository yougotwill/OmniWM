import XCTest
@testable import OmniWM

@MainActor
final class WorkspaceEventHubTests: XCTestCase {
    @MainActor
    final class StubSource: WorkspaceEventSource {
        var shouldStart = true
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private var handler: (@MainActor (WorkspaceEventHub.Event) -> Void)?

        init(shouldStart: Bool = true) {
            self.shouldStart = shouldStart
        }

        func start(handler: @escaping @MainActor (WorkspaceEventHub.Event) -> Void) -> Bool {
            startCount += 1
            guard shouldStart else {
                self.handler = nil
                return false
            }
            self.handler = handler
            return true
        }

        func stop() {
            stopCount += 1
            handler = nil
        }

        func emit(_ event: WorkspaceEventHub.Event) {
            handler?(event)
        }
    }

    func testPrefersRuntimeSourceWhenAvailable() {
        let runtime = StubSource(shouldStart: true)
        let fallback = StubSource(shouldStart: true)
        let hub = WorkspaceEventHub(runtimeSource: runtime, legacySource: fallback)

        var seenActivatedPid: pid_t?
        let token = hub.subscribe { event in
            if case let .activated(pid) = event {
                seenActivatedPid = pid
            }
        }

        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(fallback.startCount, 0)

        runtime.emit(.activated(42))
        XCTAssertEqual(seenActivatedPid, 42)

        hub.unsubscribe(token)
        XCTAssertEqual(runtime.stopCount, 1)
        XCTAssertEqual(fallback.stopCount, 0)
    }

    func testFallsBackWhenRuntimeSourceCannotStart() {
        let runtime = StubSource(shouldStart: false)
        let fallback = StubSource(shouldStart: true)
        let hub = WorkspaceEventHub(runtimeSource: runtime, legacySource: fallback)

        var activeSpaceEventCount = 0
        let token = hub.subscribe { event in
            if case .activeSpaceChanged = event {
                activeSpaceEventCount += 1
            }
        }

        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(fallback.startCount, 1)

        fallback.emit(.activeSpaceChanged)
        XCTAssertEqual(activeSpaceEventCount, 1)

        hub.unsubscribe(token)
        XCTAssertEqual(runtime.stopCount, 0)
        XCTAssertEqual(fallback.stopCount, 1)
    }

    func testSourceStopsAfterLastSubscriberUnsubscribes() {
        let runtime = StubSource(shouldStart: true)
        let fallback = StubSource(shouldStart: true)
        let hub = WorkspaceEventHub(runtimeSource: runtime, legacySource: fallback)

        let token1 = hub.subscribe { _ in }
        let token2 = hub.subscribe { _ in }

        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.stopCount, 0)

        hub.unsubscribe(token1)
        XCTAssertEqual(runtime.stopCount, 0)

        hub.unsubscribe(token2)
        XCTAssertEqual(runtime.stopCount, 1)
    }
}
