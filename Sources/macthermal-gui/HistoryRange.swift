import Foundation

enum HistoryRange: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case twentyFourHours
    case sevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 min"
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .oneHour: 60 * 60
        case .sixHours: 6 * 60 * 60
        case .twentyFourHours: 24 * 60 * 60
        case .sevenDays: 7 * 24 * 60 * 60
        }
    }
}
