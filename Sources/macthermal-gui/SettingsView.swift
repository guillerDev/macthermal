import AppKit
import SwiftUI

struct SettingsView: View {
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
    @EnvironmentObject private var status: AppStatusState
    @State private var confirmsHistoryClear = false

    var body: some View {
        Form {
            Section("General") {
                Picker("Temperature unit", selection: $settings.unit) {
                    ForEach(TempUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
                Picker("Menu bar temperature", selection: $settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                LaunchAtLoginToggle(monitor: monitor)
            }

            Section("History") {
                Picker("Record a sample every", selection: $settings.historyInterval) {
                    Text("15 seconds").tag(TimeInterval(15))
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                }
                Picker("Keep history for", selection: $settings.retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
            }

            Section("Alerts") {
                Toggle("Temperature and pressure alerts", isOn: $settings.alertsEnabled)
                LabeledContent("Hotspot threshold") {
                    HStack {
                        Slider(value: $settings.alertThresholdCelsius, in: 70...110, step: 1)
                        Text(settings.unit.format(settings.alertThresholdCelsius, decimals: 0))
                            .monospacedDigit()
                    }
                }
                .disabled(!settings.alertsEnabled)
                Picker("Sustained for", selection: $settings.sustainedAlertSeconds) {
                    Text("15 seconds").tag(TimeInterval(15))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                }
                .disabled(!settings.alertsEnabled)
                Picker("Notification cooldown", selection: $settings.alertCooldownMinutes) {
                    Text("5 minutes").tag(5.0)
                    Text("15 minutes").tag(15.0)
                    Text("1 hour").tag(60.0)
                }
                .disabled(!settings.alertsEnabled)
                Toggle("Notify when macOS reports thermal throttling", isOn: $settings.notifyOnThermalPressure)
                    .disabled(!settings.alertsEnabled)
                LabeledContent("Permission") {
                    if status.notificationsAuthorized {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow Notifications", action: monitor.requestNotificationAuthorization)
                    }
                }
            }

            Section("Automatic incident capture") {
                Toggle("Serious or critical macOS pressure", isOn: $settings.autoRecordPressureIncidents)
                Toggle("Sustained temperature above the alert threshold", isOn: $settings.autoRecordTemperatureIncidents)
                Picker("Stop after recovery", selection: $settings.automaticIncidentRecoverySeconds) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("2 minutes").tag(TimeInterval(120))
                }
                .disabled(!settings.autoRecordPressureIncidents && !settings.autoRecordTemperatureIncidents)
                Picker("Split long recordings every", selection: $settings.maximumIncidentDurationMinutes) {
                    Text("30 minutes").tag(30.0)
                    Text("1 hour").tag(60.0)
                    Text("2 hours").tag(120.0)
                }
                Picker("Keep recorded incidents for", selection: $settings.incidentRetentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Picker("Maximum recordings", selection: $settings.maximumStoredIncidents) {
                    Text("10 incidents").tag(10)
                    Text("25 incidents").tag(25)
                    Text("50 incidents").tag(50)
                }
                Text("Automatic recordings include up to two minutes before the trigger, preserve high-resolution samples through the episode, and stop after sustained recovery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                LabeledContent("Stored samples", value: archive.history.count.formatted())
                LabeledContent("Recorded incidents", value: archive.incidents.count.formatted())
                HStack {
                    Button("Open Data Folder", systemImage: "folder", action: openDataFolder)
                    Spacer()
                    Button("Clear History", systemImage: "trash", role: .destructive) {
                        confirmsHistoryClear = true
                    }
                    .confirmationDialog(
                        "Clear all thermal history?",
                        isPresented: $confirmsHistoryClear,
                        titleVisibility: .visible
                    ) {
                        Button("Clear History", role: .destructive, action: monitor.clearHistory)
                    } message: {
                        Text("Recorded incidents are preserved. This action cannot be undone.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 600, height: 720)
    }

    private func openDataFolder() {
        let directory = URL.applicationSupportDirectory.appending(path: "MacThermal", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(directory) else {
                throw CocoaError(.fileNoSuchFile)
            }
        } catch {
            status.presentedError = UserFacingError(message: "The data folder could not be opened: \(error.localizedDescription)")
        }
    }
}
