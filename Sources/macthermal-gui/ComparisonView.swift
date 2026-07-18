import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var range: HistoryRange = .oneHour
    @State private var comparison: ThermalComparison?

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: DesignMetrics.standardSpacing)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Period", selection: $range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Text("Current period vs previous period")
                    .foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            if let comparison,
               comparison.baseline.sampleCount > 0,
               comparison.current.sampleCount > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignMetrics.sectionSpacing) {
                        LazyVGrid(columns: columns, spacing: DesignMetrics.standardSpacing) {
                            ComparisonMetricCard(
                                title: "Average hotspot",
                                baseline: settings.unit.format(comparison.baseline.averageHotspotCelsius),
                                current: settings.unit.format(comparison.current.averageHotspotCelsius),
                                delta: temperatureDelta(comparison.hotspotDeltaCelsius),
                                improved: comparison.hotspotDeltaCelsius <= 0,
                                systemImage: "thermometer.medium"
                            )
                            ComparisonMetricCard(
                                title: "Peak hotspot",
                                baseline: settings.unit.format(comparison.baseline.peakHotspotCelsius),
                                current: settings.unit.format(comparison.current.peakHotspotCelsius),
                                delta: temperatureDelta(comparison.peakDeltaCelsius),
                                improved: comparison.peakDeltaCelsius <= 0,
                                systemImage: "thermometer.high"
                            )
                            ComparisonMetricCard(
                                title: "Average fan load",
                                baseline: percent(comparison.baseline.averageFanUtilization),
                                current: percent(comparison.current.averageFanUtilization),
                                delta: signedPercent(comparison.fanDeltaPercent),
                                improved: comparison.fanDeltaPercent <= 0,
                                systemImage: "fan"
                            )
                            ComparisonMetricCard(
                                title: "Thermal pressure",
                                baseline: String(comparison.baseline.pressureSampleCount),
                                current: String(comparison.current.pressureSampleCount),
                                delta: signedCount(comparison.current.pressureSampleCount - comparison.baseline.pressureSampleCount),
                                improved: comparison.current.pressureSampleCount <= comparison.baseline.pressureSampleCount,
                                systemImage: "gauge.with.dots.needle.67percent"
                            )
                        }
                        ComparisonInterpretationView(comparison: comparison)
                    }
                    .padding()
                }
            } else {
                EmptyStateView(
                    title: "Two periods are required",
                    message: "Keep MacThermal running long enough to collect both a current and a previous \(range.title) period.",
                    systemImage: "arrow.left.arrow.right"
                )
            }
        }
        .navigationTitle("Before & After")
        .task(id: range) { await updateComparison() }
        .task(id: archive.history.count) { await updateComparison() }
    }

    private func updateComparison() async {
        let currentEnd = Date.now
        let result = await AnalyticsEngine.shared.comparison(
            samples: archive.history,
            currentEnd: currentEnd,
            duration: range.duration
        )
        guard !Task.isCancelled else { return }
        comparison = result
    }

    private func temperatureDelta(_ value: Double) -> String {
        let convertedDelta = settings.unit == .celsius ? value : value * 9 / 5
        return "\(convertedDelta >= 0 ? "+" : "")\(convertedDelta.formatted(.number.precision(.fractionLength(1))))\(settings.unit.symbol)"
    }

    private func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func signedPercent(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func signedCount(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : String(value)
    }
}
