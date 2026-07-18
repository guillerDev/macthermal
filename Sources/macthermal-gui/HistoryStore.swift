import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

actor HistoryStore {
    private let directory: URL
    private let historyURL: URL
    private let incidentsURL: URL
    private let pruneStampURL: URL
    private var lastPruneAt: Date?
    private var latestIncidentRevision = 0
    private let pruneInterval: TimeInterval = 24 * 60 * 60

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "MacThermal", directoryHint: .isDirectory)
        let pruneStampURL = directory.appending(path: ".last-history-prune")
        self.directory = directory
        historyURL = directory.appending(path: "history.ndjson")
        incidentsURL = directory.appending(path: "incidents.json")
        self.pruneStampURL = pruneStampURL
        lastPruneAt = Self.loadPruneDate(from: pruneStampURL)
    }

    func load(retentionDays: Int) -> (samples: [ThermalSample], incidents: [ThermalIncident]) {
        createDirectoryIfNeeded()
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .distantPast
        let decoder = JSONDecoder()

        let samples = (try? loadSamples(since: cutoff, decoder: decoder)) ?? []

        let incidents = (try? Data(contentsOf: incidentsURL))
            .flatMap { try? decoder.decode([ThermalIncident].self, from: $0) } ?? []
        return (samples, incidents.sorted { $0.startedAt > $1.startedAt })
    }

    func append(_ sample: ThermalSample, retentionDays: Int) throws {
        createDirectoryIfNeeded()
        var data = try JSONEncoder().encode(sample)
        data.append(0x0A)

        if FileManager.default.fileExists(atPath: historyURL.path) {
            let handle = try FileHandle(forWritingTo: historyURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: historyURL, options: .atomic)
        }

        if lastPruneAt.map({ Date.now.timeIntervalSince($0) >= pruneInterval }) ?? true {
            try prune(retentionDays: retentionDays)
            let now = Date.now
            lastPruneAt = now
            try? persistPruneDate(now)
        }
    }

    func saveIncidents(_ incidents: [ThermalIncident], revision: Int) throws {
        guard revision >= latestIncidentRevision else { return }
        createDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(incidents).write(to: incidentsURL, options: .atomic)
        latestIncidentRevision = revision
    }

    func clearHistory() throws {
        if FileManager.default.fileExists(atPath: historyURL.path) {
            try FileManager.default.removeItem(at: historyURL)
        }
    }

    nonisolated var storageDirectory: URL { directory }

    private func prune(retentionDays: Int) throws {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .distantPast
        if let oldestTimestamp = try oldestSampleTimestamp(), oldestTimestamp >= cutoff { return }

        let temporaryURL = directory.appending(path: "history-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let output = try FileHandle(forWritingTo: temporaryURL)
        var outputClosed = false
        defer {
            if !outputClosed { try? output.close() }
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let decoder = JSONDecoder()
        let newline = Data([0x0A])
        try forEachHistoryLine { line in
            guard let envelope = try? decoder.decode(TimestampEnvelope.self, from: line),
                  envelope.timestamp >= cutoff else { return }
            try output.write(contentsOf: line)
            try output.write(contentsOf: newline)
        }
        try output.synchronize()
        try output.close()
        outputClosed = true
        _ = try FileManager.default.replaceItemAt(historyURL, withItemAt: temporaryURL)
    }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func loadSamples(since cutoff: Date, decoder: JSONDecoder) throws -> [ThermalSample] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        var samples: [ThermalSample] = []
        try forEachHistoryLine { line in
            guard let sample = try? decoder.decode(ThermalSample.self, from: line),
                  sample.timestamp >= cutoff else { return }
            samples.append(sample)
        }
        return samples
    }

    private func oldestSampleTimestamp() throws -> Date? {
        let input = try FileHandle(forReadingFrom: historyURL)
        defer { try? input.close() }
        guard let chunk = try input.read(upToCount: 64 * 1_024), !chunk.isEmpty else { return nil }
        let end = chunk.firstIndex(of: 0x0A) ?? chunk.endIndex
        guard end > chunk.startIndex else { return nil }
        let line = chunk.subdata(in: chunk.startIndex..<end)
        return try? JSONDecoder().decode(TimestampEnvelope.self, from: line).timestamp
    }

    private func forEachHistoryLine(_ body: (Data) throws -> Void) throws {
        let input = try FileHandle(forReadingFrom: historyURL)
        defer { try? input.close() }
        var buffer = Data()

        while let chunk = try input.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                if newline > lineStart {
                    try body(buffer.subdata(in: lineStart..<newline))
                }
                lineStart = buffer.index(after: newline)
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
        }

        if !buffer.isEmpty { try body(buffer) }
    }

    private func persistPruneDate(_ date: Date) throws {
        try Data(String(date.timeIntervalSince1970).utf8).write(to: pruneStampURL, options: .atomic)
    }

    private static func loadPruneDate(from url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let interval = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}

private struct TimestampEnvelope: Decodable {
    let timestamp: Date
}
