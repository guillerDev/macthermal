import Foundation

public enum ThermalIncidentTrigger: String, Codable, Sendable {
    case manual
    case automaticThermalPressure
    case automaticHighTemperature

    public var isAutomatic: Bool { self != .manual }
}

public struct ThermalIncident: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let startedAt: Date
    public let endedAt: Date
    public let samples: [ThermalSample]
    public let trigger: ThermalIncidentTrigger?

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date,
        samples: [ThermalSample],
        trigger: ThermalIncidentTrigger? = .manual
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.samples = samples
        self.trigger = trigger
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    public var summary: ThermalSummary { ThermalSummary(samples: samples) }
    public var effectiveTrigger: ThermalIncidentTrigger { trigger ?? .manual }

    public func renamed(to name: String) -> ThermalIncident {
        ThermalIncident(
            id: id,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            samples: samples,
            trigger: trigger
        )
    }
}
