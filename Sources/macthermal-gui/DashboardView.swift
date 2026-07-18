import SwiftUI

struct DashboardView: View {
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var archive: ThermalArchiveState
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
        } detail: {
            DashboardDetailView(selection: selection ?? .overview, monitor: monitor, settings: settings)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh", systemImage: "arrow.clockwise", action: monitor.refresh)
                    .keyboardShortcut("r")
                Button(
                    archive.isRecordingIncident ? "Stop Incident" : "Record Incident",
                    systemImage: archive.isRecordingIncident ? "stop.circle.fill" : "record.circle",
                    action: monitor.toggleIncidentRecording
                )
                .foregroundStyle(archive.isRecordingIncident ? .red : .primary)
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
