import AppKit
import Foundation
import UniformTypeIdentifiers

/// Export utility for chart data — filename generation, NSSavePanel, ISO 8601 formatting.
enum ChartExporter {
    enum ChartType: String, Sendable {
        case clusterThroughput = "ClusterThroughput"
        case pingLatency = "PingLatency"
        case topicThroughput = "TopicThroughput"
        case isrHealth = "ISRHealth"
        case consumerGroupLag = "ConsumerGroupLag"
        case topicLag = "TopicLag"
        case partitionLag = "PartitionLag"
        case consumerMemberLag = "ConsumerMemberLag"
    }

    // MARK: - Filename

    /// Generate filename: `Swifka_{Cluster}_{ChartType}_{Start}-{End}_{ExportTime}.xlsx`
    static func xlsxFilename(
        clusterName: String,
        chartType: ChartType,
        dataPoints: [Date],
    ) -> String {
        baseName(clusterName: clusterName, chartType: chartType, dataPoints: dataPoints) + ".xlsx"
    }

    private static func baseName(
        clusterName: String,
        chartType: ChartType,
        dataPoints: [Date],
    ) -> String {
        let sanitized = sanitizeFilename(clusterName)
        let now = compactTimestamp(Date())

        let rangeStr: String = if let earliest = dataPoints.min(), let latest = dataPoints.max() {
            "\(compactTimestamp(earliest))-\(compactTimestamp(latest))"
        } else {
            now
        }

        return "Swifka_\(sanitized)_\(chartType.rawValue)_\(rangeStr)_\(now)"
    }

    // MARK: - Save

    /// Present NSSavePanel and write an .xlsx file.
    static func saveXLSX(data: Data, defaultFilename: String) {
        let panel = NSSavePanel()
        if let xlsxType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsxType]
        }
        panel.nameFieldStringValue = defaultFilename
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showError(error)
        }
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Helpers

    /// ISO 8601 timestamp formatter with fractional seconds for export data.
    static func iso8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression,
        )
        return cleaned.replacingOccurrences(
            of: "-{2,}",
            with: "-",
            options: .regularExpression,
        )
    }

    /// Compact timestamp for filenames: `20260217T143000`
    private static func compactTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = .current
        return f.string(from: date)
    }
}
