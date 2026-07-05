import SwiftUI
import UniformTypeIdentifiers

/// Copy (tab-separated) + Export CSV… buttons for a result table.
/// `rows` should reflect what the user currently sees.
struct TableExport: View {
    let header: [String]
    let rows: [[String]]
    var filename = "dicomflow-export.csv"

    var body: some View {
        Button { copy() } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless).hint("Copy (tab-separated)").disabled(rows.isEmpty)
        Button { exportCSV() } label: { Image(systemName: "square.and.arrow.down") }
            .buttonStyle(.borderless).hint("Export CSV…").disabled(rows.isEmpty)
    }

    private func copy() {
        let text = ([header] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportCSV() {
        func esc(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        let csv = ([header] + rows).map { $0.map(esc).joined(separator: ",") }.joined(separator: "\n") + "\n"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
