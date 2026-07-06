import Foundation
import SwiftUI
import simd

/// Display transform shared by the shader and CPU hit-testing (probe/measure).
/// `toPlane` must mirror the fragment shader exactly.
struct PlaneOrientation {
    var zoom: Float = 1
    var pan: SIMD2<Float> = .zero
    var quarter: Int = 0
    var flipH = false
    var flipV = false

    private var q: Int { ((quarter % 4) + 4) % 4 }
    var swapsAspect: Bool { q % 2 == 1 }

    /// Screen uv over the fitted rect ([0,1], y-down) → plane uv.
    func toPlane(_ s: SIMD2<Float>) -> SIMD2<Float> {
        var uv = (s - 0.5) / max(zoom, 0.01) + 0.5 + pan
        if flipH { uv.x = 1 - uv.x }
        if flipV { uv.y = 1 - uv.y }
        var c = uv - 0.5
        for _ in 0..<q { c = SIMD2(-c.y, c.x) }
        return c + 0.5
    }
    /// Plane uv → screen uv (inverse of `toPlane`).
    func toScreen(_ p: SIMD2<Float>) -> SIMD2<Float> {
        var c = p - 0.5
        for _ in 0..<((4 - q) % 4) { c = SIMD2(-c.y, c.x) }
        var uv = c + 0.5
        if flipV { uv.y = 1 - uv.y }
        if flipH { uv.x = 1 - uv.x }
        return (uv - 0.5 - pan) * max(zoom, 0.01) + 0.5
    }
}

/// Active mouse tool in the 2D viewer.
enum ViewerTool: String, CaseIterable, Identifiable {
    case windowLevel = "Window/Level"
    case pan = "Pan"
    case probe = "Probe"
    case measure = "Measure"
    case roi = "ROI"
    case angle = "Angle"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .windowLevel: return "circle.lefthalf.filled"
        case .pan: return "hand.draw"
        case .probe: return "eyedropper"
        case .measure: return "ruler"
        case .roi: return "rectangle.dashed"
        case .angle: return "angle"
        }
    }
}

/// Shared viewer state: the loaded volume, window/level, and the linked
/// crosshair (normalized volume coordinates in [0,1]).
@MainActor
final class ViewerState: ObservableObject {
    @Published var volume: Volume?
    @Published var layout: ViewerLayout = .slice2D
    @Published var srText: String?            // non-nil when an SR series is shown
    @Published var colorImage: ColorImage?    // non-nil when a color image is shown
    @Published var colorFrame = 0             // current frame for a multi-frame color clip
    /// Source files backing the current view — used by "Send to PACS".
    @Published var currentFiles: [String] = []
    @Published var winCenter: Float = 40
    @Published var winWidth: Float = 400
    @Published var crosshair = SIMD3<Float>(0.5, 0.5, 0.5)
    // --- Compare (side-by-side) layout ---
    @Published var compareVolume: Volume?        // right pane
    @Published var compareSeriesID: String?
    @Published var compareFrac: Float = 0.5      // right-pane axial slice
    @Published var compareWinCenter: Float = 40
    @Published var compareWinWidth: Float = 400
    @Published var syncCompare = true
    @Published var renderMode: RenderMode = .mip
    @Published var tfPresetIndex = 0
    @Published var clipMin = SIMD3<Float>(0, 0, 0)
    @Published var clipMax = SIMD3<Float>(1, 1, 1)
    @Published var light3D = true
    @Published var isoValue: Float = 300
    @Published var requestedView: ArcballCamera.View?
    @Published var requestedReset = false       // recenter/refit the 3D camera
    @Published var showSeriesPanel = true
    // Phase D — viewer power tools
    @Published var zoom: Float = 1
    @Published var pan: SIMD2<Float> = .zero
    @Published var invert = false
    @Published var isPlaying = false
    @Published var tool: ViewerTool = .windowLevel
    /// Plane shown by the single-plane 2D layout. Switching clears measurements
    /// (their plane coordinates would be wrong on another plane).
    @Published var plane2D: MPRAxis = .axial {
        didSet { if plane2D != oldValue { clearMeasurement() } }
    }
    /// Corner info overlays (W/L, zoom, slice position) on the 2D canvas.
    @Published var showOverlays = true
    @Published var measureStart: SIMD2<Float>?   // normalized plane coords (a,b)
    @Published var measureEnd: SIMD2<Float>?
    @Published var roiStart: SIMD2<Float>?       // ROI rect corners (plane coords)
    @Published var roiEnd: SIMD2<Float>?
    @Published var anglePoints: [SIMD2<Float>] = []   // up to 3 (vertex = middle)

    /// A committed measurement. Coordinates are normalized plane coordinates
    /// (orientation-independent — they survive rotate/flip), pinned to a plane
    /// and slice.
    struct Annotation: Identifiable {
        enum Kind {
            case distance(SIMD2<Float>, SIMD2<Float>)
            case roi(SIMD2<Float>, SIMD2<Float>)
            case angle([SIMD2<Float>])
        }
        let id = UUID()
        let kind: Kind
        let plane: MPRAxis
        let slice: Float
        /// Computed once at commit for .roi (the voxel scan is expensive; never
        /// recompute it in a SwiftUI body / on every W-L tick).
        var roiStats: Volume.ROIStats?
        var symbol: String {
            switch kind {
            case .distance: return "ruler"
            case .roi: return "rectangle.dashed"
            case .angle: return "angle"
            }
        }
    }
    @Published var annotations: [Annotation] = []

    /// Whether an image (grayscale volume or color) is currently displayed.
    var hasImage: Bool { volume != nil || colorImage != nil }

    /// Step one slice (grayscale) or one frame (color clip).
    func stepSlice(_ dir: Int) {
        if let ci = colorImage {
            colorFrame = min(max(colorFrame + dir, 0), ci.frameCount - 1)
        } else {
            let axis: MPRAxis = layout == .slice2D ? plane2D : .axial
            scrollSlice(axis, wheel: dir > 0 ? -1 : 1)   // scrollSlice: wheel>0 = previous
        }
    }

    /// Reset zoom/pan (2D/MPR) or the camera (3D).
    func resetView() {
        if layout == .volume3D { requestedReset = true }
        else { zoom = 1; pan = .zero }
    }

    /// Right-drag window/level: horizontal → center, vertical → width.
    func nudgeWindowLevel(dx: CGFloat, dy: CGFloat) {
        winCenter += Float(dx) * 2
        winWidth = max(1, winWidth + Float(dy) * 2)
    }

    func commit(_ kind: Annotation.Kind) {
        var stats: Volume.ROIStats?
        if case .roi(let a, let b) = kind {
            stats = volume?.roiStats(axis: plane2D, a: a, b: b, sliceFrac: slice2D)
        }
        annotations.append(Annotation(kind: kind, plane: plane2D, slice: slice2D, roiStats: stats))
    }
    // Display orientation (applies to 2D + MPR planes)
    @Published var rotationQuarter = 0           // 90° turns (0…3)
    @Published var flipH = false
    @Published var flipV = false

    /// Rotate the displayed image 90°; measurements are cleared.
    func rotate(by delta: Int) {
        rotationQuarter = (((rotationQuarter + delta) % 4) + 4) % 4
        clearMeasurement()
    }
    func toggleFlipH() { flipH.toggle(); clearMeasurement() }
    func toggleFlipV() { flipV.toggle(); clearMeasurement() }
    func resetOrientation() { rotationQuarter = 0; flipH = false; flipV = false; clearMeasurement() }
    func clearMeasurement() {
        measureStart = nil; measureEnd = nil
        roiStart = nil; roiEnd = nil
        anglePoints = []
    }

    /// Slice fraction along the current 2D plane's axis.
    var slice2D: Float {
        get {
            switch plane2D {
            case .axial: return crosshair.z
            case .coronal: return crosshair.y
            case .sagittal: return crosshair.x
            }
        }
        set {
            switch plane2D {
            case .axial: crosshair.z = newValue
            case .coronal: crosshair.y = newValue
            case .sagittal: crosshair.x = newValue
            }
        }
    }

    /// Slice count along the current 2D plane's axis.
    var slice2DCount: Int {
        guard let m = volume?.meta else { return 1 }
        return plane2D.sliceCount(nx: m.nx, ny: m.ny, nz: m.nz)
    }
    @Published var isLoading = false
    @Published var isRefining = false       // full-res decode running after a preview
    @Published var errorText: String?
    @Published var warnings: [String] = []
    // Phase E — study/series browser
    @Published var series: [DicomEngine.SeriesInfo] = []
    @Published var selectedSeriesID: String?
    var selectedSeries: DicomEngine.SeriesInfo? { series.first { $0.id == selectedSeriesID } }

    /// Window/level presets (HU) — CT only; other modalities have no universal
    /// windows, so they get "Full range" + "Auto" instead.
    static let ctPresets: [(name: String, center: Float, width: Float)] = [
        ("CT Soft Tissue", 40, 400),
        ("CT Bone", 500, 2000),
        ("CT Lung", -600, 1500),
        ("CT Brain", 40, 80),
    ]

    /// Presets to show for the loaded modality.
    var presets: [(name: String, center: Float, width: Float)] {
        (volume?.meta.modality == "CT") ? Self.ctPresets : []
    }

    /// Window to the volume's full stored value range.
    func applyFullRangeWindow() {
        guard let m = volume?.meta else { return }
        let lo = Float(m.valueMin) * m.slope + m.intercept
        let hi = Float(m.valueMax) * m.slope + m.intercept
        winCenter = (lo + hi) / 2
        winWidth = max(hi - lo, 1)
    }

    /// Load a series from the current study into the compare (right) pane.
    func loadCompareSeries(_ info: DicomEngine.SeriesInfo, client: DicomEngine) {
        compareSeriesID = info.id
        Task { await decodeCompare(files: info.files, client: client) }
    }
    /// Load an external file/folder into the compare (right) pane.
    func loadCompareFiles(_ files: [String], client: DicomEngine) {
        compareSeriesID = nil
        Task { await decodeCompare(files: files, client: client) }
    }
    private func decodeCompare(files: [String], client: DicomEngine) async {
        guard let vol = try? await client.decodeVolume(files: files) else { return }
        compareVolume = vol
        compareWinCenter = vol.meta.defaultWindowCenter
        compareWinWidth = vol.meta.defaultWindowWidth
        compareFrac = 0.5
    }
    /// Axial scroll for a compare pane; when synced, both panes step together.
    func scrollCompare(left: Bool, wheel: Double) {
        let dir: Float = wheel > 0 ? -1 : 1
        func step(_ frac: Float, _ n: Int) -> Float {
            n > 1 ? min(1, max(0, frac + dir / Float(n - 1))) : frac
        }
        if left || syncCompare, let lv = volume { crosshair.z = step(crosshair.z, lv.meta.nz) }
        if !left || syncCompare, let rv = compareVolume { compareFrac = step(compareFrac, rv.meta.nz) }
    }

    /// Advance the slice for a plane by mouse-wheel (scroll down = next slice).
    func scrollSlice(_ axis: MPRAxis, wheel: Double) {
        guard let vol = volume else { return }
        let n: Int; let v: Float
        switch axis {
        case .axial: n = vol.meta.nz; v = crosshair.z
        case .coronal: n = vol.meta.ny; v = crosshair.y
        case .sagittal: n = vol.meta.nx; v = crosshair.x
        }
        guard n > 1 else { return }
        let dir: Float = wheel > 0 ? -1 : 1
        let nv = min(1, max(0, v + dir / Float(n - 1)))
        switch axis {
        case .axial: crosshair.z = nv
        case .coronal: crosshair.y = nv
        case .sagittal: crosshair.x = nv
        }
    }

    /// In-flight load; cancelled whenever a new load starts so a slow stale
    /// series can't overwrite a newer one (or leave selectedSeriesID mismatched).
    private var loadTask: Task<Void, Never>?

    func load(directory: String, client: DicomEngine, preferSeriesUID: String? = nil) {
        loadTask?.cancel()
        isLoading = true; errorText = nil; warnings = []; series = []; selectedSeriesID = nil
        annotations = []; clearMeasurement(); srText = nil; colorImage = nil; compareVolume = nil; compareSeriesID = nil
        loadTask = Task {
            let found = await client.scanSeries(directory: directory)
            if Task.isCancelled { return }
            self.series = found
            // Honor an explicit series request (e.g. SCP "open selected series"),
            // else pick the largest.
            if let pick = preferSeriesUID.flatMap({ uid in found.first { $0.id == uid } })
                ?? found.max(by: { $0.count < $1.count }) {
                await loadSeries(pick, client: client)
            } else {
                // No groupable series — decode the directory directly.
                await decode(files: nil, directory: directory, client: client,
                             manifest: CurrentStudy(kind: "directory", directory: directory))
            }
            self.isLoading = false
        }
    }

    /// Open a single DICOM file. Structured Reports render as text; anything
    /// else decodes just that file (a multi-frame file still yields a full,
    /// scrollable stack). The sandbox grant covers only the picked file, so the
    /// parent folder is not scanned.
    func loadFile(path: String, client: DicomEngine) {
        loadTask?.cancel()
        isLoading = true; errorText = nil; warnings = []
        series = []; selectedSeriesID = nil; currentFiles = [path]
        annotations = []; clearMeasurement(); srText = nil; colorImage = nil; compareVolume = nil; compareSeriesID = nil
        loadTask = Task {
            if let text = try? await client.readReport(path: path) {
                if Task.isCancelled { return }
                volume = nil; srText = text
                CurrentStudy(kind: "sr", files: [path]).write()
            } else if let color = await client.decodeColorImage(path: path) {
                if Task.isCancelled { return }
                volume = nil; colorImage = color; colorFrame = 0
                layout = .slice2D               // color has no MPR/3D
                CurrentStudy(kind: "file", files: [path]).write()
            } else {
                await decode(files: [path], directory: nil, client: client,
                             manifest: CurrentStudy(kind: "file", files: [path]))
            }
            isLoading = false
        }
    }

    /// Switch series from the rail — tracked so a slow prior load can't win.
    func selectSeries(_ info: DicomEngine.SeriesInfo, client: DicomEngine) {
        loadTask?.cancel()
        loadTask = Task { await loadSeries(info, client: client) }
    }

    /// Load a specific series (used by the series rail).
    func loadSeries(_ info: DicomEngine.SeriesInfo, client: DicomEngine) async {
        selectedSeriesID = info.id
        currentFiles = info.files
        errorText = nil
        let manifest = CurrentStudy(kind: info.modality == "SR" ? "sr" : "series",
                                    directory: (info.files.first as NSString?)?.deletingLastPathComponent,
                                    files: info.files, seriesUID: info.id,
                                    seriesDescription: info.description, modality: info.modality,
                                    patient: info.patient, studyDescription: info.studyDescription)
        // Structured Reports have no pixel data → show their text instead.
        if info.modality == "SR", let first = info.files.first {
            isLoading = true
            do {
                srText = try await client.readReport(path: first); volume = nil
                if !Task.isCancelled { manifest.write() }
            }
            catch { errorText = error.localizedDescription; srText = nil }
            isLoading = false
            return
        }
        isLoading = true
        await decode(files: info.files, directory: nil, client: client, manifest: manifest)
        isLoading = false
    }

    /// Decode and show a volume. `manifest` is published only after the decode
    /// SUCCEEDS and this load hasn't been superseded — the manifest must always
    /// describe what is actually on screen, never a failed or stale load.
    private func decode(files: [String]?, directory: String?, client: DicomEngine,
                        manifest: CurrentStudy? = nil) async {
        do {
            var shownPreview = false
            // Progressive load: a coarse preview (every Nth slice) shows fast, then
            // the full-resolution volume swaps in once decoded.
            if let files, files.count >= 48 {
                let step = max(2, files.count / 24)
                let preview = Swift.stride(from: 0, to: files.count, by: step).map { files[$0] }
                if preview.count >= 2, let coarse = try? await client.decodeVolume(files: preview) {
                    apply(coarse, resetView: true)
                    isLoading = false
                    isRefining = true
                    shownPreview = true
                }
            }
            let vol: Volume
            if let files { vol = try await client.decodeVolume(files: files) }
            else { vol = try await client.decodeVolume(directory: directory ?? "") }
            apply(vol, resetView: !shownPreview)
            if !Task.isCancelled { manifest?.write() }
            isRefining = false
        } catch {
            self.errorText = error.localizedDescription
            isRefining = false
        }
    }

    private func apply(_ vol: Volume, resetView: Bool) {
        if Task.isCancelled { return }   // a newer load superseded this one
        self.colorImage = nil
        self.volume = vol
        self.srText = nil
        self.warnings = vol.meta.warnings
        if resetView {
            self.winCenter = vol.meta.defaultWindowCenter
            self.winWidth = vol.meta.defaultWindowWidth
            self.crosshair = SIMD3(0.5, 0.5, 0.5)
            self.zoom = 1; self.pan = .zero
        }
    }
}
