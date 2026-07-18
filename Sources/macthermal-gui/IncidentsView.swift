import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct IncidentsView: View {
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @State private var selectedIncidentID: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                IncidentRecordingHeader(monitor: monitor)
                    .padding()
                Divider()
                List(archive.incidents, selection: $selectedIncidentID) { incident in
                    IncidentListRow(incident: incident, unit: settings.unit)
                        .tag(incident.id)
                }
            }
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)

            if let incident = selectedIncident {
                IncidentDetailView(incident: incident, monitor: monitor, settings: settings)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    title: "No incident selected",
                    message: "Record a thermal incident while reproducing a slowdown, or select an existing recording.",
                    systemImage: "record.circle"
                )
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Incident Recorder")
        .task(id: incidentIDs) {
            if let selectedIncidentID,
               archive.incidents.contains(where: { $0.id == selectedIncidentID }) {
                return
            }
            selectedIncidentID = archive.incidents.first?.id
        }
    }

    private var selectedIncident: ThermalIncident? {
        archive.incidents.first { $0.id == selectedIncidentID }
    }

    private var incidentIDs: [UUID] {
        archive.incidents.map(\.id)
    }
}
