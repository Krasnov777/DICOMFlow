import SwiftUI

/// Shared remote-node target (host/port/AE) used by the echo/store/Q-R tools.
/// Seeded from app defaults (editable in Settings).
@MainActor
final class TesterTarget: ObservableObject {
    @Published var host = Defaults.host
    @Published var port = Defaults.port
    @Published var aeTitle = Defaults.calledAE
    @Published var callingAE = Defaults.callingAE

    func apply(_ p: PacsProfile) {
        host = p.host; port = p.port; aeTitle = p.aeTitle; callingAE = p.callingAE
    }
    var asProfileFields: (String, Int, String, String) { (host, port, aeTitle, callingAE) }
}

/// Reusable host / port / AE-title form with a saved-profiles menu.
struct TargetForm: View {
    @EnvironmentObject var target: TesterTarget
    @EnvironmentObject var profiles: PacsProfileStore
    @AppStorage("dimseTLS") private var dimseTLS = false
    @State private var newName = ""
    @State private var showSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Menu {
                    if profiles.profiles.isEmpty {
                        Text("No saved profiles")
                    } else {
                        ForEach(profiles.profiles) { p in
                            Button("\(p.name)  —  \(p.aeTitle)@\(p.host):\(p.port)") { target.apply(p) }
                        }
                        Divider()
                        Menu("Delete") {
                            ForEach(profiles.profiles) { p in
                                Button(p.name, role: .destructive) { profiles.delete(p) }
                            }
                        }
                    }
                } label: { Label("Profiles", systemImage: "bookmark") }
                .menuStyle(.borderlessButton).fixedSize()

                Button { showSave = true } label: { Label("Save", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showSave) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Save PACS profile").font(.headline)
                            TextField("Name", text: $newName).frame(width: 220)
                            HStack {
                                Spacer()
                                Button("Save") {
                                    let (h, p, ae, cae) = target.asProfileFields
                                    profiles.add(PacsProfile(name: newName.isEmpty ? ae : newName,
                                                             host: h, port: p, aeTitle: ae, callingAE: cae))
                                    newName = ""; showSave = false
                                }.buttonStyle(.glassProminent)
                            }
                        }.padding()
                    }
                Spacer()
            }

            // Flexible fields so the form never clips on a narrow window.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Host").gridColumnAlignment(.trailing)
                    TextField("127.0.0.1", text: $target.host).frame(maxWidth: .infinity)
                    Text("Port").gridColumnAlignment(.trailing)
                    TextField("4242", value: $target.port, format: .number.grouping(.never)).frame(width: 88)
                }
                GridRow {
                    Text("Called AE").gridColumnAlignment(.trailing)
                    TextField("ORTHANC", text: $target.aeTitle).frame(maxWidth: .infinity)
                    Text("Calling AE").gridColumnAlignment(.trailing)
                    TextField("DICOMBENCH", text: $target.callingAE).frame(maxWidth: .infinity)
                }
            }
            .textFieldStyle(.roundedBorder)

            Toggle("TLS", isOn: $dimseTLS)
                .toggleStyle(.checkbox)
                .onChange(of: dimseTLS) { _, _ in DicomEngine.applyTLSConfig() }
                .help("Use DICOM TLS (BCP 195) for outgoing connections. Certificate verification is configured in Settings → Networking.")
        }
    }
}
