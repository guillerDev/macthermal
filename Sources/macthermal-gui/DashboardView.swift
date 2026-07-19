import SwiftUI

struct DashboardView: View {
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var recording: IncidentRecordingState
    @EnvironmentObject private var status: AppStatusState
    @State private var selection: DashboardSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("MacThermal Pro")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Text(AppInfo.displayVersion)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .help("MacThermal Pro \(AppInfo.displayVersion)")
            }
        } detail: {
            DashboardDetailView(
                selection: selection ?? .overview,
                monitor: monitor,
                settings: settings,
                onShowContributors: { selection = .contributors }
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh", systemImage: "arrow.clockwise", action: monitor.refresh)
                    .keyboardShortcut("r")
                Button(
                    recording.isRecording ? "Stop Incident" : "Record Incident",
                    systemImage: recording.isRecording ? "stop.circle.fill" : "record.circle",
                    action: monitor.toggleIncidentRecording
                )
                .foregroundStyle(recording.isRecording ? .red : .primary)
            }
            ToolbarItem(placement: .primaryAction) {
                if #available(macOS 14, *) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings (Command-,)")
                } else {
                    Button("Settings", systemImage: "gearshape", action: SettingsWindowOpener.openLegacy)
                        .help("Open Settings (Command-,)")
                }
            }
        }
        .alert(item: $status.presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
        .background {
            WindowVisibilityObserver(onChange: monitor.setDashboardPresented)
                .frame(width: 0, height: 0)
        }
    }
}
