import SwiftUI

/// Negotiation probe: proposes a matrix of storage SOP classes × transfer
/// syntaxes and shows which the peer accepts — a quick "what does this PACS
/// support?" capability map.
struct NegotiationView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var target: TesterTarget
    @State private var result: ProbeResult?
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Negotiation Probe",
                       subtitle: "Discover which SOP classes & transfer syntaxes a node accepts",
                       symbol: "checklist")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TargetForm()
                    HStack {
                        Button { runProbe() } label: { Label("Probe", systemImage: "checklist") }
                            .buttonStyle(.glassProminent)
                            .disabled(busy || !sidecar.ready)
                        if busy { ProgressView().controlSize(.small) }
                        if let result {
                            Spacer()
                            TableExport(header: ["SOP Class", "SOP UID", "Accepted", "Transfer Syntaxes"],
                                        rows: result.contexts.map { c in
                                            [c.sopName, c.sopClass, c.accepted ? "yes" : "no",
                                             c.transferSyntaxes.joined(separator: "; ")]
                                        },
                                        filename: "negotiation.csv")
                        }
                    }
                }
                .onSubmit { if !busy { runProbe() } }
            }

            if let errorText {
                Card { Label(errorText, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }
            if let result {
                if result.success {
                    let accepted = result.contexts.filter { $0.accepted }
                    StatusPill(result.message ?? "\(accepted.count) accepted",
                               state: accepted.isEmpty ? .warn : .ok,
                               symbol: accepted.isEmpty ? "exclamationmark.triangle" : "checkmark.seal.fill")
                    resultsList
                } else {
                    Card {
                        Label(result.message ?? "Negotiation failed", systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// Accepted contexts first (with their transfer syntaxes), then rejected.
    private var resultsList: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                let sorted = result?.contexts.sorted { ($0.accepted ? 0 : 1, $0.sopName) < ($1.accepted ? 0 : 1, $1.sopName) } ?? []
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Divider() }
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        Image(systemName: c.accepted ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(c.accepted ? Color.green : Color.secondary)
                            .accessibilityLabel(c.accepted ? "accepted" : "rejected")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.sopName).font(.callout.weight(.medium))
                                .foregroundStyle(c.accepted ? .primary : .secondary)
                            if c.accepted {
                                Text(c.transferSyntaxes.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
    }

    private func runProbe() {
        guard let client = sidecar.client else { return }
        busy = true; errorText = nil; result = nil
        let (h, p, ae, cae) = (target.host, target.port, target.aeTitle, target.callingAE)
        Task {
            do { result = try await client.probeContexts(host: h, port: p, aeTitle: ae, callingAE: cae) }
            catch { errorText = error.localizedDescription }
            busy = false
        }
    }
}
