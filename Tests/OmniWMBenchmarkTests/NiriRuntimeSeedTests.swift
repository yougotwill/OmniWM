import CZigLayout
import XCTest

@testable import OmniWM

@MainActor
final class NiriRuntimeSeedTests: XCTestCase {
    func testSeedRuntimeStateAcceptsWorkspaceWithEmptyColumn() throws {
        let workspace = WorkspaceDescriptor(name: "seed-empty")
        let engine = NiriLayoutEngine()
        _ = engine.ensureRoot(for: workspace.id)

        let snapshot = NiriStateZigKernel.makeSnapshot(columns: engine.columns(in: workspace.id))
        XCTAssertEqual(snapshot.columns.count, 1)
        XCTAssertEqual(snapshot.windows.count, 0)

        let context = try XCTUnwrap(engine.ensureLayoutContext(for: workspace.id))
        let rc = NiriStateZigKernel.seedRuntimeState(
            context: context,
            snapshot: snapshot
        )

        XCTAssertEqual(rc, Int32(OMNI_OK))
    }

    func testSeedRuntimeStateAcceptsCompletelyEmptyExport() throws {
        let context = try XCTUnwrap(NiriLayoutZigKernel.LayoutContext())
        let emptyExport = NiriStateZigKernel.RuntimeStateExport(columns: [], windows: [])

        let rc = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: emptyExport
        )

        XCTAssertEqual(rc, Int32(OMNI_OK))
    }
}
