import SwiftUI

/// Displays a DICOM Structured Report (SR) as readable text. SR instances carry
/// no pixel data, so the viewer shows their content tree instead of an image.
struct SRReportView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc.text.below.ecg")
                    .font(.title).foregroundStyle(Theme.accent)
                    .symbolRenderingMode(.hierarchical)
                Text("Structured Report").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless)
            }
            .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.lg)
            }
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
