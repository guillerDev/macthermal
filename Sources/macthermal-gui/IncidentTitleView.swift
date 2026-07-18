import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct IncidentTitleView: View {
    let incident: ThermalIncident

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.compactSpacing) {
            Text(incident.name)
                .font(.title2)
                .bold()
            Text("\(incident.startedAt.formatted(date: .long, time: .standard)) · \(durationText)")
                .foregroundStyle(.secondary)
            if incident.effectiveTrigger.isAutomatic {
                Label(incident.effectiveTrigger.helpText, systemImage: "bolt.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var durationText: String {
        let totalSeconds = max(0, Int(incident.duration))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(seconds)s"
    }
}
