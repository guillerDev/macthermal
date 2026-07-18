import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

/// Owns the non-Sendable IOKit connection so sensor access never crosses an
/// isolation boundary or blocks the main actor.
actor SMCReader {
    private let smc: SMC?

    init() {
        smc = try? SMC()
    }

    var available: Bool { smc != nil }

    func capture() -> Snapshot? {
        guard let smc else { return nil }
        return Snapshot.capture(smc)
    }
}
