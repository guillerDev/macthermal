import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct IncidentContributorsView: View {
    let samples: [ThermalSample]
    @State private var contributors: [HeatContributor] = []

    var body: some View {
        GroupBox("Likely contributors") {
            if contributors.isEmpty {
                Text("Not enough process samples during hot periods to attribute the heat.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: DesignMetrics.standardSpacing) {
                    ForEach(contributors.prefix(5)) { item in
                        LabeledContent {
                            Text("\(item.hotAverageCPUPercent.formatted(.number.precision(.fractionLength(1))))%")
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.processName)
                                Text(item.pattern.label)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, DesignMetrics.compactSpacing)
            }
        }
        .task(id: SampleRevision(samples)) {
            do {
                contributors = try await AnalyticsEngine.shared.heatContributors(samples)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}
