import Combine
import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

/// Frequently changing sensor state. Views that only show stored diagnostics
/// deliberately do not observe this object.
@MainActor
final class ThermalLiveState: ObservableObject {
    @Published private var content = ThermalLiveContent()

    var temps: [TempReading] { content.temps }
    var temperatureGroups: [TempGroup] { content.temperatureGroups }
    var fans: [FanReading] { content.fans }
    var thermal: ThermalState { content.thermal }
    var available: Bool { content.available }

    var hottest: TempReading? { temps.first }
    var averageCelsius: Double { temps.averageCelsius }
    var menuBarSeverity: Severity { hottest.map { tempLevel($0.celsius).severity } ?? .ok }
    var menuBarSymbol: String { menuBarSeverity == .critical ? "thermometer.high" : "thermometer.medium" }
    var throttleAssessment: ThrottleAssessment {
        ThrottleAssessment(hottestCelsius: hottest?.celsius ?? 0, thermalState: thermal)
    }

    func apply(_ snapshot: Snapshot) {
        let next = ThermalLiveContent(
            temps: snapshot.temps,
            temperatureGroups: TempGroup.grouped(snapshot.temps),
            fans: snapshot.fans,
            thermal: snapshot.thermal,
            available: true
        )
        if content != next { content = next }
    }

    func setAvailable(_ available: Bool) {
        guard content.available != available else { return }
        var next = content
        next.available = available
        content = next
    }
}

private struct ThermalLiveContent: Equatable {
    var temps: [TempReading] = []
    var temperatureGroups: [TempGroup] = []
    var fans: [FanReading] = []
    var thermal = ThermalState.current()
    var available = true
}
