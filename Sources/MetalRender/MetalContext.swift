import Metal
import MetalKit

/// Shared Metal device, queue, library, and pipelines.
public final class MetalContext {
    public static let shared = MetalContext()

    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let library: MTLLibrary
    let mprPipeline: MTLRenderPipelineState
    let raycastPipeline: MTLRenderPipelineState
    let linearSampler: MTLSamplerState

    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available on this Mac")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("could not create Metal command queue")
        }
        self.queue = queue

        // Shaders are compiled into the app bundle's default.metallib.
        guard let library = device.makeDefaultLibrary() else {
            fatalError("could not load default Metal library")
        }
        self.library = library

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertex_mpr")
        desc.fragmentFunction = library.makeFunction(name: "fragment_mpr")
        desc.colorAttachments[0].pixelFormat = Self.colorPixelFormat
        do {
            self.mprPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("failed to build MPR pipeline: \(error)")
        }

        let rc = MTLRenderPipelineDescriptor()
        rc.vertexFunction = library.makeFunction(name: "vertex_raycast")
        rc.fragmentFunction = library.makeFunction(name: "fragment_raycast")
        rc.colorAttachments[0].pixelFormat = Self.colorPixelFormat
        do {
            self.raycastPipeline = try device.makeRenderPipelineState(descriptor: rc)
        } catch {
            fatalError("failed to build raycast pipeline: \(error)")
        }

        let samp = MTLSamplerDescriptor()
        samp.minFilter = .linear
        samp.magFilter = .linear
        samp.mipFilter = .notMipmapped
        samp.sAddressMode = .clampToEdge
        samp.tAddressMode = .clampToEdge
        samp.rAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samp) else {
            fatalError("could not create sampler")
        }
        self.linearSampler = sampler
    }
}
