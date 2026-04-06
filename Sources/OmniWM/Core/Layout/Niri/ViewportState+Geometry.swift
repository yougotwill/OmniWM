import COmniWMKernels
import Foundation

private extension CenterFocusedColumn {
    var zigRawValue: UInt32 {
        switch self {
        case .never:
            return UInt32(OMNIWM_CENTER_FOCUSED_COLUMN_NEVER)
        case .always:
            return UInt32(OMNIWM_CENTER_FOCUSED_COLUMN_ALWAYS)
        case .onOverflow:
            return UInt32(OMNIWM_CENTER_FOCUSED_COLUMN_ON_OVERFLOW)
        }
    }
}

extension ViewportState {
    private func withSpanBuffer<Result>(
        containers: [NiriContainer],
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>,
        _ body: (UnsafeBufferPointer<Double>) -> Result
    ) -> Result {
        withUnsafeTemporaryAllocation(of: Double.self, capacity: containers.count) { spans in
            for (index, container) in containers.enumerated() {
                spans[index] = container[keyPath: sizeKeyPath]
            }
            return body(UnsafeBufferPointer(start: spans.baseAddress, count: containers.count))
        }
    }

    func columnX(at index: Int, columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        containerPosition(at: index, containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func totalWidth(columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        totalSpan(containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func containerPosition(
        at index: Int,
        containers: [NiriContainer],
        gap: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>
    ) -> CGFloat {
        guard index >= 0 else { return 0 }

        return withSpanBuffer(containers: containers, sizeKeyPath: sizeKeyPath) { spans in
            omniwm_geometry_container_position(
                spans.baseAddress,
                spans.count,
                gap,
                numericCast(index)
            )
        }
    }

    func totalSpan(
        containers: [NiriContainer],
        gap: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>
    ) -> CGFloat {
        withSpanBuffer(containers: containers, sizeKeyPath: sizeKeyPath) { spans in
            omniwm_geometry_total_span(
                spans.baseAddress,
                spans.count,
                gap
            )
        }
    }

    func computeCenteredOffset(
        containerIndex: Int,
        containers: [NiriContainer],
        gap: CGFloat,
        viewportSpan: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>
    ) -> CGFloat {
        guard containerIndex >= 0 else { return 0 }

        return withSpanBuffer(containers: containers, sizeKeyPath: sizeKeyPath) { spans in
            omniwm_geometry_centered_offset(
                spans.baseAddress,
                spans.count,
                gap,
                viewportSpan,
                numericCast(containerIndex)
            )
        }
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
        fromContainerIndex: Int? = nil,
        scale: CGFloat = 2.0
    ) -> CGFloat {
        guard containerIndex >= 0 else { return 0 }

        return withSpanBuffer(containers: containers, sizeKeyPath: sizeKeyPath) { spans in
            omniwm_geometry_visible_offset(
                spans.baseAddress,
                spans.count,
                gap,
                viewportSpan,
                Int32(containerIndex),
                currentViewStart,
                centerMode.zigRawValue,
                alwaysCenterSingleColumn ? 1 : 0,
                Int32(fromContainerIndex ?? -1),
                scale
            )
        }
    }

    func computeCenteredOffset(
        columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        computeCenteredOffset(
            containerIndex: columnIndex,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth
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
        fromColumnIndex: Int? = nil,
        scale: CGFloat = 2.0
    ) -> CGFloat {
        let columnPosition = columnX(at: columnIndex, columns: columns, gap: gap)
        return computeVisibleOffset(
            containerIndex: columnIndex,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: columnPosition + currentOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromColumnIndex,
            scale: scale
        )
    }
}
