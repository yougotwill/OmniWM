import Foundation
import CoreGraphics
struct DwindleSettings {
    var defaultSplitRatio: CGFloat = 1.0
    var splitWidthMultiplier: CGFloat = 1.0
    var smartSplit: Bool = true
    var resizeStep: CGFloat = 0.1
    var singleWindowAspectRatio: CGSize = CGSize(width: 4, height: 3)
    var singleWindowAspectRatioTolerance: CGFloat = 0.1
    var innerGap: CGFloat = 8.0
    var outerGapTop: CGFloat = 0
    var outerGapBottom: CGFloat = 0
    var outerGapLeft: CGFloat = 0
    var outerGapRight: CGFloat = 0
    func clampedRatio(_ ratio: CGFloat) -> CGFloat {
        min(max(ratio, 0.1), 1.9)
    }
    func ratioToFraction(_ ratio: CGFloat) -> CGFloat {
        let clamped = clampedRatio(ratio)
        return min(max(clamped / 2.0, 0.05), 0.95)
    }
}
