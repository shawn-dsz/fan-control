import Foundation

struct Fan: Identifiable, Equatable {
    let id: Int
    let name: String
    let actual: Int
    let minimum: Int
    let maximum: Int
    let target: Int
    let isAutomatic: Bool
}

enum FanParser {
    static func fillUnavailableReadings(in fans: [Fan], from output: String) -> [Fan] {
        var readings: [String: Int] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2,
                  parts[0].first == "[", parts[0].last == "]",
                  let value = number(String(parts[1])), value > 0 else { continue }
            let key = String(parts[0].dropFirst().dropLast())
            readings[key] = value
        }
        return fans.map { fan in
            Fan(id: fan.id, name: fan.name,
                actual: fan.actual >= 0 ? fan.actual : readings["F\(fan.id)Ac"] ?? -1,
                minimum: fan.minimum, maximum: fan.maximum,
                target: fan.target >= 0 ? fan.target : readings["F\(fan.id)Tg"] ?? -1,
                isAutomatic: fan.isAutomatic)
        }
    }

    static func parse(_ output: String) -> [Fan] {
        var fans: [Fan] = []
        var fields: [String: String] = [:]
        var currentID: Int?
        var currentName = ""

        func appendCurrent() {
            guard let id = currentID,
                  let actual = number(fields["Actual speed"]),
                  let minimum = number(fields["Minimal speed"]),
                  let maximum = number(fields["Maximum speed"]),
                  let target = number(fields["Target speed"]),
                  let mode = fields["Mode"], minimum >= 0, maximum > minimum else { return }
            fans.append(Fan(id: id, name: currentName, actual: actual,
                            minimum: minimum, maximum: maximum, target: target,
                            isAutomatic: mode == "automatic"))
        }

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if let id = Int(key) {
                appendCurrent()
                currentID = id
                currentName = value
                fields = [:]
            } else if currentID != nil {
                fields[key] = value
            }
        }
        appendCurrent()
        return fans
    }

    private static func number(_ value: String?) -> Int? {
        guard let value, let number = Double(value), number.isFinite, number >= -1 else { return nil }
        return Int(number.rounded())
    }
}
