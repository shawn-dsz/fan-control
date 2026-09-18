import Foundation

enum TemperatureFanAction: Equatable {
    case manual(Int)
    case automatic
}

struct TemperatureFanController {
    private(set) var isCooling = false
    private(set) var requestedPercent: Int?
    private var filteredCelsius: Double?
    private var coolReadings = 0
    private var lastChangeAt: Date?

    mutating func reset(isCooling: Bool = false, requestedPercent: Int? = nil) {
        self.isCooling = isCooling
        self.requestedPercent = requestedPercent
        filteredCelsius = nil
        coolReadings = 0
        lastChangeAt = nil
    }

    mutating func nextAction(averageCelsius: Double?, at now: Date) -> TemperatureFanAction? {
        guard let averageCelsius, averageCelsius.isFinite,
              averageCelsius > 0, averageCelsius < 125 else {
            return isCooling ? .automatic : nil
        }

        let filtered = filteredCelsius.map { $0 * 0.5 + averageCelsius * 0.5 } ?? averageCelsius
        filteredCelsius = filtered
        coolReadings = filtered < 37 ? coolReadings + 1 : 0

        if isCooling && coolReadings >= 3 { return .automatic }
        guard filtered >= 40 || isCooling else { return nil }

        let percent = min(100, 50 + max(0, Int(floor(filtered - 40))) * 10)
        guard !isCooling || requestedPercent != percent else { return nil }
        if isCooling, let lastChangeAt, now.timeIntervalSince(lastChangeAt) < 8 {
            return nil
        }
        return .manual(percent)
    }

    mutating func didApply(_ action: TemperatureFanAction, at now: Date) {
        lastChangeAt = now
        switch action {
        case .manual(let percent):
            isCooling = true
            requestedPercent = percent
        case .automatic:
            isCooling = false
            requestedPercent = nil
            coolReadings = 0
        }
    }
}
