import SwiftUI
import AppKit
import Combine
import ServiceManagement

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

// MARK: - Launch at login
//
// Uses the modern ServiceManagement API (macOS 13+): `SMAppService.mainApp`
// registers *this* app bundle as a login item — no helper bundle and none of
// the deprecated `SMLoginItemSetEnabled` plumbing. Toggled from the status-item
// right-click menu below.

enum LaunchAtLogin {
    /// Current registration status. `.requiresApproval` means the user must
    /// enable it under System Settings ▸ General ▸ Login Items.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Checkmark state for the menu item: on, mixed (registered but pending the
    /// user's approval), or off.
    static var menuItemState: NSControl.StateValue {
        switch status {
        case .enabled:          return .on
        case .requiresApproval: return .mixed
        default:                return .off
        }
    }

    /// Toggles registration: registers when not registered, otherwise
    /// unregisters — covering both `.enabled` and the pending `.requiresApproval`
    /// state (so a single click always flips it). Returns `false`, and logs, if
    /// the system rejected the change — e.g. an unsigned build run from a
    /// transient location.
    @discardableResult
    static func toggle() -> Bool {
        do {
            switch status {
            case .enabled, .requiresApproval: try SMAppService.mainApp.unregister()
            default:                          try SMAppService.mainApp.register()
            }
            return true
        } catch {
            NSLog("macthermal: could not change launch-at-login state: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - App
//
// The whole app lives in the status bar. SwiftUI's `MenuBarExtra` can't tell a
// left- from a right-click, so the status item is driven directly with AppKit
// (see `StatusItemController`): left-click opens the SwiftUI panel in a popover,
// right-click shows a small menu with the "Open at Login" toggle and Quit.

@main
struct MacThermalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real window — `Settings` just satisfies the `App` scene
        // requirement without showing anything (the UI is the status item).
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController()
    }
}

// MARK: - Status-item controller

@MainActor
final class StatusItemController {
    private let monitor = ThermalMonitor()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init() {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(monitor: monitor))

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "thermometer.medium",
                                   accessibilityDescription: "Temperature")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateTitle()

        // Mirror the monitor's published readings onto the menu-bar title.
        cancellable = monitor.$temps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
    }

    private func updateTitle() {
        statusItem.button?.title = " " + monitor.menuBarText
    }

    @objc private func handleClick() {
        let isRightClick = NSApp.currentEvent.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false

        if isRightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()

        let loginItem = NSMenuItem(title: "Open at Login",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLogin.menuItemState
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit macthermal",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Pop the menu up just under the button rather than assigning it to the
        // status item permanently (which would steal the left-click that opens
        // the panel).
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
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
