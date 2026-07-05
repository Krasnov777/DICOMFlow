import Foundation
import Network
import AppKit

/// Loopback control channel: lets `dicomflow-mcp` (and only local, token-holding
/// processes) drive the running app — open a study in the viewer, read the live
/// viewer state, navigate slices / window-level. One JSON request per TCP
/// connection, one JSON reply, then close (see `ControlEndpoint`).
final class ControlServer {
    private let listener: NWListener
    private let token = UUID().uuidString + "-" + UUID().uuidString
    private let queue = DispatchQueue(label: "dicomflow.control")
    private unowned let state: AppState

    init?(state: AppState) {
        self.state = state
        let params = NWParameters.tcp
        // Loopback only — never reachable from the network.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else { return nil }
        listener = l
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] st in
            guard let self, case .ready = st, let port = self.listener.port?.rawValue else { return }
            ControlEndpoint(port: port, token: self.token).write()
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { conn.cancel(); return }
            conn.start(queue: self.queue)
            self.receive(conn, buffer: Data())
        }
        listener.start(queue: queue)
        // Best-effort cleanup so a stale endpoint doesn't linger after quit.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: nil) { _ in
            ControlEndpoint.remove()
        }
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, err in
            guard let self, err == nil else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > 1 << 20 { conn.cancel(); return }   // absurd request
            if let nl = buf.firstIndex(of: 0x0A) {
                self.handle(line: buf[..<nl], on: conn)
            } else if done {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func handle(line: Data, on conn: NWConnection) {
        guard let req = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
              let reqToken = req["token"] as? String, reqToken == token,
              let method = req["method"] as? String else {
            reply(["ok": false, "error": "unauthorized or malformed request"], on: conn)
            return
        }
        let params = req["params"] as? [String: Any] ?? [:]
        Task { @MainActor in
            let result = self.dispatch(method: method, params: params)
            self.queue.async { self.reply(result, on: conn) }
        }
    }

    private func reply(_ obj: [String: Any], on conn: NWConnection) {
        var data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{\"ok\":false}".utf8)
        data.append(0x0A)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Commands (main actor: they touch app/viewer state)

    @MainActor
    private func dispatch(method: String, params: [String: Any]) -> [String: Any] {
        switch method {
        case "ping":
            return ["ok": true, "app": "DicomFlow",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"]

        case "viewer_state":
            return viewerStateSnapshot()

        case "open_study":
            let path = params["path"] as? String ?? params["directory"] as? String
            guard let path else { return ["ok": false, "error": "missing path/directory"] }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                return ["ok": false, "error": "no such path: \(path) (note: the sandboxed app can only read user-opened locations, its own container, and temp dirs)"]
            }
            NSApp.activate(ignoringOtherApps: true)
            if isDir.boolValue {
                state.openInViewer(directory: path, seriesUID: params["seriesUID"] as? String)
            } else {
                state.mode = .viewer
                state.viewerState.loadFile(path: path, client: state.engine)
            }
            return ["ok": true, "opened": path]

        case "viewer_goto":
            let v = state.viewerState
            guard v.volume != nil || v.colorImage != nil || v.srText != nil else {
                return ["ok": false, "error": "nothing is loaded in the viewer"]
            }
            if let p = params["plane"] as? String {
                guard let axis = MPRAxis(rawValue: p) else { return ["ok": false, "error": "plane must be axial|coronal|sagittal"] }
                v.plane2D = axis
            }
            if let l = params["layout"] as? String {
                guard let layout = ViewerLayout(rawValue: l) else { return ["ok": false, "error": "layout must be 2D|MPR|3D|Compare"] }
                v.layout = layout
            }
            if let idx = params["sliceIndex"] as? Int {
                let n = max(v.slice2DCount, 1)
                v.slice2D = n > 1 ? Float(min(max(idx, 0), n - 1)) / Float(n - 1) : 0.5
            } else if let f = params["sliceFraction"] as? Double {
                v.slice2D = Float(min(max(f, 0), 1))
            }
            if let wc = params["windowCenter"] as? Double { v.winCenter = Float(wc) }
            if let ww = params["windowWidth"] as? Double { v.winWidth = max(1, Float(ww)) }
            if let uid = params["seriesUID"] as? String {
                if let info = v.series.first(where: { $0.id == uid }) {
                    v.selectSeries(info, client: state.engine)
                } else {
                    return ["ok": false, "error": "seriesUID not in the loaded study's series list"]
                }
            }
            return viewerStateSnapshot()

        default:
            return ["ok": false, "error": "unknown method \(method)"]
        }
    }

    @MainActor
    private func viewerStateSnapshot() -> [String: Any] {
        let v = state.viewerState
        var out: [String: Any] = [
            "ok": true,
            "mode": String(describing: state.mode),
            "layout": v.layout.rawValue,
            "isLoading": v.isLoading,
        ]
        if let vol = v.volume {
            let n = v.slice2DCount
            out["plane"] = v.plane2D.rawValue
            out["sliceIndex"] = Int((v.slice2D * Float(max(n - 1, 0))).rounded())
            out["sliceCount"] = n
            out["windowCenter"] = Double(v.winCenter)
            out["windowWidth"] = Double(v.winWidth)
            out["zoom"] = Double(v.zoom)
            out["invert"] = v.invert
            out["dimensions"] = [vol.meta.nx, vol.meta.ny, vol.meta.nz]
        }
        if v.srText != nil { out["showing"] = "structured report" }
        if v.colorImage != nil { out["showing"] = "color image"; out["frame"] = v.colorFrame }
        if !v.currentFiles.isEmpty { out["files"] = v.currentFiles; out["fileCount"] = v.currentFiles.count }
        if let sel = v.selectedSeriesID { out["seriesUID"] = sel }
        if !v.series.isEmpty {
            out["series"] = v.series.map { s in
                ["seriesUID": s.id, "description": s.description, "modality": s.modality,
                 "patient": s.patient, "studyDescription": s.studyDescription, "count": s.count] as [String: Any]
            }
        }
        return out
    }
}
