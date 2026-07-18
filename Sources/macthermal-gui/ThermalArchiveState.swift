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
    @Published var isRecordingIncident = false
    @Published var incidentStartedAt: Date?
    @Published var incidentSampleCount = 0
    @Published var recordingTrigger: ThermalIncidentTrigger?
}
