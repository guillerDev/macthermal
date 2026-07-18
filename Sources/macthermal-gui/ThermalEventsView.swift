import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ThermalEventsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var range: HistoryRange = .twentyFourHours
    @State private var events: [ThermalEvent] = []

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
                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            if events.isEmpty {
                EmptyStateView(
                    title: "No thermal events in this range",
                    message: "Threshold crossings and macOS thermal-pressure transitions will appear here automatically.",
                    systemImage: "waveform.path.ecg"
                )
            } else {
                List(events) { event in
                    ThermalEventRow(event: event, unit: settings.unit)
                }
            }
        }
        .navigationTitle("Thermal Timeline")
        .task(id: range) { await updateEvents() }
        .task(id: archive.history.count) { await updateEvents() }
        .task(id: settings.alertThresholdCelsius) { await updateEvents() }
    }

    private func updateEvents() async {
        let cutoff = Date.now.addingTimeInterval(-range.duration)
        let samples = await AnalyticsEngine.shared.recentSamples(archive.history, since: cutoff)
        guard !Task.isCancelled else { return }
        let result = await AnalyticsEngine.shared.events(
            samples,
            thresholdCelsius: settings.alertThresholdCelsius
        )
        guard !Task.isCancelled else { return }
        events = result
    }
}
