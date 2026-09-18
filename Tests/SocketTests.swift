import Darwin
import Foundation

@main
struct SocketTests {
    static func main() throws {
        let path = "/tmp/fancontrol-test-\(getpid()).sock"
        defer { unlink(path) }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(server >= 0)
        defer { close(server) }
        var serverAddress = try FanSocket.address(path: path)
        precondition(FanSocket.withSockAddr(&serverAddress, { bind(server, $0, $1) }) == 0)
        precondition(listen(server, 1) == 0)

        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(client >= 0)
        defer { close(client) }
        var clientAddress = try FanSocket.address(path: path)
        precondition(FanSocket.withSockAddr(&clientAddress, { connect(client, $0, $1) }) == 0)
        let accepted = accept(server, nil, nil)
        precondition(accepted >= 0)
        defer { close(accepted) }
        var uid: uid_t = 0
        var gid: gid_t = 0
        precondition(getpeereid(accepted, &uid, &gid) == 0 && uid == getuid())
        print("Socket tests passed")
    }
}
