import SwiftUI

struct PanelView: View {
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var live: ThermalLiveState
    @EnvironmentObject private var status: AppStatusState

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.standardSpacing) {
            PanelHeader()
            Divider()

            if live.available {
                PanelTemperatureSection(groups: live.temperatureGroups, unit: settings.unit)
                PanelFanSection(fans: live.fans)
                Divider()
                PanelThrottleRow(assessment: live.throttleAssessment)
            } else {
                Label("SMC unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            PanelFooter(monitor: monitor, settings: settings)
        }
        .padding()
        .frame(width: DesignMetrics.panelWidth)
        .alert(item: $status.presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
        .onAppear { monitor.setPanelPresented(true) }
        .onDisappear { monitor.setPanelPresented(false) }
    }
}
