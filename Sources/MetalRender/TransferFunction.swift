import Metal
import simd

/// An opacity/color transfer function defined by HU control points, rasterized
/// to a 1D RGBA LUT texture for the volume ray-caster.
public struct TransferFunction: Sendable {
    public struct ControlPoint: Sendable {
        public var hu: Float
        public var color: SIMD3<Float>   // 0…1
        public var opacity: Float        // 0…1
        public init(hu: Float, color: SIMD3<Float>, opacity: Float) {
            self.hu = hu; self.color = color; self.opacity = opacity
        }
    }

    public var minHU: Float
    public var maxHU: Float
    public var points: [ControlPoint]

    public init(minHU: Float, maxHU: Float, points: [ControlPoint]) {
        self.minHU = minHU
        self.maxHU = maxHU
        self.points = points.sorted { $0.hu < $1.hu }
    }

    /// CT preset blending soft tissue (warm, faint) into bone (bright, opaque).
    public static let ctBoneSoft = TransferFunction(minHU: -1000, maxHU: 3000, points: [
        .init(hu: -1000, color: .init(0, 0, 0), opacity: 0.0),
        .init(hu: -500,  color: .init(0, 0, 0), opacity: 0.0),
        .init(hu: -100,  color: .init(0.75, 0.45, 0.35), opacity: 0.02),
        .init(hu: 80,    color: .init(0.90, 0.65, 0.55), opacity: 0.04),
        .init(hu: 300,   color: .init(0.95, 0.88, 0.75), opacity: 0.18),
        .init(hu: 1000,  color: .init(1.0, 0.98, 0.92), opacity: 0.75),
        .init(hu: 3000,  color: .init(1, 1, 1), opacity: 0.95),
    ])

    /// Angiography-ish: emphasize mid/high densities, transparent soft tissue.
    public static let ctVessels = TransferFunction(minHU: -1000, maxHU: 3000, points: [
        .init(hu: -1000, color: .init(0, 0, 0), opacity: 0.0),
        .init(hu: 100,   color: .init(0.4, 0.0, 0.0), opacity: 0.0),
        .init(hu: 200,   color: .init(0.9, 0.2, 0.2), opacity: 0.2),
        .init(hu: 600,   color: .init(1.0, 0.85, 0.4), opacity: 0.6),
        .init(hu: 3000,  color: .init(1, 1, 1), opacity: 0.9),
    ])

    public static let presets: [(name: String, tf: TransferFunction)] = [
        ("CT Bone + Soft", ctBoneSoft),
        ("CT Vessels", ctVessels),
    ]

    /// Rasterize to `n` RGBA8 entries by piecewise-linear interpolation.
    public func makeLUTTexture(n: Int = 256) -> MTLTexture? {
        var bytes = [UInt8](repeating: 0, count: n * 4)
        let range = max(maxHU - minHU, 1)
        for i in 0..<n {
            let hu = minHU + (Float(i) / Float(n - 1)) * range
            let (c, a) = sample(hu: hu)
            bytes[i * 4 + 0] = UInt8(max(0, min(1, c.x)) * 255)
            bytes[i * 4 + 1] = UInt8(max(0, min(1, c.y)) * 255)
            bytes[i * 4 + 2] = UInt8(max(0, min(1, c.z)) * 255)
            bytes[i * 4 + 3] = UInt8(max(0, min(1, a)) * 255)
        }
        let desc = MTLTextureDescriptor()
        desc.textureType = .type1D
        desc.pixelFormat = .rgba8Unorm
        desc.width = n
        desc.usage = .shaderRead
        guard let tex = MetalContext.shared.device.makeTexture(descriptor: desc) else { return nil }
        bytes.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake1D(0, n), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: 0)
        }
        return tex
    }

    private func sample(hu: Float) -> (SIMD3<Float>, Float) {
        guard let first = points.first, let last = points.last else {
            return (.zero, 0)
        }
        if hu <= first.hu { return (first.color, first.opacity) }
        if hu >= last.hu { return (last.color, last.opacity) }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if hu <= b.hu {
                let t = (hu - a.hu) / max(b.hu - a.hu, 1e-3)
                return (mix(a.color, b.color, t: t), a.opacity + (b.opacity - a.opacity) * t)
            }
        }
        return (last.color, last.opacity)
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}
