import Combine
import Foundation

/// Permissions, system integration, and user-facing errors are isolated from
/// the three-second sensor refresh path.
@MainActor
final class AppStatusState: ObservableObject {
    @Published var launchAtLogin = false
    @Published var notificationsAuthorized = false
    @Published var presentedError: UserFacingError?
}
