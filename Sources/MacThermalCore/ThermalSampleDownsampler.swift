import Foundation

/// Reduces chart density while preserving endpoints and the hottest/coolest
/// sample in each time bucket. Summaries and exports continue using full data.
public enum ThermalSampleDownsampler {
    public static func samples(
        from samples: [ThermalSample],
        maximumCount: Int,
        isCancelled: () -> Bool = { false }
    ) -> [ThermalSample] {
        guard maximumCount > 0, !samples.isEmpty else { return [] }
        guard samples.count > maximumCount else { return samples }
        if maximumCount == 1 { return [samples[samples.count - 1]] }
        if maximumCount == 2 { return [samples[0], samples[samples.count - 1]] }
        if maximumCount == 3 {
            let hottestInterior = samples[1..<(samples.count - 1)].max {
                $0.hottestCelsius < $1.hottestCelsius
            } ?? samples[1]
            return [samples[0], hottestInterior, samples[samples.count - 1]]
        }

        let lastIndex = samples.count - 1
        let bucketCount = max(1, (maximumCount - 2) / 2)
        let interiorCount = lastIndex - 1
        let bucketWidth = Double(interiorCount) / Double(bucketCount)
        var reduced = [samples[0]]
        reduced.reserveCapacity(maximumCount)

        for bucket in 0..<bucketCount {
            if bucket.isMultiple(of: 64), isCancelled() { return [] }
            let lower = 1 + Int((Double(bucket) * bucketWidth).rounded(.down))
            let upper = min(
                lastIndex,
                1 + Int((Double(bucket + 1) * bucketWidth).rounded(.down))
            )
            guard lower < upper else { continue }

            var minimumIndex = lower
            var maximumIndex = lower
            for index in (lower + 1)..<upper {
                if index.isMultiple(of: 512), isCancelled() { return [] }
                if samples[index].hottestCelsius < samples[minimumIndex].hottestCelsius {
                    minimumIndex = index
                }
                if samples[index].hottestCelsius > samples[maximumIndex].hottestCelsius {
                    maximumIndex = index
                }
            }

            if minimumIndex == maximumIndex {
                reduced.append(samples[minimumIndex])
            } else {
                reduced.append(samples[min(minimumIndex, maximumIndex)])
                reduced.append(samples[max(minimumIndex, maximumIndex)])
            }
        }

        reduced.append(samples[lastIndex])
        return reduced
    }
}
