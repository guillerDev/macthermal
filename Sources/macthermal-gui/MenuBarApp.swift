import SwiftUI
import AppKit
import ServiceManagement
// Shared sensor core: a real module under SwiftPM/Xcode, but folded into a
// single module by the flat `swiftc` Makefile build (where `canImport` is false
// and this guard drops the import).
#if canImport(MacThermalCore)
import MacThermalCore
// When the core is a separate module, `import AppKit` also pulls in the ObjC
// `Category` typedef (objc/runtime.h), making bare `Category` ambiguous. Pin it
// to ours. (In the flat Makefile build our same-module `Category` already wins,
// and this guarded alias isn't compiled.)
typealias Category = MacThermalCore.Category
#endif

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

// MARK: - Grouped temperatures (panel presentation model)

/// One category's sensors, hottest-first. A value type with a stable `id` so the
/// panel's `ForEach` can diff rows and skip unchanged ones. Constructed only for
/// non-empty categories, so `hottest` is always present.
struct TempGroup: Identifiable, Equatable {
    let category: Category
    let readings: [TempReading]
    var id: Category { category }
    var hottest: TempReading { readings[0] }
    /// Mean across the category's sensors — same computation the CLI and JSON use.
    var averageCelsius: Double { readings.averageCelsius }

    /// Right-hand detail line. Includes the group average only when it adds
    /// information — with a single sensor the average equals the hottest value
    /// already shown, so it's omitted (and "sensor" is singular).
    func detail(unit: TempUnit, level: String) -> String {
        let n = readings.count
        let sensors = "\(n) sensor\(n == 1 ? "" : "s")"
        return n > 1
            ? "avg \(unit.format(averageCelsius)) · \(sensors) · \(level)"
            : "\(sensors) · \(level)"
    }

    /// Groups readings by category in `Category.allCases` order, dropping empties.
    /// `Dictionary(grouping:)` preserves input order, so hottest-first `temps`
    /// keeps each group's `readings.first` the hottest sensor in that category.
    static func grouped(_ temps: [TempReading]) -> [TempGroup] {
        let byCategory = Dictionary(grouping: temps, by: \.category)
        return Category.allCases.compactMap { cat in
            guard let readings = byCategory[cat], !readings.isEmpty else { return nil }
            return TempGroup(category: cat, readings: readings)
        }
    }
}

// MARK: - Monitor
//
// Polls the reader on a timer and republishes snapshots to SwiftUI on the main
// actor. Holds no IOKit state itself.

@MainActor
final class ThermalMonitor: ObservableObject {
    /// Live readings, hottest-first. Grouped-by-category is derived state the
    /// panel renders, so it's cached here (recomputed only when `temps` actually
    /// changes) rather than re-grouped on every view `body` pass.
    @Published var temps: [TempReading] = [] {
        didSet { temperatureGroups = TempGroup.grouped(temps) }
    }
    @Published private(set) var temperatureGroups: [TempGroup] = []
    @Published var fans: [FanReading] = []
    @Published var thermal = ThermalState.current()
    @Published var available = true
    /// Whether the app is registered as a login item. Loaded (and updated) off
    /// the main thread — the backing `SMAppService` calls hit a daemon and are
    /// slow, so the UI binds to this cached flag, never to a live query.
    @Published var launchAtLogin = false

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
            launchAtLogin = await Self.loginItemEnabled()
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

    /// Toggles launch-at-login optimistically: the published flag flips at once
    /// so the checkbox responds instantly, then the slow, daemon-backed
    /// `SMAppService` call runs off the main thread and the flag is reconciled to
    /// the real status (so a failed register/unregister visibly reverts).
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        Task { launchAtLogin = await Self.applyLoginItem(enabled) }
    }

    // Run off the main actor (nonisolated async): `SMAppService` register /
    // unregister / status are synchronous round-trips to the login-items daemon
    // and must not block the UI.
    nonisolated private static func loginItemEnabled() async -> Bool {
        LaunchAtLogin.isEnabled
    }
    nonisolated private static func applyLoginItem(_ enabled: Bool) async -> Bool {
        LaunchAtLogin.setEnabled(enabled)
        return LaunchAtLogin.isEnabled
    }

    var hottest: TempReading? { temps.first }
    var averageC: Double { temps.averageCelsius }

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
            // Menu-bar title: a fixed, untinted thermometer + hottest temp, so the
            // item keeps the standard monochrome menu-bar style and sits cleanly
            // alongside other items. (Heat color lives in the panel instead.)
            Image(systemName: "thermometer.medium")
            Text(monitor.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Dropdown panel

// A thin composer: it owns the panel's outer container and hands each section
// the narrow inputs it renders, so a change to one (e.g. fans) doesn't
// re-evaluate the bodies of the others (header, temperatures, footer).
struct PanelView: View {
    @ObservedObject var monitor: ThermalMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(severity: monitor.menuBarSeverity, thermal: monitor.thermal)
            Divider()

            if monitor.available {
                TemperatureSection(groups: monitor.temperatureGroups, unit: monitor.unit)
                Divider()
                FanSection(fans: monitor.fans)
            } else {
                Label("SMC unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            PanelFooter(monitor: monitor)
        }
        .padding(12)
        .frame(width: 320)
    }
}

private struct PanelHeader: View {
    let severity: Severity
    let thermal: ThermalState

    var body: some View {
        HStack(spacing: 6) {
            // Same thermometer glyph as the menu bar, tinted by severity here
            // (in-panel color is fine; it doesn't affect menu-bar alignment).
            Image(systemName: "thermometer.medium")
                .symbolRenderingMode(.palette)
                .foregroundStyle(severity.color)
            Text("MacThermal").font(.headline)
            Spacer()
            Circle().fill(thermal.severity.color).frame(width: 8, height: 8)
                .accessibilityHidden(true)   // decorative; `thermal.name` beside it carries the info
            Text(thermal.name).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// A `Grid` aligns the label / value / detail columns to their widest content, so
// there are no hand-tuned column widths to keep in sync as labels change.
private struct TemperatureSection: View {
    let groups: [TempGroup]
    let unit: TempUnit

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(groups) { group in
                let lvl = tempLevel(group.hottest.celsius)
                GridRow {
                    Text(group.category.rawValue)
                    Text(unit.format(group.hottest.celsius))
                        .bold().foregroundStyle(lvl.severity.color)
                    Text(group.detail(unit: unit, level: lvl.label))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct FanSection: View {
    let fans: [FanReading]

    var body: some View {
        if fans.isEmpty {
            Label("No fans (fanless or unavailable)", systemImage: "wind")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(fans, id: \.index) { f in
                    let lvl = fanLevel(f.utilization)
                    GridRow {
                        Text("Fan \(f.index + 1)")
                        Text(String(format: "%.0f rpm", f.rpm))
                            .foregroundStyle(lvl.severity.color)
                        // Flexible bar fills the middle column (no magic width).
                        ProgressView(value: f.utilization, total: 100)
                            .frame(maxWidth: .infinity)
                        Text(lvl.label).font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct PanelFooter: View {
    @ObservedObject var monitor: ThermalMonitor

    /// Bound to the monitor's cached flag so the checkbox flips instantly; the
    /// (slow) registration runs off the main thread in `setLaunchAtLogin`. Reading
    /// a plain Bool also avoids a live `SMAppService` query on every panel render.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { monitor.launchAtLogin },
                set: { monitor.setLaunchAtLogin($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let h = monitor.hottest {
                    Text("Hotspot \(monitor.unit.format(h.celsius)) · \(h.key)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Temperature unit", selection: $monitor.unit) {
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
