import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ThrottleStatusView: View {
    let assessment: ThrottleAssessment

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.standardSpacing) {
            Image(systemName: assessment.level.symbol)
                .font(.title2)
                .foregroundStyle(assessment.level.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
                Text(assessment.title)
                    .font(.headline)
                Text(assessment.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DesignMetrics.cardPadding)
        .background(assessment.level.color.opacity(0.1))
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .stroke(assessment.level.color.opacity(0.3))
        }
        .accessibilityElement(children: .combine)
    }
}
