import Foundation

/// A point-in-time CPU reading for one process. CPU may exceed 100% when a
/// process is using more than one core, matching Activity Monitor semantics.
public struct ProcessUsage: Codable, Equatable, Identifiable, Sendable {
    public let pid: Int
    public let name: String
    public let cpuPercent: Double

    public var id: String { "\(pid)-\(name)" }

    public init(pid: Int, name: String, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
    }
}
