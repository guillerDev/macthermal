import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ThermalEventRow: View {
    let event: ThermalEvent
    let unit: TempUnit

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.standardSpacing) {
            Image(systemName: event.kind.symbol)
                .font(.title3)
                .foregroundStyle(event.kind.color)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
                HStack {
                    Text(event.kind.title)
                        .font(.headline)
                    Spacer()
                    Text(event.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(event.detail(unit: unit))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DesignMetrics.compactSpacing)
        .accessibilityElement(children: .combine)
    }
}
