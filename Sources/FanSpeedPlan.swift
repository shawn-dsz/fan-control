import Foundation

enum FanSpeedPlan {
    static func targets(for fans: [Fan], percent: Int) -> [Int: Int] {
        let fraction = Double(min(100, max(0, percent))) / 100
        return Dictionary(uniqueKeysWithValues: fans.map { fan in
            let rpm = Double(fan.minimum) + Double(fan.maximum - fan.minimum) * fraction
            return (fan.id, Int(rpm.rounded()))
        })
    }

    static func matches(_ fans: [Fan], targets: [Int: Int]) -> Bool {
        fans.count == targets.count && fans.allSatisfy { fan in
            guard let expected = targets[fan.id], !fan.isAutomatic else { return false }
            return fan.target < 0 || abs(fan.target - expected) <= 50
        }
    }
}
