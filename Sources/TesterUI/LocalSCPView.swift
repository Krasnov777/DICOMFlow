import SwiftUI

/// Built-in Storage SCP (mini-PACS): start/stop, watch received instances,
/// and open a received series in the Viewer.
struct LocalSCPView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var appState: AppState

    @State private var aeTitle = "DICOMBENCH"
    @State private var port = 11112
    @State private var enforceCalledAE = true
    @State private var status: SCPStatus?
    @State private var received: [ReceivedItem] = []
    @State private var selection: ReceivedItem.ID?
    @State private var receivedDir: String?
    @State private var errorText: String?

    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Test SCP", subtitle: "A local mini-PACS to receive C-STORE / C-MOVE",
                       symbol: "antenna.radiowaves.left.and.right")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.md) {
                        labeledField("AE Title", text: $aeTitle, width: 150)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Port").font(.caption).foregroundStyle(.secondary)
                            TextField("11112", value: $port, format: .number.grouping(.never))
                                .frame(width: 80).textFieldStyle(.roundedBorder)
                        }
                        Spacer()
                        if status?.running == true {
                            Button(role: .destructive) { stop() } label: { Label("Stop", systemImage: "stop.fill") }
                                .buttonStyle(.glass)
                        } else {
                            Button { start() } label: { Label("Start", systemImage: "play.fill") }
                                .buttonStyle(.glassProminent).disabled(!sidecar.ready)
                        }
                    }
                    Toggle(isOn: $enforceCalledAE) { Text("Enforce Called AE") }
                        .toggleStyle(.switch).controlSize(.small).disabled(status?.running == true)
                        .help("Refuse associations addressed to a different Called AE title")
                    if let status {
                        StatusPill(status.running ? "Listening on \(status.port) as “\(status.aeTitle)”" : "Stopped",
                                   state: status.running ? .ok : .neutral,
                                   symbol: status.running ? "antenna.radiowaves.left.and.right" : "pause.circle")
                    }
                    if let errorText { Label(errorText, systemImage: "xmark.octagon").foregroundStyle(.red) }
                }
            }

            HStack {
                Text("Received (\(received.count))").font(.headline)
                Spacer()
                Button { openReceived() } label: {
                    Label(selection == nil ? "Open in Viewer" : "Open Selected Series",
                          systemImage: "cube.transparent")
                }
                .buttonStyle(.glass).disabled(received.isEmpty)
            }

            if received.isEmpty {
                EmptyState(symbol: "tray", title: "Nothing received yet",
                           message: "Start the SCP, then send images to it from a PACS or another tool.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(received, selection: $selection) {
                    TableColumn("Patient") { Text($0.patient) }
                    TableColumn("Modality") { Text($0.modality) }
                    TableColumn("Series UID") { Text($0.seriesUID).font(.caption.monospaced()) }
                }
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .onReceive(pollTimer) { _ in if status?.running == true { refresh() } }
        .task { status = try? await sidecar.client?.scpStatus() }
    }

    private func labeledField(_ name: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(name, text: text).frame(width: width).textFieldStyle(.roundedBorder)
        }
    }

    private func start() {
        guard let client = sidecar.client else { return }
        errorText = nil
        let (ae, p, enforce) = (aeTitle, port, enforceCalledAE)
        Task {
            do { status = try await client.scpStart(aeTitle: ae, port: p, enforceCalledAE: enforce) }
            catch { errorText = error.localizedDescription }
        }
    }
    private func stop() {
        Task {
            do { status = try await sidecar.client?.scpStop() }
            catch { errorText = error.localizedDescription }
        }
    }
    private func refresh() {
        Task {
            if let list = try? await sidecar.client?.scpReceived() {
                received = list.items; receivedDir = list.receivedDir
            }
        }
    }
    private func openReceived() {
        guard let dir = receivedDir else { return }
        let seriesUID = selection.flatMap { id in received.first { $0.id == id } }?.seriesUID
        appState.openInViewer(directory: dir, seriesUID: seriesUID)
    }
}
