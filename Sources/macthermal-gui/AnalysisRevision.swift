import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct SampleRevision: Hashable, Sendable {
    let count: Int
    let firstID: UUID?
    let lastID: UUID?

    init(_ samples: [ThermalSample]) {
        count = samples.count
        firstID = samples.first?.id
        lastID = samples.last?.id
    }
}

struct RangedHistoryRevision: Hashable, Sendable {
    let range: HistoryRange
    let samples: SampleRevision
}

struct EventAnalysisRevision: Hashable, Sendable {
    let range: HistoryRange
    let samples: SampleRevision
    let thresholdCelsius: Double
}

struct ComparisonAnalysisRevision: Hashable, Sendable {
    let range: HistoryRange
    let samples: SampleRevision
    let historyInterval: TimeInterval
    let retentionDays: Int
}
