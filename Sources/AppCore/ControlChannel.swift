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
    /// Written 0600-from-birth: temp file in the same dir, chmod, then rename —
    /// no window where another user could read the token.
    public func write(to url: URL = ControlEndpoint.writeURL) {
        do {
            try secureAtomicWrite(ControlEndpoint.encoder.encode(self), to: url)
        } catch {
            // Non-fatal: external tools just can't reach the control channel.
        }
    }

    public static func read(from url: URL) -> ControlEndpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ControlEndpoint.self, from: data)
    }

    /// Endpoints whose process is still alive, newest first. Callers should try
    /// each in order — a pid can be reused by an unrelated process, so liveness
    /// here is a hint and only a successful connect is proof.
    public static func aliveEndpoints(home: String = NSHomeDirectory()) -> [ControlEndpoint] {
        readCandidates(home: home)
            .compactMap { read(from: $0) }
            .filter { kill($0.pid, 0) == 0 }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Newest live endpoint (see `aliveEndpoints`).
    public static func readLatest(home: String = NSHomeDirectory()) -> ControlEndpoint? {
        aliveEndpoints(home: home).first
    }

    /// Remove the published endpoint — but only if it is OURS. Two instances
    /// (e.g. Debug + Release) share the discovery path; the first to quit must
    /// not delete the survivor's live endpoint.
    public static func removeIfMine(at url: URL = ControlEndpoint.writeURL) {
        guard let e = read(from: url),
              e.pid == ProcessInfo.processInfo.processIdentifier else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Write `data` to `url` atomically with 0600 permissions from the first byte:
/// create a temp file in the destination directory with a restrictive mode,
/// write, then rename over the target.
func secureAtomicWrite(_ data: Data, to url: URL) throws {
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: tmp.path, contents: nil,
                                         attributes: [.posixPermissions: 0o600]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    do {
        let h = try FileHandle(forWritingTo: tmp)
        try h.write(contentsOf: data)
        try h.close()
        // usingNewMetadataOnly: keep the temp file's 0600 — the default
        // preserves the REPLACED file's permissions (e.g. a pre-existing 644).
        // replaceItemAt requires an existing destination; first write = move.
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp,
                                                      options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    } catch {
        try? FileManager.default.removeItem(at: tmp)
        throw error
    }
}
