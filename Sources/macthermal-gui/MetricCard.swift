import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(tint)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignMetrics.compactSpacing)
        }
    }
}
