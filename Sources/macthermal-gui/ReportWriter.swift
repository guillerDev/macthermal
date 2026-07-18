import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

actor ReportWriter {
    static let shared = ReportWriter()

    func writeHTML(
        title: String,
        samples: [ThermalSample],
        context: DiagnosticContext,
        to url: URL
    ) throws {
        try DiagnosticReportRenderer.html(title: title, samples: samples, context: context)
            .write(to: url, atomically: true, encoding: .utf8)
    }

    func writeCSV(samples: [ThermalSample], to url: URL) throws {
        try DiagnosticReportRenderer.csv(samples: samples)
            .write(to: url, atomically: true, encoding: .utf8)
    }
}
