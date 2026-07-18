import Charts
import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ContributorsChart: View {
    let contributors: [HeatContributor]

    var body: some View {
        Chart(contributors) { item in
            BarMark(
                x: .value("CPU while hot", item.hotAverageCPUPercent),
                y: .value("Process", item.processName)
            )
            .foregroundStyle(by: .value("Process", item.processName))
            .annotation(position: .trailing) {
                Text("\(item.hotAverageCPUPercent.formatted(.number.precision(.fractionLength(0))))%")
                    .font(.callout)
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("CPU used by each process while the Mac was hot")
    }
}
