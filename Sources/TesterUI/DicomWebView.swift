import SwiftUI
import UniformTypeIdentifiers

private struct WebStudy: Identifiable {
    let id: String
    let values: [String: String]
    func v(_ k: String) -> String { values[k] ?? "" }
}

/// DICOMweb tester: QIDO-RS query, WADO-RS retrieve → viewer, STOW-RS store.
struct DicomWebView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var appState: AppState

    @AppStorage("dicomWebURL") private var baseURL = "http://127.0.0.1:8042/dicom-web"
    @AppStorage("dicomWebUser") private var user = "admin"
    @State private var password = ""

    @State private var patientName = ""
    @State private var studyDate = ""
    @State private var modality = ""

    @State private var studies: [WebStudy] = []
    @State private var selection: WebStudy.ID?
    @State private var series: [WebStudy] = []
    @State private var seriesSelection: WebStudy.ID?
    @State private var status: String?
    @State private var busy = false
    @State private var showImporter = false
    @State private var showInstances = false
    @State private var op: Task<Void, Never>?

    private var client: DicomWebClient {
        DicomWebClient(baseURL: baseURL, username: user, password: password)
    }

    private static let keychainService = "DicomBench.dicomweb"
    private func loadPassword() {
        password = Keychain.get(service: Self.keychainService, account: baseURL) ?? ""
    }
    /// Persist only credentials that actually worked.
    private func savePassword() {
        Keychain.set(password, service: Self.keychainService, account: baseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("DICOMweb", subtitle: "QIDO-RS query · WADO-RS retrieve · STOW-RS store",
                       symbol: "globe")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("Base URL").gridColumnAlignment(.trailing)
                            TextField("http://host:8042/dicom-web", text: $baseURL).frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Text("User").gridColumnAlignment(.trailing)
                            HStack {
                                TextField("admin", text: $user).frame(maxWidth: 160)
                                Text("Password").foregroundStyle(.secondary)
                                SecureField("", text: $password).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
                        field("Patient", $patientName, "name or *")
                        field("Study Date", $studyDate, "YYYYMMDD")
                        field("Modality", $modality, "CT, MR…")
                        Button { runQuery() } label: { Label("QIDO Search", systemImage: "magnifyingglass") }
                            .buttonStyle(.glassProminent).disabled(busy)
                    }
                    .onSubmit { if !busy { runQuery() } }

                    HStack {
                        if busy {
                            ProgressView().controlSize(.small)
                            Button("Cancel") { op?.cancel() }.controlSize(.small)
                        }
                        if let status { Text(status).foregroundStyle(.secondary).font(.callout) }
                        Spacer()
                        TableExport(header: ["Patient", "Study Date", "Description", "Modalities", "Series", "StudyInstanceUID"],
                                    rows: studies.map { r in ["PatientName", "StudyDate", "StudyDescription",
                                                              "ModalitiesInStudy", "NumberOfStudyRelatedSeries",
                                                              "StudyInstanceUID"].map { r.v($0) } },
                                    filename: "dicomweb-studies.csv")
                        Button { showImporter = true } label: { Label("STOW Upload…", systemImage: "arrow.up.doc") }
                            .buttonStyle(.glass).disabled(busy)
                        Button { runRetrieve() } label: {
                            Label(seriesSelection == nil ? "Retrieve Study → Viewer" : "Retrieve Series → Viewer",
                                  systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.glass).disabled(busy || selection == nil)
                    }
                }
            }

            Table(studies, selection: $selection) {
                TableColumn("Patient") { Text($0.v("PatientName")) }
                TableColumn("Study Date") { Text($0.v("StudyDate")) }
                TableColumn("Description") { Text($0.v("StudyDescription")) }
                TableColumn("Modalities") { Text($0.v("ModalitiesInStudy")) }
                TableColumn("Series") { Text($0.v("NumberOfStudyRelatedSeries")) }
            }
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .onChange(of: selection) { _, _ in runSeriesQuery() }

            if selection != nil {
                HStack {
                    Text(series.isEmpty ? "Series" : "Series (\(series.count)) — select one to retrieve it alone")
                        .font(.headline)
                    Spacer()
                    Button { showInstances = true } label: { Label("Instances…", systemImage: "square.stack.3d.up") }
                        .buttonStyle(.glass).controlSize(.small)
                        .disabled(seriesSelection == nil)
                }
                Table(series, selection: $seriesSelection) {
                    TableColumn("#") { Text($0.v("SeriesNumber")) }.width(40)
                    TableColumn("Modality") { Text($0.v("Modality")) }.width(70)
                    TableColumn("Description") { Text($0.v("SeriesDescription")) }
                    TableColumn("Instances") { Text($0.v("NumberOfSeriesRelatedInstances")) }.width(70)
                    TableColumn("Series UID") { Text($0.v("SeriesInstanceUID")).font(.caption.monospaced()) }
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { runStore(urls) }
        }
        .onAppear { if password.isEmpty { loadPassword() } }
        .onChange(of: baseURL) { _, _ in loadPassword() }
        .sheet(isPresented: $showInstances) {
            if let id = selection, let st = studies.first(where: { $0.id == id }),
               let sid = seriesSelection, let se = series.first(where: { $0.id == sid }) {
                InstancesSheet(client: client,
                               studyUID: st.v("StudyInstanceUID"),
                               seriesUID: se.v("SeriesInstanceUID"),
                               title: "Series \(se.v("SeriesNumber")) · \(se.v("Modality"))")
            }
        }
    }

    private func field(_ name: String, _ binding: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: binding).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
        }
    }

    private func runQuery() {
        busy = true; status = nil; studies = []; selection = nil
        var filters: [String: String] = [:]
        if !patientName.isEmpty { filters["PatientName"] = patientName }
        if !studyDate.isEmpty { filters["StudyDate"] = studyDate }
        if !modality.isEmpty { filters["ModalitiesInStudy"] = modality }
        let c = client
        op = Task {
            do {
                let rows = try await c.queryStudies(filters: filters)
                studies = rows.enumerated().map { i, d in
                    WebStudy(id: d["StudyInstanceUID"].flatMap { $0.isEmpty ? nil : $0 } ?? "row\(i)", values: d)
                }
                status = "\(studies.count) studies"
                savePassword()
            } catch is CancellationError { status = "Cancelled" }
            catch let e as URLError where e.code == .cancelled { status = "Cancelled" }
            catch { status = error.localizedDescription }
            busy = false
        }
    }

    /// QIDO the series of the selected study.
    private func runSeriesQuery() {
        series = []; seriesSelection = nil
        guard let id = selection, let row = studies.first(where: { $0.id == id }) else { return }
        let uid = row.v("StudyInstanceUID")
        guard !uid.isEmpty else { return }
        let c = client
        Task {
            do {
                let rows = try await c.querySeries(studyUID: uid)
                guard selection == id else { return }
                series = rows
                    .map { WebStudy(id: $0["SeriesInstanceUID"] ?? UUID().uuidString, values: $0) }
                    .sorted { (Int($0.v("SeriesNumber")) ?? 0) < (Int($1.v("SeriesNumber")) ?? 0) }
            } catch {
                guard selection == id else { return }
                status = error.localizedDescription
            }
        }
    }

    private func runRetrieve() {
        guard let id = selection, let row = studies.first(where: { $0.id == id }) else { return }
        let uid = row.v("StudyInstanceUID")
        guard !uid.isEmpty else { status = "No StudyInstanceUID"; return }
        let seriesUID = seriesSelection.flatMap { sid in series.first(where: { $0.id == sid }) }?
            .v("SeriesInstanceUID")
        busy = true; status = seriesUID != nil ? "Retrieving series…" : "Retrieving study…"
        let dir = NSTemporaryDirectory() + "dicomweb_" + UUID().uuidString
        let c = client
        op = Task {
            do {
                let n: Int
                if let seriesUID, !seriesUID.isEmpty {
                    n = try await c.retrieveSeries(studyUID: uid, seriesUID: seriesUID, outDir: dir)
                } else {
                    n = try await c.retrieveStudy(studyUID: uid, outDir: dir)
                }
                status = "Retrieved \(n) instances"
                savePassword()
                if n > 0 { appState.openInViewer(directory: dir) }
            } catch is CancellationError { status = "Cancelled" }
            catch let e as URLError where e.code == .cancelled { status = "Cancelled" }
            catch { status = error.localizedDescription }
            busy = false
        }
    }

    // MARK: instance drill-down sheet

    private struct InstanceRow: Identifiable {
        let id: String            // SOPInstanceUID
        let values: [String: String]
        func v(_ k: String) -> String { values[k] ?? "" }
    }

    struct InstancesSheet: View {
        let client: DicomWebClient
        let studyUID: String
        let seriesUID: String
        let title: String
        @Environment(\.dismiss) private var dismiss

        struct MetaRow: Identifiable {
            let tag: String, vr: String, value: String
            var id: String { tag }
        }

        @State private var instances: [InstanceRow] = []
        @State private var selection: InstanceRow.ID?
        @State private var metadata: [MetaRow] = []
        @State private var preview: NSImage?
        @State private var status: String?

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text(title).font(.headline)
                    Text("\(instances.count) instance(s)").foregroundStyle(.secondary)
                    if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                HSplitView {
                    Table(instances, selection: $selection) {
                        TableColumn("#") { Text($0.v("InstanceNumber")) }.width(40)
                        TableColumn("Size") { Text("\($0.v("Rows"))×\($0.v("Columns"))") }.width(80)
                        TableColumn("SOP Instance UID") { Text($0.id).font(.caption.monospaced()) }
                    }
                    .frame(minWidth: 320)
                    .onChange(of: selection) { _, _ in loadDetail() }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if let preview {
                            Image(nsImage: preview)
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
                        }
                        if metadata.isEmpty {
                            EmptyState(symbol: "square.stack.3d.up",
                                       title: selection == nil ? "Select an instance" : "Loading…",
                                       message: "Rendered preview + full DICOM-JSON metadata appear here.")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Table(metadata) {
                                TableColumn("Tag") { Text($0.tag).monospaced() }.width(80)
                                TableColumn("VR") { Text($0.vr).monospaced() }.width(36)
                                TableColumn("Value") { Text($0.value).monospaced() }
                            }
                        }
                    }
                    .frame(minWidth: 300)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(minWidth: 760, minHeight: 480)
            .task { await loadInstances() }
        }

        private func loadInstances() async {
            do {
                let rows = try await client.queryInstances(studyUID: studyUID, seriesUID: seriesUID)
                instances = rows
                    .map { InstanceRow(id: $0["SOPInstanceUID"] ?? UUID().uuidString, values: $0) }
                    .sorted { (Int($0.v("InstanceNumber")) ?? 0) < (Int($1.v("InstanceNumber")) ?? 0) }
            } catch { status = error.localizedDescription }
        }

        private func loadDetail() {
            metadata = []; preview = nil
            guard let sop = selection else { return }
            Task {
                do {
                    async let meta = client.instanceMetadata(studyUID: studyUID, seriesUID: seriesUID, sopUID: sop)
                    async let img = client.renderedInstance(studyUID: studyUID, seriesUID: seriesUID, sopUID: sop)
                    let rows = try await meta
                    let image = NSImage(data: try await img)
                    guard selection == sop else { return }   // discard if selection moved on
                    metadata = rows.map { MetaRow(tag: $0.tag, vr: $0.vr, value: $0.value) }
                    preview = image
                } catch { status = error.localizedDescription }
            }
        }
    }

    private func runStore(_ urls: [URL]) {
        busy = true; status = "Uploading…"
        let fm = FileManager.default
        let files = urls.flatMap { url -> [String] in
            _ = url.startAccessingSecurityScopedResource()
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                // enumerator(at:) with isDirectory keys so we can skip subdirectories
                // (allObjects on the path-based enumerator would hand STOW folders).
                return (fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey])?
                    .allObjects as? [URL] ?? [])
                    .filter { !$0.hasDirectoryPath }.map(\.path)
            }
            return [url.path]
        }
        let c = client
        op = Task {
            defer { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                let r = try await c.store(files: files)
                status = "Stored \(r.stored), failed \(r.failed)"
                savePassword()
            } catch is CancellationError { status = "Cancelled" }
            catch let e as URLError where e.code == .cancelled { status = "Cancelled" }
            catch { status = error.localizedDescription }
            busy = false
        }
    }
}
