import COmniWMKernels
import Foundation
import Testing

private func makeNiriLayoutInput(
    workingFrame: CGRect = CGRect(x: 0, y: 0, width: 1600, height: 900),
    viewFrame: CGRect? = nil,
    scale: CGFloat = 2.0,
    primaryGap: CGFloat = 8,
    secondaryGap: CGFloat = 8,
    viewOffset: CGFloat = 0,
    workspaceOffset: CGFloat = 0,
    aspectRatio: CGFloat = 4.0 / 3.0,
    activeContainerIndex: Int32 = 0,
    hiddenPlacementMonitorIndex: Int32 = -1,
    orientation: UInt32 = UInt32(OMNIWM_NIRI_ORIENTATION_HORIZONTAL),
    singleWindowMode: Bool = false
) -> omniwm_niri_layout_input {
    let resolvedViewFrame = viewFrame ?? workingFrame
    return omniwm_niri_layout_input(
        working_x: workingFrame.minX,
        working_y: workingFrame.minY,
        working_width: workingFrame.width,
        working_height: workingFrame.height,
        view_x: resolvedViewFrame.minX,
        view_y: resolvedViewFrame.minY,
        view_width: resolvedViewFrame.width,
        view_height: resolvedViewFrame.height,
        scale: scale,
        primary_gap: primaryGap,
        secondary_gap: secondaryGap,
        tab_indicator_width: 0,
        view_offset: viewOffset,
        workspace_offset: workspaceOffset,
        single_window_aspect_ratio: aspectRatio,
        single_window_aspect_tolerance: 0.001,
        active_container_index: activeContainerIndex,
        hidden_placement_monitor_index: hiddenPlacementMonitorIndex,
        orientation: orientation,
        single_window_mode: singleWindowMode ? 1 : 0
    )
}

private func makeNiriContainerInput(
    span: CGFloat,
    windowStartIndex: UInt32,
    windowCount: UInt32,
    isTabbed: Bool = false,
    manualSingleWindowWidthOverride: Bool = false
) -> omniwm_niri_container_input {
    omniwm_niri_container_input(
        span: span,
        render_offset_x: 0,
        render_offset_y: 0,
        window_start_index: windowStartIndex,
        window_count: windowCount,
        is_tabbed: isTabbed ? 1 : 0,
        has_manual_single_window_width_override: manualSingleWindowWidthOverride ? 1 : 0
    )
}

private func makeNiriWindowInput(
    sizingMode: UInt8 = UInt8(OMNIWM_NIRI_WINDOW_SIZING_NORMAL)
) -> omniwm_niri_window_input {
    omniwm_niri_window_input(
        weight: 1,
        min_constraint: 1,
        max_constraint: 0,
        fixed_value: 0,
        render_offset_x: 0,
        render_offset_y: 0,
        has_max_constraint: 0,
        is_constraint_fixed: 0,
        has_fixed_value: 0,
        sizing_mode: sizingMode
    )
}

private func zeroContainerOutput() -> omniwm_niri_container_output {
    omniwm_niri_container_output(
        canonical_x: 0,
        canonical_y: 0,
        canonical_width: 0,
        canonical_height: 0,
        rendered_x: 0,
        rendered_y: 0,
        rendered_width: 0,
        rendered_height: 0
    )
}

private func zeroWindowOutput() -> omniwm_niri_window_output {
    omniwm_niri_window_output(
        canonical_x: 0,
        canonical_y: 0,
        canonical_width: 0,
        canonical_height: 0,
        rendered_x: 0,
        rendered_y: 0,
        rendered_width: 0,
        rendered_height: 0,
        resolved_span: 0,
        hidden_edge: 0
    )
}

private func sentinelContainerOutput() -> omniwm_niri_container_output {
    omniwm_niri_container_output(
        canonical_x: 999,
        canonical_y: 999,
        canonical_width: 999,
        canonical_height: 999,
        rendered_x: 999,
        rendered_y: 999,
        rendered_width: 999,
        rendered_height: 999
    )
}

private func sentinelWindowOutput() -> omniwm_niri_window_output {
    omniwm_niri_window_output(
        canonical_x: 999,
        canonical_y: 999,
        canonical_width: 999,
        canonical_height: 999,
        rendered_x: 999,
        rendered_y: 999,
        rendered_width: 999,
        rendered_height: 999,
        resolved_span: 999,
        hidden_edge: 255
    )
}

@Suite struct NiriLayoutKernelABITests {
    @Test func emptyBuffersReturnSuccess() {
        #expect(
            omniwm_niri_layout_solve(
                nil,
                nil,
                0,
                nil,
                0,
                nil,
                0,
                nil,
                0,
                nil,
                0
            ) == OMNIWM_KERNELS_STATUS_OK
        )
    }

    @Test func singleWindowModeAspectFitsAndPreservesExtraOutputCapacity() {
        var input = makeNiriLayoutInput(singleWindowMode: true)
        let containers = [makeNiriContainerInput(span: 0, windowStartIndex: 0, windowCount: 1)]
        let windows = [makeNiriWindowInput()]
        var containerOutputs = [zeroContainerOutput(), sentinelContainerOutput()]
        var windowOutputs = [zeroWindowOutput(), sentinelWindowOutput()]

        let status = containers.withUnsafeBufferPointer { containerBuffer in
            windows.withUnsafeBufferPointer { windowBuffer in
                containerOutputs.withUnsafeMutableBufferPointer { containerOutputBuffer in
                    windowOutputs.withUnsafeMutableBufferPointer { windowOutputBuffer in
                        omniwm_niri_layout_solve(
                            &input,
                            containerBuffer.baseAddress,
                            containerBuffer.count,
                            windowBuffer.baseAddress,
                            windowBuffer.count,
                            nil,
                            0,
                            containerOutputBuffer.baseAddress,
                            containerOutputBuffer.count,
                            windowOutputBuffer.baseAddress,
                            windowOutputBuffer.count
                        )
                    }
                }
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(abs(containerOutputs[0].canonical_x - 200) < 0.001)
        #expect(abs(containerOutputs[0].canonical_width - 1200) < 0.001)
        #expect(abs(windowOutputs[0].rendered_x - 200) < 0.001)
        #expect(abs(windowOutputs[0].rendered_width - 1200) < 0.001)
        #expect(abs(windowOutputs[0].resolved_span - 900) < 0.001)
        #expect(windowOutputs[0].hidden_edge == UInt8(OMNIWM_NIRI_HIDDEN_EDGE_NONE))
        #expect(containerOutputs[1].canonical_x == 999)
        #expect(windowOutputs[1].resolved_span == 999)
        #expect(windowOutputs[1].hidden_edge == 255)
    }

    @Test func offscreenSecondContainerReturnsMaximumHiddenEdgeInStableIndexOrder() {
        var input = makeNiriLayoutInput(
            workingFrame: CGRect(x: 0, y: 0, width: 600, height: 900),
            viewFrame: CGRect(x: 0, y: 0, width: 600, height: 900)
        )
        let containers = [
            makeNiriContainerInput(span: 600, windowStartIndex: 0, windowCount: 1),
            makeNiriContainerInput(span: 600, windowStartIndex: 1, windowCount: 1),
        ]
        let windows = [makeNiriWindowInput(), makeNiriWindowInput()]
        var containerOutputs = [zeroContainerOutput(), zeroContainerOutput()]
        var windowOutputs = [zeroWindowOutput(), zeroWindowOutput()]

        let status = containers.withUnsafeBufferPointer { containerBuffer in
            windows.withUnsafeBufferPointer { windowBuffer in
                containerOutputs.withUnsafeMutableBufferPointer { containerOutputBuffer in
                    windowOutputs.withUnsafeMutableBufferPointer { windowOutputBuffer in
                        omniwm_niri_layout_solve(
                            &input,
                            containerBuffer.baseAddress,
                            containerBuffer.count,
                            windowBuffer.baseAddress,
                            windowBuffer.count,
                            nil,
                            0,
                            containerOutputBuffer.baseAddress,
                            containerOutputBuffer.count,
                            windowOutputBuffer.baseAddress,
                            windowOutputBuffer.count
                        )
                    }
                }
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_OK)
        #expect(abs(containerOutputs[0].canonical_x - 0) < 0.001)
        #expect(abs(containerOutputs[1].canonical_x - 608) < 0.001)
        #expect(abs(windowOutputs[0].canonical_x - 0) < 0.001)
        #expect(abs(windowOutputs[1].canonical_x - 608) < 0.001)
        #expect(abs(windowOutputs[1].rendered_x - 599.5) < 0.001)
        #expect(windowOutputs[1].hidden_edge == UInt8(OMNIWM_NIRI_HIDDEN_EDGE_MAXIMUM))
    }

    @Test func insufficientOutputCapacityReturnsInvalidArgument() {
        var input = makeNiriLayoutInput()
        let containers = [makeNiriContainerInput(span: 400, windowStartIndex: 0, windowCount: 1)]
        let windows = [makeNiriWindowInput()]
        var containerOutputs = [zeroContainerOutput()]
        var windowOutputs: [omniwm_niri_window_output] = []

        let status = containers.withUnsafeBufferPointer { containerBuffer in
            windows.withUnsafeBufferPointer { windowBuffer in
                containerOutputs.withUnsafeMutableBufferPointer { containerOutputBuffer in
                    windowOutputs.withUnsafeMutableBufferPointer { windowOutputBuffer in
                        omniwm_niri_layout_solve(
                            &input,
                            containerBuffer.baseAddress,
                            containerBuffer.count,
                            windowBuffer.baseAddress,
                            windowBuffer.count,
                            nil,
                            0,
                            containerOutputBuffer.baseAddress,
                            containerOutputBuffer.count,
                            windowOutputBuffer.baseAddress,
                            windowOutputBuffer.count
                        )
                    }
                }
            }
        }

        #expect(status == OMNIWM_KERNELS_STATUS_INVALID_ARGUMENT)
    }
}
