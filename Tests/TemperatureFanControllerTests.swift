import Foundation

@main
struct TemperatureFanControllerTests {
    static func main() {
        let start = Date(timeIntervalSince1970: 0)
        var controller = TemperatureFanController()
        precondition(controller.nextAction(averageCelsius: 39, at: start) == nil)
        precondition(controller.nextAction(averageCelsius: 41, at: start.addingTimeInterval(1)) == .manual(50))
        controller.didApply(.manual(50), at: start.addingTimeInterval(1))
        precondition(controller.nextAction(averageCelsius: 50, at: start.addingTimeInterval(2)) == nil)
        precondition(controller.nextAction(averageCelsius: 50, at: start.addingTimeInterval(10)) == .manual(100))
        controller.didApply(.manual(100), at: start.addingTimeInterval(10))
        precondition(controller.nextAction(averageCelsius: 30, at: start.addingTimeInterval(20)) == .manual(50))
        controller.didApply(.manual(50), at: start.addingTimeInterval(20))
        precondition(controller.nextAction(averageCelsius: 30, at: start.addingTimeInterval(21)) == nil)
        precondition(controller.nextAction(averageCelsius: 30, at: start.addingTimeInterval(22)) == nil)
        precondition(controller.nextAction(averageCelsius: 30, at: start.addingTimeInterval(23)) == .automatic)
        controller.didApply(.automatic, at: start.addingTimeInterval(23))
        precondition(controller.nextAction(averageCelsius: nil, at: start.addingTimeInterval(24)) == nil)

        controller.reset()
        precondition(controller.nextAction(averageCelsius: 40, at: start) == .manual(50))
        controller.didApply(.manual(50), at: start)
        precondition(controller.nextAction(averageCelsius: nil, at: start.addingTimeInterval(1)) == .automatic)
        controller.reset()
        precondition(controller.nextAction(averageCelsius: 45, at: start) == .manual(100))
        print("Temperature fan controller tests passed")
    }
}
