import Foundation
import Darwin

// Duskie's version-1 local status protocol (shared/MemoryPressure.h).
struct DuskieMemoryStatus {
    let state: UInt32
    let bytes: UInt64
    let target: UInt64
    let error: Int32
    let pid: Int32
    var active: Bool { (1...3).contains(state) }
    var title: String { ["Idle", "Filling", "Held", "Releasing", "Failed"][Int(state)] }

    static func decode(_ data: Data) throws -> Self {
        guard data.count == 32 else { throw POSIXError(.EPROTO) }
        func value(_ start: Int, _ length: Int) -> UInt64 {
            (0..<length).reduce(0) { $0 | UInt64(data[start + $1]) << ($1 * 8) }
        }
        let version = value(0, 4), state = value(4, 4)
        let bytes = value(8, 8), target = value(16, 8)
        guard version == 1, state <= 4, bytes <= target else { throw POSIXError(.EPROTO) }
        return Self(state: UInt32(state), bytes: bytes, target: target,
                    error: Int32(bitPattern: UInt32(value(24, 4))), pid: Int32(bitPattern: UInt32(value(28, 4))))
    }

    static func read() throws -> Self {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = "/var/mobile/Library/Caches/com.dusklinux.duskie.memory.sock".utf8CString
        path.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: source) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            let code = errno
            if code == ENOENT || code == ECONNREFUSED {
                return Self(state: 0, bytes: 0, target: 2_147_483_648, error: 0, pid: 0)
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        var data = Data(count: 32)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count > 0 { offset += count }
                else if count < 0 && errno == EINTR { continue }
                else { throw POSIXError(count == 0 ? .ECONNRESET : POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
        }
        return try decode(data)
    }
}
