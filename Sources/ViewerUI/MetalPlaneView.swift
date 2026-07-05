import SwiftUI
import MetalKit

/// MTKView subclass that forwards scroll-wheel (slice scrubbing) to SwiftUI.
/// Trackpad/precise scroll is accumulated so one slice steps per notch-equivalent.
final class PlaneMTKView: MTKView {
    var onScroll: ((Double) -> Void)?
    /// Right-drag deltas (standard viewer convention: window/level without
    /// switching tools).
    var onRightDrag: ((CGSize) -> Void)?
    var inputDevice: InputDevice = .auto
    var naturalScroll = true
    private var accum = 0.0
    private var notches = 0.0
    private let stepPx = 16.0

    override func rightMouseDragged(with event: NSEvent) {
        onRightDrag?(CGSize(width: event.deltaX, height: event.deltaY))
    }
    override func menu(for event: NSEvent) -> NSMenu? { nil }   // keep right-drag clean

    override func scrollWheel(with event: NSEvent) {
        var dy = event.scrollingDeltaY
        if !naturalScroll { dy = -dy }
        // ⌘ or ⌃ held → fine scrubbing: it takes more scroll travel to advance a
        // slice, for frame-accurate positioning in a thick stack.
        let fine = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        if inputDevice.precise(eventHasPrecise: event.hasPreciseScrollingDeltas) {
            let step = fine ? stepPx * 4 : stepPx
            accum += dy
            while abs(accum) >= step {
                let dir = accum > 0 ? 1.0 : -1.0
                onScroll?(dir)
                accum -= dir * step
            }
        } else if dy != 0 {
            if fine {                       // mouse wheel: one slice every 4th notch
                notches += dy > 0 ? 1 : -1
                if abs(notches) >= 4 { onScroll?(notches > 0 ? 1 : -1); notches = 0 }
            } else {
                onScroll?(dy)
            }
        }
    }
}

/// SwiftUI host for an `MTKView` driven by an `MPRPlaneRenderer`. Redraws only
/// when the passed-in state changes (paused MTKView + setNeedsDisplay).
struct MetalPlaneView: NSViewRepresentable {
    let renderer: MPRPlaneRenderer
    var volume: Volume?
    var axis: MPRAxis
    var sliceFrac: Float
    var winCenter: Float
    var winWidth: Float
    var zoom: Float = 1
    var pan: SIMD2<Float> = .zero
    var invert: Bool = false
    var quarter: Int = 0
    var flipH: Bool = false
    var flipV: Bool = false
    var inputDevice: InputDevice = .auto
    var naturalScroll: Bool = true
    var onScroll: ((Double) -> Void)? = nil
    var onRightDrag: ((CGSize) -> Void)? = nil

    func makeNSView(context: Context) -> PlaneMTKView {
        let view = PlaneMTKView()
        view.device = MetalContext.shared.device
        view.colorPixelFormat = MetalContext.colorPixelFormat
        view.delegate = renderer
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        return view
    }

    func updateNSView(_ view: PlaneMTKView, context: Context) {
        renderer.volume = volume
        renderer.axis = axis
        renderer.sliceFrac = sliceFrac
        renderer.winCenter = winCenter
        renderer.winWidth = winWidth
        renderer.zoom = zoom
        renderer.pan = pan
        renderer.invert = invert
        renderer.quarter = quarter
        renderer.flipH = flipH
        renderer.flipV = flipV
        view.inputDevice = inputDevice
        view.naturalScroll = naturalScroll
        view.onScroll = onScroll
        view.onRightDrag = onRightDrag
        view.setNeedsDisplay(view.bounds)
    }
}
