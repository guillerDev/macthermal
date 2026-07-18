import Combine
import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

/// Stored history and incident state, updated far less often than live sensors.
@MainActor
final class ThermalArchiveState: ObservableObject {
    @Published var history: [ThermalSample] = []
    @Published var incidents: [ThermalIncident] = []

    func replaceHistory(with samples: [ThermalSample]) {
        history = samples
    }

    func appendHistory(_ sample: ThermalSample) {
        history.append(sample)
    }

    func clearHistory() {
        history.removeAll(keepingCapacity: false)
    }

    /// Array removal is linear, so pruning is deliberately called in batches
    /// instead of shifting the complete retained history for every new sample.
    func trimHistory(before cutoff: Date) {
        guard let firstRetained = history.firstIndex(where: { $0.timestamp >= cutoff }) else {
            history.removeAll(keepingCapacity: true)
            return
        }
        guard firstRetained > 0 else { return }
        history.removeFirst(firstRetained)
    }

    func replaceIncidents(with value: [ThermalIncident]) {
        incidents = value
    }

    func insertIncident(_ incident: ThermalIncident) {
        incidents.insert(incident, at: 0)
    }

    func renameIncident(id: UUID, to name: String) {
        guard let index = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[index] = incidents[index].renamed(to: name)
    }

    func removeIncident(id: UUID) {
        incidents.removeAll { $0.id == id }
    }

    func pruneIncidents(cutoff: Date, maximumCount: Int) {
        incidents.removeAll { $0.endedAt < cutoff }
        if incidents.count > maximumCount {
            incidents.removeLast(incidents.count - maximumCount)
        }
    }
}
