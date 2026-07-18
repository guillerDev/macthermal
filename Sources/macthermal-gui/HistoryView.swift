import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct HistoryView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var range: HistoryRange = .oneHour
    @State private var displayedSamples: [ThermalSample] = []

    var body: some View {
        VStack(spacing: 0) {
            HistoryControls(range: $range, samples: displayedSamples)
                .padding()
            Divider()

            if displayedSamples.isEmpty {
                EmptyStateView(
                    title: "No samples in this range",
                    message: "MacThermal records locally while it is running. Choose a longer range or leave it open to collect history.",
                    systemImage: "chart.xyaxis.line"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignMetrics.sectionSpacing) {
                        TemperatureHistoryChart(
                            samples: displayedSamples,
                            unit: settings.unit,
                            alertThresholdCelsius: settings.alertsEnabled ? settings.alertThresholdCelsius : nil
                        )
                        .frame(minHeight: 320)

                        HistorySummaryGrid(samples: displayedSamples, unit: settings.unit)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("History")
        .task(id: range) { await updateSamples() }
        .task(id: archive.history.count) { await updateSamples() }
    }

    private func updateSamples() async {
        let cutoff = Date.now.addingTimeInterval(-range.duration)
        let samples = await AnalyticsEngine.shared.recentSamples(archive.history, since: cutoff)
        guard !Task.isCancelled else { return }
        displayedSamples = samples
    }
}
