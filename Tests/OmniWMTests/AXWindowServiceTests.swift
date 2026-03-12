import CoreGraphics
import Testing

@testable import OmniWM

@Suite struct AXWindowServiceTests {
    @Test func fullscreenEntryFromRightColumnUsesPositionThenSize() {
        let current = CGRect(x: 1276, y: 0, width: 1276, height: 1410)
        let target = CGRect(x: 0, y: 0, width: 2560, height: 1410)

        #expect(
            AXWindowService.frameWriteOrder(currentFrame: current, targetFrame: target) == .positionThenSize
        )
    }

    @Test func fullscreenEntryFromLeftColumnUsesPositionThenSize() {
        let current = CGRect(x: 8, y: 0, width: 1276, height: 1410)
        let target = CGRect(x: 0, y: 0, width: 2560, height: 1410)

        #expect(
            AXWindowService.frameWriteOrder(currentFrame: current, targetFrame: target) == .positionThenSize
        )
    }

    @Test func fullscreenEntryFromHalfHeightTileUsesPositionThenSize() {
        let current = CGRect(x: 8, y: 709, width: 1276, height: 701)
        let target = CGRect(x: 0, y: 0, width: 2560, height: 1410)

        #expect(
            AXWindowService.frameWriteOrder(currentFrame: current, targetFrame: target) == .positionThenSize
        )
    }

    @Test func fullscreenExitBackToTileUsesSizeThenPosition() {
        let current = CGRect(x: 0, y: 0, width: 2560, height: 1410)
        let target = CGRect(x: 1276, y: 709, width: 1276, height: 701)

        #expect(
            AXWindowService.frameWriteOrder(currentFrame: current, targetFrame: target) == .sizeThenPosition
        )
    }
}
