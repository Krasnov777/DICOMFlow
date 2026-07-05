import Foundation
import SwiftUI
import CoreGraphics

/// In-process DICOM engine backed by DCMTK — the native replacement for the
/// Python sidecar. Same call shapes the UI already uses, but no IPC.
@MainActor
public final class DicomEngine: ObservableObject {
    /// Always ready (no external process to wait for).
    @Published public private(set) var ready = true

    public init() {
        DCMTKBridge.registerCodecs()
        Self.applyNetworkTimeout()
        Self.applyTLSConfig()
    }

    /// Push the persisted timeout into the DCMTK bridge (also called when the
    /// Settings value changes).
    public static func applyNetworkTimeout() {
        let t = UserDefaults.standard.object(forKey: "networkTimeout") as? Int ?? 15
        DCMTKNet.setNetworkTimeout(Int32(t))
    }

    /// Push the persisted DIMSE-TLS settings into the bridge.
    public static func applyTLSConfig() {
        let d = UserDefaults.standard
        let ca = d.string(forKey: "tlsCAPath") ?? ""
        DCMTKNet.setTLSEnabled(d.bool(forKey: "dimseTLS"),
                               verifyPeer: d.bool(forKey: "tlsVerify"),
                               caFile: ca.isEmpty ? nil : ca)
    }

    /// Lets existing call sites that used `sidecar.client?.…` keep working.
    public var client: DicomEngine? { self }

    public enum EngineError: LocalizedError {
        case noImages
        case decodeFailed(String)
        public var errorDescription: String? {
            switch self {
            case .noImages: return "No DICOM image instances found."
            case .decodeFailed(let m): return m
            }
        }
    }

    // MARK: - Tags

    public func readTags(path: String) async throws -> ReadTagsResponse {
        try await Task.detached(priority: .userInitiated) {
            let raw = try DCMTKBridge.readTags(path)
            let tags = raw.map {
                TagItem(tag: $0["tag"] ?? "", keyword: $0["keyword"] ?? "",
                        name: $0["name"] ?? "", vr: $0["vr"] ?? "", value: $0["value"] ?? "")
            }
            return ReadTagsResponse(path: path,
                                    transferSyntax: DCMTKBridge.transferSyntaxName(path),
                                    count: tags.count, tags: tags)
        }.value
    }

    public func transferSyntax(path: String) -> String? {
        DCMTKBridge.transferSyntaxName(path)
    }

    /// One attribute's IOD-conformance result (from dcmtk's dcmiod rule engine).
    public struct IODAttribute: Sendable, Identifiable {
        public let module: String
        public let tag: String
        public let name: String
        public let type: String      // "1" or "2"
        public let ok: Bool
        public let message: String
        public var id: String { module + tag }
    }

    public struct ValidationResult: Sendable {
        public let ok: Bool
        public let errors: [String]
        public let warnings: [String]
        public let info: [String: String]
        public let iodModules: [IODAttribute]
    }

    /// Validate a DICOM file for conformance: Part-10 meta, required UIDs, UID
    /// format, SOP class, per-element VR — plus authoritative type-1/2 module
    /// checks via dcmtk's dcmiod rule engine (Patient/Study/Series/Equipment/
    /// SOP Common + General Image).
    public func validate(path: String) async -> ValidationResult {
        await Task.detached(priority: .userInitiated) {
            let d = DCMTKBridge.validateFile(path)
            let iod = (d["iodModules"] as? [[String: Any]] ?? []).map { m in
                IODAttribute(module: m["module"] as? String ?? "",
                             tag: m["tag"] as? String ?? "",
                             name: m["name"] as? String ?? "",
                             type: m["type"] as? String ?? "",
                             ok: (m["ok"] as? NSNumber)?.boolValue ?? false,
                             message: m["message"] as? String ?? "")
            }
            return ValidationResult(
                ok: (d["ok"] as? NSNumber)?.boolValue ?? false,
                errors: d["errors"] as? [String] ?? [],
                warnings: d["warnings"] as? [String] ?? [],
                info: (d["info"] as? [String: String]) ?? [:],
                iodModules: iod)
        }.value
    }

    public struct GenerateResult: Sendable {
        public let success: Bool
        public let count: Int
        public let dir: String
        public let files: [String]
        public let message: String
    }

    /// Generate a synthetic DICOM series (a stackable volume) into `dir`.
    public func generateDataset(dir: String, sopClass: String, rows: Int, columns: Int,
                                slices: Int, pattern: String) async -> GenerateResult {
        await Task.detached(priority: .userInitiated) {
            let d = DCMTKBridge.generateDataset(toDir: dir, sopClass: sopClass,
                                                rows: Int32(rows), columns: Int32(columns),
                                                slices: Int32(slices), pattern: pattern)
            return GenerateResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                                  count: (d["count"] as? NSNumber)?.intValue ?? 0,
                                  dir: d["dir"] as? String ?? dir,
                                  files: d["files"] as? [String] ?? [],
                                  message: d["message"] as? String ?? "")
        }.value
    }

    /// Render a file's first frame to a display CGImage (windowed gray or RGB) —
    /// for preview / OCR. Nil if it can't be rendered.
    public func renderDisplayImage(path: String) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let d = DCMTKBridge.renderDisplay8(path),
                  let data = d["data"] as? Data,
                  let rows = (d["rows"] as? NSNumber)?.intValue,
                  let cols = (d["columns"] as? NSNumber)?.intValue,
                  let samples = (d["samples"] as? NSNumber)?.intValue,
                  let provider = CGDataProvider(data: data as CFData) else { return nil }
            let space = samples == 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray()
            return CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 8 * samples,
                           bytesPerRow: cols * samples, space: space,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }.value
    }

    public struct RedactResult: Sendable { public let success: Bool; public let message: String }

    /// Black out pixel regions (rects = [x,y,w,h] normalized, top-left) and save.
    public func redact(path: String, rects: [[Double]], outputPath: String) async -> RedactResult {
        await Task.detached(priority: .userInitiated) {
            let nsRects = rects.map { $0.map { NSNumber(value: $0) } }
            let d = DCMTKBridge.redactFile(path, rects: nsRects, outputPath: outputPath)
            return RedactResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                                message: d["message"] as? String ?? "")
        }.value
    }

    /// A dcmdump-style structural dump of a DICOM file (nil if unreadable).
    public func dump(path: String) async -> String? {
        await Task.detached(priority: .userInitiated) { DCMTKBridge.dumpFile(path) }.value
    }

    /// Parse a DICOMDIR file into its Patient → Study → Series hierarchy.
    public func readDicomDir(path: String) async -> DicomDirResult {
        await Task.detached(priority: .userInitiated) {
            let d = DCMTKBridge.readDicomDir(path)
            let patients = (d["patients"] as? [[String: Any]] ?? []).map { p in
                DicomDirPatient(
                    name: p["name"] as? String ?? "",
                    patientID: p["patientID"] as? String ?? "",
                    studies: (p["studies"] as? [[String: Any]] ?? []).map { st in
                        DicomDirStudy(
                            uid: st["uid"] as? String ?? "",
                            date: st["date"] as? String ?? "",
                            description: st["description"] as? String ?? "",
                            series: (st["series"] as? [[String: Any]] ?? []).map { se in
                                DicomDirSeries(
                                    uid: se["uid"] as? String ?? "",
                                    modality: se["modality"] as? String ?? "",
                                    number: se["number"] as? String ?? "",
                                    description: se["description"] as? String ?? "",
                                    files: se["files"] as? [String] ?? [])
                            })
                    })
            }
            return DicomDirResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                                  message: d["message"] as? String ?? "",
                                  baseDir: d["baseDir"] as? String ?? "",
                                  patients: patients)
        }.value
    }

    /// Render a Structured Report (SR) instance to readable text.
    public func readReport(path: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try DCMTKBridge.readReportText(path)
        }.value
    }

    // MARK: - Viewer

    /// One series discovered by a fast metadata scan.
    public struct SeriesInfo: Identifiable, Sendable {
        public let id: String          // SeriesInstanceUID
        public let description: String
        public let modality: String
        public let seriesNumber: String
        public let patient: String
        public let studyDescription: String
        public let files: [String]
        public var count: Int { files.count }
    }

    /// Fast metadata-only scan of a folder, grouped into series.
    public func scanSeries(directory: String) async -> [SeriesInfo] {
        await Task.detached(priority: .userInitiated) {
            DCMTKBridge.scanSeries(directory).map { g in
                SeriesInfo(id: g["seriesUID"] as? String ?? UUID().uuidString,
                           description: g["description"] as? String ?? "",
                           modality: g["modality"] as? String ?? "",
                           seriesNumber: g["seriesNumber"] as? String ?? "",
                           patient: g["patient"] as? String ?? "",
                           studyDescription: g["studyDescription"] as? String ?? "",
                           files: (g["files"] as? [String]) ?? [])
            }
        }.value
    }

    /// A small axial thumbnail (rendered middle slice) for a series.
    public func thumbnail(files: [String], size: Int = 96) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard !files.isEmpty,
                  let dict = try? DCMTKBridge.decodeFile(files[files.count / 2]),
                  let slice = DecodedSlice(dict),
                  let built = SliceStacker.buildVolume([slice]) else { return nil }
            let meta = VolumeMeta(dims: [built.nx, built.ny, built.nz],
                                  spacing: [built.sx, built.sy, built.sz], origin: built.origin,
                                  orientation: slice.orientation.map { Float($0) },
                                  slope: Float(slice.slope), intercept: Float(slice.intercept),
                                  defaultWindowCenter: Float(slice.windowCenter),
                                  defaultWindowWidth: Float(slice.windowWidth),
                                  valueMin: 0, valueMax: 0, modality: slice.modality,
                                  seriesCount: 1, warnings: [])
            guard let vol = Volume(meta: meta, data: built.data) else { return nil }
            return MPRPlaneRenderer.renderOffscreen(volume: vol, axis: .axial, sliceFrac: 0.5,
                                                    winCenter: Float(slice.windowCenter),
                                                    winWidth: Float(slice.windowWidth), size: size)
        }.value
    }

    public func decodeVolume(directory: String) async throws -> Volume {
        try await decodeVolume(files: Self.enumerateFiles(directory))
    }

    /// Decode a color image (US/RGB/YBR) → a ColorImage, or nil if the file is
    /// grayscale (caller should then use the grayscale volume path).
    public func decodeColorImage(path: String) async -> ColorImage? {
        await Task.detached(priority: .userInitiated) {
            guard let dict = try? DCMTKBridge.decodeFile(path),
                  (dict["samplesPerPixel"] as? NSNumber)?.intValue == 3,
                  let rgb = dict["rgb"] as? Data,
                  let rows = (dict["rows"] as? NSNumber)?.intValue,
                  let cols = (dict["columns"] as? NSNumber)?.intValue else { return nil }
            let frames = (dict["frames"] as? NSNumber)?.intValue ?? 1
            let modality = dict["modality"] as? String ?? ""
            return ColorImage.fromRGB8(rgb, width: cols, height: rows, frames: frames, modality: modality)
        }.value
    }

    /// Decode + stack a series into a Volume. Kept serial: DCMTK serializes the
    /// decode internally (the global dictionary lock is taken per element), so
    /// parallelizing measured ~1.05× on 12 cores. Perceived load is handled by the
    /// progressive coarse-preview path instead.
    public func decodeVolume(files inputFiles: [String]) async throws -> Volume {
        try await Task.detached(priority: .userInitiated) {
            let files = inputFiles
            var slices: [DecodedSlice] = []
            slices.reserveCapacity(files.count)
            for f in files {
                guard let dict = try? DCMTKBridge.decodeFile(f) else { continue }
                let frames = (dict["frames"] as? NSNumber)?.intValue ?? 1
                if frames > 1 {
                    slices.append(contentsOf: DecodedSlice.expandFrames(dict, frames: frames))
                } else if let s = DecodedSlice(dict) {
                    slices.append(s)
                }
            }
            guard !slices.isEmpty else { throw EngineError.noImages }

            let groups = Dictionary(grouping: slices, by: { $0.seriesUID })
            guard let chosen = groups.values.max(by: { $0.count < $1.count }),
                  let first = chosen.first,
                  let built = SliceStacker.buildVolume(chosen) else {
                throw EngineError.decodeFailed("could not assemble volume")
            }

            // stored-value range
            var lo = Int16.max, hi = Int16.min
            built.data.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Int16.self)
                for v in p { if v < lo { lo = v }; if v > hi { hi = v } }
            }

            var warnings: [String] = []
            if groups.count > 1 { warnings.append("\(groups.count) series found; showing the largest") }
            if built.resampled { warnings.append("non-uniform slice spacing; resampled to uniform z") }

            let meta = VolumeMeta(
                dims: [built.nx, built.ny, built.nz],
                spacing: [built.sx, built.sy, built.sz],
                origin: built.origin,
                orientation: first.orientation.map { Float($0) },
                slope: Float(first.slope), intercept: Float(first.intercept),
                defaultWindowCenter: Float(first.windowCenter),
                defaultWindowWidth: Float(first.windowWidth),
                valueMin: Int(lo), valueMax: Int(hi),
                modality: first.modality, seriesCount: groups.count, warnings: warnings)

            guard let vol = Volume(meta: meta, data: built.data) else {
                throw EngineError.decodeFailed("unsupported volume size or pixel format")
            }
            return vol
        }.value
    }

    // MARK: - Edit / Anonymize

    public func editTags(path: String, edits: [EditOp], outputPath: String) async throws -> EditTagsResult {
        try await Task.detached(priority: .userInitiated) {
            let ops: [[String: Any]] = edits.map {
                ["keyword": $0.keyword, "value": $0.value ?? NSNull()]
            }
            let r = try DCMTKBridge.editTags(path, edits: ops as [[String: Any]], outputPath: outputPath)
            let applied = (r["applied"] as? [[String: String]]) ?? []
            let skipped = (r["skipped"] as? [[String: String]]) ?? []
            return EditTagsResult(success: true,
                                  outputPath: (r["outputPath"] as? String) ?? outputPath,
                                  applied: applied, skipped: skipped)
        }.value
    }

    public func anonymize(directory: String, outputDir: String, profile: AnonProfileDTO) async throws -> AnonResult {
        try await Task.detached(priority: .userInitiated) {
            let files = Self.enumerateFiles(directory)
            let prof: [String: Any] = [
                "replacePatientName": profile.replacePatientName ?? NSNull(),
                "replacePatientID": profile.replacePatientID ?? NSNull(),
                "clearDates": profile.clearDates,
                "clearIdentifiers": profile.clearIdentifiers,
                "removePrivateTags": profile.removePrivateTags,
                "regenerateUIDs": profile.regenerateUIDs,
                "basicProfile": profile.basicProfile,
                "retainDates": profile.retainDates,
                "retainDeviceIdentity": profile.retainDeviceIdentity,
                "retainPatientChars": profile.retainPatientChars,
                "cleanDescriptors": profile.cleanDescriptors,
            ]
            let r = try DCMTKBridge.anonymize(files, outputDir: outputDir, profile: prof)
            return AnonResult(success: true,
                              processed: (r["processed"] as? NSNumber)?.intValue ?? 0,
                              outputDir: outputDir,
                              uidsRemapped: (r["uidsRemapped"] as? NSNumber)?.intValue ?? 0,
                              warnings: (r["warnings"] as? [String]) ?? [])
        }.value
    }

    // MARK: - Networking

    /// Where the built-in SCP and C-GET/C-MOVE deposit received instances.
    public nonisolated static let receivedDir = NSTemporaryDirectory() + "dicomflow_received"

    public func echo(host: String, port: Int, aeTitle: String, callingAE: String) async throws -> EchoResult {
        let r = try await Task.detached {
            let d = DCMTKNet.echo(toHost: host, port: Int32(port), calledAE: aeTitle, callingAE: callingAE)
            return EchoResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                              message: d["message"] as? String,
                              echoStatus: (d["echoStatus"] as? NSNumber)?.intValue,
                              supportedSOPClasses: d["sopClasses"] as? [String])
        }.value
        LogStore.shared.log("C-ECHO → \(aeTitle)@\(host):\(port): " +
            (r.success ? "verified" : (r.message ?? "failed")), r.success ? .ok : .error)
        return r
    }

    public func store(host: String, port: Int, aeTitle: String, paths: [String], callingAE: String) async throws -> StoreResult {
        let r = try await Task.detached {
            let d = DCMTKNet.storeFiles(paths, toHost: host, port: Int32(port), calledAE: aeTitle, callingAE: callingAE)
            return StoreResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                               message: d["message"] as? String,
                               sent: (d["sent"] as? NSNumber)?.intValue,
                               total: (d["total"] as? NSNumber)?.intValue, results: nil)
        }.value
        LogStore.shared.log("C-STORE → \(aeTitle)@\(host):\(port): sent \(r.sent ?? 0)/\(r.total ?? 0)",
                            (r.sent ?? 0) == (r.total ?? -1) ? .ok : .warn)
        return r
    }

    public func query(host: String, port: Int, aeTitle: String, level: String, filters: [String: String], callingAE: String) async throws -> QueryResult {
        let r = try await Task.detached {
            let d = DCMTKNet.queryHost(host, port: Int32(port), calledAE: aeTitle, callingAE: callingAE, level: level, filters: filters)
            return QueryResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                               message: d["message"] as? String,
                               count: (d["count"] as? NSNumber)?.intValue,
                               results: d["results"] as? [[String: String]])
        }.value
        LogStore.shared.log("C-FIND \(level) → \(aeTitle)@\(host): " +
            (r.success ? "\(r.count ?? 0) result(s)" : (r.message ?? "failed")), r.success ? .ok : .error)
        return r
    }

    /// C-FIND on the Modality Worklist Information Model.
    public func worklistQuery(host: String, port: Int, aeTitle: String, filters: [String: String], callingAE: String) async throws -> QueryResult {
        let r = try await Task.detached {
            let d = DCMTKNet.worklistQueryHost(host, port: Int32(port), calledAE: aeTitle, callingAE: callingAE, filters: filters)
            return QueryResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                               message: d["message"] as? String,
                               count: (d["count"] as? NSNumber)?.intValue,
                               results: d["results"] as? [[String: String]])
        }.value
        LogStore.shared.log("C-FIND MWL → \(aeTitle)@\(host): " +
            (r.success ? "\(r.count ?? 0) item(s)" : (r.message ?? "failed")), r.success ? .ok : .error)
        return r
    }

    /// Negotiation probe: which SOP classes / transfer syntaxes does the peer accept?
    public func probeContexts(host: String, port: Int, aeTitle: String, callingAE: String) async throws -> ProbeResult {
        let r = try await Task.detached {
            let d = DCMTKNet.probeContextsHost(host, port: Int32(port), calledAE: aeTitle, callingAE: callingAE)
            let rows = (d["results"] as? [[String: Any]] ?? []).map { row in
                ProbeContext(sopClass: row["sopClass"] as? String ?? "",
                             sopName: row["sopName"] as? String ?? "",
                             accepted: (row["accepted"] as? NSNumber)?.boolValue ?? false,
                             transferSyntaxes: row["transferSyntaxes"] as? [String] ?? [])
            }
            return ProbeResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                               message: d["message"] as? String, contexts: rows)
        }.value
        let ok = r.contexts.filter { $0.accepted }.count
        LogStore.shared.log("Probe → \(aeTitle)@\(host): " +
            (r.success ? "\(ok)/\(r.contexts.count) SOP classes accepted" : (r.message ?? "failed")),
            r.success ? .ok : .error)
        return r
    }

    public func retrieve(host: String, port: Int, aeTitle: String, level: String, keys: [String: String], method: String, moveDestination: String?, callingAE: String) async throws -> RetrieveResult {
        let dir = Self.receivedDir
        let r = try await Task.detached {
            let d = DCMTKNet.retrieve(fromHost: host, port: Int32(port), calledAE: aeTitle, callingAE: callingAE,
                                      level: level, keys: keys, method: method,
                                      moveDest: moveDestination, outputDir: dir)
            return RetrieveResult(success: (d["success"] as? NSNumber)?.boolValue ?? false,
                                  message: d["message"] as? String, method: method,
                                  received: (d["received"] as? NSNumber)?.intValue,
                                  receivedDir: d["receivedDir"] as? String ?? dir)
        }.value
        LogStore.shared.log("C-\(method.uppercased()) → \(aeTitle)@\(host): received \(r.received ?? 0)",
                            r.success ? .ok : .error)
        return r
    }

    public func scpStart(aeTitle: String, port: Int, enforceCalledAE: Bool = true) async throws -> SCPStatus {
        let dir = Self.receivedDir
        return try await Task.detached {
            _ = DCMTKNet.startSCP(withAETitle: aeTitle, port: Int32(port), outputDir: dir,
                                  enforceCalledAE: enforceCalledAE)
            return try await self.scpStatus()
        }.value
    }
    public func scpStop() async throws -> SCPStatus {
        _ = await Task.detached { DCMTKNet.stopSCP() }.value
        return try await scpStatus()
    }
    public func scpStatus() async throws -> SCPStatus {
        let dir = Self.receivedDir
        return await Task.detached {
            let s = DCMTKNet.scpStatus()
            let count = (try? FileManager.default.contentsOfDirectory(atPath: dir).count) ?? 0
            return SCPStatus(running: (s["running"] as? NSNumber)?.boolValue ?? false,
                             aeTitle: s["aeTitle"] as? String ?? "DICOMBENCH",
                             port: (s["port"] as? NSNumber)?.intValue ?? 0,
                             receivedCount: count, receivedDir: dir)
        }.value
    }
    public func scpReceived() async throws -> ReceivedList {
        let dir = Self.receivedDir
        return await Task.detached {
            let items = (DCMTKNet.scpReceived(from: dir)).map {
                ReceivedItem(path: $0["path"] as? String ?? "", patient: $0["patient"] as? String ?? "",
                             studyUID: $0["studyUID"] as? String ?? "", seriesUID: $0["seriesUID"] as? String ?? "",
                             sopUID: $0["sopUID"] as? String ?? "", modality: $0["modality"] as? String ?? "")
            }
            return ReceivedList(receivedDir: dir, items: items)
        }.value
    }

    nonisolated static func enumerateFiles(_ directory: String) -> [String] {
        let url = URL(fileURLWithPath: directory)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return [directory] }
        var out: [String] = []
        if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let f as URL in en where !f.hasDirectoryPath {
                if f.lastPathComponent.lowercased() == "dicomdir" { continue }
                out.append(f.path)
            }
        }
        return out
    }
}
