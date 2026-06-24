import SwiftUI
import AppKit

// MARK: - Severity → SwiftUI color

extension Severity {
    var color: Color {
        switch self {
        case .ok:       return .green
        case .normal:   return .green
        case .warn:     return .yellow
        case .hot:      return .orange
        case .critical: return .red
        }
    }
}

// MARK: - SMC reader
//
// Isolates the (non-Sendable) IOKit connection inside an actor, so every SMC
// read runs off the main thread and only an immutable, Sendable `Snapshot`
// ever crosses back to the UI.

actor SMCReader {
    private let smc: SMC?
    init() { smc = try? SMC() }

    var available: Bool { smc != nil }

    func capture() -> Snapshot? {
        guard let smc else { return nil }
        return Snapshot.capture(smc)
    }
}

// MARK: - Monitor
//
// Polls the reader on a timer and republishes snapshots to SwiftUI on the main
// actor. Holds no IOKit state itself.

@MainActor
final class ThermalMonitor: ObservableObject {
    @Published var temps: [TempReading] = []
    @Published var fans: [FanReading] = []
    @Published var thermal = ThermalState.current()
    @Published var available = true

    let interval: TimeInterval = 3
    private let reader = SMCReader()
    private var timer: Timer?

    init() {
        Task {
            available = await reader.available
            refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            guard let snap = await reader.capture() else { return }
            temps = snap.temps
            fans = snap.fans
            thermal = snap.thermal
        }
    }

    var hottest: TempReading? { temps.first }
    var averageC: Double { temps.isEmpty ? 0 : temps.map { $0.celsius }.reduce(0, +) / Double(temps.count) }
    func group(_ c: Category) -> [TempReading] { temps.filter { $0.category == c } }

    var menuBarText: String {
        guard let h = hottest else { return "––" }
        return String(format: "%.0f°", h.celsius)
    }
    var menuBarSeverity: Severity {
        guard let h = hottest else { return .ok }
        return tempLevel(h.celsius).severity
    }
}

// MARK: - App

@main
struct MacThermalApp: App {
    @StateObject private var monitor = ThermalMonitor()

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            // Menu-bar title: thermometer + hottest temp.
            Image(systemName: "thermometer.medium")
            Text(monitor.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Dropdown panel

struct PanelView: View {
    @ObservedObject var monitor: ThermalMonitor

    private var categoriesWithData: [Category] {
        Category.allCases.filter { !monitor.group($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()

            if !monitor.available {
                Label("SMC unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else {
                temperatures
                Divider()
                fansSection
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "thermometer.sun.fill")
            Text("macthermal").font(.headline)
            Spacer()
            Circle().fill(monitor.thermal.severity.color).frame(width: 8, height: 8)
            Text(monitor.thermal.name).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var temperatures: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(categoriesWithData, id: \.self) { cat in
                let group = monitor.group(cat)
                let hot = group.first!
                let lvl = tempLevel(hot.celsius)
                HStack {
                    Text(cat.rawValue).frame(width: 64, alignment: .leading)
                    Text(String(format: "%.1f°C", hot.celsius))
                        .bold().foregroundStyle(lvl.severity.color)
                    Spacer()
                    Text("\(group.count) sensors · \(lvl.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var fansSection: some View {
        if monitor.fans.isEmpty {
            Label("No fans (fanless or unavailable)", systemImage: "wind")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(monitor.fans, id: \.index) { f in
                    let lvl = fanLevel(f.utilization)
                    HStack {
                        Text("Fan \(f.index + 1)").frame(width: 64, alignment: .leading)
                        Text(String(format: "%.0f rpm", f.rpm))
                            .foregroundStyle(lvl.severity.color)
                        Spacer()
                        ProgressView(value: f.utilization, total: 100)
                            .frame(width: 70)
                        Text(lvl.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let h = monitor.hottest {
                Text(String(format: "Hotspot %.1f°C · %@", h.celsius, h.key))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { monitor.refresh() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
