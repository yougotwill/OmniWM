import CZigLayout
import XCTest

final class AXPermissionPollingTests: XCTestCase {
    func testPollRespectsMaxWaitBoundaryWhenIntervalIsLarger() {
        let started = DispatchTime.now().uptimeNanoseconds
        _ = omni_ax_permission_poll_until_trusted(25, 5_000)
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - started
        let elapsedMillis = Double(elapsedNanos) / 1_000_000

        XCTAssertLessThan(
            elapsedMillis,
            1_500,
            "AX permission poll should not overshoot max wait by seconds"
        )
    }
}
