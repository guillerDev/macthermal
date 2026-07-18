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
    @Binding var scope: TemperatureChartScope
    @State private var renderedSamples: [ThermalSample] = []
    @State private var availableScopes: [TemperatureChartScope] = [.overall]

    private static let maximumRenderedSamples = 1_000

    var body: some View {
        let selectedScope = availableScopes.contains(scope) ? scope : .overall
        let scopeSelection = Binding(
            get: { availableScopes.contains(scope) ? scope : .overall },
            set: { scope = $0 }
        )
        let hotspotValues = renderedSamples.compactMap { selectedScope.hotspot(in: $0) }
        let averageValues = renderedSamples.compactMap { selectedScope.average(in: $0) }
        let baselineCelsius = max(
            0,
            (averageValues.min() ?? hotspotValues.min() ?? 20) - 5
        )
        let seriesDomain = averageValues.isEmpty
            ? ["Hotspot"]
            : ["Hotspot", "Average"]

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Component")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Component", selection: scopeSelection) {
                    ForEach(availableScopes) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
            }

            Chart {
                ForEach(renderedSamples) { sample in
                    if let hotspot = selectedScope.hotspot(in: sample) {
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            yStart: .value("Baseline", unit.convert(baselineCelsius)),
                            yEnd: .value("Hotspot", unit.convert(hotspot))
                        )
                        .foregroundStyle(.orange.opacity(0.08))

                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Hotspot", unit.convert(hotspot)),
                            series: .value("Series", "Hotspot")
                        )
                        .foregroundStyle(by: .value("Series", "Hotspot"))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }

                    if let average = selectedScope.average(in: sample) {
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Average", unit.convert(average)),
                            series: .value("Series", "Average")
                        )
                        .foregroundStyle(by: .value("Series", "Average"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .interpolationMethod(.catmullRom)
                    }
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
            .chartForegroundStyleScale(domain: seriesDomain) { series in
                series == "Average" ? Color.blue : Color.orange
            }
            .chartYAxisLabel(unit.symbol)
            .accessibilityLabel("Temperature history, \(selectedScope.title)")
        }
        .task(id: SampleRevision(samples)) {
            let nextSamples: [ThermalSample]

            if samples.count <= Self.maximumRenderedSamples {
                nextSamples = samples
            } else {
                do {
                    nextSamples = try await AnalyticsEngine.shared.temperatureChartSamples(
                        samples,
                        maximumCount: Self.maximumRenderedSamples
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }

            renderedSamples = nextSamples
            availableScopes = TemperatureChartScope.available(in: nextSamples)
        }
    }
}
