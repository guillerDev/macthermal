import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct IncidentListRow: View {
    let incident: ThermalIncident
    let unit: TempUnit

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
            HStack {
                Text(incident.name)
                    .lineLimit(1)
                if incident.effectiveTrigger.isAutomatic {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(.orange)
                        .help(incident.effectiveTrigger.helpText)
                }
            }
            HStack {
                Text(incident.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Spacer()
                Label(unit.format(incident.summary.peakHotspotCelsius), systemImage: "thermometer.high")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignMetrics.compactSpacing)
        .accessibilityElement(children: .combine)
    }
}
