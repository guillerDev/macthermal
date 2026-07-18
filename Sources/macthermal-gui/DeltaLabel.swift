import SwiftUI

struct DeltaLabel: View {
    let value: Double
    let suffix: String
    let lowerIsBetter: Bool

    var body: some View {
        let improved = lowerIsBetter ? value <= 0 : value >= 0
        Label(formattedValue, systemImage: value <= 0 ? "arrow.down.right" : "arrow.up.right")
            .foregroundStyle(improved ? .green : .orange)
    }

    private var formattedValue: String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(1))))\(suffix)"
    }
}
