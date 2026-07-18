import Foundation

/// Serializes daemon-backed login-item calls away from the main actor.
actor LoginItemManager {
    func isEnabled() -> Bool {
        LaunchAtLogin.isEnabled
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        LaunchAtLogin.setEnabled(enabled)
        return LaunchAtLogin.isEnabled
    }
}
