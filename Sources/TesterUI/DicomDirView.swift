import SwiftUI
import UniformTypeIdentifiers

/// Browse a DICOMDIR (the index on DICOM exchange media — CD/DVD/USB exports):
/// its Patient → Study → Series tree, and open any series in the Viewer.
struct DicomDirView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var appState: AppState
    @State private var result: DicomDirResult?
    @State private var busy = false
    @State private var errorText: String?
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("DICOMDIR", subtitle: "Browse DICOM exchange media (CD / DVD / USB)",
                       symbol: "opticaldiscdrive")

            Card {
                HStack(spacing: Theme.Spacing.md) {
                    Button { showImporter = true } label: {
                        Label("Open DICOMDIR Folder…", systemImage: "folder.badge.plus")
                    }.buttonStyle(.glassProminent).disabled(!sidecar.ready)
                    if busy { ProgressView().controlSize(.small) }
                    if let r = result {
                        StatusPill(r.message, state: .ok, symbol: "checkmark.seal.fill")
                    }
                    Spacer()
                }
            }

            if let errorText {
                Card { Label(errorText, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }

            if let r = result {
                List {
                    ForEach(r.patients) { p in
                        Section("\(p.name.isEmpty ? "Unknown patient" : p.name)  ·  \(p.patientID)") {
                            ForEach(p.studies) { st in
                                DisclosureGroup {
                                    ForEach(st.series) { se in seriesRow(se, baseDir: r.baseDir) }
                                } label: {
                                    Text("\(st.description.isEmpty ? "Study" : st.description)   \(formatDate(st.date))")
                                        .font(.callout.weight(.medium))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "opticaldiscdrive", title: "No DICOMDIR loaded",
                           message: "Open a folder containing a DICOMDIR file. Its studies and series are listed here; open any of them in the Viewer.",
                           actionTitle: "Open DICOMDIR Folder…") { showImporter = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let url = urls.first { load(url) }
        }
    }

    private func seriesRow(_ se: DicomDirSeries, baseDir: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: se.modality == "SR" ? "doc.text.below.ecg" : "square.stack.3d.up")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(se.modality.isEmpty ? "?" : se.modality) · \(se.description.isEmpty ? "Series \(se.number)" : se.description)")
                    .font(.callout)
                Text("\(se.count) image(s)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { appState.openInViewer(directory: baseDir, seriesUID: se.uid) }
                .buttonStyle(.glass).disabled(se.files.isEmpty)
        }
        .padding(.vertical, 2)
    }

    private func load(_ folder: URL) {
        appState.retainAccess(folder)   // hold the scope so the Viewer can read the referenced files
        busy = true; result = nil; errorText = nil
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = entries.first(where: { $0.uppercased() == "DICOMDIR" }) else {
            busy = false; errorText = "No DICOMDIR file found in that folder."; return
        }
        let path = folder.appendingPathComponent(name).path
        Task {
            let r = await sidecar.readDicomDir(path: path)
            if r.success { result = r } else { errorText = r.message }
            busy = false
        }
    }

    private func formatDate(_ d: String) -> String {
        guard d.count == 8 else { return d }
        return "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.dropFirst(6).prefix(2))"
    }
}
