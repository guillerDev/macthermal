import Foundation

public enum ThrottleLevel: String, Codable, Sendable {
    case normal
    case elevated
    case active
    case critical
}

public struct ThrottleAssessment: Equatable, Sendable {
    public let level: ThrottleLevel
    public let title: String
    public let detail: String

    public init(hottestCelsius: Double, thermalState: ThermalState) {
        switch thermalState.severity {
        case .critical:
            level = .critical
            title = "Critical throttling"
            detail = "macOS reports critical thermal pressure and aggressive throttling."
        case .warn:
            level = .active
            title = "Throttling active"
            detail = "macOS reports serious thermal pressure and is reducing performance."
        default:
            if hottestCelsius >= 90 {
                level = .elevated
                title = "Throttling risk"
                detail = "The hotspot is very hot, but macOS has not reported active thermal pressure."
            } else {
                level = .normal
                title = "No throttling detected"
                detail = "macOS reports no serious thermal pressure."
            }
        }
    }
}
