import CZigLayout
import Foundation
import XCTest

@testable import OmniWM

final class ZigCoreRuntimeHostCallbackTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ZigCoreRuntimeHostCallbackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func testReportErrorCallbackDispatchesOnMainActorFromOffMain() async {
        let (_, runtime) = makeRuntime()

        var delivered: (code: Int32, message: String, onMain: Bool)?
        runtime.debugOnControllerErrorDispatched = { code, message in
            delivered = (code, message, Thread.isMainThread)
        }

        await runtime.debugInvokeWMReportErrorOffMain(code: Int32(OMNI_ERR_OUT_OF_RANGE), message: "threaded error")

        XCTAssertEqual(delivered?.code, Int32(OMNI_ERR_OUT_OF_RANGE))
        XCTAssertEqual(delivered?.message, "threaded error")
        XCTAssertEqual(delivered?.onMain, true)
    }

    @MainActor
    func testApplyEffectsCallbackDispatchesUIActionsOnMainActorFromOffMain() async {
        let (_, runtime) = makeRuntime()

        var delivered: ([UInt8], Bool)?
        runtime.debugOnUIActionsDispatched = { actions in
            delivered = (actions, Thread.isMainThread)
        }

        await runtime.debugInvokeWMApplyEffectsOffMain([
            rawEnumValue(OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER),
            rawEnumValue(OMNI_CONTROLLER_UI_TOGGLE_OVERVIEW),
        ])

        XCTAssertEqual(delivered?.0, [
            rawEnumValue(OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER),
            rawEnumValue(OMNI_CONTROLLER_UI_TOGGLE_OVERVIEW),
        ])
        XCTAssertEqual(delivered?.1, true)
    }

    @MainActor
    func testSecureInputAndTapCallbacksDispatchOnMainActorFromOffMain() async {
        let (_, runtime) = makeRuntime()

        var secureStates: [(Bool, Bool)] = []
        runtime.onSecureInputStateChange = { isSecure in
            secureStates.append((isSecure, Thread.isMainThread))
        }

        await runtime.debugInvokeSecureInputChangedOffMain(true)

        XCTAssertEqual(secureStates.count, 1)
        XCTAssertEqual(secureStates.first?.0, true)
        XCTAssertEqual(secureStates.first?.1, true)

        var tapEvent: (UInt8, UInt8, Bool)?
        runtime.onTapHealthNotification = { tapKind, reason in
            tapEvent = (tapKind, reason, Thread.isMainThread)
        }

        await runtime.debugInvokeTapHealthOffMain(
            tapKind: rawEnumValue(OMNI_INPUT_TAP_KIND_SECURE_INPUT),
            reason: rawEnumValue(OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT)
        )

        XCTAssertEqual(tapEvent?.0, rawEnumValue(OMNI_INPUT_TAP_KIND_SECURE_INPUT))
        XCTAssertEqual(tapEvent?.1, rawEnumValue(OMNI_INPUT_TAP_HEALTH_DISABLED_USER_INPUT))
        XCTAssertEqual(tapEvent?.2, true)
    }

    @MainActor
    func testLifecycleCallbacksDispatchOnMainActorFromOffMain() async {
        let (_, runtime) = makeRuntime()

        XCTAssertFalse(runtime.started)
        XCTAssertEqual(runtime.debugSnapshotInvalidationCount, 0)

        await runtime.debugInvokeLifecycleStateChangedOffMain(rawEnumValue(OMNI_SERVICE_LIFECYCLE_STATE_RUNNING))
        XCTAssertTrue(runtime.started)
        XCTAssertEqual(runtime.debugSnapshotInvalidationCount, 0)

        await runtime.debugInvokeLifecycleStateChangedOffMain(rawEnumValue(OMNI_SERVICE_LIFECYCLE_STATE_STOPPED))
        XCTAssertFalse(runtime.started)
        XCTAssertEqual(runtime.debugSnapshotInvalidationCount, 1)

        var delivered: (Int32, String, Bool)?
        runtime.debugOnControllerErrorDispatched = { code, message in
            delivered = (code, message, Thread.isMainThread)
        }

        await runtime.debugInvokeLifecycleErrorOffMain(code: Int32(OMNI_ERR_PLATFORM), message: "lifecycle failed")

        XCTAssertFalse(runtime.started)
        XCTAssertEqual(runtime.debugSnapshotInvalidationCount, 2)
        XCTAssertEqual(delivered?.0, Int32(OMNI_ERR_PLATFORM))
        XCTAssertEqual(delivered?.1, "lifecycle failed")
        XCTAssertEqual(delivered?.2, true)
    }

    @MainActor
    private func makeRuntime() -> (WorkspaceManager, ZigCoreRuntime) {
        let settings = SettingsStore(defaults: defaults)
        let workspaceManager = WorkspaceManager(settings: settings)
        let runtime = ZigCoreRuntime(workspaceRuntimeHandle: workspaceManager.runtimeHandle)
        return (workspaceManager, runtime)
    }

    private func rawEnumValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
        UInt8(clamping: Int(value.rawValue))
    }
}
