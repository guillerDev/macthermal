import Foundation
import UserNotifications
#if canImport(MacThermalCore)
import MacThermalCore
#endif

actor LocalNotificationManager {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func send(_ reason: ThermalAlertReason) async {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch reason {
        case .sustainedTemperature(let celsius):
            content.title = "Mac temperature alert"
            content.body = "The hotspot has remained at \(celsius.formatted(.number.precision(.fractionLength(1))))°C or higher."
        case .thermalPressure(let state):
            content.title = "Thermal throttling detected"
            content.body = "macOS reports \(state) thermal pressure and may reduce performance."
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
