import SwiftUI

struct ContributorExplanationView: View {
    var body: some View {
        Label {
            Text("Correlation compares sampled CPU use with hotspot temperature. A high value is a useful lead, but it does not prove that a process caused the heat.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundStyle(.secondary)
        .padding(DesignMetrics.cardPadding)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
    }
}
