import AppKit
import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

@main
struct MacThermalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var monitor: ThermalMonitor

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: ThermalMonitor(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor, settings: settings)
                .environmentObject(monitor.liveState)
                .environmentObject(monitor.archiveState)
                .environmentObject(monitor.recordingState)
                .environmentObject(monitor.statusState)
        } label: {
            MenuBarLabelView(settings: settings)
                .environmentObject(monitor.liveState)
                .onAppear {
                    appDelegate.prepareForTermination = { [weak monitor] in
                        await monitor?.prepareForTermination()
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("MacThermal Pro", id: "dashboard") {
            DashboardView(monitor: monitor, settings: settings)
                .environmentObject(monitor.liveState)
                .environmentObject(monitor.archiveState)
                .environmentObject(monitor.recordingState)
                .environmentObject(monitor.statusState)
                .frame(minWidth: 860, minHeight: 580)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(monitor: monitor, settings: settings)
                .environmentObject(monitor.archiveState)
                .environmentObject(monitor.statusState)
        }
    }
}
