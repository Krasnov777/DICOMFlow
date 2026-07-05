import SwiftUI
import UniformTypeIdentifiers

/// DICOM file conformance validator (Part-10 meta, required UIDs, UID format,
/// SOP class, image attributes, per-element VR checks).
struct ValidatorView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @State private var result: DicomEngine.ValidationResult?
    @State private var fileName: String?
    @State private var busy = false
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Validator", subtitle: "Check a DICOM file for basic conformance",
                       symbol: "checkmark.shield")

            Card {
                HStack(spacing: Theme.Spacing.md) {
                    Button { showImporter = true } label: { Label("Open DICOM File…", systemImage: "doc.badge.plus") }
                        .buttonStyle(.glassProminent).disabled(!sidecar.ready)
                    if let fileName { Text(fileName).font(.subheadline.weight(.medium)).lineLimit(1) }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    if let r = result {
                        StatusPill(r.ok ? (r.warnings.isEmpty ? "Conformant" : "Conformant, \(r.warnings.count) warning(s)")
                                        : "\(r.errors.count) error(s)",
                                   state: r.ok ? (r.warnings.isEmpty ? .ok : .warn) : .error,
                                   symbol: r.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        Button { copyReport(r) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).hint("Copy report")
                        Button { exportReport(r) } label: { Image(systemName: "square.and.arrow.down") }
                            .buttonStyle(.borderless).hint("Export report…")
                    }
                }
            }

            if let r = result {
                if !r.info.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            infoRow("SOP Class", r.info["sopClass"], r.info["sopClassUID"])
                            infoRow("Transfer Syntax", r.info["transferSyntax"], nil)
                            infoRow("Modality", r.info["modality"], nil)
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(r.errors, id: \.self) { issue("xmark.octagon.fill", .red, $0) }
                        ForEach(r.warnings, id: \.self) { issue("exclamationmark.triangle.fill", .orange, $0) }
                        if r.errors.isEmpty && r.warnings.isEmpty {
                            Label("No basic conformance issues found.", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green).padding(.top, 4)
                        }
                        iodSection(r)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "checkmark.shield", title: "No file validated",
                           message: "Open a DICOM file to check its conformance (required UIDs, VRs, image attributes, and more).",
                           actionTitle: "Open DICOM File…") { showImporter = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item],
                      allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let url = urls.first { validate(url) }
        }
    }

    @ViewBuilder private func infoRow(_ name: String, _ value: String?, _ sub: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(name).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                Text(value).font(.callout)
                if let sub { Text(sub).font(.caption.monospaced()).foregroundStyle(.tertiary) }
            }
        }
    }

    /// Type-1/2 module conformance from the dcmiod rule engine: a summary line +
    /// the failing attributes (type-1 red, type-2 orange), grouped by module.
    @ViewBuilder private func iodSection(_ r: DicomEngine.ValidationResult) -> some View {
        if !r.iodModules.isEmpty {
            let fails = r.iodModules.filter { !$0.ok }
            Divider().padding(.vertical, 6)
            Text("IOD module conformance — \(r.iodModules.count - fails.count)/\(r.iodModules.count) type-1/2 attributes present")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if fails.isEmpty {
                Label("All required module attributes present.", systemImage: "checkmark.seal")
                    .font(.callout).foregroundStyle(.green)
            } else {
                ForEach(fails) { a in
                    issue(a.type == "1" ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                          a.type == "1" ? .red : .orange,
                          "[\(a.module)] \(a.name) \(a.tag) — type-\(a.type): \(a.message)")
                }
            }
        }
    }

    private func issue(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol).foregroundStyle(color).font(.callout)
            Text(text).font(.callout.monospaced()).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func reportText(_ r: DicomEngine.ValidationResult) -> String {
        var lines = ["DICOM conformance report — \(fileName ?? "?")"]
        for (k, v) in r.info.sorted(by: { $0.key < $1.key }) { lines.append("\(k): \(v)") }
        lines.append(r.ok ? "RESULT: conformant (\(r.warnings.count) warning(s))"
                          : "RESULT: \(r.errors.count) error(s), \(r.warnings.count) warning(s)")
        lines += r.errors.map { "ERROR: \($0)" }
        lines += r.warnings.map { "WARNING: \($0)" }
        let iodFails = r.iodModules.filter { !$0.ok }
        if !r.iodModules.isEmpty {
            lines.append("IOD modules: \(r.iodModules.count - iodFails.count)/\(r.iodModules.count) type-1/2 attributes present")
            lines += iodFails.map { "IOD type-\($0.type) [\($0.module)] \($0.name) \($0.tag): \($0.message)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func copyReport(_ r: DicomEngine.ValidationResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText(r), forType: .string)
    }

    private func exportReport(_ r: DicomEngine.ValidationResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\((fileName as NSString?)?.deletingPathExtension ?? "dicom")-validation.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? reportText(r).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func validate(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        fileName = url.lastPathComponent; busy = true; result = nil
        let path = url.path
        Task {
            defer { url.stopAccessingSecurityScopedResource() }
            result = await sidecar.validate(path: path)
            busy = false
        }
    }
}
