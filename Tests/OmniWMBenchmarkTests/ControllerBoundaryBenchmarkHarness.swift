import CZigLayout
import CoreGraphics
import Foundation

@testable import OmniWM

struct ControllerBoundaryScenario: Codable {
    struct Seed: Codable {
        struct Workspace: Codable {
            let name: String
            let windowCount: Int
        }

        struct MonitorSeed: Codable {
            struct Insets: Codable {
                let left: Double
                let right: Double
                let top: Double
                let bottom: Double
            }

            let displayId: UInt32
            let width: Double
            let height: Double
            let visibleInsets: Insets
        }

        let maxWindowsPerColumn: Int
        let maxVisibleColumns: Int
        let gap: Double
        let scale: Double
        let monitor: MonitorSeed
        let workspaces: [Workspace]
    }

    struct Event: Codable {
        enum Kind: String, Codable, CaseIterable {
            case submitHotkey
            case submitOsEvent
            case tick
            case workspaceSnapshotCopy
            case projectionRefresh
        }

        let kind: Kind
        let count: Int
    }

    let name: String
    let warmupIterations: Int
    let measuredIterations: Int
    let seed: Seed
    let events: [Event]
}

typealias ControllerBoundaryBenchmarkReport = OmniBenchmarkReport

@MainActor
enum ControllerBoundaryBenchmarkHarness {
    static let environmentKey = "OMNI_CONTROLLER_BENCH"

    private static let reportPathEnvironmentKey = "OMNI_CONTROLLER_REPORT_PATH"

    enum Error: Swift.Error, CustomStringConvertible {
        case invalidScenario(String)
        case operationFailed(String)

        var description: String {
            switch self {
            case let .invalidScenario(message):
                return "Invalid scenario: \(message)"
            case let .operationFailed(message):
                return "Operation failed: \(message)"
            }
        }
    }

    @MainActor
    private final class Fixture {
        let defaultsSuiteName: String
        let defaults: UserDefaults
        let settings: SettingsStore
        let monitor: Monitor
        let runtimeAdapter: OmniWorkspaceRuntimeAdapter
        let workspaceManager: WorkspaceManager
        let engine: ZigNiriEngine
        let workspaceRuntime: OpaquePointer
        let controllerRuntime: OpaquePointer
        let primaryWorkspaceId: WorkspaceDescriptor.ID
        let secondaryWorkspaceId: WorkspaceDescriptor.ID
        let primaryHandle: WindowHandle
        let alternatePrimaryHandle: WindowHandle
        let secondaryHandle: WindowHandle
        let removablePrimaryWindowKey: WindowModel.WindowKey

        private var nextTickSampleTime: Double = 10
        private var isCleanedUp: Bool = false

        init(seed: ControllerBoundaryScenario.Seed) throws {
            guard seed.workspaces.count >= 2 else {
                throw Error.invalidScenario("at least two workspaces are required")
            }

            let suiteName = "ControllerBoundaryBenchmarkHarness.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                throw Error.operationFailed("failed to create isolated defaults suite")
            }
            var shouldCleanupDefaults = true
            var temporaryWorkspaceRuntime: OpaquePointer?
            var temporaryControllerRuntime: OpaquePointer?
            var initialized = false
            defer {
                if !initialized {
                    if let temporaryControllerRuntime {
                        _ = omni_wm_controller_stop(temporaryControllerRuntime)
                        omni_wm_controller_destroy(temporaryControllerRuntime)
                    }
                    if let temporaryWorkspaceRuntime {
                        _ = omni_workspace_runtime_stop(temporaryWorkspaceRuntime)
                        omni_workspace_runtime_destroy(temporaryWorkspaceRuntime)
                    }
                    if shouldCleanupDefaults {
                        defaults.removePersistentDomain(forName: suiteName)
                    }
                }
            }

            defaultsSuiteName = suiteName
            self.defaults = defaults
            defaults.removePersistentDomain(forName: suiteName)
            settings = SettingsStore(defaults: defaults)

            guard let workspaceRuntime = Self.makeWorkspaceRuntime() else {
                throw Error.operationFailed("failed to create workspace runtime")
            }
            temporaryWorkspaceRuntime = workspaceRuntime
            self.workspaceRuntime = workspaceRuntime

            runtimeAdapter = OmniWorkspaceRuntimeAdapter(existingRuntimeHandle: workspaceRuntime)
            monitor = Self.makeMonitor(seed.monitor)
            workspaceManager = WorkspaceManager(
                settings: settings,
                runtimeAdapter: runtimeAdapter,
                initialMonitors: [monitor]
            )

            let workspaceIds = try Self.seedWorkspaces(
                seed: seed,
                monitor: monitor,
                runtimeAdapter: runtimeAdapter
            )
            primaryWorkspaceId = workspaceIds.primaryWorkspaceId
            secondaryWorkspaceId = workspaceIds.secondaryWorkspaceId

            guard workspaceManager.syncRuntimeStateFromCore() else {
                throw Error.operationFailed("failed to sync workspace manager from runtime")
            }

            engine = ZigNiriEngine(
                maxWindowsPerColumn: seed.maxWindowsPerColumn,
                maxVisibleColumns: seed.maxVisibleColumns,
                infiniteLoop: false
            )

            guard let controllerRuntime = Self.makeControllerRuntime(workspaceRuntime: workspaceRuntime) else {
                throw Error.operationFailed("failed to create wm controller")
            }
            temporaryControllerRuntime = controllerRuntime
            self.controllerRuntime = controllerRuntime

            try Self.applyControllerSettings(
                controllerRuntime: controllerRuntime,
                seed: seed
            )
            try Self.startController(controllerRuntime)

            let handlesByWorkspace = try Self.seedWorkspaceProjections(
                workspaceManager: workspaceManager,
                engine: engine,
                primaryWorkspaceId: primaryWorkspaceId,
                secondaryWorkspaceId: secondaryWorkspaceId
            )
            primaryHandle = handlesByWorkspace.primaryHandle
            alternatePrimaryHandle = handlesByWorkspace.alternatePrimaryHandle
            secondaryHandle = handlesByWorkspace.secondaryHandle
            removablePrimaryWindowKey = handlesByWorkspace.removablePrimaryWindowKey

            try submitFocusChangedEvent()
            guard WMControllerSnapshotAdapter.flushAndCapture(runtime: controllerRuntime) != nil else {
                throw Error.operationFailed("failed to establish initial controller snapshot baseline")
            }
            shouldCleanupDefaults = false
            initialized = true
        }

        func cleanup() {
            guard !isCleanedUp else { return }
            isCleanedUp = true
            _ = omni_wm_controller_stop(controllerRuntime)
            omni_wm_controller_destroy(controllerRuntime)
            _ = omni_workspace_runtime_stop(workspaceRuntime)
            omni_workspace_runtime_destroy(workspaceRuntime)
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        func submitProjectionChangingHotkey() throws {
            var command = OmniControllerCommand(
                kind: Self.rawEnumValue(OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION),
                direction: Self.rawEnumValue(OMNI_NIRI_DIRECTION_RIGHT),
                workspace_index: 0,
                monitor_direction: 0,
                has_workspace_id: 0,
                workspace_id: OmniUuid128(),
                has_window_handle_id: 0,
                window_handle_id: OmniUuid128(),
                has_secondary_window_handle_id: 0,
                secondary_window_handle_id: OmniUuid128()
            )
            let rc = withUnsafePointer(to: &command) { commandPtr in
                omni_wm_controller_submit_hotkey(controllerRuntime, commandPtr)
            }
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("submit projection-changing hotkey failed with code \(rc)")
            }
        }

        func submitLayoutAnimationHotkey() throws {
            var command = OmniControllerCommand(
                kind: Self.rawEnumValue(OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN),
                direction: 0,
                workspace_index: 0,
                monitor_direction: 0,
                has_workspace_id: 0,
                workspace_id: OmniUuid128(),
                has_window_handle_id: 0,
                window_handle_id: OmniUuid128(),
                has_secondary_window_handle_id: 0,
                secondary_window_handle_id: OmniUuid128()
            )
            let rc = withUnsafePointer(to: &command) { commandPtr in
                omni_wm_controller_submit_hotkey(controllerRuntime, commandPtr)
            }
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("submit layout hotkey failed with code \(rc)")
            }
        }

        func submitSecureInputChangedEvent() throws {
            var event = OmniControllerEvent(
                kind: Self.rawEnumValue(OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED),
                enabled: 1,
                refresh_reason: 0,
                has_display_id: 0,
                display_id: 0,
                pid: 0,
                has_window_handle_id: 0,
                window_handle_id: OmniUuid128(),
                has_workspace_id: 0,
                workspace_id: OmniUuid128()
            )
            let rc = withUnsafePointer(to: &event) { eventPtr in
                omni_wm_controller_submit_os_event(controllerRuntime, eventPtr)
            }
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("submit os event failed with code \(rc)")
            }
        }

        func submitFocusChangedEvent() throws {
            var event = OmniControllerEvent(
                kind: Self.rawEnumValue(OMNI_CONTROLLER_EVENT_FOCUS_CHANGED),
                enabled: 0,
                refresh_reason: Self.rawEnumValue(OMNI_CONTROLLER_REFRESH_REASON_TIMER),
                has_display_id: 0,
                display_id: 0,
                pid: primaryHandle.pid,
                has_window_handle_id: 1,
                window_handle_id: ZigNiriStateKernel.omniUUID(from: primaryHandle.id),
                has_workspace_id: 1,
                workspace_id: ZigNiriStateKernel.omniUUID(from: primaryWorkspaceId)
            )
            let rc = withUnsafePointer(to: &event) { eventPtr in
                omni_wm_controller_submit_os_event(controllerRuntime, eventPtr)
            }
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("focus-changed warmup failed with code \(rc)")
            }
        }

        func submitAlternatePrimaryFocusChangedEvent() throws {
            var event = OmniControllerEvent(
                kind: Self.rawEnumValue(OMNI_CONTROLLER_EVENT_FOCUS_CHANGED),
                enabled: 0,
                refresh_reason: Self.rawEnumValue(OMNI_CONTROLLER_REFRESH_REASON_TIMER),
                has_display_id: 0,
                display_id: 0,
                pid: alternatePrimaryHandle.pid,
                has_window_handle_id: 1,
                window_handle_id: ZigNiriStateKernel.omniUUID(from: alternatePrimaryHandle.id),
                has_workspace_id: 1,
                workspace_id: ZigNiriStateKernel.omniUUID(from: primaryWorkspaceId)
            )
            let rc = withUnsafePointer(to: &event) { eventPtr in
                omni_wm_controller_submit_os_event(controllerRuntime, eventPtr)
            }
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("alternate focus event failed with code \(rc)")
            }
        }

        func submitTick() throws {
            let sampleTime = nextTickSampleTime
            nextTickSampleTime += 1
            let rc = omni_wm_controller_tick(controllerRuntime, sampleTime)
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("tick failed with code \(rc)")
            }
        }

        func copyWorkspaceSnapshot() throws -> OmniWorkspaceRuntimeAdapter.StateExport {
            guard let export = WMControllerSnapshotAdapter.flushAndCapture(runtime: controllerRuntime)?.stateExport else {
                throw Error.operationFailed("workspace snapshot copy returned nil")
            }
            return export
        }

        func removeTrackedPrimaryWindowFromRuntime() throws {
            runtimeAdapter.windowRemove(key: removablePrimaryWindowKey)
            guard let export = runtimeAdapter.exportState(),
                  export.windows.contains(where: {
                      $0.pid == primaryHandle.pid && $0.windowId == Int(removablePrimaryWindowKey.windowId)
                  }) == false
            else {
                throw Error.operationFailed("failed to remove the tracked primary window from the runtime")
            }
        }

        func refreshProjectionFromCore(
            limitingTo workspaceIds: Set<WorkspaceDescriptor.ID>? = nil
        ) throws -> Set<WorkspaceDescriptor.ID> {
            guard let snapshotExport = WMControllerSnapshotAdapter.flushAndCapture(runtime: controllerRuntime) else {
                throw Error.operationFailed("projection refresh failed to capture a controller snapshot")
            }

            let limitedChangedWorkspaceIds: Set<WorkspaceDescriptor.ID>?
            if let workspaceIds {
                limitedChangedWorkspaceIds = snapshotExport.changedWorkspaceIds?.intersection(workspaceIds) ?? workspaceIds
            } else {
                limitedChangedWorkspaceIds = snapshotExport.changedWorkspaceIds
            }
            guard let refreshWorkspaceIds = ExperimentalProjectionSyncCoordinator.sync(
                workspaceManager: workspaceManager,
                zigNiriEngine: engine,
                stateExport: snapshotExport.stateExport,
                changedWorkspaceIds: limitedChangedWorkspaceIds
            ) else {
                throw Error.operationFailed("projection refresh failed to sync workspace runtime state")
            }
            let targetedRefreshWorkspaceIds = workspaceIds ?? refreshWorkspaceIds
            for workspaceId in targetedRefreshWorkspaceIds {
                guard engine.refreshWorkspaceProjection(workspaceId) else {
                    throw Error.operationFailed("projection refresh failed for workspace \(workspaceId)")
                }
            }
            return targetedRefreshWorkspaceIds
        }

        private static func makeWorkspaceRuntime() -> OpaquePointer? {
            var config = OmniWorkspaceRuntimeConfig(
                abi_version: UInt32(OMNI_WORKSPACE_RUNTIME_ABI_VERSION),
                reserved: 0
            )
            guard let runtime = withUnsafePointer(to: &config, { configPtr in
                omni_workspace_runtime_create(configPtr)
            }) else {
                return nil
            }
            guard omni_workspace_runtime_start(runtime) == Int32(OMNI_OK) else {
                omni_workspace_runtime_destroy(runtime)
                return nil
            }
            return runtime
        }

        private static func makeControllerRuntime(workspaceRuntime: OpaquePointer) -> OpaquePointer? {
            var config = OmniWMControllerConfig(
                abi_version: UInt32(OMNI_WM_CONTROLLER_ABI_VERSION),
                reserved: 0
            )
            return withUnsafePointer(to: &config) { configPtr in
                omni_wm_controller_create(configPtr, workspaceRuntime, nil)
            }
        }

        private static func applyControllerSettings(
            controllerRuntime: OpaquePointer,
            seed: ControllerBoundaryScenario.Seed
        ) throws {
            var delta = OmniControllerSettingsDelta()
            delta.struct_size = MemoryLayout<OmniControllerSettingsDelta>.size
            delta.has_layout_gap = 1
            delta.layout_gap = seed.gap
            delta.has_niri_max_visible_columns = 1
            delta.niri_max_visible_columns = Int64(seed.maxVisibleColumns)
            delta.has_niri_max_windows_per_column = 1
            delta.niri_max_windows_per_column = Int64(seed.maxWindowsPerColumn)

            let rc = withUnsafePointer(to: &delta) { deltaPtr in
                omni_wm_controller_apply_settings(controllerRuntime, deltaPtr)
            }
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("apply settings failed with code \(rc)")
            }
        }

        private static func startController(_ controllerRuntime: OpaquePointer) throws {
            let rc = omni_wm_controller_start(controllerRuntime)
            guard rc == Int32(OMNI_OK) else {
                throw Error.operationFailed("controller start failed with code \(rc)")
            }
        }

        private static func makeMonitor(_ seed: ControllerBoundaryScenario.Seed.MonitorSeed) -> Monitor {
            let frame = CGRect(x: 0, y: 0, width: seed.width, height: seed.height)
            let visibleFrame = CGRect(
                x: frame.minX + seed.visibleInsets.left,
                y: frame.minY + seed.visibleInsets.bottom,
                width: max(1, frame.width - seed.visibleInsets.left - seed.visibleInsets.right),
                height: max(1, frame.height - seed.visibleInsets.top - seed.visibleInsets.bottom)
            )
            return Monitor(
                id: Monitor.ID(displayId: seed.displayId),
                displayId: seed.displayId,
                frame: frame,
                visibleFrame: visibleFrame,
                hasNotch: false,
                name: "Benchmark"
            )
        }

        private static func seedWorkspaces(
            seed: ControllerBoundaryScenario.Seed,
            monitor: Monitor,
            runtimeAdapter: OmniWorkspaceRuntimeAdapter
        ) throws -> (primaryWorkspaceId: WorkspaceDescriptor.ID, secondaryWorkspaceId: WorkspaceDescriptor.ID) {
            guard let primaryWorkspaceId = runtimeAdapter.workspaceId(
                forName: seed.workspaces[0].name,
                createIfMissing: true
            ), let secondaryWorkspaceId = runtimeAdapter.workspaceId(
                forName: seed.workspaces[1].name,
                createIfMissing: true
            ) else {
                throw Error.operationFailed("failed to create benchmark workspaces")
            }

            guard runtimeAdapter.setActiveWorkspace(primaryWorkspaceId, monitorDisplayId: monitor.displayId) else {
                throw Error.operationFailed("failed to set active workspace")
            }

            let workspaceIds = [primaryWorkspaceId, secondaryWorkspaceId]
            var nextWindowSerial = 1000
            for (workspaceIndex, workspace) in seed.workspaces.enumerated() {
                let workspaceId = workspaceIds[min(workspaceIndex, workspaceIds.count - 1)]
                for windowIndex in 0 ..< max(1, workspace.windowCount) {
                    let pid = pid_t(9000 + workspaceIndex)
                    let windowId = nextWindowSerial + windowIndex
                    guard let handleId = runtimeAdapter.windowUpsert(
                        pid: pid,
                        windowId: windowId,
                        workspaceId: workspaceId,
                        preferredHandleId: nil
                    ) else {
                        throw Error.operationFailed("failed to upsert benchmark window \(windowId)")
                    }
                    guard runtimeAdapter.windowSetLayoutReason(handleId: handleId, reason: .standard) else {
                        throw Error.operationFailed("failed to set layout reason for benchmark window \(windowId)")
                    }
                }
                nextWindowSerial += max(1, workspace.windowCount)
            }

            return (primaryWorkspaceId, secondaryWorkspaceId)
        }

        @MainActor
        private static func seedWorkspaceProjections(
            workspaceManager: WorkspaceManager,
            engine: ZigNiriEngine,
            primaryWorkspaceId: WorkspaceDescriptor.ID,
            secondaryWorkspaceId: WorkspaceDescriptor.ID
        ) throws -> (
            primaryHandle: WindowHandle,
            alternatePrimaryHandle: WindowHandle,
            secondaryHandle: WindowHandle,
            removablePrimaryWindowKey: WindowModel.WindowKey
        ) {
            let primaryEntries = workspaceManager.entries(in: primaryWorkspaceId)
            let secondaryEntries = workspaceManager.entries(in: secondaryWorkspaceId)
            let primaryHandles = primaryEntries.map(\.handle)
            let secondaryHandles = secondaryEntries.map(\.handle)

            guard let primaryHandle = primaryHandles.first,
                  let alternatePrimaryHandle = primaryHandles.dropFirst().first,
                  let secondaryHandle = secondaryHandles.first,
                  let removablePrimaryEntry = primaryEntries.last else {
                throw Error.operationFailed("benchmark fixture expected windows in both workspaces")
            }

            _ = engine.syncWindows(primaryHandles, in: primaryWorkspaceId, selectedNodeId: nil, focusedHandle: primaryHandle)
            _ = engine.syncWindows(secondaryHandles, in: secondaryWorkspaceId, selectedNodeId: nil, focusedHandle: secondaryHandle)

            guard let primaryNodeId = engine.nodeId(for: primaryHandle),
                  let secondaryNodeId = engine.nodeId(for: secondaryHandle) else {
                throw Error.operationFailed("benchmark fixture failed to decode node ids")
            }

            _ = engine.syncWindows(
                primaryHandles,
                in: primaryWorkspaceId,
                selectedNodeId: primaryNodeId,
                focusedHandle: primaryHandle
            )
            _ = engine.syncWindows(
                secondaryHandles,
                in: secondaryWorkspaceId,
                selectedNodeId: secondaryNodeId,
                focusedHandle: secondaryHandle
            )

            guard engine.refreshWorkspaceProjection(primaryWorkspaceId),
                  engine.refreshWorkspaceProjection(secondaryWorkspaceId) else {
                throw Error.operationFailed("benchmark fixture failed to prime workspace projections")
            }

            return (
                primaryHandle,
                alternatePrimaryHandle,
                secondaryHandle,
                WindowModel.WindowKey(
                    pid: removablePrimaryEntry.handle.pid,
                    windowId: removablePrimaryEntry.windowId
                )
            )
        }

        private static func rawEnumValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
            UInt8(clamping: Int(value.rawValue))
        }
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func loadScenario(from url: URL) throws -> ControllerBoundaryScenario {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ControllerBoundaryScenario.self, from: data)
    }

    static func runScenario(_ scenario: ControllerBoundaryScenario) throws -> ControllerBoundaryBenchmarkReport {
        guard scenario.seed.workspaces.count >= 2 else {
            throw Error.invalidScenario("at least two workspaces are required")
        }
        guard !scenario.events.isEmpty else {
            throw Error.invalidScenario("events cannot be empty")
        }
        guard scenario.warmupIterations >= 0 else {
            throw Error.invalidScenario("warmupIterations cannot be negative")
        }
        guard scenario.measuredIterations > 0 else {
            throw Error.invalidScenario("measuredIterations must be greater than zero")
        }

        var samplesByPath: [ControllerBoundaryScenario.Event.Kind: [UInt64]] = Dictionary(
            uniqueKeysWithValues: ControllerBoundaryScenario.Event.Kind.allCases.map { ($0, []) }
        )

        for _ in 0 ..< scenario.warmupIterations {
            try replay(events: scenario.events, seed: scenario.seed, samplesByPath: &samplesByPath, collectSamples: false)
        }

        for hotPath in ControllerBoundaryScenario.Event.Kind.allCases {
            samplesByPath[hotPath]?.removeAll(keepingCapacity: true)
        }

        for _ in 0 ..< scenario.measuredIterations {
            try replay(events: scenario.events, seed: scenario.seed, samplesByPath: &samplesByPath, collectSamples: true)
        }

        let metrics = metricsByName(from: samplesByPath)
        let sampleCounts = OmniBenchmarkSupport.sampleCountsByName(from: metrics)
        let expectedSamples = expectedSamplesByPath(
            events: scenario.events,
            measuredIterations: scenario.measuredIterations
        )

        let report = ControllerBoundaryBenchmarkReport(
            schemaVersion: OmniBenchmarkSupport.reportSchemaVersion,
            scenarioName: scenario.name,
            generatedAt: OmniBenchmarkSupport.timestampNowISO8601(),
            warmupIterations: scenario.warmupIterations,
            measuredIterations: scenario.measuredIterations,
            sampleCounts: sampleCounts,
            expectedSamplesByPath: expectedSamples,
            metrics: metrics
        )

        try OmniBenchmarkSupport.writeReportIfRequested(
            report,
            pathEnvironmentKey: reportPathEnvironmentKey
        )
        return report
    }

    private static func replay(
        events: [ControllerBoundaryScenario.Event],
        seed: ControllerBoundaryScenario.Seed,
        samplesByPath: inout [ControllerBoundaryScenario.Event.Kind: [UInt64]],
        collectSamples: Bool
    ) throws {
        for event in events {
            let repetitions = max(1, event.count)
            for _ in 0 ..< repetitions {
                let fixture = try prepareFixture(for: event.kind, seed: seed)
                defer { fixture.cleanup() }
                if collectSamples {
                    let measurement = try OmniBenchmarkSupport.measure {
                        try execute(event: event.kind, fixture: fixture)
                    }
                    samplesByPath[event.kind, default: []].append(measurement.elapsedNanoseconds)
                } else {
                    try execute(event: event.kind, fixture: fixture)
                }
            }
        }
    }

    private static func prepareFixture(
        for event: ControllerBoundaryScenario.Event.Kind,
        seed: ControllerBoundaryScenario.Seed
    ) throws -> Fixture {
        let fixture = try Fixture(seed: seed)

        switch event {
        case .submitHotkey, .submitOsEvent, .workspaceSnapshotCopy:
            break
        case .tick:
            try fixture.submitLayoutAnimationHotkey()
        case .projectionRefresh:
            try fixture.submitAlternatePrimaryFocusChangedEvent()
        }

        return fixture
    }

    private static func execute(
        event: ControllerBoundaryScenario.Event.Kind,
        fixture: Fixture
    ) throws {
        switch event {
        case .submitHotkey:
            try fixture.submitProjectionChangingHotkey()

        case .submitOsEvent:
            try fixture.submitSecureInputChangedEvent()

        case .tick:
            try fixture.submitTick()

        case .workspaceSnapshotCopy:
            let export = try fixture.copyWorkspaceSnapshot()
            guard export.workspaces.count >= 2, export.windows.count >= 2 else {
                throw Error.operationFailed("workspace snapshot copy did not include the seeded runtime state")
            }

        case .projectionRefresh:
            let changedWorkspaceIds = try fixture.refreshProjectionFromCore(
                limitingTo: [fixture.primaryWorkspaceId]
            )
            guard changedWorkspaceIds == Set([fixture.primaryWorkspaceId]) else {
                throw Error.operationFailed("projection refresh did not isolate the changed workspace")
            }
            guard fixture.engine.workspaceView(for: fixture.primaryWorkspaceId) != nil,
                  fixture.engine.workspaceView(for: fixture.secondaryWorkspaceId) != nil else {
                throw Error.operationFailed("projection refresh failed to retain workspace views")
            }
            guard !fixture.engine.isWorkspaceProjectionDirty(fixture.primaryWorkspaceId),
                  !fixture.engine.isWorkspaceProjectionDirty(fixture.secondaryWorkspaceId) else {
                throw Error.operationFailed("projection refresh left workspace projections dirty")
            }
        }
    }

    private static func metricsByName(
        from samplesByPath: [ControllerBoundaryScenario.Event.Kind: [UInt64]]
    ) -> [String: ZigNiriLatencyStats] {
        var metrics: [String: ZigNiriLatencyStats] = [:]
        metrics.reserveCapacity(ControllerBoundaryScenario.Event.Kind.allCases.count)
        for hotPath in ControllerBoundaryScenario.Event.Kind.allCases {
            metrics[hotPath.rawValue] = ZigNiriLatencyStats.from(
                samplesNanoseconds: samplesByPath[hotPath] ?? []
            )
        }
        return metrics
    }

    private static func expectedSamplesByPath(
        events: [ControllerBoundaryScenario.Event],
        measuredIterations: Int
    ) -> [String: Int] {
        var perIteration: [ControllerBoundaryScenario.Event.Kind: Int] = Dictionary(
            uniqueKeysWithValues: ControllerBoundaryScenario.Event.Kind.allCases.map { ($0, 0) }
        )

        for event in events {
            perIteration[event.kind, default: 0] += max(1, event.count)
        }

        var expected: [String: Int] = [:]
        expected.reserveCapacity(ControllerBoundaryScenario.Event.Kind.allCases.count)
        for hotPath in ControllerBoundaryScenario.Event.Kind.allCases {
            expected[hotPath.rawValue] = (perIteration[hotPath] ?? 0) * measuredIterations
        }
        return expected
    }
}
