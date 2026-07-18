import Foundation
import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonPeriodSummaryView: View {
    let title: String
    let systemImage: String
    let start: Date
    let end: Date
    let coverage: ThermalPeriodCoverage

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
                Text(dateRange)
                    .font(.headline)
                Text("\(coveragePercent)% coverage · \(sampleLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignMetrics.compactSpacing)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityElement(children: .combine)
    }

    private var coveragePercent: Int {
        Int((coverage.fraction * 100).rounded())
    }

    private var sampleLabel: String {
        "\(coverage.sampleCount.formatted()) \(coverage.sampleCount == 1 ? "sample" : "samples")"
    }

    private var dateRange: String {
        let formatter = DateIntervalFormatter()
        formatter.locale = .autoupdatingCurrent
        if end.timeIntervalSince(start) >= 2 * 24 * 60 * 60 {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: start, to: end)
    }
}
