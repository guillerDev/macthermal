import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonView: View {
    @ObservedObject var settings: AppSettings
    let onShowContributors: () -> Void
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var range: HistoryRange = .oneHour
    @State private var analysis: ComparisonAnalysis?

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: DesignMetrics.standardSpacing),
        GridItem(.flexible(minimum: 220), spacing: DesignMetrics.standardSpacing),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Period", selection: $range) {
                    // Only offer ranges the current retention can actually compare
                    // (per-option `.disabled` is a no-op on a segmented picker).
                    ForEach(HistoryRange.allCases.filter {
                        $0.supportsComparison(retentionDays: settings.retentionDays)
                    }) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Text("Current period vs immediately preceding period")
                    .foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            if let analysis, analysis.hasComparableData {
                let comparison = analysis.comparison
                let assessment = ThermalComparisonAssessment(comparison: comparison)
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignMetrics.sectionSpacing) {
                        if !analysis.isReliable {
                            limitedCoverageBanner
                        }
                        LazyVGrid(columns: columns, spacing: DesignMetrics.standardSpacing) {
                            ComparisonPeriodSummaryView(
                                title: "Previous",
                                systemImage: "clock.arrow.circlepath",
                                start: analysis.baselineStart,
                                end: analysis.baselineEnd,
                                coverage: analysis.baselineCoverage
                            )
                            ComparisonPeriodSummaryView(
                                title: "Current",
                                systemImage: "clock",
                                start: analysis.currentStart,
                                end: analysis.currentEnd,
                                coverage: analysis.currentCoverage
                            )
                        }

                        Text("Thermal metrics")
                            .font(.headline)

                        LazyVGrid(columns: columns, spacing: DesignMetrics.standardSpacing) {
                            ComparisonMetricCard(
                                title: "Average hotspot",
                                baseline: settings.unit.format(comparison.baseline.averageHotspotCelsius),
                                current: settings.unit.format(comparison.current.averageHotspotCelsius),
                                delta: temperatureDelta(
                                    comparison.hotspotDeltaCelsius,
                                    trend: assessment.averageHotspotTrend
                                ),
                                deltaValue: comparison.hotspotDeltaCelsius,
                                trend: assessment.averageHotspotTrend,
                                systemImage: "thermometer.medium"
                            )
                            ComparisonMetricCard(
                                title: "Peak hotspot",
                                baseline: settings.unit.format(comparison.baseline.peakHotspotCelsius),
                                current: settings.unit.format(comparison.current.peakHotspotCelsius),
                                delta: temperatureDelta(
                                    comparison.peakDeltaCelsius,
                                    trend: assessment.peakHotspotTrend
                                ),
                                deltaValue: comparison.peakDeltaCelsius,
                                trend: assessment.peakHotspotTrend,
                                systemImage: "thermometer.high"
                            )
                            ComparisonMetricCard(
                                title: "Average fan load",
                                baseline: fanValue(comparison.baseline),
                                current: fanValue(comparison.current),
                                delta: fanDelta(comparison: comparison, trend: assessment.fanTrend),
                                deltaValue: comparison.fanDataAvailable ? comparison.fanDeltaPercent : 0,
                                trend: assessment.fanTrend,
                                systemImage: "fan"
                            )
                            ComparisonMetricCard(
                                title: "Thermal pressure rate",
                                baseline: percent(comparison.baseline.pressureFraction * 100),
                                current: percent(comparison.current.pressureFraction * 100),
                                delta: percentageDelta(
                                    comparison.pressureFractionDelta * 100,
                                    trend: assessment.pressureTrend
                                ),
                                deltaValue: comparison.pressureFractionDelta,
                                trend: assessment.pressureTrend,
                                systemImage: "gauge.with.dots.needle.67percent"
                            )
                        }
                        ComparisonInterpretationView(
                            assessment: assessment,
                            onShowContributors: onShowContributors
                        )
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
        .navigationTitle("Period Comparison")
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

    private func temperatureDelta(_ value: Double, trend: ComparisonTrend) -> String {
        guard trend != .unchanged else { return "Unchanged" }
        let convertedDelta = settings.unit == .celsius ? value : value * 9 / 5
        let change = "\(convertedDelta >= 0 ? "+" : "")\(convertedDelta.formatted(.number.precision(.fractionLength(1))))\(settings.unit.symbol)"
        return "\(change) · \(value > 0 ? "Warmer" : "Cooler")"
    }

    private func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))%"
    }

    private func percentageDelta(_ value: Double, trend: ComparisonTrend) -> String {
        guard trend != .unchanged else { return "Unchanged" }
        let change = "\(value >= 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(0))))%"
        return "\(change) · \(value > 0 ? "Higher" : "Lower")"
    }

    private func fanValue(_ summary: ThermalSummary) -> String {
        summary.hasFanData ? percent(summary.averageFanUtilization) : "Not available"
    }

    private func fanDelta(comparison: ThermalComparison, trend: ComparisonTrend) -> String {
        guard comparison.fanDataAvailable else { return "No comparable fan data" }
        return percentageDelta(comparison.fanDeltaPercent, trend: trend)
    }

    private var analysisRevision: ComparisonAnalysisRevision {
        ComparisonAnalysisRevision(
            range: range,
            samples: SampleRevision(archive.history),
            historyInterval: settings.historyInterval,
            retentionDays: settings.retentionDays
        )
    }

    private var limitedCoverageBanner: some View {
        Label(
            "Limited coverage — one or both periods have sampling gaps (the Mac may have been idle or asleep), so treat this comparison as approximate.",
            systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.secondary)
        .padding(DesignMetrics.cardPadding)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
    }

    private var emptyStateTitle: String {
        range.supportsComparison(retentionDays: settings.retentionDays)
            ? "Not enough data yet"
            : "Retention is too short"
    }

    private var emptyStateMessage: String {
        if !range.supportsComparison(retentionDays: settings.retentionDays) {
            return "A \(range.title) comparison requires at least two complete periods. Increase history retention in Settings or choose a shorter range."
        }
        return "Keep MacThermal running to record two \(range.title) periods to compare."
    }
}
