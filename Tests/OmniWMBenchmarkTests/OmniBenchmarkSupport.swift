import Dispatch
import Foundation

@testable import OmniWM

struct OmniBenchmarkReport: Codable {
    let schemaVersion: Int
    let scenarioName: String
    let generatedAt: String
    let warmupIterations: Int
    let measuredIterations: Int
    let sampleCounts: [String: Int]
    let expectedSamplesByPath: [String: Int]
    let metrics: [String: ZigNiriLatencyStats]
}

typealias ZigNiriRuntimeBenchmarkReport = OmniBenchmarkReport

enum OmniBenchmarkSupport {
    static let reportSchemaVersion = 1

    static func measure<T>(_ body: () throws -> T) rethrows -> (elapsedNanoseconds: UInt64, value: T) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        let end = DispatchTime.now().uptimeNanoseconds
        return (end &- start, value)
    }

    static func sampleCountsByName(from metrics: [String: ZigNiriLatencyStats]) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(metrics.count)
        for (key, stats) in metrics {
            counts[key] = stats.count
        }
        return counts
    }

    static func writeReportIfRequested(
        _ report: OmniBenchmarkReport,
        pathEnvironmentKey: String
    ) throws {
        guard let outputPath = ProcessInfo.processInfo.environment[pathEnvironmentKey],
              !outputPath.isEmpty else {
            return
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: outputURL, options: .atomic)
    }

    static func timestampNowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
