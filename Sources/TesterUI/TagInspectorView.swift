import SwiftUI
import UniformTypeIdentifiers

/// A single decoded tag row (UUID id because flattened sequences can repeat tags).
struct TagRow: Identifiable {
    let id = UUID()
    let tag: String
    let name: String
    let vr: String
    let value: String
    let keyword: String
}

/// Open a DICOM file and browse all of its elements in a searchable table.
struct TagInspectorView: View {
    @EnvironmentObject var sidecar: DicomEngine

    @State private var rows: [TagRow] = []
    @State private var query = ""
    @State private var fileName: String?
    @State private var transferSyntax: String?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showImporter = false
    @State private var sortOrder = [KeyPathComparator(\TagRow.tag)]

    private var filtered: [TagRow] {
        let base: [TagRow]
        if query.isEmpty { base = rows } else {
            let q = query.lowercased()
            base = rows.filter {
                $0.tag.lowercased().contains(q) || $0.name.lowercased().contains(q) ||
                $0.keyword.lowercased().contains(q) || $0.vr.lowercased().contains(q) ||
                $0.value.lowercased().contains(q)
            }
        }
        return base.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Tag Inspector", subtitle: "Browse every element of a DICOM file",
                       symbol: "tag")

            Card {
                HStack(spacing: Theme.Spacing.md) {
                    Button { showImporter = true } label: { Label("Open DICOM File…", systemImage: "doc.badge.plus") }
                        .buttonStyle(.glassProminent).disabled(!sidecar.ready)
                    if let fileName {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fileName).font(.subheadline.weight(.medium)).lineLimit(1)
                            if let transferSyntax {
                                Text("\(rows.count) tags · \(transferSyntax)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                    TableExport(header: ["Tag", "Name", "VR", "Value", "Keyword"],
                                rows: filtered.map { [$0.tag, $0.name, $0.vr, $0.value, $0.keyword] },
                                filename: "\((fileName as NSString?)?.deletingPathExtension ?? "dicom")-tags.csv")
                    TextField("Filter", text: $query)
                        .textFieldStyle(.roundedBorder).frame(width: 220).disabled(rows.isEmpty)
                }
            }

            if let errorText {
                Card { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            } else if rows.isEmpty {
                EmptyState(symbol: "doc.text.magnifyingglass", title: "No file open",
                           message: "Open a DICOM file to inspect its tags.",
                           actionTitle: "Open DICOM File…") { showImporter = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered, sortOrder: $sortOrder) {
                    TableColumn("Tag", value: \.tag) { Text($0.tag).monospaced() }.width(110)
                    TableColumn("Name", value: \.name).width(min: 160, ideal: 240)
                    TableColumn("VR", value: \.vr) { Text($0.vr).monospaced() }.width(46)
                    TableColumn("Value", value: \.value) {
                        Text($0.value).monospaced().textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { load(url: url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url: url); return true
        }
    }

    private func load(url: URL) {
        guard let client = sidecar.client else { errorText = "Engine not ready."; return }
        _ = url.startAccessingSecurityScopedResource()
        fileName = url.lastPathComponent; errorText = nil; isLoading = true; rows = []
        let path = url.path
        Task {
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let resp = try await client.readTags(path: path)
                rows = resp.tags.map { TagRow(tag: $0.tag, name: $0.name, vr: $0.vr, value: $0.value, keyword: $0.keyword) }
                transferSyntax = resp.transferSyntax
            } catch { errorText = error.localizedDescription }
            isLoading = false
        }
    }
}
