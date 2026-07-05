import SwiftUI

private struct FHIRRow: Identifiable {
    let id = UUID()
    let values: [String: String]
    func v(_ k: String) -> String { values[k] ?? "" }
}

/// FHIR ImagingStudy search.
struct FHIRView: View {
    @AppStorage("fhirURL") private var baseURL = "https://hapi.fhir.org/baseR4"
    @AppStorage("fhirUser") private var user = ""
    @State private var password = ""
    @State private var patient = ""
    @State private var modality = ""
    @State private var rows: [FHIRRow] = []
    @State private var status: String?
    @State private var busy = false
    @State private var op: Task<Void, Never>?

    private var client: FHIRClient { FHIRClient(baseURL: baseURL, username: user, password: password) }

    private static let keychainService = "DicomBench.fhir"
    private func loadPassword() {
        password = Keychain.get(service: Self.keychainService, account: baseURL) ?? ""
    }
    private func savePassword() {
        Keychain.set(password, service: Self.keychainService, account: baseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("FHIR", subtitle: "Search ImagingStudy resources (FHIR R4)", symbol: "waveform.path")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text("Base URL").font(.caption).foregroundStyle(.secondary)
                        TextField("https://server/baseR4", text: $baseURL)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                        Text("User").font(.caption).foregroundStyle(.secondary)
                        TextField("(optional)", text: $user)
                            .textFieldStyle(.roundedBorder).frame(width: 110)
                        Text("Password").font(.caption).foregroundStyle(.secondary)
                        SecureField("", text: $password)
                            .textFieldStyle(.roundedBorder).frame(width: 130)
                    }
                    HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
                        field("Patient", $patient, "patient id/name")
                        field("Modality", $modality, "CT, MR…")
                        Button { runSearch() } label: { Label("Search", systemImage: "magnifyingglass") }
                            .buttonStyle(.glassProminent).disabled(busy)
                    }
                    HStack {
                        if busy {
                            ProgressView().controlSize(.small)
                            Button("Cancel") { op?.cancel() }.controlSize(.small)
                        }
                        if let status { Text(status).foregroundStyle(.secondary).font(.callout) }
                        Spacer()
                        TableExport(header: ["Patient", "Started", "Modality", "Series", "Instances", "Description", "StudyUID"],
                                    rows: rows.map { r in ["Patient", "Started", "Modality", "Series",
                                                           "Instances", "Description", "StudyUID"].map { r.v($0) } },
                                    filename: "fhir-imagingstudy.csv")
                    }
                }
                .onSubmit { if !busy { runSearch() } }
            }

            Table(rows) {
                TableColumn("Patient") { Text($0.v("Patient")) }
                TableColumn("Started") { Text($0.v("Started")) }
                TableColumn("Modality") { Text($0.v("Modality")) }
                TableColumn("Series") { Text($0.v("Series")) }
                TableColumn("Instances") { Text($0.v("Instances")) }
                TableColumn("Description") { Text($0.v("Description")) }
            }
            .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .onAppear { if password.isEmpty { loadPassword() } }
        .onChange(of: baseURL) { _, _ in loadPassword() }
    }

    private func field(_ name: String, _ binding: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: binding).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
        }
    }

    private func runSearch() {
        busy = true; status = nil; rows = []
        var filters: [String: String] = [:]
        if !patient.isEmpty { filters["patient"] = patient }
        if !modality.isEmpty { filters["modality"] = modality }
        let c = client
        op = Task {
            do {
                let r = try await c.searchImagingStudies(filters: filters)
                rows = r.map { FHIRRow(values: $0) }
                status = "\(rows.count) ImagingStudy resource(s)"
                savePassword()
            } catch is CancellationError { status = "Cancelled" }
            catch let e as URLError where e.code == .cancelled { status = "Cancelled" }
            catch { status = error.localizedDescription }
            busy = false
        }
    }
}
