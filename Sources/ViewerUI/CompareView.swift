import SwiftUI
import UniformTypeIdentifiers

/// Side-by-side comparison of two series (axial). The left pane shows the primary
/// volume; the right pane loads a second series — from the same study or an
/// external file/folder. With "Sync" on (bottom bar), both panes scroll together.
struct CompareView: View {
    @EnvironmentObject var viewer: ViewerState
    @EnvironmentObject var sidecar: DicomEngine
    @AppStorage("inputDevice") private var inputDevice = InputDevice.auto
    @AppStorage("naturalScroll") private var naturalScroll = true
    @State private var leftRenderer = MPRPlaneRenderer()
    @State private var rightRenderer = MPRPlaneRenderer()
    @State private var showImporter = false

    var body: some View {
        HStack(spacing: 2) {
            pane(volume: viewer.volume, frac: viewer.crosshair.z, renderer: leftRenderer,
                 wc: viewer.winCenter, ww: viewer.winWidth, title: title(viewer.selectedSeriesID, viewer.volume),
                 left: true)
            if viewer.compareVolume != nil {
                pane(volume: viewer.compareVolume, frac: viewer.compareFrac, renderer: rightRenderer,
                     wc: viewer.compareWinCenter, ww: viewer.compareWinWidth,
                     title: title(viewer.compareSeriesID, viewer.compareVolume), left: false)
            } else {
                chooser
            }
        }
        .background(Color.black)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item, .folder],
                      allowsMultipleSelection: true) { res in
            if case .success(let urls) = res { openCompare(urls) }
        }
    }

    // MARK: right-pane empty state

    private var chooser: some View {
        ZStack {
            Color.black
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Choose a series to compare").foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.md) {
                    if !otherSeries.isEmpty {
                        Menu("From this study") {
                            ForEach(otherSeries) { s in
                                Button(seriesLabel(s)) { viewer.loadCompareSeries(s, client: sidecar) }
                            }
                        }.fixedSize()
                    }
                    Button("Open File / Folder…") { showImporter = true }.buttonStyle(.glass)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: a pane

    private func pane(volume: Volume?, frac: Float, renderer: MPRPlaneRenderer,
                      wc: Float, ww: Float, title: String, left: Bool) -> some View {
        ZStack(alignment: .top) {
            Color.black
            if let volume {
                MetalPlaneView(renderer: renderer, volume: volume, axis: .axial,
                               sliceFrac: frac, winCenter: wc, winWidth: ww, invert: viewer.invert,
                               inputDevice: inputDevice, naturalScroll: naturalScroll,
                               onScroll: { viewer.scrollCompare(left: left, wheel: $0) },
                               onRightDrag: { d in nudgeWL(left: left, dx: d.width, dy: d.height) })
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    if let v = volume {
                        Text("Slice \(sliceIndex(frac, v.meta.nz)) / \(v.meta.nz)  ·  W \(Int(ww)) L \(Int(wc))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !left {
                    Menu {
                        ForEach(otherSeries) { s in
                            Button(seriesLabel(s)) { viewer.loadCompareSeries(s, client: sidecar) }
                        }
                        Divider()
                        Button("Open File / Folder…") { showImporter = true }
                        Button("Remove", role: .destructive) { viewer.compareVolume = nil; viewer.compareSeriesID = nil }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: helpers

    private var otherSeries: [DicomEngine.SeriesInfo] {
        viewer.series.filter { $0.id != viewer.selectedSeriesID }
    }
    private func seriesLabel(_ s: DicomEngine.SeriesInfo) -> String {
        let name = s.description.isEmpty ? s.modality : s.description
        return "\(name) (\(s.count))"
    }
    private func title(_ id: String?, _ vol: Volume?) -> String {
        if let id, let s = viewer.series.first(where: { $0.id == id }) { return seriesLabel(s) }
        return vol.map { "\($0.meta.modality) · \($0.meta.nz) slices" } ?? "—"
    }
    private func sliceIndex(_ frac: Float, _ n: Int) -> Int { Int((frac * Float(max(n - 1, 0))).rounded()) + 1 }
    private func nudgeWL(left: Bool, dx: CGFloat, dy: CGFloat) {
        if left { viewer.nudgeWindowLevel(dx: dx, dy: dy) }
        else {
            viewer.compareWinCenter += Float(dx) * 2
            viewer.compareWinWidth = max(1, viewer.compareWinWidth + Float(dy) * 2)
        }
    }
    private func openCompare(_ urls: [URL]) {
        var files: [String] = []
        let fm = FileManager.default
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let f as URL in en where !f.hasDirectoryPath { files.append(f.path) }
                }
            } else {
                files.append(url.path)
            }
        }
        if !files.isEmpty { viewer.loadCompareFiles(files, client: sidecar) }
    }
}
