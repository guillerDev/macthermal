import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Temperature unit (GUI display only)
//
// Readings stay in Celsius everywhere in the sensor layer (and in the CLI/JSON);
// this is purely a presentation choice for the menu-bar app.

enum TempUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    var name: String { self == .celsius ? "Celsius" : "Fahrenheit" }
    func convert(_ c: Double) -> Double { self == .celsius ? c : c * 9.0 / 5.0 + 32.0 }
    /// Formats a Celsius value in this unit, e.g. `65°C` / `149°F`.
    func format(_ c: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%@", convert(c), symbol)
    }
}

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

    /// Display unit, persisted across launches. Sensor data stays in Celsius.
    @Published var unit: TempUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: "tempUnit") }
    }

    let interval: TimeInterval = 3
    private let reader = SMCReader()
    private var timer: Timer?
    private var refreshing = false

    init() {
        unit = TempUnit(rawValue: UserDefaults.standard.string(forKey: "tempUnit") ?? "") ?? .celsius
        Task {
            available = await reader.available
            refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Let the OS coalesce our wakeups with other timers instead of demanding
        // a precise tick every `interval`s — a meaningful energy win for a
        // long-lived menu-bar app, at no cost to a 3s-refresh UX.
        timer?.tolerance = interval * 0.5
    }

    func refresh() {
        // Skip if a capture is still in flight, so a slow read can't let timer
        // ticks pile up overlapping tasks.
        guard !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            guard let snap = await reader.capture() else { return }
            // Only republish what actually changed, so an unchanged tick doesn't
            // make SwiftUI re-diff the panel every interval for nothing.
            if temps != snap.temps { temps = snap.temps }
            if fans != snap.fans { fans = snap.fans }
            if thermal != snap.thermal { thermal = snap.thermal }
        }
    }

    var hottest: TempReading? { temps.first }
    var averageC: Double { temps.averageCelsius }
    func group(_ c: Category) -> [TempReading] { temps.filter { $0.category == c } }

    var menuBarText: String {
        guard let h = hottest else { return "––" }
        return unit.format(h.celsius, decimals: 0)   // e.g. "65°C"
    }
    var menuBarSeverity: Severity {
        guard let h = hottest else { return .ok }
        return tempLevel(h.celsius).severity
    }
}

// MARK: - Launch at login
//
// Uses the modern ServiceManagement API (macOS 13+): `SMAppService.mainApp`
// registers this very app bundle as a login item — no helper bundle and none of
// the deprecated `SMLoginItemSetEnabled` plumbing.

enum LaunchAtLogin {
    /// On when the app is registered as a login item — including the
    /// `.requiresApproval` state (registered, but the user must enable it under
    /// System Settings ▸ General ▸ Login Items).
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default:                          return false
        }
    }

    /// Registers/unregisters the app as a login item. Registers only from a
    /// not-registered state and unregisters from any active/pending one, so it
    /// never re-registers an already-pending item. Failures are logged, not
    /// fatal (e.g. an unsigned build run from a transient location).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, .notRegistered), (true, .notFound):
                try SMAppService.mainApp.register()
            case (false, .enabled), (false, .requiresApproval):
                try SMAppService.mainApp.unregister()
            default:
                break   // already in the desired state
            }
            return true
        } catch {
            NSLog("macthermal: could not change launch-at-login state: \(error.localizedDescription)")
            return false
        }
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

    /// Reflects and sets the login-item registration. Reads live on each render
    /// so the checkbox matches reality even if it was changed in System Settings.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.setEnabled($0) })
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
                    Text(monitor.unit.format(hot.celsius))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let h = monitor.hottest {
                    Text("Hotspot \(monitor.unit.format(h.celsius)) · \(h.key)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $monitor.unit) {
                    ForEach(TempUnit.allCases) { u in Text(u.symbol).tag(u) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 84)
            }
            HStack {
                Toggle("Open at Login", isOn: launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Refresh") { monitor.refresh() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
