import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ComparisonInterpretationView: View {
    let comparison: ThermalComparison

    var body: some View {
        let improved = comparison.hotspotDeltaCelsius <= -2 && comparison.fanDeltaPercent <= 0
        let regressed = comparison.hotspotDeltaCelsius >= 2 || comparison.pressureFractionDelta > 0

        Label {
            Text(message(improved: improved, regressed: regressed))
        } icon: {
            Image(systemName: improved ? "checkmark.circle.fill" : regressed ? "exclamationmark.triangle.fill" : "equal.circle.fill")
        }
        .foregroundStyle(improved ? .green : regressed ? .orange : .secondary)
        .padding(DesignMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
    }

    private func message(improved: Bool, regressed: Bool) -> String {
        if improved {
            "The current period is meaningfully cooler without additional fan effort."
        } else if regressed {
            "The current period is hotter or contains more thermal-pressure samples. Review likely contributors."
        } else {
            "The two periods are thermally similar. Small changes may be normal workload variation."
        }
    }
}
