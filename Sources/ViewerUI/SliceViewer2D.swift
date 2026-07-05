import SwiftUI
import simd

/// Interactive axial canvas: window/level, pan, HU probe, and distance measure,
/// plus pinch-zoom. Slice scrubbing + W/L sliders live in the floating overlay.
struct SliceViewer2D: View {
    @EnvironmentObject var viewer: ViewerState
    @AppStorage("inputDevice") private var inputDevice = InputDevice.auto
    @AppStorage("naturalScroll") private var naturalScroll = true
    @State private var renderer = MPRPlaneRenderer()
    @State private var dragPrev: CGSize = .zero
    @State private var hoverPoint: CGPoint?
    @State private var probeHU: Float?
    @State private var activeROIStats: Volume.ROIStats?   // live stats during ROI drag

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                MetalPlaneView(renderer: renderer, volume: viewer.volume, axis: viewer.plane2D,
                               sliceFrac: viewer.slice2D,
                               winCenter: viewer.winCenter, winWidth: viewer.winWidth,
                               zoom: viewer.zoom, pan: viewer.pan, invert: viewer.invert,
                               quarter: viewer.rotationQuarter, flipH: viewer.flipH, flipV: viewer.flipV,
                               inputDevice: inputDevice, naturalScroll: naturalScroll,
                               onScroll: { viewer.scrollSlice(viewer.plane2D, wheel: $0) },
                               onRightDrag: { d in
                                   // Standard viewer convention: right-drag = W/L, any tool.
                                   viewer.nudgeWindowLevel(dx: d.width, dy: d.height)
                               })

                if let vol = viewer.volume { overlays(vol, size: geo.size) }
            }
            .contentShape(Rectangle())
            .gesture(drag(in: geo.size))
            .simultaneousGesture(MagnifyGesture().onChanged { v in
                viewer.zoom = max(0.2, min(8, Float(v.magnification) * lastZoom))
            }.onEnded { _ in lastZoom = viewer.zoom })
            .onContinuousHover { phase in
                // Only react while probing — avoids redraw storms on plain mouse-move.
                guard viewer.tool == .probe else {
                    if hoverPoint != nil { hoverPoint = nil; probeHU = nil }
                    return
                }
                switch phase {
                case .active(let p): hoverPoint = p; probeHU = sampleHU(at: p, size: geo.size)
                case .ended: hoverPoint = nil; probeHU = nil
                }
            }
            // VoiceOver: describe the plane + slice, and make it slice-adjustable.
            .accessibilityElement()
            .accessibilityLabel("\(viewer.plane2D.title) image\(viewer.volume.map { ", \($0.meta.modality)" } ?? "")")
            .accessibilityValue(sliceValue)
            .accessibilityAdjustableAction { d in
                viewer.scrollSlice(viewer.plane2D, wheel: d == .increment ? -1 : 1)
            }
        }
    }

    private var sliceValue: String {
        let n = viewer.slice2DCount
        let i = Int((viewer.slice2D * Float(max(n - 1, 0))).rounded()) + 1
        return "Slice \(i) of \(n)"
    }

    @State private var lastZoom: Float = 1

    @ViewBuilder
    private func overlays(_ vol: Volume, size: CGSize) -> some View {
        let rect = fittedRect(vol, in: size)
        // Committed annotations on this plane, near this slice.
        let tol = 0.5 / Float(max(viewer.slice2DCount - 1, 1))
        ForEach(viewer.annotations.filter { $0.plane == viewer.plane2D && abs($0.slice - viewer.slice2D) <= tol }) { ann in
            switch ann.kind {
            case .distance(let a, let b): distanceOverlay(a, b, vol, rect: rect)
            case .roi(let a, let b): roiOverlay(a, b, rect: rect, stats: ann.roiStats)
            case .angle(let pts): angleOverlay(pts, vol, rect: rect)
            }
        }
        // Active (in-progress) measurement.
        if let a = viewer.measureStart, let b = viewer.measureEnd {
            distanceOverlay(a, b, vol, rect: rect)
        }
        if let a = viewer.roiStart, let b = viewer.roiEnd {
            roiOverlay(a, b, rect: rect, stats: activeROIStats)
        }
        if !viewer.anglePoints.isEmpty {
            angleOverlay(viewer.anglePoints, vol, rect: rect)
            if viewer.anglePoints.count < 3, viewer.tool == .angle,
               let last = viewer.anglePoints.last {
                let p = planeToScreen(last, rect: rect)
                Text(viewer.anglePoints.count == 1 ? "Click the vertex" : "Click the end point")
                    .font(.caption2).padding(4)
                    .glassEffect(.regular, in: .capsule)
                    .position(x: p.x + 60, y: p.y - 14)
            }
        }
        // Probe readout
        if viewer.tool == .probe, let p = hoverPoint, let hu = probeHU {
            Text("\(Int(hu)) HU").font(.caption.monospacedDigit().weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
                .position(x: p.x + 44, y: p.y - 14)
        }
        // Corner info overlays (toggle with O / bottom-bar menu)
        if viewer.showOverlays { cornerOverlays(vol, size: size) }
    }

    // MARK: annotation drawing (shared by active + committed)

    @ViewBuilder
    private func distanceOverlay(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ vol: Volume, rect: CGRect) -> some View {
        let pa = planeToScreen(a, rect: rect), pb = planeToScreen(b, rect: rect)
        Path { $0.move(to: pa); $0.addLine(to: pb) }
            .stroke(Theme.accent, style: .init(lineWidth: 1.5, dash: [4, 3]))
        ForEach([pa, pb], id: \.self) { p in
            Circle().fill(Theme.accent).frame(width: 6, height: 6).position(p)
        }
        Text(String(format: "%.1f mm", distanceMM(a, b, vol)))
            .font(.caption.monospacedDigit()).padding(4)
            .glassEffect(.regular, in: .capsule)
            .position(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2 - 14)
    }

    @ViewBuilder
    private func roiOverlay(_ a: SIMD2<Float>, _ b: SIMD2<Float>, rect: CGRect, stats: Volume.ROIStats?) -> some View {
        let pa = planeToScreen(a, rect: rect), pb = planeToScreen(b, rect: rect)
        let r = CGRect(x: min(pa.x, pb.x), y: min(pa.y, pb.y),
                       width: abs(pb.x - pa.x), height: abs(pb.y - pa.y))
        Path { $0.addRect(r) }
            .stroke(Theme.accent, style: .init(lineWidth: 1.5, dash: [5, 3]))
        if let s = stats {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "mean %.1f HU  σ %.1f", s.mean, s.sd))
                Text(String(format: "min %.0f · max %.0f", s.min, s.max))
                Text(String(format: "%.0f mm² · %d px", s.areaMM2, s.count))
                if !s.histogram.isEmpty {
                    HistogramView(bins: s.histogram)
                        .frame(width: 130, height: 22)
                }
            }
            .font(.caption.monospacedDigit())
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.chip))
            .position(x: r.midX, y: max(r.minY - 40, 30))
        }
    }

    @ViewBuilder
    private func angleOverlay(_ points: [SIMD2<Float>], _ vol: Volume, rect: CGRect) -> some View {
        let pts = points.map { planeToScreen($0, rect: rect) }
        if !pts.isEmpty {
            Path { p in
                p.move(to: pts[0])
                for q in pts.dropFirst() { p.addLine(to: q) }
            }
            .stroke(Theme.accent, style: .init(lineWidth: 1.5, dash: [4, 3]))
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                Circle().fill(Theme.accent).frame(width: 6, height: 6).position(p)
            }
            if points.count == 3 {
                Text(String(format: "%.1f°", angleDegrees(points, vol)))
                    .font(.caption.monospacedDigit()).padding(4)
                    .glassEffect(.regular, in: .capsule)
                    .position(x: pts[1].x, y: pts[1].y - 18)
            }
        }
    }

    @ViewBuilder
    private func cornerOverlays(_ vol: Volume, size: CGSize) -> some View {
        let n = viewer.slice2DCount
        let idx = Int((viewer.slice2D * Float(max(n - 1, 1))).rounded())
        let spacing = viewer.plane2D == .axial ? vol.meta.spacing[2]
            : viewer.plane2D == .coronal ? vol.meta.spacing[1] : vol.meta.spacing[0]
        let mm = Float(idx) * spacing
        VStack(alignment: .trailing, spacing: 1) {
            Text(String(format: "C %.0f  W %.0f", viewer.winCenter, viewer.winWidth))
            Text(String(format: "%.0f%%", viewer.zoom * 100))
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
        .shadow(radius: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(10)
        .allowsHitTesting(false)

        VStack(alignment: .leading, spacing: 1) {
            Text("\(viewer.plane2D.title)  \(idx + 1)/\(n)")
            Text(String(format: "%.1f mm", mm))
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
        .shadow(radius: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(10)
        .allowsHitTesting(false)
    }

    // MARK: gestures

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let d = CGSize(width: g.translation.width - dragPrev.width,
                               height: g.translation.height - dragPrev.height)
                dragPrev = g.translation
                guard let vol = viewer.volume else { return }
                switch viewer.tool {
                case .windowLevel:
                    viewer.nudgeWindowLevel(dx: d.width, dy: d.height)
                case .pan:
                    let rect = fittedRect(vol, in: size)
                    viewer.pan.x -= Float(d.width / max(rect.width, 1)) / viewer.zoom
                    viewer.pan.y -= Float(d.height / max(rect.height, 1)) / viewer.zoom
                case .probe:
                    probeHU = sampleHU(at: g.location, size: size); hoverPoint = g.location
                case .measure:
                    let rect = fittedRect(vol, in: size)
                    if viewer.measureStart == nil || dragPrev == g.translation {
                        viewer.measureStart = screenToPlane(g.startLocation, rect: rect)
                    }
                    viewer.measureEnd = screenToPlane(g.location, rect: rect)
                case .roi:
                    let rect = fittedRect(vol, in: size)
                    if viewer.roiStart == nil || dragPrev == g.translation {
                        viewer.roiStart = screenToPlane(g.startLocation, rect: rect)
                    }
                    viewer.roiEnd = screenToPlane(g.location, rect: rect)
                    // Compute stats here (during the drag), not in the view body,
                    // so unrelated invalidations (W/L, cine) don't re-scan voxels.
                    if let a = viewer.roiStart, let b = viewer.roiEnd {
                        activeROIStats = vol.roiStats(axis: viewer.plane2D, a: a, b: b, sliceFrac: viewer.slice2D)
                    }
                case .angle:
                    break   // point placement happens on click (onEnded)
                }
            }
            .onEnded { g in
                switch viewer.tool {
                case .angle:
                    if let vol = viewer.volume,
                       abs(g.translation.width) < 3, abs(g.translation.height) < 3 {
                        // A click places a point: A, vertex B, then C (commits).
                        let p = screenToPlane(g.location, rect: fittedRect(vol, in: size))
                        if viewer.anglePoints.count >= 3 { viewer.anglePoints = [] }
                        viewer.anglePoints.append(p)
                        if viewer.anglePoints.count == 3 {
                            viewer.commit(.angle(viewer.anglePoints))
                            viewer.anglePoints = []
                        }
                    }
                case .measure:
                    if let a = viewer.measureStart, let b = viewer.measureEnd, a != b {
                        viewer.commit(.distance(a, b))
                    }
                    viewer.measureStart = nil; viewer.measureEnd = nil
                case .roi:
                    if let a = viewer.roiStart, let b = viewer.roiEnd, a != b {
                        viewer.commit(.roi(a, b))
                    }
                    viewer.roiStart = nil; viewer.roiEnd = nil; activeROIStats = nil
                default: break
                }
                dragPrev = .zero
            }
    }

    // MARK: coordinate helpers

    private var orient: PlaneOrientation {
        PlaneOrientation(zoom: viewer.zoom, pan: viewer.pan, quarter: viewer.rotationQuarter,
                         flipH: viewer.flipH, flipV: viewer.flipV)
    }

    private func planeAspect(_ vol: Volume) -> CGFloat {
        let m = vol.meta
        let (nu, nv) = viewer.plane2D.planeDims(nx: m.nx, ny: m.ny, nz: m.nz)
        let (su, sv) = viewer.plane2D.planeSpacing(SIMD3(m.spacing[0], m.spacing[1], m.spacing[2]))
        let a = CGFloat(nu) * CGFloat(su) / max(CGFloat(nv) * CGFloat(sv), 0.0001)
        return orient.swapsAspect ? 1 / a : a
    }

    private func fittedRect(_ vol: Volume, in size: CGSize) -> CGRect {
        let pa = planeAspect(vol), va = size.width / max(size.height, 1)
        var cw = size.width, ch = size.height
        if pa > va { ch = size.width / pa } else { cw = size.height * pa }
        return CGRect(x: (size.width - cw) / 2, y: (size.height - ch) / 2, width: cw, height: ch)
    }

    /// View point → plane normalized (a,b), undoing letterbox + orientation.
    private func screenToPlane(_ p: CGPoint, rect: CGRect) -> SIMD2<Float> {
        let s = SIMD2(Float((p.x - rect.minX) / max(rect.width, 1)),
                      Float((p.y - rect.minY) / max(rect.height, 1)))
        return orient.toPlane(s)
    }

    private func planeToScreen(_ ab: SIMD2<Float>, rect: CGRect) -> CGPoint {
        let s = orient.toScreen(ab)
        return CGPoint(x: rect.minX + CGFloat(s.x) * rect.width,
                       y: rect.minY + CGFloat(s.y) * rect.height)
    }

    private func sampleHU(at p: CGPoint, size: CGSize) -> Float? {
        guard let vol = viewer.volume else { return nil }
        let ab = screenToPlane(p, rect: fittedRect(vol, in: size))
        guard ab.x >= 0, ab.x <= 1, ab.y >= 0, ab.y <= 1 else { return nil }
        return vol.hu(tc: viewer.plane2D.toVolume(ab, slice: viewer.slice2D))
    }

    /// Plane point → physical mm on the current plane.
    private func planeMM(_ p: SIMD2<Float>, _ vol: Volume) -> SIMD2<Float> {
        let m = vol.meta
        let (nu, nv) = viewer.plane2D.planeDims(nx: m.nx, ny: m.ny, nz: m.nz)
        let (su, sv) = viewer.plane2D.planeSpacing(SIMD3(m.spacing[0], m.spacing[1], m.spacing[2]))
        return SIMD2(p.x * Float(nu) * su, p.y * Float(nv) * sv)
    }

    private func distanceMM(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ vol: Volume) -> Float {
        simd_length(planeMM(b, vol) - planeMM(a, vol))
    }

    /// Angle at the vertex (middle point), measured in physical (mm) space so
    /// anisotropic pixels don't distort it.
    private func angleDegrees(_ pts: [SIMD2<Float>], _ vol: Volume) -> Float {
        Annotations.angleDegrees(pts, plane: viewer.plane2D, vol)
    }
}

/// Tiny bar chart of an HU distribution (ROI badge).
struct HistogramView: View {
    let bins: [Int]
    var body: some View {
        Canvas { ctx, size in
            guard let maxV = bins.max(), maxV > 0 else { return }
            let w = size.width / CGFloat(bins.count)
            for (i, v) in bins.enumerated() where v > 0 {
                let h = max(size.height * CGFloat(v) / CGFloat(maxV), 1)
                let r = CGRect(x: CGFloat(i) * w, y: size.height - h,
                               width: max(w - 0.5, 0.5), height: h)
                ctx.fill(Path(r), with: .color(Theme.accent.opacity(0.85)))
            }
        }
        .accessibilityLabel("HU histogram")
    }
}

/// Plane-aware measurement math shared by the canvas and the annotations list.
enum Annotations {
    static func planeMM(_ p: SIMD2<Float>, plane: MPRAxis, _ vol: Volume) -> SIMD2<Float> {
        let m = vol.meta
        let (nu, nv) = plane.planeDims(nx: m.nx, ny: m.ny, nz: m.nz)
        let (su, sv) = plane.planeSpacing(SIMD3(m.spacing[0], m.spacing[1], m.spacing[2]))
        return SIMD2(p.x * Float(nu) * su, p.y * Float(nv) * sv)
    }

    static func distanceMM(_ a: SIMD2<Float>, _ b: SIMD2<Float>, plane: MPRAxis, _ vol: Volume) -> Float {
        simd_length(planeMM(b, plane: plane, vol) - planeMM(a, plane: plane, vol))
    }

    static func angleDegrees(_ pts: [SIMD2<Float>], plane: MPRAxis, _ vol: Volume) -> Float {
        guard pts.count == 3 else { return 0 }
        let v1 = planeMM(pts[0], plane: plane, vol) - planeMM(pts[1], plane: plane, vol)
        let v2 = planeMM(pts[2], plane: plane, vol) - planeMM(pts[1], plane: plane, vol)
        let denom = simd_length(v1) * simd_length(v2)
        guard denom > 0 else { return 0 }
        let cosA = max(-1, min(1, simd_dot(v1, v2) / denom))
        return acos(cosA) * 180 / .pi
    }

    static func label(_ ann: ViewerState.Annotation, _ vol: Volume) -> String {
        switch ann.kind {
        case .distance(let a, let b):
            return String(format: "%.1f mm", distanceMM(a, b, plane: ann.plane, vol))
        case .roi:
            if let s = ann.roiStats {   // cached at commit — don't re-scan voxels
                return String(format: "mean %.1f HU · %.0f mm²", s.mean, s.areaMM2)
            }
            return "ROI"
        case .angle(let pts):
            return String(format: "%.1f°", angleDegrees(pts, plane: ann.plane, vol))
        }
    }
}

/// Popover listing all committed measurements: jump to slice, delete, clear.
struct AnnotationListView: View {
    @EnvironmentObject var viewer: ViewerState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Measurements").font(.headline)
                Spacer()
                Button("Clear All", role: .destructive) { viewer.annotations.removeAll() }
                    .controlSize(.small).disabled(viewer.annotations.isEmpty)
            }
            if viewer.annotations.isEmpty {
                Text("Drag with the Measure/ROI tools or click three points with Angle — finished measurements collect here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(width: 260)
            } else if let vol = viewer.volume {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(viewer.annotations) { ann in
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: ann.symbol).frame(width: 18)
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(Annotations.label(ann, vol)).font(.callout.monospacedDigit())
                                    Text("\(ann.plane.title) · slice \(sliceIndex(ann))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    viewer.annotations.removeAll { $0.id == ann.id }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).hint("Delete measurement")
                            }
                            .padding(.vertical, 3).padding(.horizontal, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { jump(to: ann) }
                            .background(.background.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                        }
                    }
                }
                .frame(width: 280, height: min(CGFloat(viewer.annotations.count) * 44 + 8, 300))
            }
        }
        .padding(Theme.Spacing.md)
    }

    private func sliceIndex(_ ann: ViewerState.Annotation) -> Int {
        guard let m = viewer.volume?.meta else { return 0 }
        let n = ann.plane.sliceCount(nx: m.nx, ny: m.ny, nz: m.nz)
        return Int((ann.slice * Float(max(n - 1, 1))).rounded()) + 1
    }

    private func jump(to ann: ViewerState.Annotation) {
        viewer.layout = .slice2D
        viewer.plane2D = ann.plane
        viewer.slice2D = ann.slice
    }
}
