import Charts
import Foundation
import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct TemperatureHistoryChart: View {
    let samples: [ThermalSample]
    let unit: TempUnit
    let alertThresholdCelsius: Double?
    @State private var renderedSamples: [ThermalSample] = []

    private static let maximumRenderedSamples = 1_000

    var body: some View {
        let baselineCelsius = max(
            0,
            (renderedSamples.lazy.map(\.averageCelsius).min() ?? 20) - 5
        )
        Chart {
            ForEach(renderedSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    yStart: .value("Baseline", unit.convert(baselineCelsius)),
                    yEnd: .value("Hotspot", unit.convert(sample.hottestCelsius))
                )
                .foregroundStyle(.orange.opacity(0.08))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Hotspot", unit.convert(sample.hottestCelsius))
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Average", unit.convert(sample.averageCelsius))
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if let alertThresholdCelsius {
                RuleMark(y: .value("Alert", unit.convert(alertThresholdCelsius)))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Alert threshold")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
            }
        }
        .chartForegroundStyleScale([
            "Hotspot": Color.orange,
            "Average": Color.blue,
        ])
        .chartYAxisLabel(unit.symbol)
        .accessibilityLabel("Temperature history")
        .task(id: SampleRevision(samples)) {
            if samples.count <= Self.maximumRenderedSamples {
                renderedSamples = samples
                return
            }

            do {
                let reduced = try await AnalyticsEngine.shared.temperatureChartSamples(
                    samples,
                    maximumCount: Self.maximumRenderedSamples
                )
                renderedSamples = reduced
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}
