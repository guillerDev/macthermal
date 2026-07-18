import AppKit
import UniformTypeIdentifiers
#if canImport(MacThermalCore)
import MacThermalCore
#endif

@MainActor
enum ReportExporter {
    static func exportHTML(title: String, samples: [ThermalSample]) async throws {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostic Report"
        panel.nameFieldStringValue = sanitizedFilename(title) + ".html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try await ReportWriter.shared.writeHTML(
            title: title,
            samples: samples,
            context: SystemProfileProvider.current(),
            to: url
        )
    }

    static func exportCSV(title: String, samples: [ThermalSample]) async throws {
        let panel = NSSavePanel()
        panel.title = "Export Thermal Samples"
        panel.nameFieldStringValue = sanitizedFilename(title) + ".csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try await ReportWriter.shared.writeCSV(samples: samples, to: url)
    }

    private static func sanitizedFilename(_ value: String) -> String {
        value
            .replacing("/", with: "-")
            .replacing(":", with: "-")
    }
}
