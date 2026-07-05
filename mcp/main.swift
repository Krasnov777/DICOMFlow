// DicomFlow MCP server — exposes the native DICOM engine as agent tools over
// the Model Context Protocol (stdio, newline-delimited JSON-RPC 2.0).
//
// Reuses the same DCMTK bridge as the app (DicomNative) with none of the SwiftUI/
// Metal layers. Read-only + network-read tools are always available; mutating
// tools (store/anonymize/retrieve) require --allow-write (added in a later slice).
//
// Transport contract: every JSON-RPC message is one UTF-8 line on stdin; every
// response is one line on stdout. NOTHING else may go to stdout — logs go to
// stderr, or the client's JSON parser breaks.

import Foundation

// MARK: - I/O

let allowWrite = CommandLine.arguments.contains("--allow-write")

func logErr(_ s: String) {
    FileHandle.standardError.write(Data(("[dicomflow-mcp] " + s + "\n").utf8))
}

let out = FileHandle.standardOutput
func send(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
    out.write(data)
    out.write(Data("\n".utf8))
}
func reply(id: Any, result: Any) { send(["jsonrpc": "2.0", "id": id, "result": result]) }
func replyError(id: Any?, code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
}

/// A tool result is a `content` array; text items carry pretty-printed JSON or plain text.
func textContent(_ s: String) -> [String: Any] { ["type": "text", "text": s] }
func imageContent(_ png: Data) -> [String: Any] {
    ["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]
}
func jsonString(_ value: Any) -> String {
    if let d = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
       let s = String(data: d, encoding: .utf8) { return s }
    return "\(value)"
}

// MARK: - Tool catalog

func obj(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
    ["type": "object", "properties": properties, "required": required]
}
let strProp: [String: Any] = ["type": "string"]
let intProp: [String: Any] = ["type": "integer"]

let tools: [[String: Any]] = [
    ["name": "dicom_current_study",
     "description": "What is open in the DicomFlow app viewer right now. Returns the study the user is looking at — kind (series/file/sr/directory), patient, modality, series description/UID, and the local file paths — so you can feed them straight into dicom_render_slice, dicom_read_tags, etc. The app publishes this whenever a study is loaded; errors if the app hasn't opened anything yet.",
     "inputSchema": obj([:])],

    ["name": "dicom_viewer_state",
     "description": "Live state of the running DicomFlow app's viewer: layout, plane, slice index/count, window/level, zoom, loaded series (with UIDs) and file paths. Requires the app to be running; if it isn't, fall back to dicom_current_study.",
     "inputSchema": obj([:])],

    ["name": "dicom_viewer_open",
     "description": "Open a study in the running DicomFlow app's viewer (brings the app to front). Give a `path` (single DICOM file) or `directory` (series folder; optional `seriesUID` picks a series). Note: the sandboxed app can read user-opened locations, its own container, and temp dirs — not arbitrary files.",
     "inputSchema": obj(["path": strProp, "directory": strProp, "seriesUID": strProp])],

    ["name": "dicom_viewer_goto",
     "description": "Navigate the running DicomFlow app's viewer: `plane` (axial|coronal|sagittal), `sliceIndex` (0-based) or `sliceFraction` (0…1), `windowCenter`/`windowWidth`, `layout` (2D|MPR|3D|Compare), or switch series with `seriesUID`. Returns the resulting viewer state.",
     "inputSchema": obj(["plane": ["type": "string", "enum": ["axial", "coronal", "sagittal"]],
                         "sliceIndex": intProp, "sliceFraction": ["type": "number"],
                         "windowCenter": ["type": "number"], "windowWidth": ["type": "number"],
                         "layout": ["type": "string", "enum": ["2D", "MPR", "3D", "Compare"]],
                         "seriesUID": strProp])],

    ["name": "dicom_read_tags",
     "description": "Read every DICOM data element of a file (tag, name, VR, value, keyword). Use to inspect a study's metadata.",
     "inputSchema": obj(["path": strProp], required: ["path"])],

    ["name": "dicom_validate",
     "description": "Validate a DICOM file for basic Part-10 conformance (required UIDs/format, SOP class, image attributes, per-element VR). Returns ok, errors, warnings, info.",
     "inputSchema": obj(["path": strProp], required: ["path"])],

    ["name": "dicom_read_report",
     "description": "Render a DICOM Structured Report (SR) as readable text — e.g. a Radiation Dose report. Non-SR files return an error.",
     "inputSchema": obj(["path": strProp], required: ["path"])],

    ["name": "dicom_series_info",
     "description": "Scan a folder and group its DICOM files into series (SeriesInstanceUID) — returns per-series modality, description, instance count, and first file.",
     "inputSchema": obj(["directory": strProp], required: ["directory"])],

    ["name": "dicom_render_slice",
     "description": "Render a DICOM slice to a PNG image you can look at. Axial: give a single-file `path`, OR a `directory` (optionally `seriesUID`, else the largest series) with a slice `index` (default middle). Reslice: set `plane` to coronal | sagittal | oblique with a `directory` — the whole series is stacked into a volume and resliced (`position` 0…1 picks the slice; `oblique` also takes `angle` degrees, rotating a vertical plane in the axial plane). `window`/`level` override defaults; `frame` selects a frame in multi-frame files (axial); `maxSize` caps the longest side (default 512).",
     "inputSchema": obj(["path": strProp, "directory": strProp, "seriesUID": strProp,
                         "plane": ["type": "string", "enum": ["axial", "coronal", "sagittal", "oblique"]],
                         "index": intProp, "position": ["type": "number"], "angle": ["type": "number"],
                         "frame": intProp,
                         "window": ["type": "number"], "level": ["type": "number"],
                         "maxSize": intProp])],

    ["name": "dicom_echo",
     "description": "C-ECHO (verification) to a DICOM node — confirms connectivity and association negotiation.",
     "inputSchema": obj(["host": strProp, "port": intProp, "calledAE": strProp, "callingAE": strProp],
                        required: ["host", "port", "calledAE"])],

    ["name": "dicom_query",
     "description": "C-FIND (study-root query/retrieve) against a PACS. level = STUDY | SERIES | IMAGE; filters is a map of DICOM keyword → match value (e.g. {\"PatientID\":\"620548472\"}). Read-only.",
     "inputSchema": obj(["host": strProp, "port": intProp, "calledAE": strProp, "callingAE": strProp,
                         "level": ["type": "string", "enum": ["STUDY", "SERIES", "IMAGE"]],
                         "filters": ["type": "object", "additionalProperties": strProp]],
                        required: ["host", "port", "calledAE", "level"])],

    ["name": "dicom_web_query",
     "description": "DICOMweb QIDO-RS query. level = studies | series | instances. For series pass studyUID; for instances pass studyUID + seriesUID. filters is a keyword→value map (studies level). baseURL like http://host:8042/dicom-web; optional username/password (Basic auth). Read-only.",
     "inputSchema": obj(["baseURL": strProp,
                         "level": ["type": "string", "enum": ["studies", "series", "instances"]],
                         "studyUID": strProp, "seriesUID": strProp,
                         "filters": ["type": "object", "additionalProperties": strProp],
                         "username": strProp, "password": strProp],
                        required: ["baseURL", "level"])],
]

/// Mutating / retrieving tools — only listed and callable with --allow-write.
let writeTools: [[String: Any]] = [
    ["name": "dicom_store",
     "description": "C-STORE files to a PACS (uploads local DICOM). Provide `paths` (files) or a `directory`. Requires --allow-write.",
     "inputSchema": obj(["host": strProp, "port": intProp, "calledAE": strProp, "callingAE": strProp,
                         "paths": ["type": "array", "items": strProp], "directory": strProp],
                        required: ["host", "port", "calledAE"])],

    ["name": "dicom_retrieve",
     "description": "C-GET/C-MOVE from a PACS to a local folder. method = GET | MOVE (MOVE needs moveDest). level + keys identify what to pull (e.g. level STUDY, keys {\"StudyInstanceUID\":\"…\"}). Writes files to outputDir. Requires --allow-write.",
     "inputSchema": obj(["host": strProp, "port": intProp, "calledAE": strProp, "callingAE": strProp,
                         "level": ["type": "string", "enum": ["STUDY", "SERIES", "IMAGE"]],
                         "keys": ["type": "object", "additionalProperties": strProp],
                         "method": ["type": "string", "enum": ["GET", "MOVE"]],
                         "moveDest": strProp, "outputDir": strProp],
                        required: ["host", "port", "calledAE", "level", "keys", "outputDir"])],

    ["name": "dicom_anonymize",
     "description": "De-identify DICOM files to a new folder (source untouched). Provide `paths` or `directory` + `outputDir`. Options: replacePatientName, replacePatientID, clearDates, clearIdentifiers, removePrivateTags, regenerateUIDs. Requires --allow-write.",
     "inputSchema": obj(["paths": ["type": "array", "items": strProp], "directory": strProp,
                         "outputDir": strProp,
                         "replacePatientName": strProp, "replacePatientID": strProp,
                         "clearDates": ["type": "boolean"], "clearIdentifiers": ["type": "boolean"],
                         "removePrivateTags": ["type": "boolean"], "regenerateUIDs": ["type": "boolean"]],
                        required: ["outputDir"])],
]

let allTools = allowWrite ? tools + writeTools : tools

// MARK: - Tool dispatch

/// Run an async op to completion from the synchronous server loop. Safe because
/// the ops here (DicomWebClient) are NOT @MainActor — the detached task runs on a
/// background thread while the main thread blocks, so there's no actor deadlock.
func runSync<T>(_ op: @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    var outcome: Result<T, Error>!
    Task.detached {
        do { outcome = .success(try await op()) }
        catch { outcome = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try outcome.get()
}

func str(_ args: [String: Any], _ key: String) -> String { (args[key] as? String) ?? "" }
func int32(_ args: [String: Any], _ key: String, default def: Int32 = 0) -> Int32 {
    if let n = args[key] as? Int { return Int32(n) }
    if let n = args[key] as? NSNumber { return n.int32Value }
    if let s = args[key] as? String, let n = Int32(s) { return n }
    return def
}

func text(_ s: String, isError: Bool = false) -> (content: [[String: Any]], isError: Bool) {
    ([textContent(s)], isError)
}

func callTool(_ name: String, _ args: [String: Any]) -> (content: [[String: Any]], isError: Bool) {
    switch name {
    case "dicom_viewer_state":
        do { return text(jsonString(try ControlClient.call("viewer_state"))) }
        catch { return text(error.localizedDescription, isError: true) }

    case "dicom_viewer_open":
        var p: [String: Any] = [:]
        if let v = args["path"] as? String { p["path"] = v }
        if let v = args["directory"] as? String { p["directory"] = v }
        if let v = args["seriesUID"] as? String { p["seriesUID"] = v }
        guard !p.isEmpty else { return text("give a path or directory", isError: true) }
        do { return text(jsonString(try ControlClient.call("open_study", params: p))) }
        catch { return text(error.localizedDescription, isError: true) }

    case "dicom_viewer_goto":
        var p: [String: Any] = [:]
        for k in ["plane", "layout", "seriesUID"] { if let v = args[k] as? String { p[k] = v } }
        if let v = args["sliceIndex"] as? Int { p["sliceIndex"] = v }
        for k in ["sliceFraction", "windowCenter", "windowWidth"] {
            if let v = args[k] as? NSNumber { p[k] = v.doubleValue }
        }
        do { return text(jsonString(try ControlClient.call("viewer_goto", params: p))) }
        catch { return text(error.localizedDescription, isError: true) }

    case "dicom_current_study":
        guard let s = CurrentStudy.readLatest() else {
            return text("No study is published. Open a study in the DicomFlow app first — the viewer writes a manifest on every load.", isError: true)
        }
        var out: [String: Any] = [
            "kind": s.kind,
            "updatedAt": ISO8601DateFormatter().string(from: s.updatedAt),
            "ageSeconds": Int(Date().timeIntervalSince(s.updatedAt)),
            "files": s.files,
            "fileCount": s.files.count,
        ]
        if let v = s.directory { out["directory"] = v }
        if let v = s.seriesUID { out["seriesUID"] = v }
        if let v = s.seriesDescription { out["seriesDescription"] = v }
        if let v = s.modality { out["modality"] = v }
        if let v = s.patient { out["patient"] = v }
        if let v = s.studyDescription { out["studyDescription"] = v }
        return text(jsonString(out))

    case "dicom_read_tags":
        let path = str(args, "path")
        do {
            let tags = try DCMTKBridge.readTags(path)
            let ts = DCMTKBridge.transferSyntaxName(path) ?? "?"
            return text(jsonString(["transferSyntax": ts, "count": tags.count, "tags": tags]))
        } catch {
            return text("Could not read \(path) as DICOM: \(error.localizedDescription)", isError: true)
        }

    case "dicom_validate":
        return text(jsonString(DCMTKBridge.validateFile(str(args, "path"))))

    case "dicom_read_report":
        do { return text(try DCMTKBridge.readReportText(str(args, "path"))) }
        catch { return text(error.localizedDescription, isError: true) }

    case "dicom_series_info":
        let series = DCMTKBridge.scanSeries(str(args, "directory"))
        return text(jsonString(["count": series.count, "series": series]))

    case "dicom_echo":
        let r = DCMTKNet.echo(toHost: str(args, "host"), port: int32(args, "port", default: 104),
                              calledAE: str(args, "calledAE"),
                              callingAE: args["callingAE"] as? String ?? "DICOMBENCH")
        return text(jsonString(r), isError: (r["success"] as? Bool) != true)

    case "dicom_query":
        let filters = (args["filters"] as? [String: String]) ?? [:]
        let r = DCMTKNet.queryHost(str(args, "host"), port: int32(args, "port", default: 104),
                                   calledAE: str(args, "calledAE"),
                                   callingAE: args["callingAE"] as? String ?? "DICOMBENCH",
                                   level: str(args, "level").isEmpty ? "STUDY" : str(args, "level"),
                                   filters: filters)
        return text(jsonString(r), isError: (r["success"] as? Bool) != true)

    case "dicom_render_slice":
        return renderSlice(args)

    case "dicom_web_query":
        let client = DicomWebClient(baseURL: str(args, "baseURL"),
                                    username: str(args, "username"), password: str(args, "password"))
        do {
            let rows: [[String: String]]
            switch str(args, "level") {
            case "series":
                rows = try runSync { try await client.querySeries(studyUID: str(args, "studyUID")) }
            case "instances":
                rows = try runSync { try await client.queryInstances(studyUID: str(args, "studyUID"),
                                                                     seriesUID: str(args, "seriesUID")) }
            default:
                rows = try runSync { try await client.queryStudies(filters: (args["filters"] as? [String: String]) ?? [:]) }
            }
            return text(jsonString(["count": rows.count, "results": rows]))
        } catch {
            return text("DICOMweb query failed: \(error.localizedDescription)", isError: true)
        }

    // ---- write-gated (require --allow-write) ----
    case "dicom_store":
        guard allowWrite else { return text("dicom_store requires the server to be launched with --allow-write.", isError: true) }
        let files = collectFiles(args)
        guard !files.isEmpty else { return text("No DICOM files found to store.", isError: true) }
        let r = DCMTKNet.storeFiles(files, toHost: str(args, "host"), port: int32(args, "port", default: 104),
                                    calledAE: str(args, "calledAE"),
                                    callingAE: args["callingAE"] as? String ?? "DICOMBENCH")
        return text(jsonString(r), isError: (r["success"] as? Bool) != true)

    case "dicom_retrieve":
        guard allowWrite else { return text("dicom_retrieve requires the server to be launched with --allow-write.", isError: true) }
        let keys = (args["keys"] as? [String: String]) ?? [:]
        let method = str(args, "method").isEmpty ? "GET" : str(args, "method")
        let r = DCMTKNet.retrieve(fromHost: str(args, "host"), port: int32(args, "port", default: 104),
                                  calledAE: str(args, "calledAE"),
                                  callingAE: args["callingAE"] as? String ?? "DICOMBENCH",
                                  level: str(args, "level"), keys: keys, method: method,
                                  moveDest: args["moveDest"] as? String, outputDir: str(args, "outputDir"))
        return text(jsonString(r), isError: (r["success"] as? Bool) != true)

    case "dicom_anonymize":
        guard allowWrite else { return text("dicom_anonymize requires the server to be launched with --allow-write.", isError: true) }
        let files = collectFiles(args)
        guard !files.isEmpty else { return text("No DICOM files found to anonymize.", isError: true) }
        var profile: [String: Any] = [
            "replacePatientName": args["replacePatientName"] ?? NSNull(),
            "replacePatientID": args["replacePatientID"] ?? NSNull(),
            "clearDates": (args["clearDates"] as? Bool) ?? true,
            "clearIdentifiers": (args["clearIdentifiers"] as? Bool) ?? true,
            "removePrivateTags": (args["removePrivateTags"] as? Bool) ?? true,
            "regenerateUIDs": (args["regenerateUIDs"] as? Bool) ?? true,
        ]
        do {
            let r = try DCMTKBridge.anonymize(files, outputDir: str(args, "outputDir"), profile: profile)
            return text(jsonString(r))
        } catch {
            return text("Anonymize failed: \(error.localizedDescription)", isError: true)
        }

    default:
        return text("Unknown tool: \(name)", isError: true)
    }
}

/// Files to operate on: explicit `paths`, else all DICOM files under `directory`
/// (grouped-and-flattened via scanSeries so non-DICOM files are ignored).
func collectFiles(_ args: [String: Any]) -> [String] {
    if let paths = args["paths"] as? [String], !paths.isEmpty { return paths }
    let dir = str(args, "directory")
    guard !dir.isEmpty else { return [] }
    return DCMTKBridge.scanSeries(dir).flatMap { ($0["files"] as? [String]) ?? [] }
}

/// Resolve a path (single file, or the Nth file of a series in a folder), render
/// it, and return an image + info-text result.
func renderSlice(_ args: [String: Any]) -> (content: [[String: Any]], isError: Bool) {
    let plane = (args["plane"] as? String ?? "axial").lowercased()
    let window = (args["window"] as? NSNumber)?.doubleValue
    let level = (args["level"] as? NSNumber)?.doubleValue
    let maxSize = Int(int32(args, "maxSize", default: 512))

    // Reslice planes (coronal/sagittal/oblique) need the full stacked volume.
    if plane == "coronal" || plane == "sagittal" || plane == "oblique" {
        let dir = str(args, "directory")
        guard !dir.isEmpty else {
            return text("plane '\(plane)' needs a `directory` (the whole series to stack into a volume).", isError: true)
        }
        guard let files = seriesFiles(dir, seriesUID: str(args, "seriesUID")), !files.isEmpty else {
            return text("No DICOM series found in \(dir).", isError: true)
        }
        do {
            let vol = try SliceRender.buildVolume(files)
            let position = (args["position"] as? NSNumber)?.doubleValue ?? 0.5
            let angle = (args["angle"] as? NSNumber)?.doubleValue ?? 0
            let r = SliceRender.reslice(vol, plane: plane, position: position, angle: angle,
                                        window: window, level: level, maxSize: maxSize)
            return ([imageContent(r.png), textContent(jsonString(r.info))], false)
        } catch {
            return text("Reslice failed: \(error.localizedDescription)", isError: true)
        }
    }

    // Axial: single file, or the Nth file of a series (fast — no volume needed).
    var path = str(args, "path")
    var sliceLabel = ""
    if path.isEmpty {
        let dir = str(args, "directory")
        guard !dir.isEmpty else { return text("Provide `path` or `directory`.", isError: true) }
        let series = DCMTKBridge.scanSeries(dir)
        guard !series.isEmpty else { return text("No DICOM series found in \(dir).", isError: true) }
        let wantUID = str(args, "seriesUID")
        let chosen = series.first { ($0["seriesUID"] as? String) == wantUID }
            ?? series.max { (($0["files"] as? [String])?.count ?? 0) < (($1["files"] as? [String])?.count ?? 0) }!
        let files = (chosen["files"] as? [String]) ?? []
        guard !files.isEmpty else { return text("Series has no files.", isError: true) }
        let idx = min(max(Int(int32(args, "index", default: Int32(files.count / 2))), 0), files.count - 1)
        path = files[idx]
        sliceLabel = " (\(chosen["modality"] as? String ?? "?") \(chosen["description"] as? String ?? "") — slice \(idx + 1)/\(files.count))"
    }
    do {
        let r = try SliceRender.render(
            path: path,
            frame: Int(int32(args, "frame", default: 0)),
            window: window, level: level, maxSize: maxSize)
        return ([imageContent(r.png), textContent(jsonString(r.info) + sliceLabel)], false)
    } catch {
        return text("Render failed: \(error.localizedDescription)", isError: true)
    }
}

/// Files of the chosen series (by UID, else the largest) under a directory.
func seriesFiles(_ dir: String, seriesUID: String) -> [String]? {
    let series = DCMTKBridge.scanSeries(dir)
    guard !series.isEmpty else { return nil }
    let chosen = series.first { ($0["seriesUID"] as? String) == seriesUID }
        ?? series.max { (($0["files"] as? [String])?.count ?? 0) < (($1["files"] as? [String])?.count ?? 0) }!
    return chosen["files"] as? [String]
}

// MARK: - Server loop

DCMTKBridge.registerCodecs()   // JPEG2000 etc. so decode/validate handle all TS.
logErr("ready (writes \(allowWrite ? "ENABLED" : "disabled"))")

while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    guard let data = line.data(using: .utf8),
          let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        logErr("dropping malformed line")
        continue
    }
    let method = msg["method"] as? String ?? ""
    let id = msg["id"]   // absent for notifications

    switch method {
    case "initialize":
        reply(id: id ?? NSNull(), result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "dicomflow", "version": "2.0"],
        ])
    case "notifications/initialized", "initialized":
        break   // notification — no reply
    case "ping":
        if let id { reply(id: id, result: [String: Any]()) }
    case "tools/list":
        reply(id: id ?? NSNull(), result: ["tools": allTools])
    case "tools/call":
        let params = msg["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let (content, isError) = callTool(name, args)
        reply(id: id ?? NSNull(), result: ["content": content, "isError": isError])
    default:
        if let id { replyError(id: id, code: -32601, "Method not found: \(method)") }
    }
}
