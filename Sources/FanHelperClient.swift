import Darwin
import Foundation

enum FanHelperClient {
    static func send(_ command: String) throws {
        let path = FanSocket.path(uid: getuid())
        var address = try FanSocket.address(path: path)
        let connection = socket(AF_UNIX, SOCK_STREAM, 0)
        guard connection >= 0 else { throw FanSocket.SocketError.message("Could not open fan helper connection") }
        defer { close(connection) }
        guard FanSocket.withSockAddr(&address, { connect(connection, $0, $1) }) == 0 else {
            throw FanSocket.SocketError.message("Fan helper is not installed. Use Enable control once.")
        }
        let request = Array((command + "\n").utf8)
        let sent = request.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
        guard sent == request.count else { throw FanSocket.SocketError.message("Could not send fan request") }
        var buffer = [UInt8](repeating: 0, count: 2048)
        let received = read(connection, &buffer, buffer.count)
        guard received > 0 else { throw FanSocket.SocketError.message("Fan helper did not respond") }
        let response = String(decoding: buffer.prefix(received), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if response == "OK" { return }
        if response.hasPrefix("ERROR ") {
            throw FanSocket.SocketError.message(String(response.dropFirst(6)))
        }
        throw FanSocket.SocketError.message("Unexpected fan helper response")
    }

    static func isReady() -> Bool {
        (try? send("ping")) != nil
    }

    static func install() throws {
        guard let resources = Bundle.main.resourceURL else {
            throw FanSocket.SocketError.message("App resources are missing")
        }
        let script = resources.appendingPathComponent("install-helper.sh").path
        guard FileManager.default.fileExists(atPath: script) else {
            throw FanSocket.SocketError.message("Helper installer is missing")
        }
        let command = "/bin/zsh \(shellQuote(script)) \(getuid())"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw FanSocket.SocketError.message(output.isEmpty ? "Helper installation was cancelled or failed" : output)
        }
        for _ in 0..<20 {
            if isReady() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw FanSocket.SocketError.message("Helper installed but did not start")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
