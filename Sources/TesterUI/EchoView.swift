import SwiftUI

/// C-ECHO connection tester. Reports verification status + accepted SOP classes.
struct EchoView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var target: TesterTarget
    @State private var result: EchoResult?
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("C-ECHO", subtitle: "Verify connectivity to a DICOM node",
                       symbol: "dot.radiowaves.left.and.right")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TargetForm()
                    Button { runEcho() } label: {
                        Label("Send C-ECHO", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(busy || !sidecar.ready)
                }
                .onSubmit { if !busy { runEcho() } }
            }

            if busy { ProgressView().controlSize(.small) }
            if let errorText {
                Card { Label(errorText, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }
            if let result {
                if result.success && (result.echoStatus ?? -1) == 0 {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            StatusPill("Verification succeeded (0x0000)", state: .ok, symbol: "checkmark.seal.fill")
                            if let sop = result.supportedSOPClasses, !sop.isEmpty {
                                Text("Accepted SOP classes (\(sop.count))").font(.headline)
                                ForEach(sop, id: \.self) {
                                    Text($0).font(.callout.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Card {
                        Label(result.message ?? "Echo failed (status \(result.echoStatus ?? -1))",
                              systemImage: "xmark.octagon").foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func runEcho() {
        guard let client = sidecar.client else { return }
        busy = true; errorText = nil; result = nil
        let (h, p, ae, cae) = (target.host, target.port, target.aeTitle, target.callingAE)
        Task {
            do { result = try await client.echo(host: h, port: p, aeTitle: ae, callingAE: cae) }
            catch { errorText = error.localizedDescription }
            busy = false
        }
    }
}
