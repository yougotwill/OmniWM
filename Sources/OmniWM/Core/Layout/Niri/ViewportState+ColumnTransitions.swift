import AppKit
import Foundation

extension ViewportState {
    mutating func setActiveColumn(
        _ index: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        animate: Bool = false
    ) {
        guard !columns.isEmpty else { return }
        let safeCurrentIndex = activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let clampedIndex = index.clamped(to: 0 ... (columns.count - 1))
        transitionToColumn(
            clampedIndex,
            columns: columns,
            gap: gap,
            viewportWidth: viewportWidth,
            animate: animate,
            centerMode: .always,
            alwaysCenterSingleColumn: true,
            fromColumnIndex: safeCurrentIndex,
            scale: 2.0
        )
    }

    mutating func transitionToColumn(
        _ newIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        animate: Bool,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromColumnIndex: Int? = nil,
        scale: CGFloat = 2.0
    ) {
        guard !columns.isEmpty else { return }
        let safeCurrentIndex = activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let requestedNonNegative = max(newIndex, 0)
        let resolvedFromColumnIndex: Int = if let fromColumnIndex,
                                              (0 ..< columns.count).contains(fromColumnIndex) {
            fromColumnIndex
        } else {
            safeCurrentIndex
        }
        let spans = columns.map { Double($0.cachedWidth) }
        let plan = NiriViewportZigMath.transitionPlan(
            spans: spans,
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: requestedNonNegative,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: viewOffsetPixels.target(),
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: resolvedFromColumnIndex,
            scale: scale
        )

        activeColumnIndex = plan.resolvedColumnIndex
        viewOffsetPixels.offset(delta: Double(plan.offsetDelta))

        if plan.snapToTargetImmediately {
            viewOffsetPixels.offset(delta: Double(plan.snapDelta))
            activatePrevColumnOnRemoval = nil
            viewOffsetToRestore = nil
            return
        }

        if animate {
            animateToOffset(plan.targetOffset)
        } else {
            viewOffsetPixels = .static(plan.targetOffset)
        }

        activatePrevColumnOnRemoval = nil
        viewOffsetToRestore = nil
    }

    mutating func ensureContainerVisible(
        containerIndex: Int,
        containers: [NiriContainer],
        gap: CGFloat,
        viewportSpan: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>,
        animate: Bool = true,
        centerMode: CenterFocusedColumn = .never,
        alwaysCenterSingleColumn: Bool = false,
        animationConfig: SpringConfig? = nil,
        fromContainerIndex: Int? = nil
    ) {
        guard !containers.isEmpty, containerIndex >= 0, containerIndex < containers.count else { return }
        let safeActiveIndex = activeColumnIndex.clamped(to: 0 ... (containers.count - 1))
        let normalizedFromContainerIndex: Int? = if let fromContainerIndex {
            if (0 ..< containers.count).contains(fromContainerIndex) {
                fromContainerIndex
            } else {
                safeActiveIndex
            }
        } else {
            nil
        }
        let spans = containers.map { Double($0[keyPath: sizeKeyPath]) }
        let currentOffset = viewOffsetPixels.current()
        let plan = NiriViewportZigMath.ensureVisiblePlan(
            spans: spans,
            activeContainerIndex: safeActiveIndex,
            targetContainerIndex: containerIndex,
            gap: gap,
            viewportSpan: viewportSpan,
            currentOffset: currentOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: normalizedFromContainerIndex
        )

        if plan.isNoop {
            return
        }

        if animate {
            let now = animationClock?.now() ?? CACurrentMediaTime()
            let currentVelocity = viewOffsetPixels.currentVelocity()
            let config = animationConfig ?? springConfig
            let animation = SpringAnimation(
                from: Double(currentOffset),
                to: Double(plan.targetOffset),
                initialVelocity: currentVelocity,
                startTime: now,
                config: config,
                displayRefreshRate: displayRefreshRate
            )
            viewOffsetPixels = .spring(animation)
        } else {
            viewOffsetPixels = .static(plan.targetOffset)
        }
    }

    mutating func snapToColumn(
        _ columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat
    ) {
        guard !columns.isEmpty else { return }
        let safeCurrentIndex = activeColumnIndex.clamped(to: 0 ... (columns.count - 1))
        let requestedNonNegative = max(columnIndex, 0)
        let spans = columns.map { Double($0.cachedWidth) }
        let plan = NiriViewportZigMath.transitionPlan(
            spans: spans,
            currentActiveIndex: safeCurrentIndex,
            requestedIndex: requestedNonNegative,
            gap: gap,
            viewportSpan: viewportWidth,
            currentTargetOffset: viewOffsetPixels.target(),
            centerMode: .always,
            alwaysCenterSingleColumn: true,
            fromContainerIndex: safeCurrentIndex,
            scale: 2.0
        )

        activeColumnIndex = plan.resolvedColumnIndex
        viewOffsetPixels = .static(plan.targetOffset)
        selectionProgress = 0
    }

    mutating func scrollByPixels(
        _ deltaPixels: CGFloat,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        changeSelection: Bool
    ) -> Int? {
        let spans = columns.map { Double($0.cachedWidth) }
        let result = NiriViewportZigMath.scrollStep(
            spans: spans,
            deltaPixels: deltaPixels,
            viewportSpan: viewportWidth,
            gap: gap,
            currentOffset: viewOffsetPixels.current(),
            selectionProgress: selectionProgress,
            changeSelection: changeSelection
        )

        guard result.applied else {
            return nil
        }

        viewOffsetPixels = .static(result.newOffset)
        selectionProgress = result.selectionProgress
        return result.selectionSteps
    }
}
