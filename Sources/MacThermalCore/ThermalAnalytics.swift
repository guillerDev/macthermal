import Foundation

public enum ThermalAnalytics {
    public static func processCorrelations(
        samples: [ThermalSample],
        minimumObservations: Int = 3
    ) -> [ProcessCorrelation] {
        guard samples.count >= minimumObservations else { return [] }

        struct Aggregate {
            var cpuSum = 0.0
            var cpuSquaredSum = 0.0
            var cpuTemperatureSum = 0.0
            var peakCPU = 0.0
            var observations = 0
        }

        let count = Double(samples.count)
        let temperatureSum = samples.reduce(0) { $0 + $1.hottestCelsius }
        let temperatureSquaredSum = samples.reduce(0) { $0 + $1.hottestCelsius * $1.hottestCelsius }
        var aggregates: [String: Aggregate] = [:]

        for sample in samples {
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

}
