import AppKit
import SwiftUI

struct PanelFooter: View {
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.standardSpacing) {
            HStack {
                Picker("Temperature unit", selection: $settings.unit) {
                    ForEach(TempUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Button("Refresh", systemImage: "arrow.clockwise", action: monitor.refresh)
                    .labelStyle(.iconOnly)
                if #available(macOS 14, *) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                } else {
                    Button("Settings", systemImage: "gearshape", action: SettingsWindowOpener.openLegacy)
                        .labelStyle(.iconOnly)
                }
                Button("Quit", systemImage: "power", action: quit)
                    .labelStyle(.iconOnly)
            }

            LaunchAtLoginToggle(monitor: monitor)
                .toggleStyle(.checkbox)

            HStack {
                Button("Open Dashboard", systemImage: "macwindow", action: openDashboard)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button(
                    archive.isRecordingIncident ? "Stop" : "Record",
                    systemImage: archive.isRecordingIncident ? "stop.circle.fill" : "record.circle",
                    action: monitor.toggleIncidentRecording
                )
                .tint(archive.isRecordingIncident ? .red : .accentColor)
            }
        }
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
