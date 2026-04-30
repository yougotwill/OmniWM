// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import Foundation
import Testing

@testable import OmniWM

@Suite struct GhosttySurfaceSizingTests {
    @Test func normalizesFinitePointSizeWithCeilingRounding() throws {
        let metrics = try #require(GhosttySurfaceCellMetrics(cellWidthPx: 10, cellHeightPx: 20))
        let decision = GhosttySurfacePixelSizeNormalizer.normalize(
            pointSize: CGSize(width: 320.2, height: 100.1),
            backingScale: 2,
            cellMetrics: metrics
        )

        #expect(decision.pixelSize == GhosttySurfacePixelSize(widthPx: 641, heightPx: 201))
        #expect(decision.diagnostic == nil)
    }

    @Test func keepsSubpixelPositiveSizesAtOnePixel() {
        let decision = GhosttySurfacePixelSizeNormalizer.normalize(
            pointSize: CGSize(width: 0.1, height: 0.2),
            backingScale: 2,
            cellMetrics: nil
        )

        #expect(decision.pixelSize == GhosttySurfacePixelSize(widthPx: 1, heightPx: 1))
    }

    @Test func rejectsInvalidPointSizesAndBackingScales() {
        let invalidSizes = [
            CGSize(width: 0, height: 20),
            CGSize(width: -1, height: 20),
            CGSize(width: CGFloat.nan, height: 20),
            CGSize(width: 20, height: CGFloat.infinity)
        ]

        for size in invalidSizes {
            let decision = GhosttySurfacePixelSizeNormalizer.normalize(
                pointSize: size,
                backingScale: 1,
                cellMetrics: nil
            )
            #expect(decision.pixelSize == nil)
        }

        for scale in [CGFloat(0), CGFloat(-1), CGFloat.nan, CGFloat.infinity] {
            let decision = GhosttySurfacePixelSizeNormalizer.normalize(
                pointSize: CGSize(width: 20, height: 20),
                backingScale: scale,
                cellMetrics: nil
            )
            #expect(decision.pixelSize == nil)
        }
    }

    @Test func clampsToGhosttyGridLimitUsingCellMetrics() throws {
        let metrics = try #require(GhosttySurfaceCellMetrics(cellWidthPx: 8, cellHeightPx: 16))
        let decision = GhosttySurfacePixelSizeNormalizer.normalize(
            pointSize: CGSize(width: 1_000_000, height: 2_000_000),
            backingScale: 1,
            cellMetrics: metrics
        )

        #expect(decision.pixelSize == GhosttySurfacePixelSize(widthPx: 524_280, heightPx: 1_048_560))
        #expect(decision.diagnostic?.kind == .clampedToGridLimit)
    }
}

@Suite struct QuakeTerminalGeometryPolicyTests {
    @Test func normalizesQuakePercentagesToUISupportedBounds() {
        #expect(QuakeTerminalGeometryPolicy.normalizedDimensionPercent(5) == 10)
        #expect(QuakeTerminalGeometryPolicy.normalizedDimensionPercent(150) == 100)
        #expect(QuakeTerminalGeometryPolicy.normalizedDimensionPercent(Double.nan) == 50)
    }

    @Test func rejectsInvalidCustomFrames() {
        let valid = CGRect(x: 10, y: 20, width: 600, height: 300)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        #expect(QuakeTerminalGeometryPolicy.normalizedCustomFrame(valid, visibleFrame: visibleFrame) == valid)
        #expect(QuakeTerminalGeometryPolicy.normalizedCustomFrame(
            CGRect(x: 0, y: 0, width: 199, height: 300)
        ) == nil)
        #expect(QuakeTerminalGeometryPolicy.normalizedCustomFrame(
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 300)
        ) == nil)
        #expect(QuakeTerminalGeometryPolicy.normalizedCustomFrame(
            CGRect(x: 0, y: 0, width: 70_000, height: 300)
        ) == nil)
        #expect(QuakeTerminalGeometryPolicy.normalizedCustomFrame(
            CGRect(x: 2_000, y: 0, width: 600, height: 300),
            visibleFrame: visibleFrame
        ) == nil)
    }
}

@Suite struct QuakeGhosttyInputBridgeTests {
    @Test func suppressesOnlySingleC0ControlCharactersWhileComposing() {
        #expect(QuakeGhosttyInputBridge.shouldSuppressComposingControlInput("\u{08}", composing: true))
        #expect(QuakeGhosttyInputBridge.shouldSuppressComposingControlInput("\r", composing: true))

        #expect(!QuakeGhosttyInputBridge.shouldSuppressComposingControlInput("\u{08}", composing: false))
        #expect(!QuakeGhosttyInputBridge.shouldSuppressComposingControlInput("a", composing: true))
        #expect(!QuakeGhosttyInputBridge.shouldSuppressComposingControlInput("\u{08}\u{08}", composing: true))
        #expect(!QuakeGhosttyInputBridge.shouldSuppressComposingControlInput(nil, composing: true))
    }
}
