import Foundation
import XCTest

@testable import OmniWM

@MainActor
final class ControllerBoundaryBenchmarkTests: XCTestCase {
    private static var cachedReport: ControllerBoundaryBenchmarkReport?
    private static var cachedScenario: ControllerBoundaryScenario?

    func testConfiguredControllerStagesProduceSamples() throws {
        try requireBenchmarkEnabled()
        let report = try benchmarkReport()
        let scenario = try loadScenario()

        for event in scenario.events {
            let stats = try XCTUnwrap(report.metrics[event.kind.rawValue])
            XCTAssertGreaterThan(stats.count, 0, "Expected non-zero samples for \(event.kind.rawValue)")
            XCTAssertEqual(
                report.sampleCounts[event.kind.rawValue],
                report.expectedSamplesByPath[event.kind.rawValue]
            )
        }
    }

    func testReplayReproducibilityForCountsAndSchema() throws {
        try requireBenchmarkEnabled()
        let scenario = try loadScenario()

        let first = try ControllerBoundaryBenchmarkHarness.runScenario(scenario)
        let second = try ControllerBoundaryBenchmarkHarness.runScenario(scenario)

        XCTAssertEqual(first.schemaVersion, OmniBenchmarkSupport.reportSchemaVersion)
        XCTAssertEqual(second.schemaVersion, OmniBenchmarkSupport.reportSchemaVersion)
        XCTAssertEqual(Set(first.metrics.keys), Set(second.metrics.keys))
        XCTAssertEqual(first.sampleCounts, second.sampleCounts)
        XCTAssertEqual(first.expectedSamplesByPath, second.expectedSamplesByPath)
    }

    func testReportIsWrittenWhenPathIsConfigured() throws {
        try requireBenchmarkEnabled()
        _ = try benchmarkReport()

        guard let path = ProcessInfo.processInfo.environment["OMNI_CONTROLLER_REPORT_PATH"],
              !path.isEmpty else {
            throw XCTSkip("OMNI_CONTROLLER_REPORT_PATH not set")
        }

        let reportURL = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(ControllerBoundaryBenchmarkReport.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, OmniBenchmarkSupport.reportSchemaVersion)
        XCTAssertEqual(decoded.scenarioName, try loadScenario().name)
    }

    func testScenarioFixtureDecodes() throws {
        let scenario = try loadScenario()

        XCTAssertGreaterThanOrEqual(scenario.seed.workspaces.count, 2)
        XCTAssertFalse(scenario.events.isEmpty)
    }

    private func benchmarkReport() throws -> ControllerBoundaryBenchmarkReport {
        if let cached = Self.cachedReport {
            return cached
        }

        let scenario = try loadScenario()
        let report = try ControllerBoundaryBenchmarkHarness.runScenario(scenario)
        Self.cachedScenario = scenario
        Self.cachedReport = report
        return report
    }

    private func loadScenario() throws -> ControllerBoundaryScenario {
        if let cached = Self.cachedScenario {
            return cached
        }

        guard let url = Bundle.module.url(forResource: "controller-replay", withExtension: "json") else {
            throw XCTSkip("Missing controller-replay.json fixture")
        }
        return try ControllerBoundaryBenchmarkHarness.loadScenario(from: url)
    }

    private func requireBenchmarkEnabled() throws {
        if !ControllerBoundaryBenchmarkHarness.isEnabled {
            throw XCTSkip("Set \(ControllerBoundaryBenchmarkHarness.environmentKey)=1 to run controller benchmark tests")
        }
    }
}
