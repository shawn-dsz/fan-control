import Foundation

@main
struct CPUTemperatureParserTests {
    static func main() {
        let sample = """
        [Tp00]     40.0
        [Tp04]     42.0
        [Tp0O]     38.0
        [Tp0R]     39.0
        [Tp08]     0.0
        [TVMX]     61.0
        """
        guard let result = CPUTemperatureParser.parse(sample) else {
            preconditionFailure("Expected a CPU temperature sample")
        }
        precondition(result.coreCount == 4)
        precondition(abs(result.averageCelsius - 39.75) < 0.01)
        precondition(result.peakCelsius == 42)
        precondition(CPUTemperatureParser.parse("[Tp00] 40.0\n[Tp04] 41.0") == nil)
        print("CPU temperature parser tests passed")
    }
}
