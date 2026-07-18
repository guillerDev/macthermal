import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case history
    case events
    case contributors
    case comparison
    case incidents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .history: "History"
        case .events: "Timeline"
        case .contributors: "Contributors"
        case .comparison: "Compare"
        case .incidents: "Incidents"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .history: "chart.xyaxis.line"
        case .events: "waveform.path.ecg"
        case .contributors: "bolt.horizontal.circle"
        case .comparison: "arrow.left.arrow.right"
        case .incidents: "record.circle"
        }
    }
}
