import Foundation

struct CPUTemperatureSample {
    let averageCelsius: Double
    let peakCelsius: Double
    let coreCount: Int
}

enum CPUTemperatureParser {
    // Stats identifies these M5 SMC keys as CPU core temperature sensors.
    private static let coreKeys: Set<String> = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
        "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
    ]

    static func parse(_ output: String) -> CPUTemperatureSample? {
        var readings: [String: Double] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2,
                  parts[0].first == "[", parts[0].last == "]",
                  let value = Double(parts[1]), value.isFinite,
                  value > 0, value < 125 else { continue }
            let key = String(parts[0].dropFirst().dropLast())
            if coreKeys.contains(key) { readings[key] = value }
        }
        guard readings.count >= 4, let peak = readings.values.max() else { return nil }
        let average = readings.values.reduce(0, +) / Double(readings.count)
        return CPUTemperatureSample(averageCelsius: average, peakCelsius: peak, coreCount: readings.count)
    }
}
