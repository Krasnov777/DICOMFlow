import SwiftUI
import UniformTypeIdentifiers

/// C-STORE sender: pick files (or a folder) and push them to the target node.
struct StoreView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var target: TesterTarget
    @EnvironmentObject var appState: AppState
    @State private var paths: [String] = []
    @State private var accessed: [URL] = []   // security-scoped grants held until re-pick
    @State private var result: StoreResult?
    @State private var errorText: String?
    @State private var busy = false
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("C-STORE", subtitle: "Send DICOM files to a node", symbol: "paperplane")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TargetForm()
                    HStack {
                        Button { showImporter = true } label: {
                            Label("Choose Files / Folder…", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.glass)
                        if !paths.isEmpty {
                            Text("\(paths.count) file(s)").foregroundStyle(.secondary)
                            Button("Clear") { paths = []; result = nil }.buttonStyle(.glass)
                        }
                        Spacer()
                        Button { runStore() } label: { Label("Send", systemImage: "paperplane.fill") }
                            .buttonStyle(.glassProminent)
                            .disabled(busy || paths.isEmpty || !sidecar.ready)
                    }
                }
            }

            if busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Button("Dismiss") { cancelOp() }.controlSize(.small)
                }
            }
            if let errorText { Card { Label(errorText, systemImage: "xmark.octagon").foregroundStyle(.red) } }
            if let result {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if result.success {
                            let ok = (result.sent ?? 0) == (result.total ?? -1)
                            StatusPill("Sent \(result.sent ?? 0)/\(result.total ?? 0)",
                                       state: ok ? .ok : .warn,
                                       symbol: ok ? "checkmark.seal.fill" : "exclamationmark.triangle")
                            let failures = (result.results ?? []).filter { !$0.ok }
                            ForEach(failures, id: \.file) { f in
                                Text("\(f.file): \(f.error ?? "status \(f.status ?? -1)")")
                                    .font(.callout).foregroundStyle(.red)
                            }
                        } else {
                            Label(result.message ?? "Store failed", systemImage: "xmark.octagon")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data, .item, .folder],
                      allowsMultipleSelection: true) { res in
            if case .success(let urls) = res { paths = expand(urls) }
        }
        // Drag files/folders straight onto the C-STORE form.
        .dropDestination(for: URL.self) { urls, _ in paths = expand(urls); return true }
        // Files handed over from the Viewer's "Send to PACS" (already accessible).
        .onChange(of: appState.pendingStorePaths) { _, new in consumeHandoff(new) }
        .task { consumeHandoff(appState.pendingStorePaths) }
    }

    private func consumeHandoff(_ new: [String]?) {
        guard let files = new, !files.isEmpty else { return }
        paths = files
        errorText = nil
        appState.pendingStorePaths = nil
    }

    private func expand(_ urls: [URL]) -> [String] {
        // Release the previous selection's grants before taking new ones; access
        // must persist past this call because the C-STORE reads the files later.
        accessed.forEach { $0.stopAccessingSecurityScopedResource() }
        accessed = urls
        var out: [String] = []
        let fm = FileManager.default
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let f as URL in en where !f.hasDirectoryPath { out.append(f.path) }
                }
            } else {
                out.append(url.path)
            }
        }
        return out
    }

    @State private var opID = 0

    /// Unblock the UI; the in-flight C-STORE finishes in the background
    /// (bounded by the network timeout) and its result is discarded.
    private func cancelOp() {
        opID += 1
        busy = false
        errorText = "Dismissed — the C-STORE keeps running in the background."
    }

    private func runStore() {
        guard let client = sidecar.client else { return }
        busy = true; errorText = nil; result = nil
        let (h, p, ae, cae, ps) = (target.host, target.port, target.aeTitle, target.callingAE, paths)
        let id = opID
        Task {
            do {
                let r = try await client.store(host: h, port: p, aeTitle: ae, paths: ps, callingAE: cae)
                guard id == opID else { return }
                result = r
            } catch { guard id == opID else { return }; errorText = error.localizedDescription }
            if id == opID { busy = false }
        }
    }
}
