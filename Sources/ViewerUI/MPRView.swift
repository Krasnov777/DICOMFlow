import SwiftUI
import simd

/// Per-plane accent colors so the four zones read as distinct.
enum PlaneStyle {
    static func rgb(_ axis: MPRAxis) -> (Double, Double, Double) {
        switch axis {
        case .axial: return (0.32, 0.64, 1.0)    // blue
        case .coronal: return (0.34, 0.82, 0.48) // green
        case .sagittal: return (1.0, 0.68, 0.28) // amber
        }
    }
    static func color(_ axis: MPRAxis) -> Color { let c = rgb(axis); return Color(red: c.0, green: c.1, blue: c.2) }
    static let volumeRGB = (0.74, 0.52, 1.0)     // purple
    static let volume = Color(red: volumeRGB.0, green: volumeRGB.1, blue: volumeRGB.2)

    /// Black or white text for a legible (WCAG-passing) label on a color fill.
    static func textOn(_ c: (Double, Double, Double)) -> Color {
        (0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2) > 0.6 ? .black : .white
    }
}

/// A framed, labeled quadrant: colored border + corner label chip + hover lift.
struct PaneFrame<Content: View>: View {
    let title: String
    let color: Color
    var chipText: Color = .white
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) { chip }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color.opacity(hovering ? 0.95 : 0.55),
                                  lineWidth: hovering ? 2 : 1)
            )
            .onHover { hovering = $0 }
    }

    private var chip: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold)).tracking(0.5)
            .foregroundStyle(chipText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color, in: Capsule())
            .padding(6)
    }
}

/// Orthanc-style 2×2: axial · coronal · sagittal · 3D, with a linked crosshair.
struct MPRView: View {
    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                pane(.axial); pane(.coronal)
            }
            GridRow {
                pane(.sagittal)
                PaneFrame(title: "3D", color: PlaneStyle.volume,
                          chipText: PlaneStyle.textOn(PlaneStyle.volumeRGB)) { VolumeView3D() }
            }
        }
        .padding(8)
        .background(Color(white: 0.04))
    }

    private func pane(_ axis: MPRAxis) -> some View {
        PaneFrame(title: axis.title, color: PlaneStyle.color(axis),
                  chipText: PlaneStyle.textOn(PlaneStyle.rgb(axis))) { MPRPane(axis: axis) }
    }
}

/// One MPR pane: Metal plane + linked crosshair, scroll to scrub, click to move.
struct MPRPane: View {
    @EnvironmentObject var viewer: ViewerState
    @AppStorage("inputDevice") private var inputDevice = InputDevice.auto
    @AppStorage("naturalScroll") private var naturalScroll = true
    let axis: MPRAxis
    @State private var renderer = MPRPlaneRenderer()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                MetalPlaneView(renderer: renderer, volume: viewer.volume, axis: axis,
                               sliceFrac: sliceFrac, winCenter: viewer.winCenter,
                               winWidth: viewer.winWidth, invert: viewer.invert,
                               quarter: viewer.rotationQuarter, flipH: viewer.flipH, flipV: viewer.flipV,
                               inputDevice: inputDevice, naturalScroll: naturalScroll,
                               onScroll: { viewer.scrollSlice(axis, wheel: $0) },
                               onRightDrag: { d in viewer.nudgeWindowLevel(dx: d.width, dy: d.height) })

                if viewer.volume != nil {
                    crosshair(in: fittedRect(in: geo.size))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in handleTap(at: v.location, in: geo.size) }   // live drag (trackpad + mouse)
                .onEnded { v in handleTap(at: v.location, in: geo.size) })
            // VoiceOver: describe the plane + slice, and make it slice-adjustable.
            .accessibilityElement()
            .accessibilityLabel("\(axis.title) plane\(viewer.volume.map { ", \($0.meta.modality)" } ?? "")")
            .accessibilityValue(sliceValue)
            .accessibilityAdjustableAction { d in
                viewer.scrollSlice(axis, wheel: d == .increment ? -1 : 1)
            }
        }
    }

    private var sliceValue: String {
        guard let m = viewer.volume?.meta else { return "no image" }
        let n = axis.sliceCount(nx: m.nx, ny: m.ny, nz: m.nz)
        let i = Int((sliceFrac * Float(max(n - 1, 0))).rounded()) + 1
        return "Slice \(i) of \(n)"
    }

    private var sliceFrac: Float {
        switch axis {
        case .axial: return viewer.crosshair.z
        case .coronal: return viewer.crosshair.y
        case .sagittal: return viewer.crosshair.x
        }
    }
    private var planeCoords: (a: Float, b: Float) {
        let c = viewer.crosshair
        switch axis {
        case .axial: return (c.x, c.y)
        case .coronal: return (c.x, 1 - c.z)
        case .sagittal: return (c.y, 1 - c.z)
        }
    }
    private var orient: PlaneOrientation {
        PlaneOrientation(quarter: viewer.rotationQuarter, flipH: viewer.flipH, flipV: viewer.flipV)
    }
    private var planeAspect: CGFloat {
        guard let m = viewer.volume?.meta else { return 1 }
        let sx = CGFloat(m.spacing[0]), sy = CGFloat(m.spacing[1]), sz = CGFloat(m.spacing[2])
        let nx = CGFloat(m.nx), ny = CGFloat(m.ny), nz = CGFloat(m.nz)
        let a: CGFloat
        switch axis {
        case .axial: a = (nx * sx) / max(ny * sy, 0.0001)
        case .coronal: a = (nx * sx) / max(nz * sz, 0.0001)
        case .sagittal: a = (ny * sy) / max(nz * sz, 0.0001)
        }
        return orient.swapsAspect ? 1 / a : a
    }
    private func fittedRect(in size: CGSize) -> CGRect {
        let va = size.width / max(size.height, 1)
        var cw = size.width, ch = size.height
        if planeAspect > va { ch = size.width / planeAspect } else { cw = size.height * planeAspect }
        return CGRect(x: (size.width - cw) / 2, y: (size.height - ch) / 2, width: cw, height: ch)
    }
    /// Crosshair through the (transformed) point; lines colored by reference plane.
    private func crosshair(in rect: CGRect) -> some View {
        let p = planeCoords
        let s = orient.toScreen(SIMD2(p.a, p.b))
        let x = rect.minX + CGFloat(s.x) * rect.width
        let y = rect.minY + CGFloat(s.y) * rect.height
        let (hColor, vColor) = referenceColors
        return ZStack {
            Path { $0.move(to: CGPoint(x: rect.minX, y: y)); $0.addLine(to: CGPoint(x: rect.maxX, y: y)) }
                .stroke(hColor.opacity(0.85), lineWidth: 0.8)
            Path { $0.move(to: CGPoint(x: x, y: rect.minY)); $0.addLine(to: CGPoint(x: x, y: rect.maxY)) }
                .stroke(vColor.opacity(0.85), lineWidth: 0.8)
        }
    }
    /// (horizontal-line color, vertical-line color) = the orthogonal planes.
    private var referenceColors: (Color, Color) {
        switch axis {
        case .axial:    return (PlaneStyle.color(.coronal), PlaneStyle.color(.sagittal))
        case .coronal:  return (PlaneStyle.color(.axial), PlaneStyle.color(.sagittal))
        case .sagittal: return (PlaneStyle.color(.axial), PlaneStyle.color(.coronal))
        }
    }
    private func handleTap(at loc: CGPoint, in size: CGSize) {
        let rect = fittedRect(in: size)
        guard rect.width > 0, rect.height > 0 else { return }
        let s = SIMD2(Float((loc.x - rect.minX) / rect.width), Float((loc.y - rect.minY) / rect.height))
        let pl = orient.toPlane(s)
        let a = min(max(pl.x, 0), 1), b = min(max(pl.y, 0), 1)
        switch axis {
        case .axial: viewer.crosshair.x = a; viewer.crosshair.y = b
        case .coronal: viewer.crosshair.x = a; viewer.crosshair.z = 1 - b
        case .sagittal: viewer.crosshair.y = a; viewer.crosshair.z = 1 - b
        }
    }
}
