import Combine
import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

/// High-frequency recording progress is isolated from stored history so a
/// two-second sample counter cannot invalidate charts and historical analytics.
@MainActor
final class IncidentRecordingState: ObservableObject {
    @Published var isRecording = false
    @Published var startedAt: Date?
    @Published var sampleCount = 0
    @Published var trigger: ThermalIncidentTrigger?
}
