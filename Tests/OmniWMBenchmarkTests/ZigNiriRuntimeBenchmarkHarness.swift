import Foundation

@testable import OmniWM

struct ZigNiriRuntimeScenario: Codable {
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
            case seedRuntimeState
            case navigationTxn
            case windowMutationTxn
            case workspaceTxn
            case lifecycleAddWindow
            case lifecycleRemoveWindow
            case runtimeSnapshot
            case runtimeRender
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

@MainActor
enum ZigNiriRuntimeBenchmarkHarness {
    static let environmentKey = "OMNI_RUNTIME_BENCH"

    private static let reportPathEnvironmentKey = "OMNI_RUNTIME_REPORT_PATH"

    enum Error: Swift.Error, CustomStringConvertible {
        case invalidScenario(String)
        case missingWindow(String)
        case operationFailed(String)

        var description: String {
            switch self {
            case let .invalidScenario(message):
                return "Invalid scenario: \(message)"
            case let .missingWindow(message):
                return "Missing window: \(message)"
            case let .operationFailed(message):
                return "Operation failed: \(message)"
            }
        }
    }

    private struct Fixture {
        let engine: ZigNiriEngine
        let monitorFrame: CGRect
        let workingArea: ZigNiriWorkingAreaContext
        let gaps: ZigNiriGaps
        let primaryWorkspaceId: WorkspaceDescriptor.ID
        let secondaryWorkspaceId: WorkspaceDescriptor.ID
        let primaryHandles: [WindowHandle]
        let secondaryHandles: [WindowHandle]
        let trackedHandle: WindowHandle
        let removableHandle: WindowHandle
        let pendingAddHandle: WindowHandle
        let trackedNodeId: NodeId
        let navigationNodeId: NodeId
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func loadScenario(from url: URL) throws -> ZigNiriRuntimeScenario {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ZigNiriRuntimeScenario.self, from: data)
    }

    static func runScenario(_ scenario: ZigNiriRuntimeScenario) throws -> ZigNiriRuntimeBenchmarkReport {
        guard scenario.workspacesCount >= 2 else {
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

        var samplesByPath: [ZigNiriRuntimeScenario.Event.Kind: [UInt64]] = Dictionary(
            uniqueKeysWithValues: ZigNiriRuntimeScenario.Event.Kind.allCases.map { ($0, []) }
        )

        for _ in 0 ..< scenario.warmupIterations {
            try replay(events: scenario.events, seed: scenario.seed, samplesByPath: &samplesByPath, collectSamples: false)
        }

        for hotPath in ZigNiriRuntimeScenario.Event.Kind.allCases {
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

        let report = ZigNiriRuntimeBenchmarkReport(
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
        events: [ZigNiriRuntimeScenario.Event],
        seed: ZigNiriRuntimeScenario.Seed,
        samplesByPath: inout [ZigNiriRuntimeScenario.Event.Kind: [UInt64]],
        collectSamples: Bool
    ) throws {
        for event in events {
            let repetitions = max(1, event.count)
            for _ in 0 ..< repetitions {
                var fixture = try prepareFixture(for: event.kind, seed: seed)
                if collectSamples {
                    let measurement = try OmniBenchmarkSupport.measure {
                        try execute(event: event.kind, fixture: &fixture)
                    }
                    samplesByPath[event.kind, default: []].append(measurement.elapsedNanoseconds)
                } else {
                    try execute(event: event.kind, fixture: &fixture)
                }
            }
        }
    }

    private static func prepareFixture(
        for event: ZigNiriRuntimeScenario.Event.Kind,
        seed: ZigNiriRuntimeScenario.Seed
    ) throws -> Fixture {
        let fixture = try makeFixture(seed: seed)

        switch event {
        case .seedRuntimeState:
            break
        case .navigationTxn,
             .windowMutationTxn,
             .lifecycleAddWindow,
             .lifecycleRemoveWindow,
             .runtimeSnapshot,
             .runtimeRender:
            seedRuntime(for: fixture.primaryWorkspaceId, handles: fixture.primaryHandles, fixture: fixture)
            seedRuntime(for: fixture.secondaryWorkspaceId, handles: fixture.secondaryHandles, fixture: fixture)
        case .workspaceTxn:
            seedRuntime(for: fixture.primaryWorkspaceId, handles: fixture.primaryHandles, fixture: fixture)
            seedRuntime(for: fixture.secondaryWorkspaceId, handles: fixture.secondaryHandles, fixture: fixture)
        }

        return fixture
    }

    private static func seedRuntime(
        for workspaceId: WorkspaceDescriptor.ID,
        handles: [WindowHandle],
        fixture: Fixture
    ) {
        let selectedNodeId = workspaceId == fixture.primaryWorkspaceId ? fixture.trackedNodeId : fixture.engine.nodeId(for: fixture.secondaryHandles[0])
        let focusedHandle = workspaceId == fixture.primaryWorkspaceId ? fixture.trackedHandle : fixture.secondaryHandles[0]
        _ = fixture.engine.syncWindows(
            handles,
            in: workspaceId,
            selectedNodeId: selectedNodeId,
            focusedHandle: focusedHandle
        )
    }

    private static func execute(
        event: ZigNiriRuntimeScenario.Event.Kind,
        fixture: inout Fixture
    ) throws {
        switch event {
        case .seedRuntimeState:
            seedRuntime(for: fixture.primaryWorkspaceId, handles: fixture.primaryHandles, fixture: fixture)
            seedRuntime(for: fixture.secondaryWorkspaceId, handles: fixture.secondaryHandles, fixture: fixture)

        case .navigationTxn:
            let applied = fixture.engine.setSelectedNodeId(
                fixture.navigationNodeId,
                in: fixture.primaryWorkspaceId,
                focusedWindowId: fixture.navigationNodeId
            )
            guard applied else {
                throw Error.operationFailed("navigation request did not apply")
            }

        case .windowMutationTxn:
            let result = fixture.engine.applyMutation(
                .moveWindow(
                    windowId: fixture.trackedNodeId,
                    direction: .right,
                    orientation: .horizontal
                ),
                in: fixture.primaryWorkspaceId
            )
            guard result.applied else {
                throw Error.operationFailed("moveWindow mutation did not apply")
            }

        case .workspaceTxn:
            let result = fixture.engine.applyWorkspace(
                .moveWindow(
                    windowId: fixture.trackedNodeId,
                    targetWorkspaceId: fixture.secondaryWorkspaceId
                ),
                in: fixture.primaryWorkspaceId
            )
            guard result.applied else {
                throw Error.operationFailed("workspace move did not apply")
            }

        case .lifecycleAddWindow:
            let updatedHandles = fixture.primaryHandles + [fixture.pendingAddHandle]
            _ = fixture.engine.syncWindows(
                updatedHandles,
                in: fixture.primaryWorkspaceId,
                selectedNodeId: fixture.trackedNodeId,
                focusedHandle: fixture.trackedHandle
            )
            guard fixture.engine.nodeId(for: fixture.pendingAddHandle) != nil else {
                throw Error.operationFailed("pending add handle was not projected into the workspace")
            }

        case .lifecycleRemoveWindow:
            let remainingHandles = fixture.primaryHandles.filter { $0 != fixture.removableHandle }
            _ = fixture.engine.syncWindows(
                remainingHandles,
                in: fixture.primaryWorkspaceId,
                selectedNodeId: fixture.trackedNodeId,
                focusedHandle: fixture.trackedHandle
            )
            guard fixture.engine.nodeId(for: fixture.removableHandle) == nil else {
                throw Error.operationFailed("removable handle still exists after syncWindows removal")
            }

        case .runtimeSnapshot:
            guard let snapshot = fixture.engine.benchmarkRuntimeSnapshot(workspaceId: fixture.primaryWorkspaceId) else {
                throw Error.operationFailed("runtime snapshot returned nil")
            }
            guard !snapshot.windows.isEmpty else {
                throw Error.operationFailed("runtime snapshot produced no windows")
            }

        case .runtimeRender:
            let rendered = fixture.engine.calculateLayout(
                ZigNiriLayoutRequest(
                    workspaceId: fixture.primaryWorkspaceId,
                    monitorFrame: fixture.monitorFrame,
                    screenFrame: nil,
                    gaps: fixture.gaps,
                    scale: fixture.workingArea.scale,
                    workingArea: fixture.workingArea,
                    orientation: .horizontal,
                    viewportOffset: 0
                )
            )
            guard !rendered.frames.isEmpty else {
                throw Error.operationFailed("runtime render produced no frames")
            }
        }
    }

    private static func makeFixture(seed: ZigNiriRuntimeScenario.Seed) throws -> Fixture {
        let monitorFrame = CGRect(
            x: 0,
            y: 0,
            width: seed.monitor.width,
            height: seed.monitor.height
        )
        let visibleFrame = CGRect(
            x: monitorFrame.minX + seed.monitor.visibleInsets.left,
            y: monitorFrame.minY + seed.monitor.visibleInsets.bottom,
            width: max(1, monitorFrame.width - seed.monitor.visibleInsets.left - seed.monitor.visibleInsets.right),
            height: max(1, monitorFrame.height - seed.monitor.visibleInsets.top - seed.monitor.visibleInsets.bottom)
        )

        let engine = ZigNiriEngine(
            maxWindowsPerColumn: seed.maxWindowsPerColumn,
            maxVisibleColumns: seed.maxVisibleColumns,
            infiniteLoop: false
        )

        let primaryWorkspace = WorkspaceDescriptor(name: seed.workspaces[0].name)
        let secondaryWorkspace = WorkspaceDescriptor(name: seed.workspaces[1].name)

        let primaryHandles = makeWindowHandles(count: max(3, seed.workspaces[0].windowCount))
        let secondaryHandles = makeWindowHandles(count: max(1, seed.workspaces[1].windowCount))
        let pendingAddHandle = makeWindowHandles(count: 1)[0]

        _ = engine.syncWindows(
            primaryHandles,
            in: primaryWorkspace.id,
            selectedNodeId: nil,
            focusedHandle: primaryHandles.first
        )
        _ = engine.syncWindows(
            secondaryHandles,
            in: secondaryWorkspace.id,
            selectedNodeId: nil,
            focusedHandle: secondaryHandles.first
        )

        guard let trackedHandle = primaryHandles.first,
              let removableHandle = primaryHandles.last,
              let trackedNodeId = engine.nodeId(for: trackedHandle),
              let navigationHandle = primaryHandles.dropFirst().first,
              let navigationNodeId = engine.nodeId(for: navigationHandle) else {
            throw Error.missingWindow("primary workspace has no tracked node")
        }

        _ = engine.syncWindows(
            primaryHandles,
            in: primaryWorkspace.id,
            selectedNodeId: trackedNodeId,
            focusedHandle: trackedHandle
        )
        if let secondaryHandle = secondaryHandles.first,
           let secondaryNodeId = engine.nodeId(for: secondaryHandle) {
            _ = engine.syncWindows(
                secondaryHandles,
                in: secondaryWorkspace.id,
                selectedNodeId: secondaryNodeId,
                focusedHandle: secondaryHandle
            )
        }

        let workingArea = ZigNiriWorkingAreaContext(
            workingFrame: visibleFrame,
            viewFrame: monitorFrame,
            scale: CGFloat(seed.scale)
        )
        let gaps = ZigNiriGaps(horizontal: CGFloat(seed.gap), vertical: CGFloat(seed.gap))

        return Fixture(
            engine: engine,
            monitorFrame: monitorFrame,
            workingArea: workingArea,
            gaps: gaps,
            primaryWorkspaceId: primaryWorkspace.id,
            secondaryWorkspaceId: secondaryWorkspace.id,
            primaryHandles: primaryHandles,
            secondaryHandles: secondaryHandles,
            trackedHandle: trackedHandle,
            removableHandle: removableHandle,
            pendingAddHandle: pendingAddHandle,
            trackedNodeId: trackedNodeId,
            navigationNodeId: navigationNodeId
        )
    }

    private static func makeWindowHandles(count: Int) -> [WindowHandle] {
        let pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        return (0 ..< count).map { _ in
            WindowHandle(id: UUID(), pid: pid)
        }
    }

    private static func metricsByName(
        from samplesByPath: [ZigNiriRuntimeScenario.Event.Kind: [UInt64]]
    ) -> [String: ZigNiriLatencyStats] {
        var metrics: [String: ZigNiriLatencyStats] = [:]
        metrics.reserveCapacity(ZigNiriRuntimeScenario.Event.Kind.allCases.count)
        for hotPath in ZigNiriRuntimeScenario.Event.Kind.allCases {
            metrics[hotPath.rawValue] = ZigNiriLatencyStats.from(
                samplesNanoseconds: samplesByPath[hotPath] ?? []
            )
        }
        return metrics
    }

    private static func expectedSamplesByPath(
        events: [ZigNiriRuntimeScenario.Event],
        measuredIterations: Int
    ) -> [String: Int] {
        var perIteration: [ZigNiriRuntimeScenario.Event.Kind: Int] = Dictionary(
            uniqueKeysWithValues: ZigNiriRuntimeScenario.Event.Kind.allCases.map { ($0, 0) }
        )

        for event in events {
            perIteration[event.kind, default: 0] += max(1, event.count)
        }

        var expected: [String: Int] = [:]
        expected.reserveCapacity(ZigNiriRuntimeScenario.Event.Kind.allCases.count)
        for hotPath in ZigNiriRuntimeScenario.Event.Kind.allCases {
            expected[hotPath.rawValue] = (perIteration[hotPath] ?? 0) * measuredIterations
        }
        return expected
    }
}

private extension ZigNiriRuntimeScenario {
    var workspacesCount: Int {
        seed.workspaces.count
    }
}
