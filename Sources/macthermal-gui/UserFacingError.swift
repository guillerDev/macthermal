import Foundation

struct UserFacingError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "MacThermal Pro", message: String) {
        self.title = title
        self.message = message
    }
}
