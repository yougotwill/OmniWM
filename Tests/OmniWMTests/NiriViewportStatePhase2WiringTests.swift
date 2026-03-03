import Foundation
import Testing

@testable import OmniWM

private func phase2ApproxEqual(_ lhs: CGFloat, _ rhs: CGFloat, epsilon: CGFloat = 0.000_001) -> Bool {
    abs(lhs - rhs) <= epsilon
}

private func makePhase2Columns(widths: [CGFloat], heights: [CGFloat]? = nil) -> [NiriContainer] {
    var columns: [NiriContainer] = []
    for (index, width) in widths.enumerated() {
        let column = NiriContainer()
        column.cachedWidth = width
        if let heights {
            column.cachedHeight = heights[index]
        }
        columns.append(column)
    }
    return columns
}

@Suite struct NiriViewportStatePhase2WiringTests {
    @Test func setActiveColumnAnimateFalseDelegatesToKernelTransitionPlan() {
        let columns = makePhase2Columns(widths: [360, 420, 280])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 800

        var state = ViewportState()
        state.activeColumnIndex = 99
        state.viewOffsetPixels = .static(-24)
        state.activatePrevColumnOnRemoval = 11
        state.viewOffsetToRestore = 22

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let clampedIndex = (-7).clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: clampedIndex,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .always,
            alwaysCenterSingleColumn: true,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )

        state.setActiveColumn(
            -7,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: false
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), plan.targetOffset))
        #expect(state.activatePrevColumnOnRemoval == nil)
        #expect(state.viewOffsetToRestore == nil)
    }

    @Test func setActiveColumnAnimateTrueUsesKernelTransitionSpringTarget() {
        let columns = makePhase2Columns(widths: [500, 500, 500])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 500

        var state = ViewportState()
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)
        state.activatePrevColumnOnRemoval = 3
        state.viewOffsetToRestore = 4

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: 2,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .always,
            alwaysCenterSingleColumn: true,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )
        #expect(plan.snapToTargetImmediately == false)

        state.setActiveColumn(
            2,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: true
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        switch state.viewOffsetPixels {
        case let .spring(animation):
            #expect(phase2ApproxEqual(CGFloat(animation.target), plan.targetOffset))
        default:
            #expect(Bool(false))
        }
        #expect(state.activatePrevColumnOnRemoval == nil)
        #expect(state.viewOffsetToRestore == nil)
    }

    @Test func transitionToColumnAnimateFalseMatchesKernelPlan() {
        let columns = makePhase2Columns(widths: [340, 280, 420])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 700

        var state = ViewportState()
        state.activeColumnIndex = 99
        state.viewOffsetPixels = .static(-47)
        state.activatePrevColumnOnRemoval = 12
        state.viewOffsetToRestore = 34

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: max(-5, 0),
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )

        state.transitionToColumn(
            -5,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: false,
            centerMode: .onOverflow
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), plan.targetOffset))
        #expect(state.activatePrevColumnOnRemoval == nil)
        #expect(state.viewOffsetToRestore == nil)
    }

    @Test func transitionToColumnAnimateTrueCreatesSpringWhenNotSnapImmediate() {
        let columns = makePhase2Columns(widths: [500, 500, 500])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 500

        var state = ViewportState()
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)
        state.activatePrevColumnOnRemoval = 5
        state.viewOffsetToRestore = 6

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: 2,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .always,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )
        #expect(plan.snapToTargetImmediately == false)

        state.transitionToColumn(
            2,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: true,
            centerMode: .always
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        switch state.viewOffsetPixels {
        case let .spring(animation):
            #expect(phase2ApproxEqual(CGFloat(animation.target), plan.targetOffset))
        default:
            #expect(Bool(false))
        }
        #expect(state.activatePrevColumnOnRemoval == nil)
        #expect(state.viewOffsetToRestore == nil)
    }

    @Test func transitionToColumnSnapImmediateSkipsSpring() {
        let columns = makePhase2Columns(widths: [200, 200])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 500

        var state = ViewportState()
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(0)
        state.activatePrevColumnOnRemoval = 1
        state.viewOffsetToRestore = 2

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: 1,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .never,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )
        #expect(plan.snapToTargetImmediately)

        state.transitionToColumn(
            1,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: true,
            centerMode: .never
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        switch state.viewOffsetPixels {
        case let .static(offset):
            #expect(phase2ApproxEqual(offset, plan.targetOffset))
        default:
            #expect(Bool(false))
        }
        #expect(state.activatePrevColumnOnRemoval == nil)
        #expect(state.viewOffsetToRestore == nil)
    }

    @Test func ensureContainerVisibleNoopLeavesStateUnchanged() {
        let columns = makePhase2Columns(widths: [300, 300])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 700

        var state = ViewportState()
        state.activeColumnIndex = 0
        state.viewOffsetPixels = .static(-16)

        let plan = NiriViewportZigMath.ensureVisiblePlan(
            spans: columns.map { Double($0.cachedWidth) },
            activeContainerIndex: 0,
            targetContainerIndex: 0,
            gap: gap,
            viewportSpan: viewportWidth,
            currentOffset: -16,
            centerMode: .never,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: nil
        )
        #expect(plan.isNoop)

        state.ensureContainerVisible(
            containerIndex: 0,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            animate: true,
            centerMode: .never
        )

        switch state.viewOffsetPixels {
        case let .static(offset):
            #expect(phase2ApproxEqual(offset, -16))
        default:
            #expect(Bool(false))
        }
    }

    @Test func ensureContainerVisibleNonNoopUsesKernelTarget() {
        let columns = makePhase2Columns(widths: [220, 260, 280])
        let gap: CGFloat = 12
        let viewportWidth: CGFloat = 360

        var state = ViewportState()
        state.activeColumnIndex = 99
        state.viewOffsetPixels = .static(-30)

        let safeActiveIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.ensureVisiblePlan(
            spans: columns.map { Double($0.cachedWidth) },
            activeContainerIndex: safeActiveIndex,
            targetContainerIndex: 0,
            gap: gap,
            viewportSpan: viewportWidth,
            currentOffset: state.viewOffsetPixels.current(),
            centerMode: .never,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: nil
        )
        #expect(plan.isNoop == false)

        state.ensureContainerVisible(
            containerIndex: 0,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            animate: false,
            centerMode: .never
        )

        switch state.viewOffsetPixels {
        case let .static(offset):
            #expect(phase2ApproxEqual(offset, plan.targetOffset))
        default:
            #expect(Bool(false))
        }
    }

    @Test func ensureContainerVisibleHeightKeyPathUsesHeightSpans() {
        let columns = makePhase2Columns(
            widths: [300, 300, 300],
            heights: [120, 220, 180]
        )
        let gap: CGFloat = 10
        let viewportSpan: CGFloat = 300

        var state = ViewportState()
        state.activeColumnIndex = 1
        state.viewOffsetPixels = .static(15)

        let plan = NiriViewportZigMath.ensureVisiblePlan(
            spans: columns.map { Double($0.cachedHeight) },
            activeContainerIndex: 1,
            targetContainerIndex: 2,
            gap: gap,
            viewportSpan: viewportSpan,
            currentOffset: 15,
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: nil
        )
        #expect(plan.isNoop == false)

        state.ensureContainerVisible(
            containerIndex: 2,
            containers: columns,
            gap: gap,
            viewportSpan: viewportSpan,
            sizeKeyPath: \.cachedHeight,
            animate: false,
            centerMode: .onOverflow
        )

        switch state.viewOffsetPixels {
        case let .static(offset):
            #expect(phase2ApproxEqual(offset, plan.targetOffset))
        default:
            #expect(Bool(false))
        }
    }

    @Test func ensureContainerVisibleNormalizesOutOfRangeFromContainerIndex() {
        let columns = makePhase2Columns(widths: [220, 260, 280])
        let gap: CGFloat = 12
        let viewportWidth: CGFloat = 360

        var state = ViewportState()
        state.activeColumnIndex = 2
        state.viewOffsetPixels = .static(-30)

        let safeActiveIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.ensureVisiblePlan(
            spans: columns.map { Double($0.cachedWidth) },
            activeContainerIndex: safeActiveIndex,
            targetContainerIndex: 0,
            gap: gap,
            viewportSpan: viewportWidth,
            currentOffset: state.viewOffsetPixels.current(),
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: true,
            fromContainerIndex: safeActiveIndex
        )

        state.ensureContainerVisible(
            containerIndex: 0,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            animate: false,
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: true,
            fromContainerIndex: 999
        )

        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), plan.targetOffset))
    }

    @Test func transitionToColumnNormalizesOutOfRangeFromColumnIndex() {
        let columns = makePhase2Columns(widths: [300, 320])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 600

        var state = ViewportState()
        state.activeColumnIndex = 1
        state.viewOffsetPixels = .static(-50)

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: 0,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .onOverflow,
            alwaysCenterSingleColumn: false,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )

        state.transitionToColumn(
            0,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: false,
            centerMode: .onOverflow,
            fromColumnIndex: 999
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), plan.targetOffset))
    }

    @Test func snapToColumnUsesTransitionPlanAndResetsSelectionProgress() {
        let columns = makePhase2Columns(widths: [350, 400, 450])
        let gap: CGFloat = 16
        let viewportWidth: CGFloat = 900

        var state = ViewportState()
        state.activeColumnIndex = 88
        state.viewOffsetPixels = .static(-10)
        state.selectionProgress = 123

        let safeCurrentIndex = state.activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let plan = NiriViewportZigMath.transitionPlan(
            spans: columns.map { Double($0.cachedWidth) },
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: 1,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: state.viewOffsetPixels.target(),
            centerMode: .always,
            alwaysCenterSingleColumn: true,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )

        state.snapToColumn(
            1,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth
        )

        #expect(state.activeColumnIndex == plan.resolvedColumnIndex)
        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), plan.targetOffset))
        #expect(state.selectionProgress == 0)
    }

    @Test func scrollByPixelsAppliedUpdatesOffsetAndSelectionFromKernelResult() {
        let columns = makePhase2Columns(widths: [100, 100])
        let gap: CGFloat = 0
        let viewportWidth: CGFloat = 100

        var state = ViewportState()
        state.viewOffsetPixels = .static(0)
        state.selectionProgress = 0

        let expected = NiriViewportZigMath.scrollStep(
            spans: columns.map { Double($0.cachedWidth) },
            deltaPixels: -120,
            viewportSpan: viewportWidth,
            gap: gap,
            currentOffset: 0,
            selectionProgress: 0,
            changeSelection: true
        )
        #expect(expected.applied)

        let steps = state.scrollByPixels(
            -120,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            changeSelection: true
        )

        #expect(steps == expected.selectionSteps)
        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), expected.newOffset))
        #expect(phase2ApproxEqual(state.selectionProgress, expected.selectionProgress))
    }

    @Test func scrollByPixelsNonAppliedLeavesStateUnchanged() {
        let columns = makePhase2Columns(widths: [100, 100])
        let gap: CGFloat = 0
        let viewportWidth: CGFloat = 100

        var state = ViewportState()
        state.viewOffsetPixels = .static(42)
        state.selectionProgress = 7

        let expected = NiriViewportZigMath.scrollStep(
            spans: columns.map { Double($0.cachedWidth) },
            deltaPixels: 0,
            viewportSpan: viewportWidth,
            gap: gap,
            currentOffset: 42,
            selectionProgress: 7,
            changeSelection: true
        )
        #expect(expected.applied == false)

        let steps = state.scrollByPixels(
            0,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            changeSelection: true
        )

        #expect(steps == nil)
        #expect(phase2ApproxEqual(state.viewOffsetPixels.current(), 42))
        #expect(phase2ApproxEqual(state.selectionProgress, 7))
    }
}
