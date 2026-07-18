import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct HistoryControls: View {
    @Binding var range: HistoryRange
    let samples: [ThermalSample]
    @EnvironmentObject private var status: AppStatusState

    var body: some View {
        HStack {
            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("Diagnostic report…", systemImage: "doc.richtext", action: exportHTML)
                Button("CSV samples…", systemImage: "tablecells", action: exportCSV)
            }
            .disabled(samples.isEmpty)
        }
    }

    private func exportHTML() {
        Task {
            do {
                try await ReportExporter.exportHTML(title: "MacThermal \(range.title) report", samples: samples)
            } catch is CancellationError {
                return
            } catch {
                status.presentedError = UserFacingError(message: "The report could not be exported: \(error.localizedDescription)")
            }
        }
    }

    private func exportCSV() {
        Task {
            do {
                try await ReportExporter.exportCSV(title: "MacThermal \(range.title) samples", samples: samples)
            } catch is CancellationError {
                return
            } catch {
                status.presentedError = UserFacingError(message: "The samples could not be exported: \(error.localizedDescription)")
            }
        }
    }
}
