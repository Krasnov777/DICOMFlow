import SwiftUI
import Vision
import AppKit
import UniformTypeIdentifiers

/// Detect text burned into an image (Vision OCR) and black it out of the pixel
/// data — for de-identifying US clips, secondary captures, screenshots etc. where
/// PHI is in the pixels, not the tags.
struct RedactView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @State private var fileURL: URL?
    @State private var cgImage: CGImage?
    @State private var detections: [Detection] = []
    @State private var busy = false
    @State private var status: String?
    @State private var showImporter = false

    struct Detection: Identifiable {
        let id = UUID()
        let text: String
        var rect: CGRect      // normalized, top-left origin
        var on = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("Redact Burned-in Text", subtitle: "Detect and black out PHI burned into the image",
                       symbol: "eye.slash")

            Card {
                HStack(spacing: Theme.Spacing.md) {
                    Button { showImporter = true } label: { Label("Open Image…", systemImage: "photo.badge.plus") }
                        .buttonStyle(.glass).disabled(!sidecar.ready)
                    if cgImage != nil {
                        Button { detect() } label: { Label("Detect Text", systemImage: "text.viewfinder") }
                            .buttonStyle(.glass)
                        Button { redact() } label: { Label("Redact & Save…", systemImage: "eye.slash") }
                            .buttonStyle(.glassProminent).disabled(!detections.contains { $0.on })
                    }
                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                    if !detections.isEmpty {
                        Text("\(detections.filter { $0.on }.count)/\(detections.count) region(s)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let status {
                Card { Label(status, systemImage: "info.circle").foregroundStyle(.secondary) }
            }

            if let cg = cgImage {
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    imageView(cg)
                    if !detections.isEmpty { detectionList }
                }
            } else {
                EmptyState(symbol: "eye.slash", title: "No image loaded",
                           message: "Open a DICOM image with burned-in text (ultrasound, secondary capture, screenshots). Detect the text, review the regions, then redact them out of the pixels.",
                           actionTitle: "Open Image…") { showImporter = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item],
                      allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let url = urls.first { load(url) }
        }
    }

    private func imageView(_ cg: CGImage) -> some View {
        GeometryReader { geo in
            let fit = fittedRect(imageSize: CGSize(width: cg.width, height: cg.height), in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: cg, scale: 1)
                    .resizable().frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
                ForEach(detections) { d in
                    Rectangle()
                        .strokeBorder(d.on ? Color.red : Color.gray, lineWidth: 1.5)
                        .background((d.on ? Color.red : Color.gray).opacity(0.25))
                        .frame(width: d.rect.width * fit.width, height: d.rect.height * fit.height)
                        .position(x: fit.minX + d.rect.midX * fit.width,
                                  y: fit.minY + d.rect.midY * fit.height)
                        .onTapGesture { toggle(d) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var detectionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Detected text").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(detections) { d in
                        Toggle(isOn: Binding(get: { d.on }, set: { _ in toggle(d) })) {
                            Text(d.text).font(.callout).lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
    }

    private func fittedRect(imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func toggle(_ d: Detection) {
        if let i = detections.firstIndex(where: { $0.id == d.id }) { detections[i].on.toggle() }
    }

    private func load(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        fileURL = url; cgImage = nil; detections = []; status = nil; busy = true
        let path = url.path
        Task {
            cgImage = await sidecar.renderDisplayImage(path: path)
            busy = false
            if cgImage == nil { status = "Could not render this file as an image." }
        }
    }

    private func detect() {
        guard let cg = cgImage else { return }
        busy = true; status = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([req])
            let obs = req.results ?? []
            let dets = obs.compactMap { o -> Detection? in
                guard let top = o.topCandidates(1).first else { return nil }
                let bb = o.boundingBox   // normalized, bottom-left origin
                let rect = CGRect(x: bb.minX, y: 1 - bb.minY - bb.height, width: bb.width, height: bb.height)
                return Detection(text: top.string, rect: rect)
            }
            DispatchQueue.main.async {
                detections = dets
                busy = false
                status = dets.isEmpty ? "No text detected." : "Found \(dets.count) text region(s) — review, then redact."
            }
        }
    }

    private func redact() {
        guard let src = fileURL else { return }
        let on = detections.filter { $0.on }
        guard !on.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\((src.lastPathComponent as NSString).deletingPathExtension)-redacted.dcm"
        panel.allowedContentTypes = [UTType(filenameExtension: "dcm") ?? .data]
        guard panel.runModal() == .OK, let out = panel.url else { return }
        // Pad boxes slightly so anti-aliased glyph edges are covered.
        let pad = 0.004
        let rects = on.map { d -> [Double] in
            [max(0, d.rect.minX - pad), max(0, d.rect.minY - pad),
             min(1, d.rect.width + 2 * pad), min(1, d.rect.height + 2 * pad)]
        }
        busy = true; status = "Redacting…"
        let srcPath = src.path, outPath = out.path
        _ = out.startAccessingSecurityScopedResource()
        Task {
            defer { out.stopAccessingSecurityScopedResource() }
            let r = await sidecar.redact(path: srcPath, rects: rects, outputPath: outPath)
            busy = false
            status = r.message
            if r.success { cgImage = await sidecar.renderDisplayImage(path: outPath) }  // show redacted result
        }
    }
}
