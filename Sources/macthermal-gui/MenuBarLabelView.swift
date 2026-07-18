import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var live: ThermalLiveState

    var body: some View {
        Image(systemName: live.menuBarSymbol)
        Text(settings.unit.format(readingCelsius, decimals: 0))
    }

    private var readingCelsius: Double? {
        guard let category = settings.menuBarMetric.category else { return live.hottest?.celsius }
        return live.temperatureGroups.first { $0.category == category }?.hottest.celsius
    }
}
