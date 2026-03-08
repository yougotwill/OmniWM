import Foundation
import XCTest

@testable import OmniWM

@MainActor
final class ZigNiriRuntimeBenchmarkTests: XCTestCase {
    private static var cachedReport: ZigNiriRuntimeBenchmarkReport?
    private static var cachedScenario: ZigNiriRuntimeScenario?

    func testConfiguredRuntimeStagesProduceSamples() throws {
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

        let first = try ZigNiriRuntimeBenchmarkHarness.runScenario(scenario)
        let second = try ZigNiriRuntimeBenchmarkHarness.runScenario(scenario)

        XCTAssertEqual(first.schemaVersion, OmniBenchmarkSupport.reportSchemaVersion)
        XCTAssertEqual(second.schemaVersion, OmniBenchmarkSupport.reportSchemaVersion)
        XCTAssertEqual(Set(first.metrics.keys), Set(second.metrics.keys))
        XCTAssertEqual(first.sampleCounts, second.sampleCounts)
        XCTAssertEqual(first.expectedSamplesByPath, second.expectedSamplesByPath)
    }

    func testReportIsWrittenWhenPathIsConfigured() throws {
        try requireBenchmarkEnabled()
        _ = try benchmarkReport()

        guard let path = ProcessInfo.processInfo.environment["OMNI_RUNTIME_REPORT_PATH"],
              !path.isEmpty else {
            throw XCTSkip("OMNI_RUNTIME_REPORT_PATH not set")
        }

        let reportURL = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(ZigNiriRuntimeBenchmarkReport.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, OmniBenchmarkSupport.reportSchemaVersion)
        XCTAssertEqual(decoded.scenarioName, try loadScenario().name)
    }

    func testScenarioFixtureDecodes() throws {
        let scenario = try loadScenario()

        XCTAssertGreaterThanOrEqual(scenario.seed.workspaces.count, 2)
        XCTAssertFalse(scenario.events.isEmpty)
    }

    private func benchmarkReport() throws -> ZigNiriRuntimeBenchmarkReport {
        if let cached = Self.cachedReport {
            return cached
        }

        let scenario = try loadScenario()
        let report = try ZigNiriRuntimeBenchmarkHarness.runScenario(scenario)
        Self.cachedScenario = scenario
        Self.cachedReport = report
        return report
    }

    private func loadScenario() throws -> ZigNiriRuntimeScenario {
        if let cached = Self.cachedScenario {
            return cached
        }

        guard let url = Bundle.module.url(forResource: "runtime-replay", withExtension: "json") else {
            throw XCTSkip("Missing runtime-replay.json fixture")
        }
        return try ZigNiriRuntimeBenchmarkHarness.loadScenario(from: url)
    }

    private func requireBenchmarkEnabled() throws {
        if !ZigNiriRuntimeBenchmarkHarness.isEnabled {
            throw XCTSkip("Set \(ZigNiriRuntimeBenchmarkHarness.environmentKey)=1 to run runtime benchmark tests")
        }
    }
}
