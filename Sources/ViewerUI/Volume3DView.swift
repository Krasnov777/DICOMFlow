import SwiftUI
import MetalKit
import simd

/// MTKView subclass: drag → orbit, ⌥-drag → pan, scroll → zoom, pinch → zoom.
/// Sensitivities adapt to the configured input device.
final class RaycastMTKView: MTKView {
    weak var raycaster: RaycastRenderer?
    var inputDevice: InputDevice = .auto
    var rotationMode: RotationMode = .arcball
    /// Last-applied render inputs — lets updateNSView skip a redraw when an
    /// unrelated change (e.g. the MPR crosshair) re-runs the representable.
    var lastRenderSig: Int?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rotate(dx: Float, dy: Float) {
        switch rotationMode {
        case .arcball: raycaster?.camera.orbit(dx: dx, dy: dy)
        case .turntable: raycaster?.camera.turntable(dx: dx, dy: dy)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            raycaster?.camera.pan(dxRight: Float(event.deltaX), dyUp: Float(event.deltaY))
        } else {
            rotate(dx: Float(event.deltaX) * 0.01, dy: Float(event.deltaY) * 0.01)
        }
        setNeedsDisplay(bounds)
    }
    override func scrollWheel(with event: NSEvent) {
        let precise = inputDevice.precise(eventHasPrecise: event.hasPreciseScrollingDeltas)
        if precise {
            // Trackpad two-finger drag → orbit / ⌥pan (follows fingers, full 360°).
            // Skip the inertial (momentum) tail: without this the object keeps
            // spinning after the fingers lift, which reads as losing control and
            // drifting off-axis.
            if event.momentumPhase != [] { return }
            if event.modifierFlags.contains(.option) {
                raycaster?.camera.pan(dxRight: Float(event.scrollingDeltaX), dyUp: Float(event.scrollingDeltaY))
            } else {
                rotate(dx: Float(event.scrollingDeltaX) * 0.006, dy: Float(event.scrollingDeltaY) * 0.006)
            }
        } else {
            // Mouse wheel → zoom.
            let factor = Float(1.0 - event.scrollingDeltaY * 0.04)
            raycaster?.camera.zoom(factor: max(0.5, min(1.5, factor)))
        }
        setNeedsDisplay(bounds)
    }
    override func magnify(with event: NSEvent) {   // trackpad pinch → zoom
        raycaster?.camera.zoom(factor: Float(1.0 - event.magnification))
        setNeedsDisplay(bounds)
    }
}

struct Volume3DMetalView: NSViewRepresentable {
    let renderer: RaycastRenderer
    var volume: Volume?
    var mode: RenderMode
    var winCenter: Float
    var winWidth: Float
    var tfIndex: Int
    var clipMin: SIMD3<Float>
    var clipMax: SIMD3<Float>
    var light: Bool
    var isoValue: Float
    var inputDevice: InputDevice
    var rotationMode: RotationMode
    @Binding var requestedView: ArcballCamera.View?
    @Binding var reset: Bool

    func makeNSView(context: Context) -> RaycastMTKView {
        let view = RaycastMTKView()
        view.device = MetalContext.shared.device
        view.colorPixelFormat = MetalContext.colorPixelFormat
        view.delegate = renderer
        view.raycaster = renderer
        view.inputDevice = inputDevice
        view.rotationMode = rotationMode
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        return view
    }

    func updateNSView(_ view: RaycastMTKView, context: Context) {
        view.inputDevice = inputDevice
        view.rotationMode = rotationMode
        renderer.volume = volume
        renderer.mode = mode
        renderer.winCenter = winCenter
        renderer.winWidth = winWidth
        renderer.clipMin = clipMin
        renderer.clipMax = clipMax
        renderer.lightEnabled = light
        renderer.isoValue = isoValue
        let idx = min(tfIndex, TransferFunction.presets.count - 1)
        let preset = TransferFunction.presets[idx].tf
        if renderer.lutCache[idx] == nil { renderer.lutCache[idx] = preset.makeLUTTexture() }
        renderer.lut = renderer.lutCache[idx]
        renderer.lutMinHU = preset.minHU
        renderer.lutMaxHU = preset.maxHU
        if let v = requestedView {
            renderer.camera.set(v)
            DispatchQueue.main.async { requestedView = nil }
        }
        if reset {
            renderer.frameVolume()          // refit distance + recenter target
            renderer.camera.set(.anterior)  // back to the default orientation
            DispatchQueue.main.async { reset = false }
        }
        // Only redraw when a render-relevant input actually changed (a camera-only
        // interaction drives its own setNeedsDisplay from the mouse handlers).
        var sig = Hasher()
        sig.combine(mode); sig.combine(winCenter); sig.combine(winWidth)
        sig.combine(clipMin); sig.combine(clipMax); sig.combine(light)
        sig.combine(isoValue); sig.combine(idx)
        sig.combine(volume.map { ObjectIdentifier($0) })
        let value = sig.finalize()
        if requestedView != nil || reset || view.lastRenderSig != value {
            view.lastRenderSig = value
            view.setNeedsDisplay(view.bounds)
        }
    }
}

/// 3D ray-cast canvas. Controls live in the docked bottom bar (Volume3DControls).
struct VolumeView3D: View {
    @EnvironmentObject var viewer: ViewerState
    @AppStorage("inputDevice") private var inputDevice = InputDevice.auto
    @AppStorage("rotationMode") private var rotationMode = RotationMode.arcball
    @State private var renderer = RaycastRenderer()

    var body: some View {
        Volume3DMetalView(renderer: renderer, volume: viewer.volume,
                          mode: viewer.renderMode, winCenter: viewer.winCenter,
                          winWidth: viewer.winWidth, tfIndex: viewer.tfPresetIndex,
                          clipMin: viewer.clipMin, clipMax: viewer.clipMax, light: viewer.light3D,
                          isoValue: viewer.isoValue, inputDevice: inputDevice, rotationMode: rotationMode,
                          requestedView: $viewer.requestedView, reset: $viewer.requestedReset)
            // In the MPR 2×2 the bottom bar carries no 3D controls, so surface a
            // quick render-mode switcher along the bottom-centre of the pane.
            .overlay(alignment: .bottom) {
                if viewer.layout == .mpr, viewer.volume != nil {
                    RenderModeChips().padding(.bottom, 10)
                }
            }
    }
}

/// Compact render-mode switcher overlaid on the 3D pane (MIP / MinIP / … / Surface).
struct RenderModeChips: View {
    @EnvironmentObject var viewer: ViewerState
    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(RenderMode.allCases, id: \.self) { m in
                    Button { withAnimation(.smooth) { viewer.renderMode = m } } label: {
                        Text(m.rawValue)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .frame(minHeight: 24)
                            .foregroundStyle(viewer.renderMode == m ? PlaneStyle.textOn(PlaneStyle.volumeRGB) : .secondary)
                            .background(viewer.renderMode == m ? PlaneStyle.volume : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .hint("\(m.rawValue) rendering")
                    .accessibilityAddTraits(viewer.renderMode == m ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(3)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

/// 3D controls for the docked bottom bar (mode, TF gallery, light, clip).
/// `compact` folds the wide groups (TF gallery, iso slider, anatomical views)
/// into menus/popovers so the bar fits a narrow / split-screen window.
struct Volume3DControls: View {
    @EnvironmentObject var viewer: ViewerState
    var compact = false
    @State private var showClip = false
    @State private var showTF = false
    @State private var showIso = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Menu {
                ForEach(RenderMode.allCases, id: \.self) { m in
                    Button { viewer.renderMode = m } label: {
                        Label(m.rawValue, systemImage: viewer.renderMode == m ? "checkmark" : "")
                    }
                }
            } label: { Label(viewer.renderMode.rawValue, systemImage: "cube.transparent") }
            .menuStyle(.borderlessButton).fixedSize()

            if viewer.renderMode == .tf {
                if compact {
                    Button { showTF.toggle() } label: { Image(systemName: "paintpalette") }
                        .buttonStyle(.borderless).hint("Transfer function & lighting")
                        .popover(isPresented: $showTF, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Transfer function").font(.headline)
                                tfGallery
                                Toggle("Lighting", isOn: $viewer.light3D)
                            }.padding(Theme.Spacing.lg)
                        }
                } else {
                    tfGallery
                    Toggle(isOn: $viewer.light3D) { Image(systemName: "light.max") }
                        .toggleStyle(.button).hint("Lighting")
                }
            }
            if viewer.renderMode == .surface {
                if compact {
                    Button { showIso.toggle() } label: {
                        HStack(spacing: 4) { Image(systemName: "square.stack.3d.forward.dottedline")
                            Text("Iso \(Int(viewer.isoValue))").font(.callout.monospacedDigit()) }
                    }
                    .buttonStyle(.borderless).hint("Iso-surface threshold")
                    .popover(isPresented: $showIso, arrowEdge: .bottom) { isoSlider.padding(Theme.Spacing.lg).frame(width: 260) }
                } else {
                    isoSlider
                }
            }

            Divider().frame(height: 18)
            if compact {
                Menu {
                    ForEach(ArcballCamera.View.allCases, id: \.self) { v in
                        Button(v.rawValue) { viewer.requestedView = v }
                    }
                } label: { Label("View", systemImage: "cube") }
                .menuStyle(.borderlessButton).fixedSize()
            } else {
                ForEach(ArcballCamera.View.allCases, id: \.self) { v in
                    Button(v.rawValue) { viewer.requestedView = v }
                        .buttonStyle(.borderless).font(.callout.weight(.medium))
                        .hint("\(v) view")
                }
            }
            Button { viewer.requestedReset = true } label: { Image(systemName: "scope") }
                .buttonStyle(.borderless).hint("Recenter & fit")
            Divider().frame(height: 18)

            Button { showClip.toggle() } label: { Image(systemName: "scissors") }
                .buttonStyle(.borderless).hint("Clip planes")
                .popover(isPresented: $showClip) { clipPopover }
            Button { viewer.clipMin = .init(0, 0, 0); viewer.clipMax = .init(1, 1, 1) } label: {
                Image(systemName: "arrow.counterclockwise")
            }.buttonStyle(.borderless).hint("Reset clip")
        }
    }

    private var isoSlider: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Iso").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(viewer.isoValue) },
                                  set: { viewer.isoValue = Float($0) }), in: -500...1500)
                .frame(width: 120)
            Text("\(Int(viewer.isoValue))").font(.caption.monospacedDigit()).frame(width: 40)
        }
    }

    private var tfGallery: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(TransferFunction.presets.enumerated()), id: \.offset) { idx, p in
                Button { viewer.tfPresetIndex = idx } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(gradient: gradient(p.tf), startPoint: .leading, endPoint: .trailing))
                        .frame(width: 64, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(viewer.tfPresetIndex == idx ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .hint(p.name)
                .accessibilityAddTraits(viewer.tfPresetIndex == idx ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
    private func gradient(_ tf: TransferFunction) -> Gradient {
        Gradient(stops: tf.points.map { p in
            let loc = (p.hu - tf.minHU) / max(tf.maxHU - tf.minHU, 1)
            return .init(color: Color(.sRGB, red: Double(p.color.x), green: Double(p.color.y),
                                      blue: Double(p.color.z), opacity: Double(max(0.15, p.opacity))),
                         location: Double(min(max(loc, 0), 1)))
        })
    }
    private var clipPopover: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Clip Planes").font(.headline)
            clipAxis("X", min: $viewer.clipMin.x, max: $viewer.clipMax.x)
            clipAxis("Y", min: $viewer.clipMin.y, max: $viewer.clipMax.y)
            clipAxis("Z", min: $viewer.clipMin.z, max: $viewer.clipMax.z)
        }.padding().frame(width: 280)
    }
    private func clipAxis(_ name: String, min: Binding<Float>, max: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            HStack {
                Slider(value: Binding(get: { Double(min.wrappedValue) },
                                      set: { min.wrappedValue = Swift.min(Float($0), max.wrappedValue - 0.02) }), in: 0...1)
                Slider(value: Binding(get: { Double(max.wrappedValue) },
                                      set: { max.wrappedValue = Swift.max(Float($0), min.wrappedValue + 0.02) }), in: 0...1)
            }
        }
    }
}
