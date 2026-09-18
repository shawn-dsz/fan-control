import Foundation

@main
struct SpeedPlanTests {
    static func main() {
        let fans = [
            Fan(id: 0, name: "Fan #0", actual: 1350, minimum: 1350, maximum: 5349, target: 1350, isAutomatic: true),
            Fan(id: 1, name: "Fan #1", actual: 1458, minimum: 1350, maximum: 5777, target: 1458, isAutomatic: true)
        ]
        precondition(FanSpeedPlan.targets(for: fans, percent: 0) == [0: 1350, 1: 1350])
        precondition(FanSpeedPlan.targets(for: fans, percent: 50) == [0: 3350, 1: 3564])
        precondition(FanSpeedPlan.targets(for: fans, percent: 100) == [0: 5349, 1: 5777])
        let targets = FanSpeedPlan.targets(for: fans, percent: 50)
        let stale = [
            Fan(id: 0, name: "Fan #0", actual: 1350, minimum: 1350, maximum: 5349, target: 3350, isAutomatic: false),
            Fan(id: 1, name: "Fan #1", actual: 1458, minimum: 1350, maximum: 5777, target: 1458, isAutomatic: false)
        ]
        precondition(!FanSpeedPlan.matches(stale, targets: targets))
        let settled = [stale[0], Fan(id: 1, name: "Fan #1", actual: 1458, minimum: 1350, maximum: 5777, target: 3564, isAutomatic: false)]
        precondition(FanSpeedPlan.matches(settled, targets: targets))
        print("Speed plan tests passed")
    }
}
