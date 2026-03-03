import CZigLayout
import Foundation
import Testing

@testable import OmniWM

private let viewportOK: Int32 = 0
private let viewportErrInvalidArgs: Int32 = -1
private let viewportErrOutOfRange: Int32 = -2

private func approxEqual(_ lhs: Double, _ rhs: Double, epsilon: Double = 0.000_001) -> Bool {
    abs(lhs - rhs) <= epsilon
}

private struct ViewportLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextBool(_ trueProbability: Double = 0.5) -> Bool {
        let value = Double(next() % 10_000) / 10_000
        return value < trueProbability
    }

    mutating func nextInt(_ range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func nextDouble(_ range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

@Suite struct NiriZigViewportKernelTests {
    @Test func viewportTransitionABIStrictValidation() {
        var out = OmniViewportTransitionResult(
            resolved_column_index: 0,
            offset_delta: 0,
            adjusted_target_offset: 0,
            target_offset: 0,
            snap_delta: 0,
            snap_to_target_immediately: 0
        )

        let rcMissingSpans = withUnsafeMutablePointer(to: &out) { outPtr in
            omni_viewport_transition_to_column(
                nil,
                1,
                0,
                0,
                16,
                800,
                0,
                0,
                0,
                -1,
                2,
                outPtr
            )
        }
        #expect(rcMissingSpans == viewportErrInvalidArgs)

        let rcEmptySpans = withUnsafeMutablePointer(to: &out) { outPtr in
            omni_viewport_transition_to_column(
                nil,
                0,
                0,
                0,
                16,
                800,
                0,
                0,
                0,
                -1,
                2,
                outPtr
            )
        }
        #expect(rcEmptySpans == viewportErrOutOfRange)

        let spans = [220.0, 260.0]
        let rcInvalidCenter = spans.withUnsafeBufferPointer { spansBuf in
            withUnsafeMutablePointer(to: &out) { outPtr in
                omni_viewport_transition_to_column(
                    spansBuf.baseAddress,
                    spansBuf.count,
                    0,
                    1,
                    16,
                    800,
                    0,
                    99,
                    0,
                    -1,
                    2,
                    outPtr
                )
            }
        }
        #expect(rcInvalidCenter == viewportErrInvalidArgs)
    }

    @Test func viewportEnsureVisibleABIStrictValidation() {
        let spans = [200.0, 240.0]
        var out = OmniViewportEnsureVisibleResult(target_offset: 0, offset_delta: 0, is_noop: 0)

        let rcActiveOutOfRange = spans.withUnsafeBufferPointer { spansBuf in
            withUnsafeMutablePointer(to: &out) { outPtr in
                omni_viewport_ensure_visible(
                    spansBuf.baseAddress,
                    spansBuf.count,
                    spans.count,
                    1,
                    16,
                    900,
                    0,
                    0,
                    0,
                    -1,
                    0.001,
                    outPtr
                )
            }
        }
        #expect(rcActiveOutOfRange == viewportErrOutOfRange)

        let rcTargetOutOfRange = spans.withUnsafeBufferPointer { spansBuf in
            withUnsafeMutablePointer(to: &out) { outPtr in
                omni_viewport_ensure_visible(
                    spansBuf.baseAddress,
                    spansBuf.count,
                    0,
                    spans.count,
                    16,
                    900,
                    0,
                    0,
                    0,
                    -1,
                    0.001,
                    outPtr
                )
            }
        }
        #expect(rcTargetOutOfRange == viewportErrOutOfRange)

        let rcBadFromIndex = spans.withUnsafeBufferPointer { spansBuf in
            withUnsafeMutablePointer(to: &out) { outPtr in
                omni_viewport_ensure_visible(
                    spansBuf.baseAddress,
                    spansBuf.count,
                    0,
                    1,
                    16,
                    900,
                    0,
                    0,
                    0,
                    99,
                    0.001,
                    outPtr
                )
            }
        }
        #expect(rcBadFromIndex == viewportErrOutOfRange)
    }

    @Test func viewportScrollAndGestureABIStrictValidation() {
        var scrollOut = OmniViewportScrollResult(
            applied: 1,
            new_offset: 1,
            selection_progress: 1,
            has_selection_steps: 1,
            selection_steps: 1
        )

        let scrollRc = withUnsafeMutablePointer(to: &scrollOut) { outPtr in
            omni_viewport_scroll_step(
                nil,
                0,
                20,
                800,
                16,
                12,
                4,
                1,
                outPtr
            )
        }
        #expect(scrollRc == viewportOK)
        #expect(scrollOut.applied == 0)
        #expect(scrollOut.new_offset == 12)
        #expect(scrollOut.selection_progress == 4)

        let badGestureBeginRc = omni_viewport_gesture_begin(0, 1, nil)
        #expect(badGestureBeginRc == viewportErrInvalidArgs)

        var state = NiriViewportZigMath.gestureBegin(currentViewOffset: 0, isTrackpad: true)
        var velocityOut = Double.nan
        let badGestureVelocityStateRc = withUnsafeMutablePointer(to: &velocityOut) { outPtr in
            omni_viewport_gesture_velocity(
                nil,
                outPtr
            )
        }
        #expect(badGestureVelocityStateRc == viewportErrInvalidArgs)

        let badGestureVelocityOutRc = withUnsafePointer(to: &state) { statePtr in
            omni_viewport_gesture_velocity(
                statePtr,
                nil
            )
        }
        #expect(badGestureVelocityOutRc == viewportErrInvalidArgs)

        let gestureVelocityOkRc = withUnsafePointer(to: &state) { statePtr in
            withUnsafeMutablePointer(to: &velocityOut) { outPtr in
                omni_viewport_gesture_velocity(
                    statePtr,
                    outPtr
                )
            }
        }
        #expect(gestureVelocityOkRc == viewportOK)
        #expect(approxEqual(velocityOut, 0))

        var updateOut = OmniViewportGestureUpdateResult(
            current_view_offset: 0,
            selection_progress: 0,
            has_selection_steps: 0,
            selection_steps: 0
        )

        let badGestureUpdateRc = withUnsafeMutablePointer(to: &updateOut) { outPtr in
            omni_viewport_gesture_update(
                nil,
                nil,
                0,
                0,
                20,
                1000,
                16,
                800,
                0,
                outPtr
            )
        }
        #expect(badGestureUpdateRc == viewportErrInvalidArgs)

        let spans = [200.0]
        let activeOutOfRangeRc = withUnsafeMutablePointer(to: &state) { statePtr in
            spans.withUnsafeBufferPointer { spansBuf in
                withUnsafeMutablePointer(to: &updateOut) { outPtr in
                    omni_viewport_gesture_update(
                        statePtr,
                        spansBuf.baseAddress,
                        spansBuf.count,
                        spans.count,
                        20,
                        1000.01,
                        16,
                        800,
                        0,
                        outPtr
                    )
                }
            }
        }
        #expect(activeOutOfRangeRc == viewportErrOutOfRange)

        let badGestureEndRc = withUnsafePointer(to: &state) { statePtr in
            omni_viewport_gesture_end(
                statePtr,
                nil,
                0,
                0,
                16,
                800,
                0,
                0,
                nil
            )
        }
        #expect(badGestureEndRc == viewportErrInvalidArgs)
    }

    @Test func transitionPlanParityMatchesReference() {
        var rng = ViewportLCG(seed: 0xA11CE_1337)
        let centerModes: [CenterFocusedColumn] = [.never, .always, .onOverflow]

        for _ in 0 ..< 400 {
            let spanCount = rng.nextInt(1 ... 7)
            let spans = (0 ..< spanCount).map { _ in rng.nextDouble(120 ... 640) }
            let currentActiveIndex = rng.nextInt(0 ... (spanCount - 1))
            let requestedIndex = rng.nextInt(0 ... (spanCount + 3))
            let gap = rng.nextDouble(0 ... 48)
            let viewportSpan = rng.nextDouble(240 ... 1800)
            let currentTargetOffset = rng.nextDouble(-2400 ... 300)
            let centerMode = centerModes[rng.nextInt(0 ... (centerModes.count - 1))]
            let alwaysCenterSingleColumn = rng.nextBool()
            let fromContainerIndex: Int? = rng.nextBool(0.7) ? rng.nextInt(0 ... (spanCount - 1)) : nil
            let scale = rng.nextDouble(1 ... 3.5)

            let ref = NiriReferenceViewportKernel.transitionPlan(
                spans: spans,
                currentActiveIndex: currentActiveIndex,
                requestedIndex: requestedIndex,
                gap: gap,
                viewportSpan: viewportSpan,
                currentTargetOffset: currentTargetOffset,
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn,
                fromContainerIndex: fromContainerIndex,
                scale: scale
            )

            let zig = NiriViewportZigMath.transitionPlan(
                spans: spans,
                currentActiveIndex: currentActiveIndex,
                requestedIndex: requestedIndex,
                gap: CGFloat(gap),
                viewportSpan: CGFloat(viewportSpan),
                currentTargetOffset: CGFloat(currentTargetOffset),
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn,
                fromContainerIndex: fromContainerIndex,
                scale: CGFloat(scale)
            )

            #expect(zig.resolvedColumnIndex == ref.resolvedColumnIndex)
            #expect(approxEqual(Double(zig.offsetDelta), ref.offsetDelta))
            #expect(approxEqual(Double(zig.adjustedTargetOffset), ref.adjustedTargetOffset))
            #expect(approxEqual(Double(zig.targetOffset), ref.targetOffset))
            #expect(approxEqual(Double(zig.snapDelta), ref.snapDelta))
            #expect(zig.snapToTargetImmediately == ref.snapToTargetImmediately)
        }
    }

    @Test func ensureVisiblePlanParityMatchesReference() {
        var rng = ViewportLCG(seed: 0xCAFE_BABE)
        let centerModes: [CenterFocusedColumn] = [.never, .always, .onOverflow]

        for _ in 0 ..< 400 {
            let spanCount = rng.nextInt(1 ... 7)
            let spans = (0 ..< spanCount).map { _ in rng.nextDouble(120 ... 700) }
            let activeContainerIndex = rng.nextInt(0 ... (spanCount - 1))
            let targetContainerIndex = rng.nextInt(0 ... (spanCount - 1))
            let gap = rng.nextDouble(0 ... 40)
            let viewportSpan = rng.nextDouble(240 ... 1700)
            let currentOffset = rng.nextDouble(-2200 ... 200)
            let centerMode = centerModes[rng.nextInt(0 ... (centerModes.count - 1))]
            let alwaysCenterSingleColumn = rng.nextBool()
            let fromContainerIndex: Int? = rng.nextBool(0.7) ? rng.nextInt(0 ... (spanCount - 1)) : nil
            let epsilon = rng.nextDouble(0.0001 ... 0.01)

            let ref = NiriReferenceViewportKernel.ensureVisiblePlan(
                spans: spans,
                activeContainerIndex: activeContainerIndex,
                targetContainerIndex: targetContainerIndex,
                gap: gap,
                viewportSpan: viewportSpan,
                currentOffset: currentOffset,
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn,
                fromContainerIndex: fromContainerIndex,
                epsilon: epsilon
            )

            let zig = NiriViewportZigMath.ensureVisiblePlan(
                spans: spans,
                activeContainerIndex: activeContainerIndex,
                targetContainerIndex: targetContainerIndex,
                gap: CGFloat(gap),
                viewportSpan: CGFloat(viewportSpan),
                currentOffset: CGFloat(currentOffset),
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn,
                fromContainerIndex: fromContainerIndex,
                epsilon: CGFloat(epsilon)
            )

            #expect(approxEqual(Double(zig.targetOffset), ref.targetOffset))
            #expect(approxEqual(Double(zig.offsetDelta), ref.offsetDelta))
            #expect(zig.isNoop == ref.isNoop)
        }
    }

    @Test func scrollStepParityMatchesReference() {
        var rng = ViewportLCG(seed: 0xDEAD_BEEF)

        for _ in 0 ..< 500 {
            let spanCount = rng.nextInt(0 ... 7)
            let spans = (0 ..< spanCount).map { _ in rng.nextDouble(90 ... 500) }
            let delta = rng.nextBool(0.1) ? Double.ulpOfOne : rng.nextDouble(-800 ... 800)
            let viewportSpan = rng.nextDouble(240 ... 1700)
            let gap = rng.nextDouble(0 ... 40)
            let currentOffset = rng.nextDouble(-2200 ... 200)
            let selectionProgress = rng.nextDouble(-400 ... 400)
            let changeSelection = rng.nextBool()

            let ref = NiriReferenceViewportKernel.scrollStep(
                spans: spans,
                deltaPixels: delta,
                viewportSpan: viewportSpan,
                gap: gap,
                currentOffset: currentOffset,
                selectionProgress: selectionProgress,
                changeSelection: changeSelection
            )

            let zig = NiriViewportZigMath.scrollStep(
                spans: spans,
                deltaPixels: CGFloat(delta),
                viewportSpan: CGFloat(viewportSpan),
                gap: CGFloat(gap),
                currentOffset: CGFloat(currentOffset),
                selectionProgress: CGFloat(selectionProgress),
                changeSelection: changeSelection
            )

            #expect(zig.applied == ref.applied)
            #expect(approxEqual(Double(zig.newOffset), ref.newOffset))
            #expect(approxEqual(Double(zig.selectionProgress), ref.selectionProgress))
            #expect(zig.selectionSteps == ref.selectionSteps)
        }
    }

    @Test func gestureKernelParityMatchesReference() {
        var rng = ViewportLCG(seed: 0x0DDC_0FFE)
        let centerModes: [CenterFocusedColumn] = [.never, .always, .onOverflow]

        for _ in 0 ..< 180 {
            let spanCount = rng.nextInt(0 ... 6)
            let spans = (0 ..< spanCount).map { _ in rng.nextDouble(120 ... 620) }
            let activeContainerIndex = spans.isEmpty ? 0 : rng.nextInt(0 ... (spanCount - 1))
            let isTrackpad = rng.nextBool()
            let currentOffset = rng.nextDouble(-1400 ... 200)
            let gap = rng.nextDouble(0 ... 36)
            let viewportSpan = rng.nextDouble(240 ... 1500)
            let alwaysCenterSingleColumn = rng.nextBool()
            let centerMode = centerModes[rng.nextInt(0 ... (centerModes.count - 1))]

            var referenceState = NiriReferenceViewportKernel.gestureBegin(
                currentViewOffset: currentOffset,
                isTrackpad: isTrackpad
            )
            var zigState = NiriViewportZigMath.gestureBegin(
                currentViewOffset: CGFloat(currentOffset),
                isTrackpad: isTrackpad
            )

            var referenceProgress = 0.0
            var zigProgress: CGFloat = 0
            var timestamp = 1000.0
            let sampleCount = rng.nextInt(8 ... 28)

            for _ in 0 ..< sampleCount {
                let delta = rng.nextDouble(-140 ... 140)
                timestamp += rng.nextDouble(0.004 ... 0.018)

                let referenceUpdate = NiriReferenceViewportKernel.gestureUpdate(
                    state: &referenceState,
                    spans: spans,
                    activeContainerIndex: activeContainerIndex,
                    deltaPixels: delta,
                    timestamp: timestamp,
                    gap: gap,
                    viewportSpan: viewportSpan,
                    selectionProgress: referenceProgress
                )

                let zigUpdate = NiriViewportZigMath.gestureUpdate(
                    state: &zigState,
                    spans: spans,
                    activeContainerIndex: activeContainerIndex,
                    deltaPixels: CGFloat(delta),
                    timestamp: timestamp,
                    gap: CGFloat(gap),
                    viewportSpan: CGFloat(viewportSpan),
                    selectionProgress: zigProgress
                )

                #expect(approxEqual(zigUpdate.currentViewOffset, referenceUpdate.currentViewOffset))
                #expect(approxEqual(Double(zigUpdate.selectionProgress), referenceUpdate.selectionProgress))
                #expect(zigUpdate.selectionSteps == referenceUpdate.selectionSteps)
                #expect(approxEqual(zigState.current_view_offset, referenceState.currentViewOffset))
                #expect(approxEqual(zigState.delta_from_tracker, referenceState.deltaFromTracker))
                #expect(approxEqual(zigState.tracker_position, referenceState.trackerPosition))

                referenceProgress = referenceUpdate.selectionProgress
                zigProgress = zigUpdate.selectionProgress
            }

            let referenceEnd = NiriReferenceViewportKernel.gestureEnd(
                state: referenceState,
                spans: spans,
                activeContainerIndex: activeContainerIndex,
                gap: gap,
                viewportSpan: viewportSpan,
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn
            )

            let zigEnd = NiriViewportZigMath.gestureEnd(
                state: zigState,
                spans: spans,
                activeContainerIndex: activeContainerIndex,
                gap: CGFloat(gap),
                viewportSpan: CGFloat(viewportSpan),
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn
            )
            let zigVelocity = NiriViewportZigMath.gestureVelocity(state: zigState)

            #expect(zigEnd.resolvedColumnIndex == referenceEnd.resolvedColumnIndex)
            #expect(approxEqual(zigEnd.springFrom, referenceEnd.springFrom))
            #expect(approxEqual(zigEnd.springTo, referenceEnd.springTo))
            #expect(approxEqual(zigEnd.initialVelocity, referenceEnd.initialVelocity))
            #expect(approxEqual(zigVelocity, zigEnd.initialVelocity))
        }
    }
}
