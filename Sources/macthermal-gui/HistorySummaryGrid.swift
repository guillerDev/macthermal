import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct HistorySummaryGrid: View {
    let samples: [ThermalSample]
    let unit: TempUnit

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: DesignMetrics.standardSpacing)]

    var body: some View {
        let summary = ThermalSummary(samples: samples)
        LazyVGrid(columns: columns, spacing: DesignMetrics.standardSpacing) {
            MetricCard(
                title: "Average hotspot",
                value: unit.format(summary.averageHotspotCelsius),
                detail: "Across \(summary.sampleCount) samples",
                systemImage: "thermometer.medium",
                tint: tempLevel(summary.averageHotspotCelsius).severity.color
            )
            MetricCard(
                title: "Peak hotspot",
                value: unit.format(summary.peakHotspotCelsius),
                detail: "Highest recorded value",
                systemImage: "thermometer.high",
                tint: tempLevel(summary.peakHotspotCelsius).severity.color
            )
            MetricCard(
                title: "Average fan load",
                value: "\(summary.averageFanUtilization.formatted(.number.precision(.fractionLength(0))))%",
                detail: "Average across reported fans",
                systemImage: "fan",
                tint: fanLevel(summary.averageFanUtilization).severity.color
            )
            MetricCard(
                title: "Thermal pressure",
                value: "\(summary.pressureSampleCount)",
                detail: "Serious or critical samples",
                systemImage: "gauge.with.dots.needle.67percent",
                tint: summary.pressureSampleCount > 0 ? .orange : .green
            )
        }
    }
}
