import SwiftUI

private struct MWLRow: Identifiable {
    let id = UUID()
    let values: [String: String]
    func v(_ k: String) -> String { values[k] ?? "" }
}

/// Modality Worklist (MWL) C-FIND: query scheduled procedure steps.
struct WorklistView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var target: TesterTarget

    @State private var patientName = ""
    @State private var modality = ""
    @State private var stationAE = ""
    @State private var date = ""
    @State private var rows: [MWLRow] = []
    @State private var status: String?
    @State private var busy = false
    @State private var opID = 0

    private static let exportKeys = ["PatientName", "Modality", "ScheduledProcedureStepStartDate",
                                     "ScheduledProcedureStepStartTime", "ScheduledProcedureStepDescription",
                                     "ScheduledStationAETitle", "AccessionNumber"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Worklist", subtitle: "Modality Worklist C-FIND — scheduled procedure steps",
                       symbol: "calendar.badge.clock")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TargetForm()
                    HStack(alignment: .bottom, spacing: Theme.Spacing.md) {
                        field("Patient", $patientName, "name or *")
                        field("Modality", $modality, "CT, MR…")
                        field("Station AE", $stationAE, "e.g. CT01")
                        field("Date", $date, "YYYYMMDD or range")
                        Button { runQuery() } label: { Label("Query", systemImage: "magnifyingglass") }
                            .buttonStyle(.glassProminent).disabled(busy || !sidecar.ready)
                    }
                    HStack {
                        if busy {
                            ProgressView().controlSize(.small)
                            Button("Dismiss") { cancelOp() }.controlSize(.small)
                        }
                        if let status { Text(status).foregroundStyle(.secondary).font(.callout) }
                        Spacer()
                        Text("Tip: date supports ranges, e.g. 20260101-20260131.")
                            .font(.caption).foregroundStyle(.tertiary)
                        TableExport(header: ["Patient", "Modality", "Date", "Time", "Step", "Station AE", "Accession"],
                                    rows: rows.map { r in Self.exportKeys.map { r.v($0) } },
                                    filename: "worklist.csv")
                    }
                }
            }
            .onSubmit { runQuery() }

            Table(rows) {
                TableColumn("Patient") { Text($0.v("PatientName")) }
                TableColumn("Modality") { Text($0.v("Modality")) }
                TableColumn("Date") { Text($0.v("ScheduledProcedureStepStartDate")) }
                TableColumn("Time") { Text($0.v("ScheduledProcedureStepStartTime")) }
                TableColumn("Step") { Text($0.v("ScheduledProcedureStepDescription")) }
                TableColumn("Station AE") { Text($0.v("ScheduledStationAETitle")) }
                TableColumn("Accession") { Text($0.v("AccessionNumber")) }
            }
            .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func field(_ name: String, _ binding: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: binding).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
        }
    }

    private func cancelOp() {
        opID += 1
        busy = false
        status = "Dismissed — the request may still be running."
    }

    private func runQuery() {
        guard let client = sidecar.client, !busy else { return }
        busy = true; status = nil; rows = []
        var filters: [String: String] = [:]
        if !patientName.isEmpty { filters["PatientName"] = patientName }
        if !modality.isEmpty { filters["Modality"] = modality }
        if !stationAE.isEmpty { filters["ScheduledStationAETitle"] = stationAE }
        if !date.isEmpty { filters["ScheduledProcedureStepStartDate"] = date }
        let (h, p, ae, cae) = (target.host, target.port, target.aeTitle, target.callingAE)
        let id = opID
        Task {
            do {
                let r = try await client.worklistQuery(host: h, port: p, aeTitle: ae, filters: filters, callingAE: cae)
                guard id == opID else { return }
                if r.success {
                    rows = (r.results ?? []).map { MWLRow(values: $0) }
                    status = "\(rows.count) scheduled step(s)"
                } else { status = r.message ?? "Query failed" }
            } catch { guard id == opID else { return }; status = error.localizedDescription }
            if id == opID { busy = false }
        }
    }
}
