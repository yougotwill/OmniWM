// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation

enum QuakeTerminalGeometryPolicy {
    static let minimumDimensionPercent = 10.0
    static let maximumDimensionPercent = 100.0
    static let defaultDimensionPercent = 50.0

    static let minimumFrameWidthPoints: CGFloat = 200
    static let minimumFrameHeightPoints: CGFloat = 100
    // Persisted custom frames are screen-point geometry; the FFI boundary applies the cell-aware pixel cap.
    static let maximumFrameDimensionPoints = CGFloat(UInt16.max)

    static func normalizedDimensionPercent(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDimensionPercent }
        return min(max(value, minimumDimensionPercent), maximumDimensionPercent)
    }

    static func configuredFrameSize(
        visibleFrame: CGRect,
        widthPercent: Double,
        heightPercent: Double
    ) -> CGSize {
        let normalizedWidthPercent = normalizedDimensionPercent(widthPercent)
        let normalizedHeightPercent = normalizedDimensionPercent(heightPercent)
        return CGSize(
            width: visibleFrame.width * normalizedWidthPercent / 100.0,
            height: visibleFrame.height * normalizedHeightPercent / 100.0
        )
    }

    static func normalizedCustomFrame(
        _ frame: CGRect?,
        visibleFrame: CGRect? = nil
    ) -> CGRect? {
        guard let frame else { return nil }
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.size.width.isFinite,
              frame.size.height.isFinite,
              frame.size.width >= minimumFrameWidthPoints,
              frame.size.height >= minimumFrameHeightPoints,
              frame.size.width <= maximumFrameDimensionPoints,
              frame.size.height <= maximumFrameDimensionPoints else {
            return nil
        }

        if let visibleFrame, !visibleFrame.intersects(frame) {
            return nil
        }

        return frame
    }
}
