import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// A `dcmdump`-style structural view of a DICOM file: the full nested element
/// tree (tag, VR, length, value) including file-meta and sequence indentation —
/// the raw wire structure, complementing the Tag Inspector's decoded table.
struct DumpView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @State private var text: String?
    @State private var fileName: String?
    @State private var filter = ""
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Dataset Dump", subtitle: "Raw element tree (dcmdump-style)",
                       symbol: "curlybraces.square")

            Card {
                HStack(spacing: Theme.Spacing.md) {
                    Button { showImporter = true } label: {
                        Label("Open DICOM File…", systemImage: "doc.badge.plus")
                    }.buttonStyle(.glassProminent).disabled(!sidecar.ready)
                    if let fileName { Text(fileName).font(.subheadline.weight(.medium)).lineLimit(1) }
                    Spacer()
                    if text != nil {
                        TextField("Filter lines…", text: $filter)
                            .textFieldStyle(.roundedBorder).frame(width: 200)
                        Button { copy() } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).hint("Copy dump")
                        Button { export() } label: { Image(systemName: "square.and.arrow.down") }
                            .buttonStyle(.borderless).hint("Export dump…")
                    }
                }
            }

            if let text {
                ScrollView([.vertical, .horizontal]) {
                    Text(filtered(text))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.sm)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "curlybraces.square", title: "No file loaded",
                           message: "Open a DICOM file to see its raw element structure — every tag with its VR, length and value, sequences indented.",
                           actionTitle: "Open DICOM File…") { showImporter = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item],
                      allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let url = urls.first { load(url) }
        }
    }

    private func filtered(_ t: String) -> String {
        guard !filter.isEmpty else { return t }
        return t.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.range(of: filter, options: .caseInsensitive) != nil }
            .joined(separator: "\n")
    }

    private func load(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        fileName = url.lastPathComponent; text = nil; filter = ""
        let path = url.path
        Task {
            defer { url.stopAccessingSecurityScopedResource() }
            let d = await sidecar.dump(path: path)
            text = d ?? "Could not read the file as DICOM."
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text ?? "", forType: .string)
    }
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\((fileName as NSString?)?.deletingPathExtension ?? "dicom")-dump.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? (text ?? "").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
