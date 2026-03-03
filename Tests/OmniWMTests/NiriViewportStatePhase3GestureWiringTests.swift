import Foundation
import Testing

@testable import OmniWM

private func phase3ApproxEqual(_ lhs: CGFloat, _ rhs: CGFloat, epsilon: CGFloat = 0.000_001) -> Bool {
    abs(lhs - rhs) <= epsilon
}

private func phase3ApproxEqual(_ lhs: Double, _ rhs: Double, epsilon: Double = 0.000_001) -> Bool {
    abs(lhs - rhs) <= epsilon
}

private func makePhase3Columns(widths: [CGFloat]) -> [NiriContainer] {
    widths.map { width in
        let column = NiriContainer()
        column.cachedWidth = width
        return column
    }
}

@Suite struct NiriViewportStatePhase3GestureWiringTests {
    @Test func beginGestureSeedsKernelStateAndResetsSelectionProgress() {
        var state = ViewportState()
        state.viewOffsetPixels = .static(-48)
        state.selectionProgress = 42

        state.beginGesture(isTrackpad: true)

        #expect(phase3ApproxEqual(state.selectionProgress, 0))
        switch state.viewOffsetPixels {
        case let .gesture(gesture):
            #expect(gesture.gestureState.is_trackpad == 1)
            #expect(gesture.gestureState.history_count == 0)
            #expect(phase3ApproxEqual(gesture.currentViewOffset, -48))
            #expect(phase3ApproxEqual(gesture.stationaryViewOffset, -48))
            #expect(phase3ApproxEqual(gesture.deltaFromTracker, -48))
        default:
            #expect(Bool(false))
        }
    }

    @Test func updateGestureMatchesKernelResultAndState() {
        let columns = makePhase3Columns(widths: [320, 280, 360])
        let spans = columns.map { Double($0.cachedWidth) }
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 700
        let timestamp: TimeInterval = 1000.0
        let delta: CGFloat = -140

        var state = ViewportState()
        state.activeColumnIndex = 1
        state.viewOffsetPixels = .static(-30)
        state.beginGesture(isTrackpad: true)
        state.selectionProgress = 25

        guard case let .gesture(gestureBefore) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        var expectedGestureState = gestureBefore.gestureState
        let expected = NiriViewportZigMath.gestureUpdate(
            state: &expectedGestureState,
            spans: spans,
            activeContainerIndex: 1,
            deltaPixels: delta,
            timestamp: timestamp,
            gap: gap,
            viewportSpan: viewportWidth,
            selectionProgress: state.selectionProgress
        )

        let steps = state.updateGesture(
            deltaPixels: delta,
            timestamp: timestamp,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth
        )

        #expect(steps == expected.selectionSteps)
        #expect(phase3ApproxEqual(state.selectionProgress, expected.selectionProgress))

        guard case let .gesture(gestureAfter) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        #expect(phase3ApproxEqual(gestureAfter.currentViewOffset, expected.currentViewOffset))
        #expect(phase3ApproxEqual(gestureAfter.gestureState.current_view_offset, expectedGestureState.current_view_offset))
        #expect(phase3ApproxEqual(gestureAfter.gestureState.delta_from_tracker, expectedGestureState.delta_from_tracker))
        #expect(phase3ApproxEqual(gestureAfter.gestureState.tracker_position, expectedGestureState.tracker_position))
    }

    @Test func updateGestureNormalizesOutOfRangeActiveIndexBeforeKernelCall() {
        let columns = makePhase3Columns(widths: [260, 300, 280])
        let spans = columns.map { Double($0.cachedWidth) }
        let gap: CGFloat = 12
        let viewportWidth: CGFloat = 640
        let timestamp: TimeInterval = 2000.0
        let delta: CGFloat = -90
        let normalizedActiveIndex = columns.count - 1

        var state = ViewportState()
        state.activeColumnIndex = 999
        state.viewOffsetPixels = .static(-10)
        state.beginGesture(isTrackpad: false)

        guard case let .gesture(gestureBefore) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        var expectedGestureState = gestureBefore.gestureState
        let expected = NiriViewportZigMath.gestureUpdate(
            state: &expectedGestureState,
            spans: spans,
            activeContainerIndex: normalizedActiveIndex,
            deltaPixels: delta,
            timestamp: timestamp,
            gap: gap,
            viewportSpan: viewportWidth,
            selectionProgress: 0
        )

        let steps = state.updateGesture(
            deltaPixels: delta,
            timestamp: timestamp,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth
        )

        #expect(steps == expected.selectionSteps)
        #expect(phase3ApproxEqual(state.selectionProgress, expected.selectionProgress))

        guard case let .gesture(gestureAfter) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        #expect(phase3ApproxEqual(gestureAfter.currentViewOffset, expected.currentViewOffset))
        #expect(phase3ApproxEqual(gestureAfter.gestureState.current_view_offset, expectedGestureState.current_view_offset))
    }

    @Test func endGestureUsesKernelResultForSpringAndResolvedColumn() {
        let columns = makePhase3Columns(widths: [300, 260, 340])
        let spans = columns.map { Double($0.cachedWidth) }
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 700

        var state = ViewportState()
        state.activeColumnIndex = 1
        state.viewOffsetPixels = .static(-20)
        state.beginGesture(isTrackpad: false)
        state.activatePrevColumnOnRemoval = 123
        state.viewOffsetToRestore = 456

        _ = state.updateGesture(
            deltaPixels: -80,
            timestamp: 1000.0,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth
        )
        _ = state.updateGesture(
            deltaPixels: -40,
            timestamp: 1000.016,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth
        )

        guard case let .gesture(gestureBeforeEnd) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        let expected = NiriViewportZigMath.gestureEnd(
            state: gestureBeforeEnd.gestureState,
            spans: spans,
            activeContainerIndex: state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1)),
            gap: gap,
            viewportSpan: viewportWidth,
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: false
        )

        state.endGesture(
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: false
        )

        #expect(state.activeColumnIndex == expected.resolvedColumnIndex)
        #expect(state.activatePrevColumnOnRemoval == nil)
        #expect(state.viewOffsetToRestore == nil)
        #expect(phase3ApproxEqual(state.selectionProgress, 0))

        switch state.viewOffsetPixels {
        case let .spring(animation):
            #expect(phase3ApproxEqual(animation.from, expected.springFrom))
            #expect(phase3ApproxEqual(animation.target, expected.springTo))
            #expect(phase3ApproxEqual(animation.initialVelocityForTesting, expected.initialVelocity))
        default:
            #expect(Bool(false))
        }
    }

    @Test func emptyColumnsGestureUpdateAndEndRemainDeterministic() {
        let columns: [NiriContainer] = []
        let spans: [Double] = []
        let gap: CGFloat = 12
        let viewportWidth: CGFloat = 800

        var state = ViewportState()
        state.activeColumnIndex = 7
        state.viewOffsetPixels = .static(15)
        state.beginGesture(isTrackpad: true)
        state.selectionProgress = 3

        guard case let .gesture(gestureBeforeUpdate) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        var expectedUpdateState = gestureBeforeUpdate.gestureState
        let expectedUpdate = NiriViewportZigMath.gestureUpdate(
            state: &expectedUpdateState,
            spans: spans,
            activeContainerIndex: 0,
            deltaPixels: 30,
            timestamp: 3000.0,
            gap: gap,
            viewportSpan: viewportWidth,
            selectionProgress: 3
        )

        let steps = state.updateGesture(
            deltaPixels: 30,
            timestamp: 3000.0,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth
        )

        #expect(steps == nil)
        #expect(phase3ApproxEqual(state.selectionProgress, expectedUpdate.selectionProgress))

        guard case let .gesture(gestureAfterUpdate) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        #expect(phase3ApproxEqual(gestureAfterUpdate.currentViewOffset, expectedUpdate.currentViewOffset))

        let expectedEnd = NiriViewportZigMath.gestureEnd(
            state: gestureAfterUpdate.gestureState,
            spans: spans,
            activeContainerIndex: 0,
            gap: gap,
            viewportSpan: viewportWidth,
            centerMode: .never,
            alwaysCenterSingleColumn: false
        )

        state.endGesture(
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            centerMode: .never,
            alwaysCenterSingleColumn: false
        )

        #expect(state.activeColumnIndex == expectedEnd.resolvedColumnIndex)
        switch state.viewOffsetPixels {
        case let .spring(animation):
            #expect(phase3ApproxEqual(animation.from, expectedEnd.springFrom))
            #expect(phase3ApproxEqual(animation.target, expectedEnd.springTo))
            #expect(phase3ApproxEqual(animation.initialVelocityForTesting, expectedEnd.initialVelocity))
        default:
            #expect(Bool(false))
        }
    }

    @Test func gestureOffsetDeltaMutatesKernelBackedFields() {
        var state = ViewportState()
        state.viewOffsetPixels = .static(-12)
        state.beginGesture(isTrackpad: false)

        guard case let .gesture(before) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }
        let beforeCurrentViewOffset = before.currentViewOffset
        let beforeStationaryOffset = before.stationaryViewOffset
        let beforeDeltaFromTracker = before.deltaFromTracker

        state.viewOffsetPixels.offset(delta: 18)

        guard case let .gesture(after) = state.viewOffsetPixels else {
            #expect(Bool(false))
            return
        }

        #expect(phase3ApproxEqual(after.currentViewOffset, beforeCurrentViewOffset + 18))
        #expect(phase3ApproxEqual(after.stationaryViewOffset, beforeStationaryOffset + 18))
        #expect(phase3ApproxEqual(after.deltaFromTracker, beforeDeltaFromTracker + 18))
    }
}
