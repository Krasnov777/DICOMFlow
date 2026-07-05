import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Edit common identity/description tags and save to a NEW file (source is
/// never modified). Pixel-geometry tags are blocked by the engine.
struct TagEditorView: View {
    @EnvironmentObject var sidecar: DicomEngine

    private static let fields = [
        "PatientName", "PatientID", "PatientBirthDate", "PatientSex",
        "StudyDescription", "SeriesDescription", "AccessionNumber", "StudyDate",
        "InstitutionName", "ReferringPhysicianName",
    ]

    @State private var sourcePath: String?
    @State private var sourceURL: URL?          // held for the later Save-As read
    @State private var fileName: String?
    @State private var original: [String: String] = [:]
    @State private var edited: [String: String] = [:]
    @State private var status: String?
    @State private var busy = false
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Tag Editor", subtitle: "Edit identity tags; saves a new file",
                       symbol: "pencil")

            Card {
                HStack {
                    Button { showImporter = true } label: { Label("Open DICOM File…", systemImage: "doc") }
                        .buttonStyle(.glass).disabled(!sidecar.ready)
                    if let fileName { Text(fileName).foregroundStyle(.secondary) }
                    Spacer()
                    Button { save() } label: { Label("Save As…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.glassProminent)
                        .disabled(sourcePath == nil || changedEdits().isEmpty || busy)
                }
            }

            if sourcePath != nil {
                Card {
                    Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.md,
                         verticalSpacing: Theme.Spacing.sm) {
                        ForEach(Self.fields, id: \.self) { key in
                            GridRow {
                                Text(key).foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing).frame(minWidth: 160)
                                TextField(key, text: Binding(get: { edited[key] ?? "" },
                                                             set: { edited[key] = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            } else {
                EmptyState(symbol: "pencil", title: "No file open",
                           message: "Open a DICOM file to edit its identity tags.",
                           actionTitle: "Open DICOM File…") { showImporter = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if busy { ProgressView().controlSize(.small) }
            if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first { load(url: u) }
        }
    }

    private func changedEdits() -> [EditOp] {
        Self.fields.compactMap { key in
            let new = edited[key] ?? ""
            return new != (original[key] ?? "") ? EditOp(keyword: key, value: new) : nil
        }
    }

    private func load(url: URL) {
        guard let client = sidecar.client else { return }
        // The source must stay accessible until Save-As reads it (or a new file
        // is opened / the view disappears), so hold the grant rather than defer it.
        sourceURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        sourceURL = url
        sourcePath = url.path; fileName = url.lastPathComponent; status = nil
        busy = true
        Task {
            do {
                let resp = try await client.readTags(path: url.path)
                var vals: [String: String] = [:]
                for t in resp.tags where Self.fields.contains(t.keyword) { vals[t.keyword] = t.value }
                original = vals
                edited = Dictionary(uniqueKeysWithValues: Self.fields.map { ($0, vals[$0] ?? "") })
            } catch { status = error.localizedDescription }
            busy = false
        }
    }

    private func save() {
        guard let client = sidecar.client, let src = sourcePath else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dcm") ?? .data]
        panel.nameFieldStringValue = (fileName.map { ($0 as NSString).deletingPathExtension } ?? "edited") + "_edited.dcm"
        guard panel.runModal() == .OK, let out = panel.url?.path else { return }
        let edits = changedEdits()
        busy = true; status = "Saving…"
        Task {
            do {
                let r = try await client.editTags(path: src, edits: edits, outputPath: out)
                status = "Saved \(r.applied.count) change(s) → \(out)" + (r.skipped.isEmpty ? "" : " · skipped \(r.skipped.count)")
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
}
