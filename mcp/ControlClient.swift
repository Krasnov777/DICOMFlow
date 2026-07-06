import Foundation

/// Client side of the app's loopback control channel (see ControlEndpoint /
/// ControlServer). Synchronous by design — the MCP server loop is synchronous.
enum ControlClient {
    struct NotRunning: Error, LocalizedError {
        var errorDescription: String? {
            "The DicomFlow app is not running (no live control endpoint). "
            + "Ask the user to launch DicomFlow — or use dicom_current_study, which reports "
            + "the last study the app had open, and works app-closed."
        }
    }
    struct Failed: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One request → one JSON reply. Tries each live endpoint newest-first —
    /// a stale discovery file (pid reused by an unrelated process) must not
    /// mask a live app publishing at the other candidate path.
    static func call(_ method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        let endpoints = ControlEndpoint.aliveEndpoints()
        guard !endpoints.isEmpty else { throw NotRunning() }
        for ep in endpoints {
            if let fd = connectLoopback(port: ep.port) {
                defer { close(fd) }
                return try exchange(fd: fd, endpoint: ep, method: method, params: params)
            }
        }
        throw NotRunning()   // endpoints published but nothing accepting
    }

    private static func connectLoopback(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var yes: Int32 = 1   // a peer reset must error the call, not SIGPIPE the process
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 { close(fd); return nil }
        return fd
    }

    private static func exchange(fd: Int32, endpoint ep: ControlEndpoint,
                                 method: String, params: [String: Any]) throws -> [String: Any] {

        var req: [String: Any] = ["token": ep.token, "method": method]
        if !params.isEmpty { req["params"] = params }
        var payload = try JSONSerialization.data(withJSONObject: req)
        payload.append(0x0A)
        let sent = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == payload.count else { throw Failed(message: "short write to control channel") }

        var buf = Data(), chunk = [UInt8](repeating: 0, count: 65536)
        while !buf.contains(0x0A) {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buf.append(contentsOf: chunk[0..<n])
            if buf.count > 1 << 22 { throw Failed(message: "oversized control reply") }
        }
        guard let nl = buf.firstIndex(of: 0x0A),
              let obj = (try? JSONSerialization.jsonObject(with: buf[..<nl])) as? [String: Any] else {
            throw Failed(message: "no/invalid reply from the app's control channel")
        }
        if let ok = obj["ok"] as? Bool, !ok {
            throw Failed(message: obj["error"] as? String ?? "control command failed")
        }
        return obj
    }
}
