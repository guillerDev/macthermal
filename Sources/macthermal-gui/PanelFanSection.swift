import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct PanelFanSection: View {
    let fans: [FanReading]

    var body: some View {
        if fans.isEmpty {
            Label("Fanless Mac", systemImage: "wind")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: DesignMetrics.compactSpacing) {
                ForEach(fans, id: \.index) { fan in
                    let level = fanLevel(fan.utilization)
                    HStack {
                        Label("Fan \(fan.index + 1)", systemImage: "fan")
                        ProgressView(value: fan.utilization, total: 100)
                            .tint(level.severity.color)
                        Text("\(fan.rpm.formatted(.number.precision(.fractionLength(0)))) rpm")
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
