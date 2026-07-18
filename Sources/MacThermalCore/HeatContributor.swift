import Foundation

/// How a process' CPU use related to temperature over the window — used to
/// explain *why* a process is a likely contributor, instead of leaning on a raw
/// statistics number most users can't interpret.
public enum ContributionPattern: String, Equatable, Sendable {
    /// Heavy CPU throughout the hot period, largely independent of temperature
    /// swings — the classic "stuck" process that keeps the machine hot. Pearson
    /// correlation scores this *low* precisely because it doesn't vary, which is
    /// why load-while-hot (not correlation) drives the ranking.
    case steadyLoad
    /// CPU rose and fell together with temperature — activity-driven load.
    case tracksTemperature

    public var label: String {
        switch self {
        case .steadyLoad:        "Steady load"
        case .tracksTemperature: "Tracks temperature"
        }
    }

    public var detail: String {
        switch self {
        case .steadyLoad:
            "Used heavy CPU throughout the hot period, regardless of temperature swings."
        case .tracksTemperature:
            "CPU rose and fell together with the temperature."
        }
    }
}

/// A process ranked by how much CPU it used **while the Mac was hottest** — a
/// more actionable and intuitive "likely contributor" signal than raw Pearson
/// correlation, which ranks a steadily-pegged process low (or negative) exactly
/// because its CPU doesn't co-move with the temperature swings.
public struct HeatContributor: Equatable, Identifiable, Sendable {
    public let processName: String
    /// Average CPU (%) across the window's hottest samples — the ranking key and
    /// the number shown to the user (recognizable from Activity Monitor).
    public let hotAverageCPUPercent: Double
    /// Peak CPU (%) seen during those hot samples.
    public let peakCPUPercent: Double
    /// How many hot samples this process was actively using CPU in.
    public let hotSampleCount: Int
    /// Pearson correlation of CPU vs hotspot over the window. Kept only to derive
    /// `pattern`; never surfaced as a bare number.
    public let correlation: Double
    public let pattern: ContributionPattern

    public var id: String { processName }

    public init(
        processName: String,
        hotAverageCPUPercent: Double,
        peakCPUPercent: Double,
        hotSampleCount: Int,
        correlation: Double,
        pattern: ContributionPattern
    ) {
        self.processName = processName
        self.hotAverageCPUPercent = hotAverageCPUPercent
        self.peakCPUPercent = peakCPUPercent
        self.hotSampleCount = hotSampleCount
        self.correlation = correlation
        self.pattern = pattern
    }
}
