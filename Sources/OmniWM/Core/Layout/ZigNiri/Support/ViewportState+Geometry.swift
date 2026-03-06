import Foundation

extension ViewportState {
    func columnX(at index: Int, columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        containerPosition(at: index, containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func containerPosition(at index: Int, containers: [NiriContainer], gap: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        var pos: CGFloat = 0
        for i in 0 ..< index {
            guard i < containers.count else { break }
            pos += containers[i][keyPath: sizeKeyPath] + gap
        }
        return pos
    }

    func totalSpan(containers: [NiriContainer], gap: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        guard !containers.isEmpty else { return 0 }
        let sizeSum = containers.reduce(0) { $0 + $1[keyPath: sizeKeyPath] }
        let gapSum = CGFloat(max(0, containers.count - 1)) * gap
        return sizeSum + gapSum
    }

    func computeVisibleOffset(
        containerIndex: Int,
        containers: [NiriContainer],
        gap: CGFloat,
        viewportSpan: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>,
        currentViewStart: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromContainerIndex: Int? = nil
    ) -> CGFloat {
        guard !containers.isEmpty, containerIndex >= 0, containerIndex < containers.count else { return 0 }

        let spans = containers.map { Double($0[keyPath: sizeKeyPath]) }
        return NiriViewportZigMath.computeVisibleOffset(
            spans: spans,
            containerIndex: containerIndex,
            gap: gap,
            viewportSpan: viewportSpan,
            currentViewStart: currentViewStart,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromContainerIndex
        )
    }

    func computeVisibleOffset(
        columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        currentOffset: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromColumnIndex: Int? = nil
    ) -> CGFloat {
        let colX = columnX(at: columnIndex, columns: columns, gap: gap)
        return computeVisibleOffset(
            containerIndex: columnIndex,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: colX + currentOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromColumnIndex
        )
    }
}
