import Foundation

enum TempUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    var name: String { self == .celsius ? "Celsius" : "Fahrenheit" }

    func convert(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    func format(_ celsius: Double?, decimals: Int = 1) -> String {
        guard let celsius else { return "––" }
        let value = convert(celsius).formatted(.number.precision(.fractionLength(decimals)))
        return "\(value)\(symbol)"
    }
}
