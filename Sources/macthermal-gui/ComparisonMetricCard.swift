import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonMetricCard: View {
    let title: String
    let baseline: String
    let current: String
    let delta: String
    let deltaValue: Double
    let trend: ComparisonTrend
    let systemImage: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignMetrics.standardSpacing) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
                    Text("Current")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(current)
                        .font(.title2)
                        .bold()
                        .monospacedDigit()
                }
                LabeledContent("Previous") {
                    Text(baseline)
                        .monospacedDigit()
                }
                Label(delta, systemImage: trendSymbol)
                    .foregroundStyle(trendColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignMetrics.compactSpacing)
        }
        .accessibilityElement(children: .combine)
    }

    private var trendSymbol: String {
        switch trend {
        case .improved: "arrow.down.right"
        case .regressed: "arrow.up.right"
        case .unchanged: "equal"
        case .contextual:
            if deltaValue > 0 { "arrow.up.right" }
            else if deltaValue < 0 { "arrow.down.right" }
            else { "info.circle" }
        }
    }

    private var trendColor: Color {
        switch trend {
        case .improved: .green
        case .regressed: .orange
        case .unchanged, .contextual: .secondary
        }
    }
}
