import SwiftUI
import AppKit

/// Builds a synthetic DICOM series on demand — a stackable volume for testing the
/// viewer, C-STORE, validator, etc. without needing real patient data.
struct GeneratorView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var appState: AppState

    enum Modality: String, CaseIterable, Identifiable {
        case ct = "CT", mr = "MR", sc = "Secondary Capture"
        var id: String { rawValue }
        var sopClass: String {
            switch self {
            case .ct: return "1.2.840.10008.5.1.4.1.1.2"
            case .mr: return "1.2.840.10008.5.1.4.1.1.4"
            case .sc: return "1.2.840.10008.5.1.4.1.1.7"
            }
        }
    }
    private let patterns = ["sphere", "gradient", "rings", "checkerboard", "noise", "solid"]

    @State private var modality = Modality.ct
    @State private var size = 256
    @State private var slices = 64
    @State private var pattern = "sphere"
    @State private var busy = false
    @State private var result: DicomEngine.GenerateResult?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Synthetic Generator", subtitle: "Build a test DICOM series on demand",
                       symbol: "wand.and.stars")

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.xl) {
                        Picker("Modality", selection: $modality) {
                            ForEach(Modality.allCases) { Text($0.rawValue).tag($0) }
                        }.fixedSize()
                        Picker("Pattern", selection: $pattern) {
                            ForEach(patterns, id: \.self) { Text($0.capitalized).tag($0) }
                        }.fixedSize()
                    }
                    HStack(spacing: Theme.Spacing.xl) {
                        stepper("Size (px²)", value: $size, range: 32...1024, step: 32)
                        if modality != .sc {
                            stepper("Slices", value: $slices, range: 1...512, step: 16)
                        }
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        Button { generate() } label: { Label("Generate", systemImage: "wand.and.stars") }
                            .buttonStyle(.glassProminent).disabled(busy || !sidecar.ready)
                        if busy { ProgressView().controlSize(.small) }
                        if let r = result {
                            StatusPill(r.message, state: r.success ? .ok : .error,
                                       symbol: r.success ? "checkmark.seal.fill" : "xmark.octagon")
                        }
                    }
                }
            }

            if let r = result, r.success {
                Card {
                    HStack(spacing: Theme.Spacing.md) {
                        Button { appState.openInViewer(directory: r.dir) } label: {
                            Label("Open in Viewer", systemImage: "cube.transparent")
                        }.buttonStyle(.glass)
                        Button { appState.sendToStore(files: r.files) } label: {
                            Label("Send to C-STORE", systemImage: "paperplane")
                        }.buttonStyle(.glass).disabled(r.files.isEmpty)
                        Button { saveCopy(r) } label: {
                            Label("Save a Copy…", systemImage: "square.and.arrow.down")
                        }.buttonStyle(.glass)
                        Spacer()
                    }
                }
            } else {
                EmptyState(symbol: "wand.and.stars", title: "No dataset yet",
                           message: "Pick a modality, pattern and size, then Generate — a phantom volume you can open, validate, or send to a PACS.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)").font(.callout.monospacedDigit()).frame(width: 44, alignment: .leading)
            }.fixedSize()
        }
    }

    private func generate() {
        busy = true; result = nil
        let dir = NSTemporaryDirectory() + "dicomflow-synth"
        try? FileManager.default.removeItem(atPath: dir)
        let (sop, n, s, pat) = (modality.sopClass, size, modality == .sc ? 1 : slices, pattern)
        Task {
            result = await sidecar.generateDataset(dir: dir, sopClass: sop, rows: n, columns: n,
                                                    slices: s, pattern: pat)
            busy = false
        }
    }

    private func saveCopy(_ r: DicomEngine.GenerateResult) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let fm = FileManager.default
        for f in r.files {
            let out = dest.appendingPathComponent((f as NSString).lastPathComponent)
            try? fm.removeItem(at: out)
            try? fm.copyItem(at: URL(fileURLWithPath: f), to: out)
        }
    }
}
