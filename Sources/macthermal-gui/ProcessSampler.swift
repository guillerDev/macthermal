import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

/// Samples Activity Monitor-style process CPU using macOS' built-in `ps`.
/// Running it inside an actor keeps the synchronous process and pipe APIs away
/// from the main actor. ThermalMonitor only invokes it for persisted history or
/// an active incident, with a 15-second minimum between process launches.
actor ProcessSampler {
    func capture(limit: Int = 8) -> [ProcessUsage] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,comm="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return parse(text).prefix(limit).map { $0 }
        } catch {
            return []
        }
    }

    private func parse(_ output: String) -> [ProcessUsage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  let pid = Int(fields[0]),
                  let cpu = Double(fields[1]) else { return nil }

            let command = String(fields[2])
            let name = URL(fileURLWithPath: command).lastPathComponent
            guard name != "ps", name != "macthermal-gui" else { return nil }
            return ProcessUsage(pid: pid, name: name, cpuPercent: cpu)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
