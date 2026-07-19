import Foundation

/// Serializes daemon-backed login-item calls away from the main actor.
actor LoginItemManager {
    func isEnabled() -> Bool {
        LaunchAtLogin.isEnabled
    }

    func setEnabled(_ enabled: Bool) -> (succeeded: Bool, isEnabled: Bool) {
        let succeeded = LaunchAtLogin.setEnabled(enabled)
        return (succeeded, LaunchAtLogin.isEnabled)
    }
}
