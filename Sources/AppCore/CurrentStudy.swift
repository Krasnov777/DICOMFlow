import Foundation

/// The study currently open in the DicomFlow viewer, published for external
/// tools — the `dicomflow-mcp` server in particular. The app overwrites one
/// small JSON manifest on every viewer load; the (un-sandboxed) MCP process
/// reads it back, so an agent can ask "what is open in the app right now?"
/// and then drive the other dicom_* tools with the manifest's file paths.
public struct CurrentStudy: Codable, Equatable {
    public var updatedAt: Date
    /// "series" (grouped series), "file" (single file), "sr" (structured
    /// report shown as text), or "directory" (ungrouped folder decode).
    public var kind: String
    public var directory: String?
    public var files: [String]
    public var seriesUID: String?
    public var seriesDescription: String?
    public var modality: String?
    public var patient: String?
    public var studyDescription: String?

    public init(updatedAt: Date = Date(), kind: String, directory: String? = nil,
                files: [String] = [], seriesUID: String? = nil,
                seriesDescription: String? = nil, modality: String? = nil,
                patient: String? = nil, studyDescription: String? = nil) {
        self.updatedAt = updatedAt
        self.kind = kind
        self.directory = directory
        self.files = files
        self.seriesUID = seriesUID
        self.seriesDescription = seriesDescription
        self.modality = modality
        self.patient = patient
        self.studyDescription = studyDescription
    }

    static let subpath = "DicomFlow/current-study.json"

    /// Where the app writes: its Application Support directory — inside the
    /// sandbox container when sandboxed, plain ~/Library when not (unsigned
    /// Debug builds carry no entitlements, so they are not sandboxed).
    public static var writeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(subpath)
    }

    /// Where an un-sandboxed reader looks: the app's sandbox container first,
    /// then the plain home location (covers Debug/unsandboxed app builds).
    public static func readCandidates(home: String = NSHomeDirectory(),
                                      bundleID: String = "com.dicombench.app") -> [URL] {
        let h = URL(fileURLWithPath: home)
        return [
            h.appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/\(subpath)"),
            h.appendingPathComponent("Library/Application Support/\(subpath)"),
        ]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Atomic write; best-effort — publishing must never break a viewer load.
    public func write(to url: URL = CurrentStudy.writeURL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try CurrentStudy.encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            // Non-fatal: external tools just won't see a manifest.
        }
    }

    public static func read(from url: URL) -> CurrentStudy? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CurrentStudy.self, from: data)
    }

    /// First readable manifest among the candidates.
    public static func readLatest(home: String = NSHomeDirectory()) -> CurrentStudy? {
        for url in readCandidates(home: home) {
            if let s = read(from: url) { return s }
        }
        return nil
    }
}
