import Metal
import MetalKit
import simd

/// Renders one orthogonal (or arbitrary-fraction) plane of a volume with
/// window/level. Used live as an `MTKViewDelegate` and offscreen for tests.
public final class MPRPlaneRenderer: NSObject, MTKViewDelegate {
    public var volume: Volume?
    public var axis: MPRAxis = .axial
    public var sliceFrac: Float = 0.5
    public var winCenter: Float = 40
    public var winWidth: Float = 400
    public var zoom: Float = 1
    public var pan: SIMD2<Float> = .zero
    public var invert: Bool = false
    public var quarter: Int = 0
    public var flipH: Bool = false
    public var flipV: Bool = false

    private let ctx = MetalContext.shared

    public override init() { super.init() }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = ctx.queue.makeCommandBuffer() else { return }

        if let vol = volume,
           let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            var u = Self.uniforms(axis: axis, sliceFrac: sliceFrac,
                                  winCenter: winCenter, winWidth: winWidth,
                                  vol: vol, drawableSize: view.drawableSize,
                                  zoom: zoom, pan: pan, invert: invert,
                                  quarter: quarter, flipH: flipH, flipV: flipV)
            encode(into: enc, uniforms: &u, texture: vol.texture)
            enc.endEncoding()
        } else if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.endEncoding() // just clear
        }
        cmd.present(drawable)
        cmd.commit()
    }

    private func encode(into enc: MTLRenderCommandEncoder,
                        uniforms u: inout MPRUniforms,
                        texture: MTLTexture) {
        enc.setRenderPipelineState(ctx.mprPipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<MPRUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<MPRUniforms>.stride, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(ctx.linearSampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Build plane uniforms. Vertical axis is flipped for coronal/sagittal so
    /// superior (high z) renders at the top.
    static func uniforms(axis: MPRAxis, sliceFrac f: Float,
                         winCenter: Float, winWidth: Float,
                         vol: Volume, drawableSize: CGSize,
                         zoom: Float = 1, pan: SIMD2<Float> = .zero,
                         invert: Bool = false,
                         quarter: Int = 0, flipH: Bool = false, flipV: Bool = false) -> MPRUniforms {
        var u = MPRUniforms()
        u.zoom = zoom
        u.pan = pan
        u.invert = invert ? 1 : 0
        u.quarter = UInt32(((quarter % 4) + 4) % 4)
        u.flipMask = (flipH ? 1 : 0) | (flipV ? 2 : 0)
        let phys = vol.physicalSize
        var planeW: Float = 1, planeH: Float = 1
        switch axis {
        case .axial:
            u.originTC = SIMD4(0, 0, f, 0)
            u.uAxisTC = SIMD4(1, 0, 0, 0)
            u.vAxisTC = SIMD4(0, 1, 0, 0)
            planeW = phys.x; planeH = phys.y
        case .coronal:
            u.originTC = SIMD4(0, f, 1, 0)
            u.uAxisTC = SIMD4(1, 0, 0, 0)
            u.vAxisTC = SIMD4(0, 0, -1, 0)
            planeW = phys.x; planeH = phys.z
        case .sagittal:
            u.originTC = SIMD4(f, 0, 1, 0)
            u.uAxisTC = SIMD4(0, 1, 0, 0)
            u.vAxisTC = SIMD4(0, 0, -1, 0)
            planeW = phys.y; planeH = phys.z
        }

        // 90°/270° rotation swaps the displayed width/height.
        if u.quarter % 2 == 1 { swap(&planeW, &planeH) }

        // Letterbox the plane to its physical aspect ratio.
        let w = Float(max(drawableSize.width, 1))
        let h = Float(max(drawableSize.height, 1))
        let viewAspect = w / h
        let planeAspect = planeW / max(planeH, 0.0001)
        if planeAspect > viewAspect {
            u.fitScale = SIMD2(1, viewAspect / planeAspect)
        } else {
            u.fitScale = SIMD2(planeAspect / viewAspect, 1)
        }

        u.slope = vol.meta.slope
        u.intercept = vol.meta.intercept
        u.winCenter = winCenter
        u.winWidth = winWidth
        return u
    }

    /// Render a plane to a CGImage offscreen (used by the headless render test).
    public static func renderOffscreen(volume: Volume, axis: MPRAxis,
                                       sliceFrac: Float, winCenter: Float,
                                       winWidth: Float, size: Int = 256,
                                       zoom: Float = 1, pan: SIMD2<Float> = .zero,
                                       invert: Bool = false,
                                       quarter: Int = 0, flipH: Bool = false, flipV: Bool = false) -> CGImage? {
        let ctx = MetalContext.shared
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalContext.colorPixelFormat, width: size, height: size, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = ctx.device.makeTexture(descriptor: desc),
              let cmd = ctx.queue.makeCommandBuffer() else { return nil }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return nil }

        var u = uniforms(axis: axis, sliceFrac: sliceFrac,
                         winCenter: winCenter, winWidth: winWidth,
                         vol: volume, drawableSize: CGSize(width: size, height: size),
                         zoom: zoom, pan: pan, invert: invert,
                         quarter: quarter, flipH: flipH, flipV: flipV)
        enc.setRenderPipelineState(ctx.mprPipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<MPRUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<MPRUniforms>.stride, index: 0)
        enc.setFragmentTexture(volume.texture, index: 0)
        enc.setFragmentSamplerState(ctx.linearSampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        return Self.cgImage(from: target)
    }

    static func cgImage(from texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        let rowBytes = w * 4
        var bgra = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&bgra, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        // Keep BGRA and let CoreGraphics read it as little-endian ARGB (byteOrder32
        // little + premultipliedFirst) — avoids a per-pixel channel swap + a copy.
        guard let provider = CGDataProvider(data: Data(bgra) as CFData) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rowBytes, space: space, bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
