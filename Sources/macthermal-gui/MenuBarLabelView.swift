import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct MenuBarLabelView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var live: ThermalLiveState

    var body: some View {
        Image(systemName: symbol)
        Text(settings.unit.format(readingCelsius, decimals: 0))
    }

    private var readingCelsius: Double? {
        guard let category = settings.menuBarMetric.category else { return live.hottest?.celsius }
        return live.temperatureGroups.first { $0.category == category }?.hottest.celsius
    }

    // Icon severity follows the *displayed* reading, so selecting a cool metric
    // (e.g. CPU) never shows a hot icon driven by a different, hotter sensor.
    private var symbol: String {
        let severity = readingCelsius.map { tempLevel($0).severity } ?? .ok
        return severity == .critical ? "thermometer.high" : "thermometer.medium"
    }
}
