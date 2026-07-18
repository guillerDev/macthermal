import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct IncidentContributorsView: View {
    let samples: [ThermalSample]
    @State private var correlations: [ProcessCorrelation] = []

    var body: some View {
        GroupBox("Likely contributors") {
            if correlations.isEmpty {
                Text("No process had enough observations for a useful correlation.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: DesignMetrics.standardSpacing) {
                    ForEach(correlations.prefix(5)) { item in
                        LabeledContent {
                            Text(item.coefficient, format: .number.precision(.fractionLength(2)))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.processName)
                                Text("Average CPU \(item.averageCPUPercent.formatted(.number.precision(.fractionLength(1))))%")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, DesignMetrics.compactSpacing)
            }
        }
        .task(id: samples.count) {
            let result = await AnalyticsEngine.shared.processCorrelations(samples)
            guard !Task.isCancelled else { return }
            correlations = result
        }
    }
}
