import AppKit
import Foundation

extension ViewportState {
    mutating func beginGesture(isTrackpad: Bool) {
        let currentOffset = viewOffsetPixels.current()
        viewOffsetPixels = .gesture(ViewGesture(currentViewOffset: Double(currentOffset), isTrackpad: isTrackpad))
        selectionProgress = 0.0
    }

    mutating func updateGesture(
        deltaPixels: CGFloat,
        timestamp: TimeInterval,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat
    ) -> Int? {
        guard case let .gesture(gesture) = viewOffsetPixels else {
            return nil
        }

        let spans = columns.map { Double($0.cachedWidth) }
        let normalizedActiveIndex: Int = if columns.isEmpty {
            0
        } else {
            activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        }

        let result = NiriViewportZigMath.gestureUpdate(
            state: &gesture.gestureState,
            spans: spans,
            activeContainerIndex: normalizedActiveIndex,
            deltaPixels: deltaPixels,
            timestamp: timestamp,
            gap: gap,
            viewportSpan: viewportWidth,
            selectionProgress: selectionProgress
        )

        selectionProgress = result.selectionProgress
        return result.selectionSteps
    }

    mutating func endGesture(
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        centerMode: CenterFocusedColumn = .never,
        alwaysCenterSingleColumn: Bool = false
    ) {
        guard case let .gesture(gesture) = viewOffsetPixels else {
            return
        }

        let spans = columns.map { Double($0.cachedWidth) }
        let normalizedActiveIndex: Int = if columns.isEmpty {
            0
        } else {
            activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        }

        let result = NiriViewportZigMath.gestureEnd(
            state: gesture.gestureState,
            spans: spans,
            activeContainerIndex: normalizedActiveIndex,
            gap: gap,
            viewportSpan: viewportWidth,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        let now = animationClock?.now() ?? CACurrentMediaTime()
        let animation = SpringAnimation(
            from: result.springFrom,
            to: result.springTo,
            initialVelocity: result.initialVelocity,
            startTime: now,
            config: springConfig,
            displayRefreshRate: displayRefreshRate
        )
        activeColumnIndex = result.resolvedColumnIndex
        viewOffsetPixels = .spring(animation)

        activatePrevColumnOnRemoval = nil
        viewOffsetToRestore = nil
        selectionProgress = 0.0
    }
}
