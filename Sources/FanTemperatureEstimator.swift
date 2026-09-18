import Foundation

struct FanTemperaturePoint {
    let percent: Double
    let averageCelsius: Double
}

enum FanTemperatureEstimator {
    // Approximate room-temperature reference for scaling measured cooling effects.
    private static let referenceCelsius = 25.0
    // Measured on this M5 Pro MacBook Pro with four low-priority CPU workers,
    // after two minutes at each fan setting on 17 September 2026.
    static let calibrationPoints: [FanTemperaturePoint] = [
        FanTemperaturePoint(percent: 0, averageCelsius: 62.38),
        FanTemperaturePoint(percent: 50, averageCelsius: 54.64),
        FanTemperaturePoint(percent: 100, averageCelsius: 51.49)
    ]

    static func calibratedTemperature(at percent: Double, points: [FanTemperaturePoint]) -> Double? {
        let sorted = points.sorted { $0.percent < $1.percent }
        guard sorted.count >= 2,
              let first = sorted.first,
              let last = sorted.last else { return nil }
        let selected = min(last.percent, max(first.percent, percent))
        for (lower, upper) in zip(sorted, sorted.dropFirst()) where selected <= upper.percent {
            guard upper.percent > lower.percent else { return nil }
            let fraction = (selected - lower.percent) / (upper.percent - lower.percent)
            return lower.averageCelsius + (upper.averageCelsius - lower.averageCelsius) * fraction
        }
        return last.averageCelsius
    }

    static func range(
        selectedPercent: Double,
        referencePercent: Double,
        currentCelsius: Double,
        points: [FanTemperaturePoint]
    ) -> ClosedRange<Int>? {
        guard currentCelsius.isFinite,
              currentCelsius > referenceCelsius,
              let selected = calibratedTemperature(at: selectedPercent, points: points),
              let baseline = calibratedTemperature(at: referencePercent, points: points),
              selected > referenceCelsius, baseline > referenceCelsius else { return nil }
        let predicted = referenceCelsius + (currentCelsius - referenceCelsius) *
            (selected - referenceCelsius) / (baseline - referenceCelsius)
        let margin = max(5.0, abs(predicted - currentCelsius) * 0.25 + 4.0)
        return Int(floor(predicted - margin))...Int(ceil(predicted + margin))
    }

    static func manualPercent(for fans: [Fan]) -> Double? {
        guard !fans.isEmpty, fans.allSatisfy({ !$0.isAutomatic }) else { return nil }
        let percentages = fans.compactMap { fan -> Double? in
            guard fan.target >= fan.minimum, fan.maximum > fan.minimum else { return nil }
            return Double(fan.target - fan.minimum) / Double(fan.maximum - fan.minimum) * 100
        }
        guard percentages.count == fans.count else { return nil }
        return percentages.reduce(0, +) / Double(percentages.count)
    }
}
