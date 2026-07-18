import SwiftUI

struct DeltaLabel: View {
    let value: Double
    let suffix: String
    let lowerIsBetter: Bool

    var body: some View {
        let neutral = abs(value) < 0.05
        let improved = lowerIsBetter ? value < 0 : value > 0
        Label(
            neutral ? "Unchanged" : formattedValue,
            systemImage: neutral ? "equal" : value < 0 ? "arrow.down.right" : "arrow.up.right"
        )
        .foregroundStyle(neutral ? Color.secondary : improved ? Color.green : Color.orange)
    }

    private var formattedValue: String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(1))))\(suffix)"
    }
}
