import XCTest
@testable import OmniWM

@MainActor
final class LockScreenValidationTests: XCTestCase {
    func testLockHintRequiresLoginWindowAsFrontmostApp() {
        XCTAssertTrue(
            LockScreenValidation.shouldApplyLockHint(
                frontmostBundleId: LockScreenObserver.lockScreenAppBundleId
            )
        )
        XCTAssertFalse(LockScreenValidation.shouldApplyLockHint(frontmostBundleId: "com.apple.finder"))
        XCTAssertFalse(LockScreenValidation.shouldApplyLockHint(frontmostBundleId: nil))
    }

    func testUnlockHintRejectsLoginWindowAndAcceptsOtherApps() {
        XCTAssertFalse(
            LockScreenValidation.shouldApplyUnlockHint(
                frontmostBundleId: LockScreenObserver.lockScreenAppBundleId
            )
        )
        XCTAssertTrue(LockScreenValidation.shouldApplyUnlockHint(frontmostBundleId: "com.apple.finder"))
        XCTAssertTrue(LockScreenValidation.shouldApplyUnlockHint(frontmostBundleId: nil))
    }
}
