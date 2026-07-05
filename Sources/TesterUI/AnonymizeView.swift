import SwiftUI
import AppKit

/// Anonymize a folder of DICOM files into a new folder, with a consistent
/// UID remap. Optionally open the result in the Viewer.
struct AnonymizeView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var appState: AppState

    @State private var inputDir: String?
    @State private var inputURL: URL?    // held for the later anonymize read
    @State private var outputURL: URL?   // held so "Open in Viewer" can read the result
    @State private var replaceName = "ANON"
    @State private var replaceID = "ANON-ID"
    @State private var basicProfile = true
    @State private var retainDates = false
    @State private var retainDevice = false
    @State private var retainPatientChars = false
    @State private var cleanDescriptors = true
    @State private var removePrivate = true
    @State private var regenUIDs = true

    @State private var result: AnonResult?
    @State private var status: String?
    @State private var busy = false
    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Anonymizer", subtitle: "De-identify a series into a new folder",
                       symbol: "person.crop.circle.badge.xmark")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Button { showInput = true } label: { Label("Choose Input Folder…", systemImage: "folder") }
                            .buttonStyle(.glass).disabled(!sidecar.ready)
                        if let inputDir {
                            Text(inputDir).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Divider()
                    HStack(spacing: Theme.Spacing.md) {
                        labeled("PatientName", text: $replaceName)
                        labeled("PatientID", text: $replaceID)
                    }
                    Toggle("Apply PS3.15 Basic Confidentiality Profile", isOn: $basicProfile)
                    if basicProfile {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Toggle("Retain dates & times", isOn: $retainDates)
                            Toggle("Retain device identity (station, serial, gantry…)", isOn: $retainDevice)
                            Toggle("Retain patient characteristics (age/sex/size/weight)", isOn: $retainPatientChars)
                            Toggle("Clean descriptors (blank study/series descriptions, comments)", isOn: $cleanDescriptors)
                        }
                        .padding(.leading, Theme.Spacing.lg)
                        .font(.callout)
                    }
                    Toggle("Remove private tags", isOn: $removePrivate)
                    Toggle("Regenerate UIDs (consistent across series)", isOn: $regenUIDs)
                }
            }

            HStack {
                Button { chooseOutputAndRun() } label: { Label("Anonymize…", systemImage: "person.crop.circle.badge.xmark") }
                    .buttonStyle(.glassProminent).disabled(inputDir == nil || busy)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if let r = result, r.success {
                    Button { appState.openInViewer(directory: r.outputDir) } label: {
                        Label("Open in Viewer", systemImage: "cube.transparent")
                    }.buttonStyle(.glass)
                }
            }

            if let status {
                Card { Label(status, systemImage: result?.success == true ? "checkmark.seal.fill" : "info.circle")
                    .foregroundStyle(result?.success == true ? .green : .secondary) }
            }
        }
        .fileImporter(isPresented: $showInput, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first {
                inputURL?.stopAccessingSecurityScopedResource()
                _ = u.startAccessingSecurityScopedResource()
                inputURL = u
                inputDir = u.path
            }
        }
    }

    private func labeled(_ name: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(name, text: text).textFieldStyle(.roundedBorder).frame(width: 180)
        }
    }

    /// Ask where to write the de-identified series, then run.
    private func chooseOutputAndRun() {
        guard inputDir != nil else { return }
        let panel = NSSavePanel()
        panel.title = "Save Anonymized Series"
        panel.message = "Choose where to write the de-identified files."
        panel.prompt = "Anonymize"
        panel.nameFieldLabel = "Output folder:"
        panel.nameFieldStringValue = "anonymized"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run(outputURL: url)
    }

    private func run(outputURL: URL) {
        guard let client = sidecar.client, let input = inputDir else { return }
        let profile = AnonProfileDTO(
            replacePatientName: replaceName.isEmpty ? nil : replaceName,
            replacePatientID: replaceID.isEmpty ? nil : replaceID,
            // With the Basic Profile on it handles dates/identifiers; otherwise fall
            // back to the legacy blanket clears.
            clearDates: !basicProfile, clearIdentifiers: !basicProfile,
            removePrivateTags: removePrivate, regenerateUIDs: regenUIDs,
            basicProfile: basicProfile, retainDates: retainDates,
            retainDeviceIdentity: retainDevice, retainPatientChars: retainPatientChars,
            cleanDescriptors: cleanDescriptors)
        busy = true; status = "Anonymizing…"; result = nil
        let out = outputURL.path
        // The save-panel URL is a security-scoped write grant; hold it (not just
        // for the write) so a subsequent "Open in Viewer" can still read the folder.
        self.outputURL?.stopAccessingSecurityScopedResource()
        _ = outputURL.startAccessingSecurityScopedResource()
        self.outputURL = outputURL
        Task {
            do {
                let r = try await client.anonymize(directory: input, outputDir: out, profile: profile)
                result = r
                status = "Anonymized \(r.processed) file(s), remapped \(r.uidsRemapped) UID(s) → \(r.outputDir)"
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
}
