import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, .notRegistered), (true, .notFound):
                try SMAppService.mainApp.register()
            case (false, .enabled), (false, .requiresApproval):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
            return true
        } catch {
            NSLog("macthermal: could not change launch-at-login state: \(error.localizedDescription)")
            return false
        }
    }
}
