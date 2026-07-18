import SwiftUI

struct ComparisonMetricCard: View {
    let title: String
    let baseline: String
    let current: String
    let delta: String
    let improved: Bool
    let systemImage: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignMetrics.standardSpacing) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                LabeledContent("Previous", value: baseline)
                LabeledContent("Current", value: current)
                    .bold()
                Label(delta, systemImage: improved ? "arrow.down.right" : "arrow.up.right")
                    .foregroundStyle(improved ? .green : .orange)
            }
            .padding(.vertical, DesignMetrics.compactSpacing)
        }
        .accessibilityElement(children: .combine)
    }
}
