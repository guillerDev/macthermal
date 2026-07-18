import SwiftUI

struct IncidentRecordingHeader: View {
    let monitor: ThermalMonitor
    @EnvironmentObject private var recording: IncidentRecordingState

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.standardSpacing) {
            if recording.isRecording {
                Label(recordingTitle, systemImage: "record.circle.fill")
                    .foregroundStyle(.red)
                if let startedAt = recording.startedAt {
                    Text("Started \(startedAt, format: .dateTime.hour().minute().second()) · \(recording.sampleCount) samples")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Stop Recording", systemImage: "stop.circle.fill", action: monitor.toggleIncidentRecording)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Text("Reproduce a slowdown while recording to preserve its temperatures, fans, pressure, and top processes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Record Incident", systemImage: "record.circle", action: monitor.toggleIncidentRecording)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingTitle: String {
        switch recording.trigger {
        case .automaticThermalPressure: "Automatically recording thermal pressure"
        case .automaticHighTemperature: "Automatically recording high temperature"
        default: "Recording incident"
        }
    }
}
