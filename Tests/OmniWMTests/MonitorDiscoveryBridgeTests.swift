import CZigLayout
import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class MonitorDiscoveryBridgeTests: XCTestCase {
    @MainActor
    final class MonitorProviderState {
        var monitors: [Monitor]

        init(monitors: [Monitor]) {
            self.monitors = monitors
        }
    }

    func testQueryBridgeSupportsProbeAndMapsMonitorRecord() {
        let originalQuery = OmniMonitorQueryBridge.queryFunction
        defer { OmniMonitorQueryBridge.queryFunction = originalQuery }

        let record = OmniMonitorRecord(
            display_id: 77,
            is_main: 1,
            frame_x: 10,
            frame_y: 20,
            frame_width: 2560,
            frame_height: 1440,
            visible_x: 10,
            visible_y: 30,
            visible_width: 2560,
            visible_height: 1400,
            has_notch: 1,
            backing_scale: 2,
            name: rawName("Studio Display")
        )

        OmniMonitorQueryBridge.queryFunction = { outMonitors, outCapacity, outWritten in
            if outMonitors == nil, outCapacity == 0 {
                outWritten.pointee = 1
                return Int32(OMNI_ERR_OUT_OF_RANGE)
            }
            guard let outMonitors else {
                return Int32(OMNI_ERR_INVALID_ARGS)
            }
            outWritten.pointee = 1
            outMonitors.pointee = record
            return Int32(OMNI_OK)
        }

        let monitors = OmniMonitorQueryBridge.queryCurrentMonitors()
        XCTAssertEqual(monitors?.count, 1)
        guard let first = monitors?.first else {
            XCTFail("Expected monitor record from query bridge")
            return
        }
        XCTAssertEqual(first.displayId, 77)
        XCTAssertEqual(first.name, "Studio Display")
        XCTAssertTrue(first.hasNotch)
        XCTAssertEqual(first.scale, 2.0, accuracy: 0.0001)
        XCTAssertEqual(first.visibleFrame.height, 1400, accuracy: 0.0001)
    }

    @MainActor
    func testDisplayObserverDebounceAndDiffWithInjectedSource() async {
        var monitorA = Monitor(
            id: .init(displayId: 1001),
            displayId: 1001,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            hasNotch: false,
            name: "Primary",
            scale: 2.0
        )
        let monitorB = Monitor(
            id: .init(displayId: 1002),
            displayId: 1002,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1040),
            hasNotch: false,
            name: "Secondary",
            scale: 2.0
        )
        let monitorState = MonitorProviderState(monitors: [monitorA])
        var capturedEvents: [DisplayConfigurationObserver.DisplayEvent] = []
        var trigger: (() -> Void)?

        let observer = DisplayConfigurationObserver(
            monitorProvider: { monitorState.monitors },
            debounceInterval: 1_000_000,
            subscribeToDisplayChanges: { handler in
                trigger = {
                    Task { @MainActor in
                        handler()
                    }
                }
                return {}
            }
        )
        observer.setEventHandler { event in
            capturedEvents.append(event)
        }

        monitorState.monitors = [monitorA, monitorB]
        trigger?()
        try? await Task.sleep(nanoseconds: 20_000_000)

        monitorA = Monitor(
            id: monitorA.id,
            displayId: monitorA.displayId,
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 24, width: 1728, height: 1093),
            hasNotch: false,
            name: "Primary",
            scale: 2.0
        )
        monitorState.monitors = [monitorA, monitorB]
        trigger?()
        try? await Task.sleep(nanoseconds: 20_000_000)

        monitorState.monitors = [monitorA]
        trigger?()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(capturedEvents.count, 3)

        if case let .connected(connectedMonitor) = capturedEvents[0] {
            XCTAssertEqual(connectedMonitor.displayId, monitorB.displayId)
        } else {
            XCTFail("Expected connected event")
        }

        if case let .reconfigured(reconfiguredMonitor) = capturedEvents[1] {
            XCTAssertEqual(reconfiguredMonitor.displayId, monitorA.displayId)
            XCTAssertEqual(reconfiguredMonitor.frame.width, 1728, accuracy: 0.0001)
        } else {
            XCTFail("Expected reconfigured event")
        }

        if case let .disconnected(_, outputId) = capturedEvents[2] {
            XCTAssertEqual(outputId.displayId, monitorB.displayId)
            XCTAssertEqual(outputId.name, monitorB.name)
        } else {
            XCTFail("Expected disconnected event")
        }
    }

    private func rawName(_ value: String) -> OmniWorkspaceRuntimeName {
        var result = OmniWorkspaceRuntimeName()
        let utf8 = Array(value.utf8.prefix(Int(OMNI_WORKSPACE_RUNTIME_NAME_CAP)))
        result.length = UInt8(utf8.count)
        withUnsafeMutableBytes(of: &result.bytes) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            rawBuffer.copyBytes(from: utf8)
        }
        return result
    }
}
