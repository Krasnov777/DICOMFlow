import SwiftUI

/// First-run welcome with a quick feature overview.
struct WelcomeView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 84, height: 84)
            Text("Welcome to DicomFlow").font(.largeTitle.bold())
            Text("An engineer’s DICOM toolbench & viewer — not for diagnostic use.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                row("network", "Tester", "C-ECHO, C-STORE, Query/Retrieve, and a built-in test SCP.")
                row("cube.transparent", "Viewer", "2D slices, MPR, and GPU volume rendering (MIP + transfer function).")
                row("tag", "Tags", "Inspect, edit, and anonymize DICOM files.")
            }
            .padding(Theme.Spacing.lg)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.md))

            Button("Get Started") { onDismiss() }
                .buttonStyle(.glassProminent).controlSize(.large)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 520)
    }

    private func row(_ symbol: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical).frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(desc).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
