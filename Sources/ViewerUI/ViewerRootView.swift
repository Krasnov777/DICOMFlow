import SwiftUI
import UniformTypeIdentifiers

enum ViewerLayout: String, CaseIterable, Identifiable {
    case slice2D = "2D"
    case mpr = "MPR"
    case volume3D = "3D"
    case compare = "Compare"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .slice2D: return "square.dashed"
        case .mpr: return "squareshape.split.2x2"
        case .volume3D: return "cube"
        case .compare: return "rectangle.split.2x1"
        }
    }
}

/// Bottom-bar density tiers; the densest that fits the window is shown.
private enum BarDensity { case full, compact, min }

public struct ViewerRootView: View {
    @EnvironmentObject var sidecar: DicomEngine
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewer: ViewerState
    @State private var showImporter = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if !appState.subtitle.isEmpty {
                infoStrip
                Divider()
            }
            HStack(spacing: 0) {
                if viewer.showSeriesPanel && viewer.series.count > 1 {
                    SeriesSidebar().frame(width: 150)
                    Divider()
                }
                canvas
            }
            if viewer.volume != nil || viewer.colorImage != nil {
                Divider()
                bottomBar
            }
            Divider()
            statusLine
        }
        .toolbar { viewerToolbar }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder, .item],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { openURL(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            openURL(url)
            return true
        }
        .task { consumePendingDirectory() }
        .onChange(of: appState.pendingViewerDirectory) { _, _ in consumePendingDirectory() }
        .onChange(of: viewer.volume?.meta.modality) { _, _ in updateSubtitle() }
        // Cine loop that only runs while playing (a permanent Timer fired
        // 12.5×/s even when idle). Follows the current 2D plane.
        .task(id: viewer.isPlaying) {
            guard viewer.isPlaying else { return }
            while !Task.isCancelled && viewer.isPlaying {
                if let ci = viewer.colorImage, ci.frameCount > 1 {
                    viewer.colorFrame = (viewer.colorFrame + 1) % ci.frameCount
                } else {
                    let n = viewer.slice2DCount
                    if n > 1 {
                        var s = viewer.slice2D + 1.0 / Float(n - 1)
                        if s > 1 { s = 0 }
                        viewer.slice2D = s
                    }
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
    }

    // MARK: keyboard shortcuts (viewer-wide)

    @State private var keyMonitor: Any?

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    /// ←/→ ↑/↓ slice · space cine · 1–6 tools · A/C/S plane · I invert ·
    /// R reset · O overlays. Returns true when consumed.
    private func handleKey(_ e: NSEvent) -> Bool {
        guard viewer.volume != nil || viewer.colorImage != nil,
              !(NSApp.keyWindow?.firstResponder is NSTextView),   // not typing
              e.modifierFlags.intersection([.command, .option, .control]).isEmpty
        else { return false }

        // ← → and Space are owned by the Image menu (so they respect focus and
        // don't hijack text fields / VoiceOver). ↑ ↓ stay here for slice/frame nav.
        if viewer.colorImage != nil {
            switch e.keyCode {
            case 125: viewer.stepSlice(-1); return true   // ↓ previous frame
            case 126: viewer.stepSlice(+1); return true   // ↑ next frame
            default: return false
            }
        }

        switch e.keyCode {
        case 125: sliceStep(-1); return true   // ↓
        case 126: sliceStep(+1); return true   // ↑
        default: break
        }
        guard let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
        switch ch {
        case "1", "2", "3", "4", "5", "6":
            let tools = ViewerTool.allCases
            if let i = Int(ch), i - 1 < tools.count { viewer.tool = tools[i - 1]; return true }
            return false
        case "a": if viewer.layout == .slice2D { viewer.plane2D = .axial; return true }; return false
        case "c": if viewer.layout == .slice2D { viewer.plane2D = .coronal; return true }; return false
        case "s": if viewer.layout == .slice2D { viewer.plane2D = .sagittal; return true }; return false
        case "i": viewer.invert.toggle(); return true
        case "o": viewer.showOverlays.toggle(); return true
        case "r":
            if viewer.layout == .volume3D { viewer.requestedReset = true }
            else { viewer.zoom = 1; viewer.pan = .zero }
            return true
        default: return false
        }
    }

    private func sliceStep(_ dir: Int) {
        // scrollSlice treats wheel>0 as "previous".
        let axis: MPRAxis = viewer.layout == .slice2D ? viewer.plane2D : .axial
        viewer.scrollSlice(axis, wheel: dir > 0 ? -1 : 1)
    }

    // MARK: info strip (patient / series / dims) — below the toolbar

    private var infoStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "person.text.rectangle").foregroundStyle(.secondary)
            Text(appState.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// Recent studies shown under the empty state.
    private var recentsList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(appState.recents.prefix(6)) { r in
                Button { appState.openRecent(r) } label: {
                    Label(r.name, systemImage: r.isDirectory ? "folder" : "doc")
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(width: 320, alignment: .leading)
    }

    // MARK: canvas

    @ViewBuilder private var canvas: some View {
        ZStack {
            Color.black
            if let sr = viewer.srText {
                SRReportView(text: sr)
            } else if let color = viewer.colorImage {
                ColorImageView(image: color)
            } else if let err = viewer.errorText {
                EmptyState(symbol: "exclamationmark.triangle", title: "Couldn’t open series",
                           message: err, actionTitle: "Choose Folder…") { showImporter = true }
            } else if viewer.volume == nil && viewer.isLoading {
                ProgressView("Loading series…").controlSize(.large)
            } else if viewer.volume == nil {
                VStack(spacing: Theme.Spacing.lg) {
                    EmptyState(symbol: "cube.transparent", title: "No series loaded",
                               message: sidecar.ready
                                   ? "Open a DICOM folder or file (SRs render as text), or drag one here."
                                   : "Starting the DICOM engine…",
                               actionTitle: sidecar.ready ? "Open DICOM…" : nil) { showImporter = true }
                    if !appState.recents.isEmpty { recentsList }
                }
            } else {
                switch viewer.layout {
                case .slice2D: SliceViewer2D()
                case .mpr: MPRView()
                case .volume3D: VolumeView3D()
                case .compare: CompareView()
                }
                // Refine progress is shown once, globally, in the bottom bar (see
                // barContent) — not floating in a corner, which looked like it
                // belonged to a single MPR quadrant.
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: toolbar

    @ToolbarContentBuilder private var viewerToolbar: some ToolbarContent {
        // Always present (disabled with a single series) — making it conditional
        // on the async series scan made it pop in ~1s after a mode switch and
        // shove the toolbar left.
        ToolbarItem(placement: .navigation) {
            Button { viewer.showSeriesPanel.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .hint("Series")
            .disabled(viewer.series.count <= 1)
        }
        // The 2D/MPR/3D layout picker lives in the bottom bar (below), not the
        // top toolbar — keeping the leading toolbar identical to the Tester's
        // (just a sidebar toggle) so nothing shifts when switching modes.
        ToolbarItem(placement: .primaryAction) {
            Button { showImporter = true } label: { Label("Open DICOM", systemImage: "folder.badge.plus") }
                .disabled(!sidecar.ready)
        }
    }

    // MARK: docked bottom bar

    @ViewBuilder private var bottomBar: some View {
        GeometryReader { geo in
            Group {
                if viewer.colorImage != nil {
                    colorBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, Theme.Spacing.lg)
                } else {
                    // Density by width; a horizontal ScrollView is the fallback so
                    // the bar never clips (e.g. in a narrow split-screen window) —
                    // it fills+centres when it fits, scrolls when it doesn't.
                    let density: BarDensity = geo.size.width >= 1320 ? .full
                        : (geo.size.width >= 1060 ? .compact : .min)
                    ScrollView(.horizontal, showsIndicators: false) {
                        barContent(density)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                }
            }
        }
        .frame(height: 48)
        .background(.bar)
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: $viewer.layout.animation(.smooth)) {
            ForEach(ViewerLayout.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()   // sizes to all four segments
    }

    /// Bottom-bar controls for a color image: modality label + (multi-frame) cine.
    @ViewBuilder private var colorBar: some View {
        if let ci = viewer.colorImage {
            HStack(spacing: Theme.Spacing.md) {
                Label("Color · \(ci.modality.isEmpty ? "image" : ci.modality)", systemImage: "photo")
                    .font(.callout).foregroundStyle(.secondary)
                if ci.frameCount > 1 {
                    Divider().frame(height: 20)
                    Button { viewer.isPlaying.toggle() } label: {
                        Image(systemName: viewer.isPlaying ? "pause.fill" : "play.fill")
                    }.buttonStyle(.borderless).hint("Play / pause (Space)")
                    Slider(value: Binding(get: { Double(viewer.colorFrame) },
                                          set: { viewer.colorFrame = Int($0) }),
                           in: 0 ... Double(ci.frameCount - 1), step: 1)
                        .frame(width: 240)
                    Text("\(viewer.colorFrame + 1)/\(ci.frameCount)")
                        .font(.callout.monospacedDigit()).frame(width: 64, alignment: .trailing)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func barContent(_ density: BarDensity) -> some View {
        HStack(spacing: density == .min ? Theme.Spacing.md : Theme.Spacing.lg) {
            Spacer(minLength: 0)   // centres when it fits; collapses when scrolling
            layoutPicker
            Divider().frame(height: 20)
            switch viewer.layout {
            case .slice2D:
                planePicker
                toolPicker
                if density == .full { secondaryActions }   // invert · cine · measure · export
                overflowMenu                               // rest (incl. rotate/flip) at every width
                Divider().frame(height: 20)
                if density == .min { sliceIndex } else if viewer.volume != nil { sliceScrubber }
                WindowLevelControls(compact: density == .compact, mini: density == .min)
            case .mpr:
                Toggle(isOn: $viewer.invert) { Image(systemName: "circle.righthalf.filled") }
                    .toggleStyle(.button).hint("Invert")
                overflowMenu
                Divider().frame(height: 20)
                WindowLevelControls(compact: density == .compact, mini: density == .min)
            case .volume3D:
                Volume3DControls(compact: density != .full)
                if exportingMovie {
                    ProgressView().controlSize(.small)
                } else {
                    Button { exportMovie() } label: { Image(systemName: "film") }
                        .buttonStyle(.borderless).hint("Export MIP turntable movie…")
                }
                if viewer.renderMode.usesWindow {
                    Divider().frame(height: 20)
                    WindowLevelControls(compact: density == .compact, mini: density == .min)
                }
            case .compare:
                Toggle(isOn: $viewer.syncCompare) {
                    Label("Sync", systemImage: "link")
                }.toggleStyle(.button).hint("Scroll both panes together")
                Divider().frame(height: 20)
                WindowLevelControls(compact: density == .compact, mini: density == .min)
            }
            Spacer(minLength: 0)
        }
    }

    /// Axial / coronal / sagittal plane picker for the single-plane 2D layout.
    private var planePicker: some View {
        Picker("Plane", selection: $viewer.plane2D) {
            ForEach(MPRAxis.allCases, id: \.self) {
                Text(String($0.title.prefix(3))).tag($0)
                    .help($0.title).accessibilityLabel($0.title)
            }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 118)
        .help("2D plane (A / C / S keys)")
    }

    /// Compact slice indicator (no slider) for the narrowest layout.
    @ViewBuilder private var sliceIndex: some View {
        if viewer.volume != nil {
            let n = viewer.slice2DCount
            let idx = Int((viewer.slice2D * Float(max(n - 1, 1))).rounded())
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                Text(verbatim: "\(idx + 1)/\(n)").font(.callout.monospacedDigit())
            }
        }
    }

    /// Persistent status line at the foot of the window: Ready ↔ animated Loading.
    private var statusLine: some View {
        let loading = viewer.isLoading || viewer.isRefining
        // "Loading…" (not "Loading series…") so it doesn't echo the canvas spinner
        // word-for-word; the info strip above owns modality·dims, so this line is
        // purely the app state.
        let text = viewer.isLoading ? "Loading…"
                 : viewer.isRefining ? "Loading full-resolution slices…" : "Ready"
        return HStack(spacing: Theme.Spacing.sm) {
            if loading {
                LoadingDots()
            } else {
                Circle().fill(.green).frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.6), radius: 2)
                    .accessibilityHidden(true)
            }
            Text(text).font(.caption)
                .foregroundStyle(loading ? .primary : .secondary)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .animation(.smooth, value: loading)
        .padding(.horizontal, Theme.Spacing.lg)   // align with the bars above
        .frame(height: 24)
        .background(.bar)
    }

    private var toolPicker: some View {
        Picker("Tool", selection: $viewer.tool) {
            ForEach(ViewerTool.allCases) {
                Image(systemName: $0.symbol).tag($0)
                    .help($0.rawValue).accessibilityLabel($0.rawValue)
            }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 220)
    }

    /// Inline secondary actions (shown when the bar is wide enough).
    private var secondaryActions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: $viewer.invert) { Image(systemName: "circle.righthalf.filled") }
                .toggleStyle(.button).hint("Invert")
            Button { viewer.isPlaying.toggle() } label: {
                Image(systemName: viewer.isPlaying ? "pause.fill" : "play.fill")
            }.hint("Cine")
            Button { viewer.zoom = 1; viewer.pan = .zero } label: { Image(systemName: "1.magnifyingglass") }
                .hint("Reset zoom (R)")
            Toggle(isOn: $viewer.showOverlays) { Image(systemName: "text.viewfinder") }
                .toggleStyle(.button).hint("Info overlays (O)")
            Button { showAnnotations = true } label: {
                Image(systemName: "list.bullet.rectangle")
                    .overlay(alignment: .topTrailing) {
                        if !viewer.annotations.isEmpty {
                            Text("\(viewer.annotations.count)").font(.caption2.weight(.bold))
                                .foregroundStyle(.black)   // black on teal passes contrast
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(Theme.accent, in: Capsule())
                                .offset(x: 9, y: -8)
                        }
                    }
            }
            .hint("Measurements…")
            .popover(isPresented: $showAnnotations) { AnnotationListView().environmentObject(viewer) }
            Button { exportCurrent() } label: { Image(systemName: "square.and.arrow.down") }
                .hint("Export PNG")
            if exportingMovie {
                ProgressView().controlSize(.small)
            } else {
                Button { exportMovie() } label: { Image(systemName: "film") }
                    .hint("Export slice-sweep movie…")
            }
            // Rotate/flip now live in the overflow menu (see overflowMenu) to keep
            // the wide bar from becoming a cockpit of ~20 controls.
        }
        .buttonStyle(.borderless)
    }

    /// Overflow menu grouping the secondary actions when space is tight.
    private var overflowMenu: some View {
        Menu {
            Button { appState.sendToStore(files: viewer.currentFiles) } label: {
                Label("Send to PACS…", systemImage: "paperplane")
            }.disabled(viewer.currentFiles.isEmpty)
            Divider()
            if viewer.layout == .slice2D {
                Button { viewer.invert.toggle() } label: {
                    Label("Invert", systemImage: viewer.invert ? "checkmark" : "circle.righthalf.filled")
                }
                Button { viewer.isPlaying.toggle() } label: {
                    Label(viewer.isPlaying ? "Pause" : "Cine", systemImage: viewer.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { viewer.zoom = 1; viewer.pan = .zero } label: { Label("Reset Zoom", systemImage: "1.magnifyingglass") }
                Button { viewer.showOverlays.toggle() } label: {
                    Label("Info Overlays", systemImage: viewer.showOverlays ? "checkmark" : "text.viewfinder")
                }
                Button { exportCurrent() } label: { Label("Export PNG…", systemImage: "square.and.arrow.down") }
                Button { exportMovie() } label: { Label("Export Movie…", systemImage: "film") }
                    .disabled(exportingMovie)
                Divider()
            }
            Button { viewer.rotate(by: -1) } label: { Label("Rotate Left", systemImage: "rotate.left") }
            Button { viewer.rotate(by: 1) } label: { Label("Rotate Right", systemImage: "rotate.right") }
            Button { viewer.toggleFlipH() } label: { Label("Flip Horizontal", systemImage: "arrow.left.and.right") }
            Button { viewer.toggleFlipV() } label: { Label("Flip Vertical", systemImage: "arrow.up.and.down") }
            if viewer.rotationQuarter != 0 || viewer.flipH || viewer.flipV {
                Button { viewer.resetOrientation() } label: { Label("Reset Orientation", systemImage: "arrow.uturn.backward") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).fixedSize().hint("More tools")
    }

    private var sliceScrubber: some View {
        let n = viewer.slice2DCount
        let idx = Int((viewer.slice2D * Float(max(n - 1, 1))).rounded())
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(viewer.slice2D) },
                                  set: { viewer.slice2D = Float($0) }), in: 0...1)
                .frame(width: 150)
            Text(verbatim: "\(idx + 1)/\(n)").font(.callout.monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
    }

    @State private var exportingMovie = false
    @State private var showAnnotations = false

    /// 2D/MPR: slice sweep along the current plane · 3D: MIP turntable.
    private func exportMovie() {
        guard let vol = viewer.volume else { return }
        let (wc, ww, inv) = (viewer.winCenter, viewer.winWidth, viewer.invert)
        let is3D = viewer.layout == .volume3D
        let axis = viewer.plane2D
        let name = is3D ? "dicomflow-turntable.mov" : "dicomflow-\(axis.rawValue)-sweep.mov"
        exportingMovie = true
        ExportMovie.savePanel(suggested: name) { url in
            is3D ? try ExportMovie.turntable(volume: vol, winCenter: wc, winWidth: ww, to: url)
                 : try ExportMovie.sliceSweep(volume: vol, axis: axis, winCenter: wc, winWidth: ww,
                                              invert: inv, to: url)
        } done: { result in
            exportingMovie = false
            if case .failure(let e) = result { viewer.errorText = e.localizedDescription }
        }
    }

    private func exportCurrent() {
        guard let vol = viewer.volume,
              let img = MPRPlaneRenderer.renderOffscreen(
                volume: vol, axis: viewer.plane2D, sliceFrac: viewer.slice2D,
                winCenter: viewer.winCenter, winWidth: viewer.winWidth, size: 1024,
                zoom: viewer.zoom, pan: viewer.pan, invert: viewer.invert) else { return }
        ExportImage.savePNG(img, suggested: "dicomflow-\(viewer.plane2D.rawValue).png")
    }

    private func consumePendingDirectory() {
        guard let dir = appState.pendingViewerDirectory, let client = sidecar.client else { return }
        let seriesUID = appState.pendingViewerSeriesUID
        appState.pendingViewerDirectory = nil
        appState.pendingViewerSeriesUID = nil
        viewer.layout = .slice2D
        viewer.load(directory: dir, client: client, preferSeriesUID: seriesUID)
    }
    /// Open a folder (series scan) or a single file (SR → rendered text,
    /// image → its folder's series).
    private func openURL(_ url: URL) {
        guard let client = sidecar.client else { return }
        _ = url.startAccessingSecurityScopedResource()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            viewer.load(directory: url.path, client: client)
        } else {
            viewer.loadFile(path: url.path, client: client)
        }
    }
    private func updateSubtitle() {
        guard let m = viewer.volume?.meta else { appState.subtitle = ""; return }
        let s = viewer.selectedSeries
        var parts: [String] = []
        if let s, !s.patient.isEmpty { parts.append(s.patient) }
        if let s, !s.description.isEmpty { parts.append(s.description) }
        parts.append("\(m.modality.isEmpty ? "" : m.modality + " ")\(m.nx)×\(m.ny)×\(m.nz)")
        appState.subtitle = parts.joined(separator: "  ·  ")
    }
}

/// Window/level sliders + presets. `compact` shrinks the sliders; `mini` folds
/// everything into a popover button (for the narrowest bar, e.g. split-screen).
struct WindowLevelControls: View {
    @EnvironmentObject var viewer: ViewerState
    var compact = false
    var mini = false
    @State private var showWL = false

    var body: some View {
        if mini {
            Button { showWL.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "circle.lefthalf.filled")
                    Text(verbatim: "C\(Int(viewer.winCenter)) W\(Int(viewer.winWidth))")
                        .font(.callout.monospacedDigit())
                }
            }
            .buttonStyle(.borderless).hint("Window / Level")
            .popover(isPresented: $showWL, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Window / Level").font(.headline)
                    ForEach(viewer.presets, id: \.name) { p in
                        Button(p.name) { viewer.winCenter = p.center; viewer.winWidth = p.width }
                            .buttonStyle(.borderless)
                    }
                    Button("Full range") { viewer.applyFullRangeWindow() }.buttonStyle(.borderless)
                    Divider()
                    labeled("L", value: $viewer.winCenter, range: -1000...3000, width: 160)
                    labeled("W", value: $viewer.winWidth, range: 1...4000, width: 160)
                }
                .padding(Theme.Spacing.lg).frame(width: 280)
            }
        } else {
            HStack(spacing: Theme.Spacing.md) {
                Menu {
                    ForEach(viewer.presets, id: \.name) { p in
                        Button(p.name) { viewer.winCenter = p.center; viewer.winWidth = p.width }
                    }
                    Button("Full range") { viewer.applyFullRangeWindow() }
                } label: {
                    if compact { Image(systemName: "slider.horizontal.3") }
                    else { Label("Presets", systemImage: "slider.horizontal.3") }
                }
                .menuStyle(.borderlessButton).fixedSize().hint("Window presets")

                labeled("L", value: $viewer.winCenter, range: -1000...3000, width: compact ? 84 : 120)
                labeled("W", value: $viewer.winWidth, range: 1...4000, width: compact ? 84 : 120)
            }
        }
    }

    private func labeled(_ name: String, value: Binding<Float>, range: ClosedRange<Float>, width: CGFloat) -> some View {
        let full = name == "L" ? "Window center" : (name == "W" ? "Window width" : name)
        return HStack(spacing: Theme.Spacing.sm) {
            Text(name).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Float($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .frame(width: width)
                .accessibilityLabel(full)
                .accessibilityValue("\(Int(value.wrappedValue))")
            Text(verbatim: String(Int(value.wrappedValue))).font(.callout.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// Three dots pulsing in a wave — the status-line "loading" animation.
private struct LoadingDots: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                    .scaleEffect(!reduceMotion && animating ? 1.0 : 0.7)
                    .opacity(!reduceMotion && animating ? 1.0 : 0.7)
                    .animation(reduceMotion ? nil
                               : .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.16),
                               value: animating)
            }
        }
        .frame(width: 21, alignment: .leading)   // fixed width so text doesn't shift
        .accessibilityHidden(true)               // the "Loading…" text carries the meaning
        .onAppear { animating = true }
    }
}
