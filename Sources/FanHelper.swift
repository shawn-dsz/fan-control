import Darwin
import Foundation

private enum HelperFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

private enum SMC {
    static let executable = "/Library/PrivilegedHelperTools/local.shawndsouza.FanControl.smc"

    static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 || output.contains("[ERROR]") || output.localizedCaseInsensitiveContains("write failed") || output.contains("Error write") || output.contains("Error read") {
            throw HelperFailure.message(output.isEmpty ? "SMC command failed" : output)
        }
        return output
    }

    static func fans() throws -> [Fan] {
        let fans = FanParser.parse(try run(["fans"]))
        guard !fans.isEmpty else { throw HelperFailure.message("No fans were reported") }
        return fans
    }

    static func automatic(_ fans: [Fan]) throws {
        for fan in fans { _ = try run(["fan", String(fan.id), "-m", "0"]) }
        let after = try self.fans()
        guard after.count == fans.count && after.allSatisfy(\.isAutomatic) else {
            throw HelperFailure.message("Could not return both fans to Automatic")
        }
    }

    static func manual(percent: Int) throws {
        guard (0...100).contains(percent) else { throw HelperFailure.message("Invalid percentage") }
        let before = try fans()
        let targets = FanSpeedPlan.targets(for: before, percent: percent)
        do {
            for fan in before {
                guard let rpm = targets[fan.id] else { throw HelperFailure.message("Missing fan target") }
                _ = try run(["fan", String(fan.id), "-v", String(rpm)])
            }
            // On this Mac, the second fan's mode can change before its target RPM is readable.
            var lastReading: [Fan] = []
            for _ in 0..<20 {
                lastReading = try fans()
                if FanSpeedPlan.matches(lastReading, targets: targets) { return }
                usleep(100_000)
            }
            let details = lastReading.map { fan in
                "fan \(fan.id): mode \(fan.isAutomatic ? "automatic" : "manual"), target \(fan.target), expected \(targets[fan.id] ?? -1)"
            }.joined(separator: "; ")
            throw HelperFailure.message("Fan speeds did not settle (\(details))")
        } catch {
            try? automatic(before)
            throw error
        }
    }
}

@main
struct FanHelper {
    static func main() {
        guard geteuid() == 0, CommandLine.arguments.count == 2,
              let number = UInt32(CommandLine.arguments[1]) else { exit(1) }
        let owner = uid_t(number)
        let path = FanSocket.path(uid: owner)
        guard let address = try? FanSocket.address(path: path) else { exit(2) }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0 else { exit(3) }
        defer { close(server) }
        unlink(path)
        var mutableAddress = address
        guard FanSocket.withSockAddr(&mutableAddress, { bind(server, $0, $1) }) == 0,
              chown(path, owner, gid_t.max) == 0,
              chmod(path, 0o600) == 0,
              listen(server, 8) == 0 else { exit(4) }

        while true {
            let client = accept(server, nil, nil)
            if client < 0 { continue }
            handle(client, owner: owner)
            close(client)
        }
    }

    private static func handle(_ client: Int32, owner: uid_t) {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == owner else {
            respond(client, "ERROR Unauthorized")
            return
        }
        var buffer = [UInt8](repeating: 0, count: 128)
        let count = read(client, &buffer, buffer.count)
        guard count > 0, count < buffer.count else {
            respond(client, "ERROR Invalid request")
            return
        }
        let command = String(decoding: buffer.prefix(count), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch command {
            case "ping": break
            case "automatic": try SMC.automatic(SMC.fans())
            default:
                let parts = command.split(separator: " ")
                guard parts.count == 2, parts[0] == "manual", let percent = Int(parts[1]) else {
                    throw HelperFailure.message("Unknown command")
                }
                try SMC.manual(percent: percent)
            }
            respond(client, "OK")
        } catch {
            let message = error.localizedDescription.replacingOccurrences(of: "\n", with: " ")
            respond(client, "ERROR \(message)")
        }
    }

    private static func respond(_ client: Int32, _ message: String) {
        let bytes = Array((message + "\n").utf8)
        _ = bytes.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}
