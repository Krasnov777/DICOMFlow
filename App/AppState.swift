import Foundation
import SwiftUI
import AppKit

/// A recently-opened file/folder, remembered across launches via a
/// security-scoped bookmark (sandbox-safe).
struct RecentItem: Identifiable, Codable {
    let path: String
    let name: String
    let isDirectory: Bool
    let bookmark: Data
    var id: String { path }
}

/// Root observable owning app-wide state and the native DICOM engine.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .tester
    /// Shown in the window title bar subtitle (current file / series / target).
    @Published var subtitle: String = ""
    /// Set by tester tools to hand a received series to the Viewer.
    @Published var pendingViewerDirectory: String?
    /// Optional series to select once the directory is scanned.
    var pendingViewerSeriesUID: String?
    /// Reverse handoff: files the Viewer asked to C-STORE (Tester picks these up).
    @Published var pendingStorePaths: [String]?
    /// Tester's NavigationSplitView column visibility (owned here so the mode
    /// switch can collapse it before entering the Viewer, which has no sidebar).
    @Published var testerColumns: NavigationSplitViewVisibility = .all

    /// Recently opened studies (menu + empty-state); persisted as bookmarks.
    @Published var recents: [RecentItem] = []
    /// Help-menu sheets.
    @Published var showShortcuts = false
    @Published var showWelcome = false

    /// In-process DICOM engine (DCMTK). Replaces the old Python sidecar.
    let engine = DicomEngine()

    /// Owned here (not by ViewerRootView) so loaded series survive mode switches.
    let viewerState = ViewerState()

    private let recentsKey = "recentStudies"

    /// Loopback control channel for dicomflow-mcp (open studies, live viewer state).
    private var controlServer: ControlServer?

    func boot() {
        // Capture DCMTK's protocol log for the Protocol inspector.
        ProtocolLog.shared.startCapture()
        loadRecents()
        controlServer = ControlServer(state: self)
        controlServer?.start()
    }

    /// Switch to the Viewer and load the given folder (optionally selecting one series).
    func openInViewer(directory: String, seriesUID: String? = nil) {
        pendingViewerSeriesUID = seriesUID
        pendingViewerDirectory = directory
        mode = .viewer
    }

    /// Retain security-scoped access to an external folder for the session (so the
    /// viewer can later read files under it — e.g. a DICOMDIR's referenced images).
    private var heldScopes: [URL] = []
    func retainAccess(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { heldScopes.append(url) }
    }

    /// Hand the current viewer series to the Tester's C-STORE tool.
    func sendToStore(files: [String]) {
        guard !files.isEmpty else { return }
        pendingStorePaths = files
        mode = .tester
    }

    /// Open a DICOM file/folder from Finder (document-type association / drag).
    func open(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()   // held for the session
        mode = .viewer
        var isDir: ObjCBool = false
        let dir = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        if dir { openInViewer(directory: url.path) }
        else { viewerState.loadFile(path: url.path, client: engine) }
        rememberRecent(url, isDirectory: dir)
    }

    // MARK: Open… / Recents

    /// Show the native open panel (files or folders) and load the pick.
    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Open a DICOM file or a folder / series."
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func openRecent(_ item: RecentItem) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            recents.removeAll { $0.id == item.id }; saveRecents(); return
        }
        _ = url.startAccessingSecurityScopedResource()
        mode = .viewer
        if item.isDirectory { openInViewer(directory: url.path) }
        else { viewerState.loadFile(path: url.path, client: engine) }
        rememberRecent(url, isDirectory: item.isDirectory)   // bump to top
    }

    func clearRecents() { recents = []; saveRecents() }

    private func rememberRecent(_ url: URL, isDirectory: Bool) {
        guard let bm = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let item = RecentItem(path: url.path, name: url.lastPathComponent, isDirectory: isDirectory, bookmark: bm)
        recents.removeAll { $0.path == item.path }
        recents.insert(item, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        saveRecents()
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let items = try? JSONDecoder().decode([RecentItem].self, from: data) else { return }
        recents = items
    }
    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
}
