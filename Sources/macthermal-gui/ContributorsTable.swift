import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ContributorsTable: View {
    let correlations: [ProcessCorrelation]

    var body: some View {
        Table(correlations) {
            TableColumn("Process", value: \.processName)
            TableColumn("Correlation") { item in
                Label(
                    item.coefficient.formatted(.number.precision(.fractionLength(2))),
                    systemImage: correlationSymbol(item.coefficient)
                )
                .foregroundStyle(correlationColor(item.coefficient))
            }
            TableColumn("Average CPU") { item in
                Text(item.averageCPUPercent, format: .number.precision(.fractionLength(1)))
            }
            TableColumn("Peak CPU") { item in
                Text(item.peakCPUPercent, format: .number.precision(.fractionLength(1)))
            }
            TableColumn("Samples") { item in
                Text(item.samplesObserved, format: .number)
            }
        }
        .frame(minHeight: 220)
    }

    private func correlationSymbol(_ value: Double) -> String {
        if value >= 0.7 { "arrow.up.right.circle.fill" }
        else if value >= 0.35 { "arrow.up.right.circle" }
        else { "minus.circle" }
    }

    private func correlationColor(_ value: Double) -> Color {
        if value >= 0.7 { .orange }
        else if value >= 0.35 { .yellow }
        else { .secondary }
    }
}
