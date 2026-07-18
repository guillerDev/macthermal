import SwiftUI

struct PanelHeader: View {
    @EnvironmentObject private var live: ThermalLiveState

    var body: some View {
        HStack(spacing: DesignMetrics.compactSpacing) {
            Image(systemName: "thermometer.medium")
                .foregroundStyle(live.menuBarSeverity.color)
                .accessibilityHidden(true)
            Text("MacThermal Pro")
                .font(.headline)
            Spacer()
            Label(live.thermal.name.capitalized, systemImage: live.thermal.severity.symbol)
                .font(.callout)
                .foregroundStyle(live.thermal.severity.color)
        }
        .accessibilityElement(children: .combine)
    }
}
