// SPDX-License-Identifier: GPL-2.0-only
import CoreGraphics
import Foundation
import GhosttyKit

struct GhosttySurfaceCellMetrics: Equatable {
    // A one-pixel cell is the strictest safe assumption until Ghostty reports real glyph metrics.
    static let conservativeFallback = GhosttySurfaceCellMetrics(
        uncheckedCellWidthPx: 1,
        uncheckedCellHeightPx: 1
    )

    let cellWidthPx: UInt32
    let cellHeightPx: UInt32

    private init(uncheckedCellWidthPx: UInt32, uncheckedCellHeightPx: UInt32) {
        self.cellWidthPx = uncheckedCellWidthPx
        self.cellHeightPx = uncheckedCellHeightPx
    }

    init?(cellWidthPx: UInt32, cellHeightPx: UInt32) {
        guard cellWidthPx > 0, cellHeightPx > 0 else { return nil }
        self.cellWidthPx = cellWidthPx
        self.cellHeightPx = cellHeightPx
    }

    init?(surfaceSize: ghostty_surface_size_s) {
        self.init(
            cellWidthPx: surfaceSize.cell_width_px,
            cellHeightPx: surfaceSize.cell_height_px
        )
    }
}

struct GhosttySurfacePixelSize: Equatable {
    let widthPx: UInt32
    let heightPx: UInt32
}

enum GhosttySurfaceSizingDiagnosticKind: String {
    case invalidPointSize
    case invalidBackingScale
    case invalidScaledPixels
    case clampedToGridLimit
}

struct GhosttySurfaceSizingDiagnostic {
    let kind: GhosttySurfaceSizingDiagnosticKind
    let signature: String
}

struct GhosttySurfaceSizingDecision {
    let pixelSize: GhosttySurfacePixelSize?
    let diagnostic: GhosttySurfaceSizingDiagnostic?
}

enum GhosttySurfacePixelSizeNormalizer {
    private static let maxGhosttyGridCellCount = UInt64(UInt16.max)

    static func normalize(
        pointSize: CGSize,
        backingScale: CGFloat,
        cellMetrics: GhosttySurfaceCellMetrics?
    ) -> GhosttySurfaceSizingDecision {
        guard pointSize.width.isFinite,
              pointSize.height.isFinite,
              pointSize.width > 0,
              pointSize.height > 0 else {
            return .skip(.invalidPointSize)
        }

        guard backingScale.isFinite, backingScale > 0 else {
            return .skip(.invalidBackingScale)
        }

        let scaledWidth = Double(pointSize.width) * Double(backingScale)
        let scaledHeight = Double(pointSize.height) * Double(backingScale)
        guard scaledWidth.isFinite, scaledHeight.isFinite, scaledWidth > 0, scaledHeight > 0 else {
            return .skip(.invalidScaledPixels)
        }

        let roundedWidth = ceil(scaledWidth)
        let roundedHeight = ceil(scaledHeight)
        guard roundedWidth.isFinite, roundedHeight.isFinite else {
            return .skip(.invalidScaledPixels)
        }

        let metrics = cellMetrics ?? GhosttySurfaceCellMetrics.conservativeFallback
        let maxWidthPx = maxPixelDimension(forCellDimensionPx: metrics.cellWidthPx)
        let maxHeightPx = maxPixelDimension(forCellDimensionPx: metrics.cellHeightPx)
        let widthWasClamped = roundedWidth > Double(maxWidthPx)
        let heightWasClamped = roundedHeight > Double(maxHeightPx)
        let widthPx = UInt32(min(roundedWidth, Double(maxWidthPx)))
        let heightPx = UInt32(min(roundedHeight, Double(maxHeightPx)))

        let diagnostic: GhosttySurfaceSizingDiagnostic?
        if widthWasClamped || heightWasClamped {
            diagnostic = GhosttySurfaceSizingDiagnostic(
                kind: .clampedToGridLimit,
                signature: "clamped:\(maxWidthPx):\(maxHeightPx)"
            )
        } else {
            diagnostic = nil
        }

        return GhosttySurfaceSizingDecision(
            pixelSize: GhosttySurfacePixelSize(widthPx: widthPx, heightPx: heightPx),
            diagnostic: diagnostic
        )
    }

    private static func maxPixelDimension(forCellDimensionPx cellDimensionPx: UInt32) -> UInt32 {
        let product = maxGhosttyGridCellCount * UInt64(cellDimensionPx)
        return UInt32(min(product, UInt64(UInt32.max)))
    }
}

private extension GhosttySurfaceSizingDecision {
    static func skip(_ kind: GhosttySurfaceSizingDiagnosticKind) -> GhosttySurfaceSizingDecision {
        GhosttySurfaceSizingDecision(
            pixelSize: nil,
            diagnostic: GhosttySurfaceSizingDiagnostic(kind: kind, signature: kind.rawValue)
        )
    }
}
