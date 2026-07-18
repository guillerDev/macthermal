import SwiftUI

struct ContributorExplanationView: View {
    var body: some View {
        Label {
            Text("Ranked by the CPU each process used while your Mac was at its hottest. It's a strong lead, not proof that a process caused the heat. \"Pattern\" says whether a process ran hot steadily or rose and fell with the temperature.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundStyle(.secondary)
        .padding(DesignMetrics.cardPadding)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
    }
}
