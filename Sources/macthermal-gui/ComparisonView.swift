import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var range: HistoryRange = .oneHour
    @State private var analysis: ComparisonAnalysis?

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: DesignMetrics.standardSpacing)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Period", selection: $range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                            .disabled(!range.supportsComparison(retentionDays: settings.retentionDays))
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Text(coverageLabel)
                    .foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            if let analysis, analysis.isReliable {
                let comparison = analysis.comparison
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
                                title: "Thermal pressure rate",
                                baseline: percent(comparison.baseline.pressureFraction * 100),
                                current: percent(comparison.current.pressureFraction * 100),
                                delta: signedPercent(comparison.pressureFractionDelta * 100),
                                improved: comparison.pressureFractionDelta <= 0,
                                systemImage: "gauge.with.dots.needle.67percent"
                            )
                        }
                        ComparisonInterpretationView(comparison: comparison)
                    }
                    .padding()
                }
            } else {
                EmptyStateView(
                    title: emptyStateTitle,
                    message: emptyStateMessage,
                    systemImage: "arrow.left.arrow.right"
                )
            }
        }
        .navigationTitle("Before & After")
        .task(id: analysisRevision) { await updateComparison() }
    }

    private func updateComparison() async {
        guard range.supportsComparison(retentionDays: settings.retentionDays) else {
            analysis = nil
            return
        }
        do {
            analysis = try await AnalyticsEngine.shared.comparison(
                samples: archive.history,
                currentEnd: .now,
                duration: range.duration,
                expectedInterval: settings.historyInterval
            )
        } catch is CancellationError {
            return
        } catch {
            return
        }
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

    private var analysisRevision: ComparisonAnalysisRevision {
        ComparisonAnalysisRevision(
            range: range,
            samples: SampleRevision(archive.history),
            historyInterval: settings.historyInterval,
            retentionDays: settings.retentionDays
        )
    }

    private var coverageLabel: String {
        guard let analysis else { return "Current period vs previous period" }
        let previous = Int((analysis.baselineCoverage.fraction * 100).rounded())
        let current = Int((analysis.currentCoverage.fraction * 100).rounded())
        return "Coverage: previous \(previous)% · current \(current)%"
    }

    private var emptyStateTitle: String {
        range.supportsComparison(retentionDays: settings.retentionDays)
            ? "Complete periods are required"
            : "Retention is too short"
    }

    private var emptyStateMessage: String {
        if !range.supportsComparison(retentionDays: settings.retentionDays) {
            return "A \(range.title) comparison requires at least two complete periods. Increase history retention in Settings or choose a shorter range."
        }
        return "MacThermal requires at least 80% observed coverage in both periods. Keep it running longer or choose a shorter range."
    }
}
