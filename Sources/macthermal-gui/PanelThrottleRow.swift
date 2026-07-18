import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct PanelThrottleRow: View {
    let assessment: ThrottleAssessment

    var body: some View {
        Label(assessment.title, systemImage: assessment.level.symbol)
            .foregroundStyle(assessment.level.color)
            .help(assessment.detail)
    }
}
