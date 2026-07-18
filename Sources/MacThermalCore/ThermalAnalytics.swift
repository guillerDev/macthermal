import Foundation

public enum ThermalAnalytics {
    public static func processCorrelations(
        samples: [ThermalSample],
        minimumObservations: Int = 3,
        isCancelled: () -> Bool = { false }
    ) -> [ProcessCorrelation] {
        guard samples.count >= minimumObservations else { return [] }

        struct Aggregate {
            var cpuSum = 0.0
            var cpuSquaredSum = 0.0
            var cpuTemperatureSum = 0.0
            var peakCPU = 0.0
            var observations = 0
        }

        let uniqueSamples = uniqueByProcessSnapshot(samples, isCancelled: isCancelled)
        guard uniqueSamples.count >= minimumObservations else { return [] }

        let count = Double(uniqueSamples.count)
        var temperatureSum = 0.0
        var temperatureSquaredSum = 0.0
        var aggregates: [String: Aggregate] = [:]

        for (index, sample) in uniqueSamples.enumerated() {
            if index.isMultiple(of: 256), isCancelled() { return [] }
            temperatureSum += sample.hottestCelsius
            temperatureSquaredSum += sample.hottestCelsius * sample.hottestCelsius
            // Preserve the previous first-process-per-name behavior when an app
            // has several helper processes in the same `ps` snapshot.
            var seenNames: Set<String> = []
            for process in sample.topProcesses where seenNames.insert(process.name).inserted {
                var value = aggregates[process.name, default: Aggregate()]
                value.cpuSum += process.cpuPercent
                value.cpuSquaredSum += process.cpuPercent * process.cpuPercent
                value.cpuTemperatureSum += process.cpuPercent * sample.hottestCelsius
                value.peakCPU = max(value.peakCPU, process.cpuPercent)
                if process.cpuPercent > 0 { value.observations += 1 }
                aggregates[process.name] = value
            }
        }

        guard !isCancelled() else { return [] }
        return aggregates.compactMap { name, value in
            guard value.observations >= minimumObservations else { return nil }
            let average = value.cpuSum / count
            guard average >= 0.5 else { return nil }

            let numerator = value.cpuTemperatureSum - value.cpuSum * temperatureSum / count
            let cpuVariance = max(0, value.cpuSquaredSum - value.cpuSum * value.cpuSum / count)
            let temperatureVariance = max(
                0,
                temperatureSquaredSum - temperatureSum * temperatureSum / count
            )
            let denominator = sqrt(cpuVariance * temperatureVariance)
            let coefficient = denominator > 0 ? max(-1, min(1, numerator / denominator)) : 0

            return ProcessCorrelation(
                processName: name,
                coefficient: coefficient,
                averageCPUPercent: average,
                peakCPUPercent: value.peakCPU,
                samplesObserved: value.observations
            )
        }
        .sorted {
            if $0.coefficient == $1.coefficient {
                $0.averageCPUPercent > $1.averageCPUPercent
            } else {
                $0.coefficient > $1.coefficient
            }
        }
    }

    /// Ranks processes by how much CPU they used **while the Mac was hottest**.
    ///
    /// This is the signal the "Likely Contributors" UI ranks by, because raw
    /// correlation is misleading for the common case: a process pegged at a high,
    /// *steady* CPU (the usual culprit for sustained heat) has almost no variance,
    /// so its Pearson correlation with the fluctuating temperature is ~0 or even
    /// negative — it sinks to the bottom exactly when it's the cause. Load-while-
    /// hot matches what the user sees in Activity Monitor and is directly
    /// actionable. Correlation is kept only to label the *pattern*.
    ///
    /// "Hot" is defined relative to the window (within `hotMarginCelsius` of the
    /// window's peak hotspot) so the metric adapts to the machine instead of
    /// relying on a fixed absolute threshold that never triggers on a cool laptop.
    public static func heatContributors(
        samples: [ThermalSample],
        hotMarginCelsius: Double = 10,
        minimumObservations: Int = 3,
        isCancelled: () -> Bool = { false }
    ) -> [HeatContributor] {
        guard samples.count >= minimumObservations else { return [] }
        let uniqueSamples = uniqueByProcessSnapshot(samples, isCancelled: isCancelled)
        guard uniqueSamples.count >= minimumObservations, !isCancelled() else { return [] }

        let peak = uniqueSamples.map(\.hottestCelsius).max() ?? 0
        let threshold = peak - hotMarginCelsius
        let hotSamples = uniqueSamples.filter { $0.hottestCelsius >= threshold }
        guard hotSamples.count >= minimumObservations else { return [] }

        // Correlation over the full (deduped) window — used only for the pattern.
        let coefficients = Dictionary(
            processCorrelations(samples: uniqueSamples, minimumObservations: 1, isCancelled: isCancelled)
                .map { ($0.processName, $0.coefficient) },
            uniquingKeysWith: { first, _ in first }
        )

        struct Aggregate {
            var cpuSum = 0.0
            var peak = 0.0
            var active = 0
        }
        var aggregates: [String: Aggregate] = [:]
        for (index, sample) in hotSamples.enumerated() {
            if index.isMultiple(of: 256), isCancelled() { return [] }
            var seenNames: Set<String> = []
            for process in sample.topProcesses where seenNames.insert(process.name).inserted {
                var value = aggregates[process.name, default: Aggregate()]
                value.cpuSum += process.cpuPercent
                value.peak = max(value.peak, process.cpuPercent)
                if process.cpuPercent > 0 { value.active += 1 }
                aggregates[process.name] = value
            }
        }

        guard !isCancelled() else { return [] }
        let hotCount = Double(hotSamples.count)
        return aggregates.compactMap { name, value -> HeatContributor? in
            guard value.active >= minimumObservations else { return nil }
            // Average over *all* hot samples (absent = 0 CPU), so a process pegged
            // for the whole hot period outranks one busy only part of it.
            let average = value.cpuSum / hotCount
            guard average >= 0.5 else { return nil }
            let correlation = coefficients[name] ?? 0
            let pattern: ContributionPattern = correlation >= 0.4 ? .tracksTemperature : .steadyLoad
            return HeatContributor(
                processName: name,
                hotAverageCPUPercent: average,
                peakCPUPercent: value.peak,
                hotSampleCount: value.active,
                correlation: correlation,
                pattern: pattern
            )
        }
        .sorted {
            $0.hotAverageCPUPercent != $1.hotAverageCPUPercent
                ? $0.hotAverageCPUPercent > $1.hotAverageCPUPercent
                : $0.peakCPUPercent > $1.peakCPUPercent
        }
    }

    /// Drops samples whose process reading is a duplicate of one already seen
    /// (the same `ps` snapshot copied into several thermal samples), so a single
    /// `ps` run isn't counted as multiple independent observations.
    private static func uniqueByProcessSnapshot(
        _ samples: [ThermalSample],
        isCancelled: () -> Bool
    ) -> [ThermalSample] {
        var unique: [ThermalSample] = []
        unique.reserveCapacity(samples.count)
        var seen: Set<UUID> = []
        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 256), isCancelled() { return [] }
            if let snapshotID = sample.processSnapshotID, !seen.insert(snapshotID).inserted {
                continue
            }
            unique.append(sample)
        }
        return unique
    }
}
