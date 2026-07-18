import SwiftUI

struct DashboardDetailView: View {
    let selection: DashboardSection
    let monitor: ThermalMonitor
    @ObservedObject var settings: AppSettings
    let onShowContributors: () -> Void

    var body: some View {
        switch selection {
        case .overview:
            OverviewView(settings: settings)
        case .history:
            HistoryView(settings: settings)
        case .events:
            ThermalEventsView(settings: settings)
        case .contributors:
            ContributorsView()
        case .comparison:
            ComparisonView(settings: settings, onShowContributors: onShowContributors)
        case .incidents:
            IncidentsView(monitor: monitor, settings: settings)
        }
    }
}
