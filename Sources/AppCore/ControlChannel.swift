import Foundation

/// Discovery record for the app's local control channel. The app listens on a
/// random loopback TCP port (token-authed, JSON-line protocol) and publishes
/// `{port, token}` here; `dicomflow-mcp` reads it to drive the running app
/// (open studies, read live viewer state, navigate). One JSON request per
/// connection: `{"token":…,"method":…,"params":{…}}\n` → one JSON reply line.
public struct ControlEndpoint: Codable, Equatable {
    public var port: UInt16
    public var token: String
    public var pid: Int32
    public var startedAt: Date

    public init(port: UInt16, token: String, pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                startedAt: Date = Date()) {
        self.port = port
        self.token = token
        self.pid = pid
        self.startedAt = startedAt
    }

    static let subpath = "DicomFlow/control.json"

    /// Where the app writes (its Application Support; container path when sandboxed).
    public static var writeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(subpath)
    }

    /// Where an un-sandboxed reader looks (container first, then plain home —
    /// unsigned Debug builds are not sandboxed).
    public static func readCandidates(home: String = NSHomeDirectory(),
                                      bundleID: String = "com.dicombench.app") -> [URL] {
        let h = URL(fileURLWithPath: home)
        return [
            h.appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/\(subpath)"),
            h.appendingPathComponent("Library/Application Support/\(subpath)"),
        ]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    /// Atomic write, owner-read-only (the token is a local credential).
    public func write(to url: URL = ControlEndpoint.writeURL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try ControlEndpoint.encoder.encode(self).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Non-fatal: external tools just can't reach the control channel.
        }
    }

    public static func read(from url: URL) -> ControlEndpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ControlEndpoint.self, from: data)
    }

    /// First endpoint among the candidates whose process is still alive.
    public static func readLatest(home: String = NSHomeDirectory()) -> ControlEndpoint? {
        for url in readCandidates(home: home) {
            if let e = read(from: url), kill(e.pid, 0) == 0 { return e }
        }
        return nil
    }

    public static func remove(at url: URL = ControlEndpoint.writeURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
