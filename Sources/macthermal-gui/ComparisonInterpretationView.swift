import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonInterpretationView: View {
    let assessment: ThermalComparisonAssessment
    let onShowContributors: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignMetrics.standardSpacing) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
                Text(title)
                    .bold()
                Text(message)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignMetrics.standardSpacing)
            if showsContributorsButton {
                Button("View Contributors", systemImage: "bolt.horizontal.circle", action: onShowContributors)
            }
        }
        .padding(DesignMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
    }

    private var title: String {
        switch assessment.result {
        case .improved: "Thermal conditions improved"
        case .regressed: "Thermal conditions regressed"
        case .mixed: "Mixed result"
        case .unchanged: "No meaningful change"
        }
    }

    private var message: String {
        switch assessment.result {
        case .improved:
            return "At least one thermal indicator improved, with no meaningful regression in the others."
        case .regressed:
            return "At least one thermal indicator worsened without an offsetting improvement. Review likely contributors."
        case .mixed:
            if assessment.averageHotspotTrend == .regressed,
               assessment.peakHotspotTrend == .improved {
                return "Average temperature increased, but the recorded peak was lower. Review each metric before drawing a conclusion."
            }
            return "Some thermal indicators improved while others worsened. Review each metric before drawing a conclusion."
        case .unchanged:
            return "The periods are within normal variation for average temperature, peak temperature, and thermal pressure."
        }
    }

    private var symbol: String {
        switch assessment.result {
        case .improved: "checkmark.circle.fill"
        case .regressed: "exclamationmark.triangle.fill"
        case .mixed: "arrow.triangle.branch"
        case .unchanged: "equal.circle.fill"
        }
    }

    private var tint: Color {
        switch assessment.result {
        case .improved: .green
        case .regressed: .orange
        case .mixed: .blue
        case .unchanged: .secondary
        }
    }

    private var showsContributorsButton: Bool {
        assessment.result == .regressed || assessment.result == .mixed
    }
}
