import Darwin
import Foundation

enum FanSocket {
    static func path(uid: uid_t) -> String {
        "/private/var/run/local.shawndsouza.fancontrol.\(uid).sock"
    }

    static func address(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8CString)
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= maxLength else {
            throw SocketError.message("Socket path is too long")
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { target in
                target.withMemoryRebound(to: CChar.self, capacity: maxLength) {
                    _ = strncpy($0, source, maxLength)
                }
            }
        }
        return address
    }

    static func withSockAddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    enum SocketError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let message) = self { return message }
            return nil
        }
    }
}
