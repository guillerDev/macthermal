import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct FanOverviewView: View {
    let fans: [FanReading]

    var body: some View {
        GroupBox("Fans") {
            if fans.isEmpty {
                Label("This Mac is fanless or does not report fan sensors.", systemImage: "wind")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignMetrics.compactSpacing)
            } else {
                VStack(spacing: DesignMetrics.standardSpacing) {
                    ForEach(fans, id: \.index) { fan in
                        FanRow(fan: fan)
                    }
                }
                .padding(.vertical, DesignMetrics.compactSpacing)
            }
        }
    }
}
