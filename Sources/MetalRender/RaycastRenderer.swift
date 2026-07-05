import Metal
import MetalKit
import simd

/// GPU volume ray-caster (single-pass fragment): MIP and transfer-function
/// compositing. Used live as an `MTKViewDelegate` and offscreen for tests.
public final class RaycastRenderer: NSObject, MTKViewDelegate {
    public var volume: Volume? {
        didSet { if oldValue !== volume { frameVolume() } }
    }
    public var camera = ArcballCamera()
    public var mode: RenderMode = .mip
    public var winCenter: Float = 40
    public var winWidth: Float = 400
    public var lut: MTLTexture?
    public var lutMinHU: Float = -1000
    public var lutMaxHU: Float = 3000
    /// Built LUT textures keyed by transfer-function preset index (avoids
    /// re-allocating a texture on every SwiftUI update).
    public var lutCache: [Int: MTLTexture] = [:]
    public var clipMin = SIMD3<Float>(0, 0, 0)
    public var clipMax = SIMD3<Float>(1, 1, 1)
    public var lightEnabled = true
    public var isoValue: Float = 300

    private let ctx = MetalContext.shared

    public override init() {
        super.init()
        lut = TransferFunction.ctBoneSoft.makeLUTTexture()
    }

    /// Pull the camera back to frame the whole volume.
    public func frameVolume() {
        guard let v = volume else { return }
        let s = v.physicalSize
        camera.distance = max(s.x, max(s.y, s.z)) * 2.2
        camera.resetTarget()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = ctx.queue.makeCommandBuffer() else { return }
        if let vol = volume, let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            var u = uniforms(drawableSize: view.drawableSize, vol: vol)
            encode(into: enc, uniforms: &u, vol: vol)
            enc.endEncoding()
        } else if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
    }

    private func encode(into enc: MTLRenderCommandEncoder,
                        uniforms u: inout RaycastUniforms, vol: Volume) {
        enc.setRenderPipelineState(ctx.raycastPipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<RaycastUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<RaycastUniforms>.stride, index: 0)
        enc.setFragmentTexture(vol.texture, index: 0)
        enc.setFragmentTexture(lut, index: 1)
        enc.setFragmentSamplerState(ctx.linearSampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func uniforms(drawableSize: CGSize, vol: Volume) -> RaycastUniforms {
        var u = RaycastUniforms()
        let b = camera.basis()
        u.camPos = SIMD4(b.eye.x, b.eye.y, b.eye.z, 0)
        u.camForward = SIMD4(b.forward.x, b.forward.y, b.forward.z, 0)
        u.camRight = SIMD4(b.right.x, b.right.y, b.right.z, 0)
        u.camUp = SIMD4(b.up.x, b.up.y, b.up.z, 0)
        let half = vol.physicalSize * 0.5
        u.boxHalf = SIMD4(half.x, half.y, half.z, 0)

        let aspect = Float(drawableSize.width / max(drawableSize.height, 1))
        let thy = tan(camera.fovY * 0.5)
        u.tanHalfFov = SIMD2(thy * aspect, thy)

        u.slope = vol.meta.slope
        u.intercept = vol.meta.intercept
        u.winCenter = winCenter
        u.winWidth = winWidth

        let sp = vol.meta.spacing
        let minSp = min(sp[0], min(sp[1], sp[2]))
        let maxExtent = max(vol.physicalSize.x, max(vol.physicalSize.y, vol.physicalSize.z))
        // ~512 samples max along a ray — smooth orbit, still good quality.
        u.stepMM = max(minSp, maxExtent / 512)

        u.lutMinHU = lutMinHU
        u.lutMaxHU = lutMaxHU
        u.mode = mode.index
        u.isoValue = isoValue
        u.clipMin = SIMD4(clipMin.x, clipMin.y, clipMin.z, 0)
        u.clipMax = SIMD4(clipMax.x, clipMax.y, clipMax.z, 0)
        u.lightEnabled = lightEnabled ? 1 : 0
        return u
    }

    /// Render the current settings to a CGImage offscreen (headless test).
    public func renderOffscreen(size: Int = 384) -> CGImage? {
        guard let vol = volume else { return nil }
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

        var u = uniforms(drawableSize: CGSize(width: size, height: size), vol: vol)
        encode(into: enc, uniforms: &u, vol: vol)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        return MPRPlaneRenderer.cgImage(from: target)
    }
}
