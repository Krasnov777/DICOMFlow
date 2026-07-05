import SwiftUI

private struct QRRow: Identifiable {
    let id: String
    let values: [String: String]
    func v(_ k: String) -> String { values[k] ?? "" }
}

/// C-FIND query at study level, drill into series, then C-GET/C-MOVE a whole
/// study or a single series.
struct QueryRetrieveView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var target: TesterTarget
    @EnvironmentObject var appState: AppState

    @State private var patientName = ""
    @State private var modality = ""
    @State private var studyDate = ""
    @State private var rows: [QRRow] = []
    @State private var selection: QRRow.ID?
    @State private var seriesRows: [QRRow] = []
    @State private var seriesSelection: QRRow.ID?
    @State private var status: String?
    @State private var busy = false
    @State private var useMove = false
    @State private var opID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Query / Retrieve", subtitle: "C-FIND a PACS, then C-GET or C-MOVE",
                       symbol: "magnifyingglass")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TargetForm()
                    HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
                        field("Patient", $patientName, "name or *")
                        field("Modality", $modality, "CT, MR…")
                        field("Study Date", $studyDate, "YYYYMMDD")
                        Button { runQuery() } label: { Label("C-FIND", systemImage: "magnifyingglass") }
                            .buttonStyle(.glassProminent)
                            .disabled(busy || !sidecar.ready)
                    }
                    .onSubmit { if !busy { runQuery() } }
                    HStack {
                        if busy {
                            ProgressView().controlSize(.small)
                            Button("Dismiss") { cancelOp() }.controlSize(.small)
                        }
                        if let status { Text(status).foregroundStyle(.secondary).font(.callout) }
                        Spacer()
                        TableExport(header: ["Patient", "Study Date", "Description", "Modalities", "Series", "StudyInstanceUID"],
                                    rows: rows.map { r in ["PatientName", "StudyDate", "StudyDescription",
                                                           "ModalitiesInStudy", "NumberOfStudyRelatedSeries",
                                                           "StudyInstanceUID"].map { r.v($0) } },
                                    filename: "qr-studies.csv")
                        Toggle("C-MOVE", isOn: $useMove).toggleStyle(.switch).controlSize(.small)
                        Button { runRetrieve() } label: {
                            Label(seriesSelection == nil ? "Retrieve Study" : "Retrieve Series",
                                  systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.glass)
                        .disabled(busy || selection == nil)
                    }
                }
            }

            Table(rows, selection: $selection) {
                TableColumn("Patient") { Text($0.v("PatientName")) }
                TableColumn("Study Date") { Text($0.v("StudyDate")) }
                TableColumn("Description") { Text($0.v("StudyDescription")) }
                TableColumn("Modalities") { Text($0.v("ModalitiesInStudy")) }
                TableColumn("Series") { Text($0.v("NumberOfStudyRelatedSeries")) }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .onChange(of: selection) { _, _ in runSeriesQuery() }

            if selection != nil {
                HStack {
                    Text(seriesRows.isEmpty ? "Series" : "Series (\(seriesRows.count)) — select one to retrieve it alone")
                        .font(.headline)
                    Spacer()
                    TableExport(header: ["#", "Modality", "Description", "Instances", "SeriesInstanceUID"],
                                rows: seriesRows.map { r in ["SeriesNumber", "Modality", "SeriesDescription",
                                                             "NumberOfSeriesRelatedInstances", "SeriesInstanceUID"].map { r.v($0) } },
                                filename: "qr-series.csv")
                }
                Table(seriesRows, selection: $seriesSelection) {
                    TableColumn("#") { Text($0.v("SeriesNumber")) }.width(40)
                    TableColumn("Modality") { Text($0.v("Modality")) }.width(70)
                    TableColumn("Description") { Text($0.v("SeriesDescription")) }
                    TableColumn("Instances") { Text($0.v("NumberOfSeriesRelatedInstances")) }.width(70)
                    TableColumn("Series UID") { Text($0.v("SeriesInstanceUID")).font(.caption.monospaced()) }
                }
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private func field(_ name: String, _ binding: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: binding).textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    /// Unblock the UI. The in-flight DIMSE call keeps running in the background
    /// (bounded by the network timeout) but its result is discarded.
    private func cancelOp() {
        opID += 1
        busy = false
        status = "Dismissed — the request may still be running."
    }

    private func runQuery() {
        guard let client = sidecar.client else { return }
        busy = true; status = nil; rows = []; selection = nil
        var filters: [String: String] = [:]
        if !patientName.isEmpty { filters["PatientName"] = patientName }
        if !modality.isEmpty { filters["ModalitiesInStudy"] = modality }
        if !studyDate.isEmpty { filters["StudyDate"] = studyDate }
        let (h, p, ae, cae) = (target.host, target.port, target.aeTitle, target.callingAE)
        let id = opID
        Task {
            do {
                let r = try await client.query(host: h, port: p, aeTitle: ae,
                                               level: "STUDY", filters: filters, callingAE: cae)
                guard id == opID else { return }
                if r.success {
                    rows = (r.results ?? []).enumerated().map { i, d in
                        QRRow(id: d["StudyInstanceUID"] ?? "row\(i)", values: d)
                    }
                    status = "\(rows.count) studies"
                } else { status = r.message ?? "Query failed" }
            } catch { guard id == opID else { return }; status = error.localizedDescription }
            if id == opID { busy = false }
        }
    }

    /// C-FIND at SERIES level for the selected study.
    private func runSeriesQuery() {
        seriesRows = []; seriesSelection = nil
        guard let client = sidecar.client, let id = selection,
              let row = rows.first(where: { $0.id == id }) else { return }
        let studyUID = row.v("StudyInstanceUID")
        guard !studyUID.isEmpty else { return }
        let (h, p, ae, cae) = (target.host, target.port, target.aeTitle, target.callingAE)
        let opID = opID
        Task {
            do {
                let r = try await client.query(host: h, port: p, aeTitle: ae, level: "SERIES",
                                               filters: ["StudyInstanceUID": studyUID], callingAE: cae)
                guard opID == self.opID, selection == id else { return }
                guard r.success else { status = r.message ?? "Series query failed"; return }
                seriesRows = (r.results ?? []).enumerated()
                    .map { i, d in QRRow(id: d["SeriesInstanceUID"] ?? "s\(i)", values: d) }
                    .sorted { (Int($0.v("SeriesNumber")) ?? 0) < (Int($1.v("SeriesNumber")) ?? 0) }
            } catch {
                guard opID == self.opID, selection == id else { return }
                status = error.localizedDescription
            }
        }
    }

    private func runRetrieve() {
        guard let client = sidecar.client, let id = selection,
              let row = rows.first(where: { $0.id == id }) else { return }
        let uid = row.v("StudyInstanceUID")
        var level = "STUDY"
        var keys = ["StudyInstanceUID": uid]
        if let sid = seriesSelection, let s = seriesRows.first(where: { $0.id == sid }) {
            level = "SERIES"
            keys["SeriesInstanceUID"] = s.v("SeriesInstanceUID")
        }
        busy = true; status = level == "SERIES" ? "Retrieving series…" : "Retrieving study…"
        let (h, p, ae, cae) = (target.host, target.port, target.aeTitle, target.callingAE)
        let method = useMove ? "move" : "get"
        let opID = opID
        Task {
            do {
                let r = try await client.retrieve(host: h, port: p, aeTitle: ae, level: level,
                                                  keys: keys,
                                                  method: method, moveDestination: nil, callingAE: cae)
                guard opID == self.opID else { return }
                if r.success {
                    status = "Received \(r.received ?? 0) instances"
                    if let dir = r.receivedDir, (r.received ?? 0) > 0 { appState.openInViewer(directory: dir) }
                } else { status = r.message ?? "Retrieve failed" }
            } catch { guard opID == self.opID else { return }; status = error.localizedDescription }
            if opID == self.opID { busy = false }
        }
    }
}
