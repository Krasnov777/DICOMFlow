import SwiftUI
import UniformTypeIdentifiers

private struct DiffRow: Identifiable {
    let id: String            // tag
    let name: String
    let vr: String
    let a: String?
    let b: String?
    enum Status { case same, changed, onlyA, onlyB }
    var status: Status {
        if a == nil { return .onlyB }
        if b == nil { return .onlyA }
        return a == b ? .same : .changed
    }
}

/// Tag-level diff of two DICOM files.
struct DiffView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @State private var nameA: String?
    @State private var nameB: String?
    @State private var tagsA: [String: (name: String, vr: String, value: String)] = [:]
    @State private var tagsB: [String: (name: String, vr: String, value: String)] = [:]
    @State private var busy = false
    @State private var onlyDiffs = true
    @State private var showImporter = false
    @State private var pendingSide: Side = .a
    @State private var errorText: String?
    private enum Side { case a, b }

    private var rows: [DiffRow] {
        let keys = Set(tagsA.keys).union(tagsB.keys)
        let all = keys.map { tag -> DiffRow in
            let a = tagsA[tag], b = tagsB[tag]
            return DiffRow(id: tag, name: a?.name ?? b?.name ?? "", vr: a?.vr ?? b?.vr ?? "",
                           a: a?.value, b: b?.value)
        }.sorted { $0.id < $1.id }
        return onlyDiffs ? all.filter { $0.status != .same } : all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Compare", subtitle: "Tag-level diff of two DICOM files", symbol: "arrow.left.and.right.square")

            Card {
                HStack(spacing: Theme.Spacing.lg) {
                    filePicker("File A", nameA, .a)
                    Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
                    filePicker("File B", nameB, .b)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Toggle("Differences only", isOn: $onlyDiffs).toggleStyle(.checkbox)
                    Text("\(rows.count) rows").font(.callout).foregroundStyle(.secondary)
                    Button { copyAll() } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).hint("Copy (tab-separated)").disabled(rows.isEmpty)
                    Button { exportCSV() } label: { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.borderless).hint("Export CSV…").disabled(rows.isEmpty)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }

            if tagsA.isEmpty && tagsB.isEmpty {
                EmptyState(symbol: "arrow.left.and.right.square", title: "No files to compare",
                           message: "Open two DICOM files to see which tags were added, removed, or changed.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows) {
                    TableColumn("Tag") { Text($0.id).monospaced() }.width(110)
                    TableColumn("Name") { Text($0.name) }.width(min: 140, ideal: 200)
                    TableColumn("A") { Text($0.a ?? "—").monospaced().foregroundStyle($0.a == nil ? .secondary : .primary) }
                    TableColumn("B") { Text($0.b ?? "—").monospaced().foregroundStyle($0.b == nil ? .secondary : .primary) }
                    TableColumn("") { r in badge(r.status) }.width(90)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data, .item], allowsMultipleSelection: false) { r in
            // NB: don't derive the side from the presentation binding — SwiftUI
            // clears it on dismiss before this handler runs.
            if case .success(let urls) = r, let url = urls.first { load(url, pendingSide) }
        }
    }

    private func filePicker(_ label: String, _ name: String?, _ side: Side) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Button { pendingSide = side; showImporter = true } label: {
                Label(name ?? "Open…", systemImage: "doc.badge.plus").lineLimit(1)
            }.buttonStyle(.bordered).disabled(!sidecar.ready)
        }
    }

    // MARK: copy / export (current view: honors "differences only" + sort)

    private static func statusText(_ s: DiffRow.Status) -> String {
        switch s {
        case .same: return "same"
        case .changed: return "changed"
        case .onlyA: return "only A"
        case .onlyB: return "only B"
        }
    }

    private var header: [String] {
        ["Tag", "Name", "VR", "A (\(nameA ?? "—"))", "B (\(nameB ?? "—"))", "Status"]
    }
    private func cells(_ r: DiffRow) -> [String] {
        [r.id, r.name, r.vr, r.a ?? "", r.b ?? "", Self.statusText(r.status)]
    }

    private func copyAll() {
        let text = ([header] + rows.map(cells))
            .map { $0.joined(separator: "\t") }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportCSV() {
        func esc(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        let csv = ([header] + rows.map(cells))
            .map { $0.map(esc).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dicom-compare.csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @ViewBuilder private func badge(_ s: DiffRow.Status) -> some View {
        switch s {
        case .same: Text("same").font(.caption2).foregroundStyle(.secondary)
        case .changed: Text("changed").font(.caption2.weight(.bold)).foregroundStyle(.orange)
        case .onlyA: Text("only A").font(.caption2.weight(.bold)).foregroundStyle(.red)
        case .onlyB: Text("only B").font(.caption2.weight(.bold)).foregroundStyle(.green)
        }
    }

    private func load(_ url: URL, _ side: Side) {
        _ = url.startAccessingSecurityScopedResource()
        busy = true; errorText = nil
        if side == .a { nameA = url.lastPathComponent } else { nameB = url.lastPathComponent }
        let path = url.path
        Task {
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let resp = try await sidecar.readTags(path: path)
                let map = Dictionary(resp.tags.map { ($0.tag, (name: $0.name, vr: $0.vr, value: $0.value)) },
                                     uniquingKeysWith: { first, _ in first })
                if side == .a { tagsA = map } else { tagsB = map }
            } catch {
                errorText = "\(url.lastPathComponent): \(error.localizedDescription)"
                if side == .a { nameA = nil } else { nameB = nil }
            }
            busy = false
        }
    }
}
