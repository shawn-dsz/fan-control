import Foundation

@main
struct ParserTests {
    static func main() throws {
        let sample = """
        Number of fans: 2.0

        0: Fan #0
        Actual speed: 1345.0
        Minimal speed: 1350.0
        Maximum speed: 5349.0
        Target speed: 1350.0
        Mode: automatic

        1: Fan #1
        Actual speed: 2450.0
        Minimal speed: 1350.0
        Maximum speed: 5777.0
        Target speed: 2400.0
        Mode: forced
        """
        let fans = FanParser.parse(sample)
        precondition(fans.count == 2)
        precondition(fans[0].id == 0 && fans[0].actual == 1345 && fans[0].minimum == 1350)
        precondition(fans[0].maximum == 5349 && fans[0].isAutomatic)
        precondition(fans[1].id == 1 && fans[1].target == 2400 && !fans[1].isAutomatic)
        precondition(FanParser.parse("not fan data").isEmpty)
        let unavailable = sample
            .replacingOccurrences(of: "1345.0", with: "-1.0")
            .replacingOccurrences(of: "1350.0\nMode:", with: "-1.0\nMode:")
        let unavailableFans = FanParser.parse(unavailable)
        precondition(unavailableFans.count == 2)
        precondition(unavailableFans[0].actual == -1 && unavailableFans[0].target == -1)
        let keyOutput = """
        [F0Ac]     1351.0
        [F0Tg]     1350.0
        [F1Ac]     1463.0
        [F1Tg]     1458.0
        """
        let recovered = FanParser.fillUnavailableReadings(in: unavailableFans, from: keyOutput)
        precondition(recovered[0].actual == 1351 && recovered[0].target == 1350)
        precondition(recovered[1].actual == 2450 && recovered[1].target == 2400)
        let zeroKeys = """
        [F0Ac]     0.0
        [F0Tg]     0.0
        """
        let stillUnavailable = FanParser.fillUnavailableReadings(in: unavailableFans, from: zeroKeys)
        precondition(stillUnavailable[0].actual == -1 && stillUnavailable[0].target == -1)
        print("Parser tests passed")
    }
}
