import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct LiveMetricsGrid: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var live: ThermalLiveState
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignMetrics.standardSpacing) {
            MetricCard(
                title: "Hotspot",
                value: settings.unit.format(live.hottest?.celsius),
                detail: live.hottest.map { "\($0.label) · \($0.key)" } ?? "No reading",
                systemImage: "thermometer.high",
                tint: live.menuBarSeverity.color
            )
            MetricCard(
                title: "System average",
                value: settings.unit.format(live.averageCelsius),
                detail: "Across \(live.temps.count) temperature sensors",
                systemImage: "thermometer.variable",
                tint: .primary
            )
            MetricCard(
                title: "Thermal pressure",
                value: live.thermal.name.capitalized,
                detail: live.thermal.note,
                systemImage: live.thermal.severity.symbol,
                tint: live.thermal.severity.color
            )
            MetricCard(
                title: "Fans",
                value: fanValue,
                detail: fanDetail,
                systemImage: "fan",
                tint: fanSeverity.color
            )
        }
    }

    private var fanValue: String {
        guard !live.fans.isEmpty else { return "Fanless" }
        let average = live.fans.map(\.rpm).reduce(0, +) / Double(live.fans.count)
        return "\(average.formatted(.number.precision(.fractionLength(0)))) rpm"
    }

    private var fanDetail: String {
        live.fans.isEmpty ? "No fan hardware reported" : "\(live.fans.count) active fan\(live.fans.count == 1 ? "" : "s")"
    }

    private var fanSeverity: Severity {
        live.fans.map { fanLevel($0.utilization).severity }.max(by: severityOrder) ?? .ok
    }

    private func severityOrder(_ lhs: Severity, _ rhs: Severity) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private func rank(_ severity: Severity) -> Int {
        switch severity {
        case .ok: 0
        case .normal: 1
        case .warn: 2
        case .hot: 3
        case .critical: 4
        }
    }
}
