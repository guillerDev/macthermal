import AppKit

@MainActor
enum SettingsWindowOpener {
    static func openLegacy() {
        let application = NSApplication.shared
        let selectors = ["showPreferencesWindow:", "showSettingsWindow:"]
        for name in selectors where application.sendAction(Selector((name)), to: nil, from: nil) {
            application.activate(ignoringOtherApps: true)
            return
        }
        NSLog("macthermal: could not open Settings — no known selector responded (macOS may have renamed it).")
    }
}
