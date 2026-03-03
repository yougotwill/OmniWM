import Foundation

@testable import OmniWM

enum NiriReferenceViewportKernel {
    struct SwipeEvent {
        let delta: Double
        let timestamp: TimeInterval
    }

    static let gestureHistoryLimit: TimeInterval = 0.150
    static let gestureDecelerationRate: Double = 0.997
    static let gestureWorkingAreaMovement: Double = 1200.0

    struct TransitionPlan {
        let resolvedColumnIndex: Int
        let offsetDelta: Double
        let adjustedTargetOffset: Double
        let targetOffset: Double
        let snapDelta: Double
        let snapToTargetImmediately: Bool
    }

    struct EnsureVisiblePlan {
        let targetOffset: Double
        let offsetDelta: Double
        let isNoop: Bool
    }

    struct ScrollStepResult {
        let applied: Bool
        let newOffset: Double
        let selectionProgress: Double
        let selectionSteps: Int?
    }

    struct GestureState {
        var isTrackpad: Bool
        var history: [SwipeEvent]
        var trackerPosition: Double
        var currentViewOffset: Double
        var stationaryViewOffset: Double
        var deltaFromTracker: Double
    }

    struct GestureUpdateResult {
        let currentViewOffset: Double
        let selectionProgress: Double
        let selectionSteps: Int?
    }

    struct GestureEndResult {
        let resolvedColumnIndex: Int
        let springFrom: Double
        let springTo: Double
        let initialVelocity: Double
    }

    private static func effectiveCenterMode(
        _ centerMode: CenterFocusedColumn,
        spanCount: Int,
        alwaysCenterSingleColumn: Bool
    ) -> CenterFocusedColumn {
        if spanCount == 1, alwaysCenterSingleColumn {
            return .always
        }
        return centerMode
    }

    private static func containerPosition(spans: [Double], index: Int, gap: Double) -> Double {
        guard index > 0 else { return 0 }
        return spans.prefix(index).reduce(0) { $0 + $1 + gap }
    }

    private static func totalSpan(spans: [Double], gap: Double) -> Double {
        guard !spans.isEmpty else { return 0 }
        return spans.reduce(0, +) + Double(max(0, spans.count - 1)) * gap
    }

    private static func computeCenteredOffset(
        spans: [Double],
        containerIndex: Int,
        gap: Double,
        viewportSpan: Double
    ) -> Double {
        guard spans.indices.contains(containerIndex) else { return 0 }

        let total = totalSpan(spans: spans, gap: gap)
        let pos = containerPosition(spans: spans, index: containerIndex, gap: gap)

        if total <= viewportSpan {
            return -pos - (viewportSpan - total) / 2
        }

        let containerSize = spans[containerIndex]
        let centeredOffset = -(viewportSpan - containerSize) / 2
        let maxOffset = 0.0
        let minOffset = viewportSpan - total
        return min(max(centeredOffset, minOffset), maxOffset)
    }

    private static func computeFitOffset(
        currentViewPos: Double,
        viewSpan: Double,
        targetPos: Double,
        targetSpan: Double,
        gap: Double
    ) -> Double {
        if viewSpan <= targetSpan {
            return 0
        }

        let padding = min(max((viewSpan - targetSpan) / 2, 0), gap)
        let newPos = targetPos - padding
        let newEndPos = targetPos + targetSpan + padding

        if currentViewPos <= newPos, newEndPos <= currentViewPos + viewSpan {
            return -(targetPos - currentViewPos)
        }

        let distToStart = abs(currentViewPos - newPos)
        let distToEnd = abs((currentViewPos + viewSpan) - newEndPos)

        if distToStart <= distToEnd {
            return -padding
        }

        return -(viewSpan - padding - targetSpan)
    }

    static func computeVisibleOffset(
        spans: [Double],
        containerIndex: Int,
        gap: Double,
        viewportSpan: Double,
        currentViewStart: Double,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        fromContainerIndex: Int?
    ) -> Double {
        guard spans.indices.contains(containerIndex) else { return 0 }

        let targetPos = containerPosition(spans: spans, index: containerIndex, gap: gap)
        let targetSize = spans[containerIndex]
        let effectiveCenterMode = effectiveCenterMode(
            centerMode,
            spanCount: spans.count,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        let targetOffset: Double
        switch effectiveCenterMode {
        case .always:
            targetOffset = computeCenteredOffset(
                spans: spans,
                containerIndex: containerIndex,
                gap: gap,
                viewportSpan: viewportSpan
            )

        case .onOverflow:
            if targetSize > viewportSpan {
                targetOffset = computeCenteredOffset(
                    spans: spans,
                    containerIndex: containerIndex,
                    gap: gap,
                    viewportSpan: viewportSpan
                )
            } else if let fromContainerIndex, fromContainerIndex != containerIndex {
                let sourceIdx: Int
                if fromContainerIndex > containerIndex {
                    sourceIdx = min(containerIndex + 1, spans.count - 1)
                } else {
                    sourceIdx = containerIndex > 0 ? containerIndex - 1 : 0
                }

                let sourcePos = containerPosition(spans: spans, index: sourceIdx, gap: gap)
                let sourceSize = spans[sourceIdx]

                let totalSpanNeeded: Double
                if sourcePos < targetPos {
                    totalSpanNeeded = targetPos - sourcePos + targetSize + gap * 2
                } else {
                    totalSpanNeeded = sourcePos - targetPos + sourceSize + gap * 2
                }

                if totalSpanNeeded <= viewportSpan {
                    targetOffset = computeFitOffset(
                        currentViewPos: currentViewStart,
                        viewSpan: viewportSpan,
                        targetPos: targetPos,
                        targetSpan: targetSize,
                        gap: gap
                    )
                } else {
                    targetOffset = computeCenteredOffset(
                        spans: spans,
                        containerIndex: containerIndex,
                        gap: gap,
                        viewportSpan: viewportSpan
                    )
                }
            } else {
                targetOffset = computeFitOffset(
                    currentViewPos: currentViewStart,
                    viewSpan: viewportSpan,
                    targetPos: targetPos,
                    targetSpan: targetSize,
                    gap: gap
                )
            }

        case .never:
            targetOffset = computeFitOffset(
                currentViewPos: currentViewStart,
                viewSpan: viewportSpan,
                targetPos: targetPos,
                targetSpan: targetSize,
                gap: gap
            )
        }

        let total = totalSpan(spans: spans, gap: gap)
        let maxOffset = 0.0
        let minOffset = viewportSpan - total
        if minOffset < maxOffset {
            return min(max(targetOffset, minOffset), maxOffset)
        }
        return targetOffset
    }

    static func findSnapTarget(
        spans: [Double],
        gap: Double,
        viewportSpan: Double,
        projectedViewPos: Double,
        currentViewPos: Double,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool
    ) -> (viewPos: Double, columnIndex: Int) {
        guard !spans.isEmpty else {
            return (0, 0)
        }

        let effectiveCenterMode = effectiveCenterMode(
            centerMode,
            spanCount: spans.count,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        let totalW = totalSpan(spans: spans, gap: gap)
        let minViewPos = viewportSpan - totalW
        let maxViewPos = 0.0

        var bestViewPos = 0.0
        var bestColIdx = 0
        var bestDistance = Double.infinity

        func consider(_ candidateViewPos: Double, _ candidateColIdx: Int) -> (Double, Int, Double) {
            let clamped = min(max(candidateViewPos, minViewPos), maxViewPos)
            let distance = abs(clamped - projectedViewPos)
            if distance < bestDistance {
                return (clamped, candidateColIdx, distance)
            }
            return (bestViewPos, bestColIdx, bestDistance)
        }

        if effectiveCenterMode == .always {
            for idx in spans.indices {
                let colX = containerPosition(spans: spans, index: idx, gap: gap)
                let offset = computeCenteredOffset(
                    spans: spans,
                    containerIndex: idx,
                    gap: gap,
                    viewportSpan: viewportSpan
                )
                let result = consider(colX + offset, idx)
                bestViewPos = result.0
                bestColIdx = result.1
                bestDistance = result.2
            }
        } else {
            var colX = 0.0
            for idx in spans.indices {
                let colW = spans[idx]
                let padding = min(max((viewportSpan - colW) / 2, 0), gap)
                let leftSnap = colX - padding
                let rightSnap = colX + colW + padding - viewportSpan

                var result = consider(leftSnap, idx)
                bestViewPos = result.0
                bestColIdx = result.1
                bestDistance = result.2

                if rightSnap != leftSnap {
                    result = consider(rightSnap, idx)
                    bestViewPos = result.0
                    bestColIdx = result.1
                    bestDistance = result.2
                }

                colX += colW + gap
            }
        }

        var resolvedColIdx = bestColIdx
        if effectiveCenterMode != .always {
            let scrollingRight = projectedViewPos >= currentViewPos
            if scrollingRight {
                var idx = resolvedColIdx + 1
                while idx < spans.count {
                    let colX = containerPosition(spans: spans, index: idx, gap: gap)
                    let colW = spans[idx]
                    let padding = min(max((viewportSpan - colW) / 2, 0), gap)
                    if bestViewPos + viewportSpan >= colX + colW + padding {
                        resolvedColIdx = idx
                    } else {
                        break
                    }
                    idx += 1
                }
            } else {
                var idx = resolvedColIdx - 1
                while idx >= 0 {
                    let colX = containerPosition(spans: spans, index: idx, gap: gap)
                    let colW = spans[idx]
                    let padding = min(max((viewportSpan - colW) / 2, 0), gap)
                    if colX - padding >= bestViewPos {
                        resolvedColIdx = idx
                    } else {
                        break
                    }
                    idx -= 1
                }
            }
        }

        return (bestViewPos, resolvedColIdx)
    }

    static func transitionPlan(
        spans: [Double],
        currentActiveIndex: Int,
        requestedIndex: Int,
        gap: Double,
        viewportSpan: Double,
        currentTargetOffset: Double,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        fromContainerIndex: Int?,
        scale: Double
    ) -> TransitionPlan {
        let resolvedColumnIndex = min(max(0, requestedIndex), max(0, spans.count - 1))
        let oldActiveX = containerPosition(spans: spans, index: currentActiveIndex, gap: gap)
        let newActiveX = containerPosition(spans: spans, index: resolvedColumnIndex, gap: gap)
        let offsetDelta = oldActiveX - newActiveX
        let adjustedTargetOffset = currentTargetOffset + offsetDelta

        let targetOffset = computeVisibleOffset(
            spans: spans,
            containerIndex: resolvedColumnIndex,
            gap: gap,
            viewportSpan: viewportSpan,
            currentViewStart: newActiveX + adjustedTargetOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromContainerIndex
        )

        let snapDelta = targetOffset - adjustedTargetOffset
        let snapToTargetImmediately = abs(snapDelta) < (1 / scale)
        return TransitionPlan(
            resolvedColumnIndex: resolvedColumnIndex,
            offsetDelta: offsetDelta,
            adjustedTargetOffset: adjustedTargetOffset,
            targetOffset: targetOffset,
            snapDelta: snapDelta,
            snapToTargetImmediately: snapToTargetImmediately
        )
    }

    static func ensureVisiblePlan(
        spans: [Double],
        activeContainerIndex: Int,
        targetContainerIndex: Int,
        gap: Double,
        viewportSpan: Double,
        currentOffset: Double,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        fromContainerIndex: Int?,
        epsilon: Double
    ) -> EnsureVisiblePlan {
        let activePos = containerPosition(spans: spans, index: activeContainerIndex, gap: gap)
        let targetOffset = computeVisibleOffset(
            spans: spans,
            containerIndex: targetContainerIndex,
            gap: gap,
            viewportSpan: viewportSpan,
            currentViewStart: activePos + currentOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromContainerIndex
        )
        let offsetDelta = targetOffset - currentOffset
        return EnsureVisiblePlan(
            targetOffset: targetOffset,
            offsetDelta: offsetDelta,
            isNoop: abs(offsetDelta) < abs(epsilon)
        )
    }

    static func scrollStep(
        spans: [Double],
        deltaPixels: Double,
        viewportSpan: Double,
        gap: Double,
        currentOffset: Double,
        selectionProgress: Double,
        changeSelection: Bool
    ) -> ScrollStepResult {
        guard abs(deltaPixels) > Double.ulpOfOne else {
            return ScrollStepResult(
                applied: false,
                newOffset: currentOffset,
                selectionProgress: selectionProgress,
                selectionSteps: nil
            )
        }
        guard !spans.isEmpty else {
            return ScrollStepResult(
                applied: false,
                newOffset: currentOffset,
                selectionProgress: selectionProgress,
                selectionSteps: nil
            )
        }

        let totalW = totalSpan(spans: spans, gap: gap)
        guard totalW > 0 else {
            return ScrollStepResult(
                applied: false,
                newOffset: currentOffset,
                selectionProgress: selectionProgress,
                selectionSteps: nil
            )
        }

        var newOffset = currentOffset + deltaPixels
        let maxOffset = 0.0
        let minOffset = viewportSpan - totalW
        if minOffset < maxOffset {
            newOffset = min(max(newOffset, minOffset), maxOffset)
        } else {
            newOffset = 0
        }

        var progress = selectionProgress
        var steps: Int?
        if changeSelection {
            let avgColumnWidth = totalW / Double(spans.count)
            progress += deltaPixels
            let stepCount = Int((progress / avgColumnWidth).rounded(.towardZero))
            if stepCount != 0 {
                progress -= Double(stepCount) * avgColumnWidth
                steps = stepCount
            }
        }

        return ScrollStepResult(
            applied: true,
            newOffset: newOffset,
            selectionProgress: progress,
            selectionSteps: steps
        )
    }

    static func gestureBegin(
        currentViewOffset: Double,
        isTrackpad: Bool
    ) -> GestureState {
        GestureState(
            isTrackpad: isTrackpad,
            history: [],
            trackerPosition: 0,
            currentViewOffset: currentViewOffset,
            stationaryViewOffset: currentViewOffset,
            deltaFromTracker: currentViewOffset
        )
    }

    private static func trimHistory(_ state: inout GestureState, currentTime: TimeInterval) {
        let cutoff = currentTime - gestureHistoryLimit
        state.history.removeAll { $0.timestamp < cutoff }
    }

    private static func trackerVelocity(_ state: GestureState) -> Double {
        guard state.history.count >= 2 else { return 0 }

        guard let firstTime = state.history.first?.timestamp,
              let lastTime = state.history.last?.timestamp
        else {
            return 0
        }

        let totalTime = lastTime - firstTime
        guard totalTime > 0.001 else { return 0 }

        let totalDelta = state.history.reduce(0) { $0 + $1.delta }
        return totalDelta / totalTime
    }

    private static func projectedEndPosition(_ state: GestureState) -> Double {
        let velocity = trackerVelocity(state)
        guard abs(velocity) > 0.001 else { return state.trackerPosition }

        let coeff = 1000.0 * log(gestureDecelerationRate)
        return state.trackerPosition - velocity / coeff
    }

    static func gestureUpdate(
        state: inout GestureState,
        spans: [Double],
        activeContainerIndex: Int,
        deltaPixels: Double,
        timestamp: TimeInterval,
        gap: Double,
        viewportSpan: Double,
        selectionProgress: Double
    ) -> GestureUpdateResult {
        state.trackerPosition += deltaPixels
        state.history.append(.init(delta: deltaPixels, timestamp: timestamp))
        trimHistory(&state, currentTime: timestamp)

        let normFactor = state.isTrackpad ? viewportSpan / gestureWorkingAreaMovement : 1.0
        let pos = state.trackerPosition * normFactor
        let viewOffset = pos + state.deltaFromTracker

        guard !spans.isEmpty else {
            state.currentViewOffset = viewOffset
            return GestureUpdateResult(
                currentViewOffset: viewOffset,
                selectionProgress: selectionProgress,
                selectionSteps: nil
            )
        }

        let activeColX = containerPosition(spans: spans, index: activeContainerIndex, gap: gap)
        let totalW = totalSpan(spans: spans, gap: gap)
        var leftmost = 0.0
        var rightmost = max(0.0, totalW - viewportSpan)
        leftmost -= activeColX
        rightmost -= activeColX

        let minOffset = min(leftmost, rightmost)
        let maxOffset = max(leftmost, rightmost)
        let clampedOffset = min(max(viewOffset, minOffset), maxOffset)

        state.deltaFromTracker += clampedOffset - viewOffset
        state.currentViewOffset = clampedOffset

        let avgColumnWidth = totalW / Double(spans.count)
        var progress = selectionProgress + deltaPixels
        let steps = Int((progress / avgColumnWidth).rounded(.towardZero))
        if steps != 0 {
            progress -= Double(steps) * avgColumnWidth
        }

        return GestureUpdateResult(
            currentViewOffset: clampedOffset,
            selectionProgress: progress,
            selectionSteps: steps == 0 ? nil : steps
        )
    }

    static func gestureEnd(
        state: GestureState,
        spans: [Double],
        activeContainerIndex: Int,
        gap: Double,
        viewportSpan: Double,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool
    ) -> GestureEndResult {
        let velocity = trackerVelocity(state)
        let currentOffset = state.currentViewOffset
        let normFactor = state.isTrackpad ? viewportSpan / gestureWorkingAreaMovement : 1.0
        let projectedTrackerPos = projectedEndPosition(state) * normFactor
        let projectedOffset = projectedTrackerPos + state.deltaFromTracker

        let activeColX = spans.isEmpty ? 0 : containerPosition(spans: spans, index: activeContainerIndex, gap: gap)
        let currentViewPos = activeColX + currentOffset
        let projectedViewPos = activeColX + projectedOffset

        let snap = findSnapTarget(
            spans: spans,
            gap: gap,
            viewportSpan: viewportSpan,
            projectedViewPos: projectedViewPos,
            currentViewPos: currentViewPos,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        let newColX = spans.isEmpty ? 0 : containerPosition(spans: spans, index: snap.columnIndex, gap: gap)
        let offsetDelta = activeColX - newColX
        let targetOffset = snap.viewPos - newColX

        let totalW = totalSpan(spans: spans, gap: gap)
        let maxOffset = 0.0
        let minOffset = viewportSpan - totalW
        let clampedTarget = min(max(targetOffset, minOffset), maxOffset)

        return GestureEndResult(
            resolvedColumnIndex: snap.columnIndex,
            springFrom: currentOffset + offsetDelta,
            springTo: clampedTarget,
            initialVelocity: velocity
        )
    }
}
