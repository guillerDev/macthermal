import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ContributorsView: View {
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var range: HistoryRange = .oneHour
    @State private var correlations: [ProcessCorrelation] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
            }
            .padding()
            Divider()

            if correlations.isEmpty {
                EmptyStateView(
                    title: "Not enough process evidence",
                    message: "Keep MacThermal running while the Mac heats up. At least three observations of a process are required.",
                    systemImage: "bolt.horizontal.circle"
                )
            } else {
                VStack(alignment: .leading, spacing: DesignMetrics.sectionSpacing) {
                    ContributorExplanationView()
                    ContributorsChart(correlations: Array(correlations.prefix(8)))
                        .frame(minHeight: 230)
                    ContributorsTable(correlations: correlations)
                }
                .padding()
            }
        }
        .navigationTitle("Likely Contributors")
        .task(id: analysisRevision) { await updateCorrelations() }
    }

    private func updateCorrelations() async {
        do {
            let cutoff = Date.now.addingTimeInterval(-range.duration)
            let samples = try await AnalyticsEngine.shared.recentSamples(archive.history, since: cutoff)
            correlations = try await AnalyticsEngine.shared.processCorrelations(samples)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private var analysisRevision: RangedHistoryRevision {
        RangedHistoryRevision(range: range, samples: SampleRevision(archive.history))
    }
}
