import Foundation

@main
struct FanTemperatureEstimatorTests {
    static func main() {
        let points = [
            FanTemperaturePoint(percent: 0, averageCelsius: 65),
            FanTemperaturePoint(percent: 50, averageCelsius: 55),
            FanTemperaturePoint(percent: 100, averageCelsius: 50)
        ]
        precondition(FanTemperatureEstimator.calibratedTemperature(at: 25, points: points) == 60)
        precondition(FanTemperatureEstimator.calibratedTemperature(at: 75, points: points) == 52.5)
        let estimate = FanTemperatureEstimator.range(
            selectedPercent: 100, referencePercent: 0, currentCelsius: 45, points: points
        )!
        precondition(estimate.contains(37) && !estimate.contains(45))
        let at50 = FanTemperatureEstimator.range(
            selectedPercent: 50, referencePercent: 0, currentCelsius: 45, points: points
        )!
        precondition(estimate.lowerBound <= at50.lowerBound && estimate.upperBound <= at50.upperBound)
        let calibration = FanTemperatureEstimator.calibrationPoints
        precondition(calibration[0].averageCelsius > calibration[1].averageCelsius)
        precondition(calibration[1].averageCelsius > calibration[2].averageCelsius)
        precondition(FanTemperatureEstimator.range(
            selectedPercent: 100, referencePercent: 0, currentCelsius: 45, points: []
        ) == nil)
        let fans = [
            Fan(id: 0, name: "Left fan", actual: 3350, minimum: 1350, maximum: 5349, target: 3350, isAutomatic: false),
            Fan(id: 1, name: "Right fan", actual: 3564, minimum: 1350, maximum: 5777, target: 3564, isAutomatic: false)
        ]
        precondition(abs(FanTemperatureEstimator.manualPercent(for: fans)! - 50) < 0.1)
        print("Fan temperature estimator tests passed")
    }
}
