import Foundation
import Metal
import simd

/// A decoded volume resident on the GPU as an `r16Snorm` 3D texture.
///
/// The int16 stored values are uploaded directly (no float conversion): r16Snorm
/// maps the int16 bit pattern to v/32767, so shaders recover the stored value as
/// `sample * 32767` before applying slope/intercept. This halves GPU + transfer
/// memory vs r32Float and keeps linear filtering. CPU probing uses `stored`.
public final class Volume {
    public let meta: VolumeMeta
    /// r16Snorm 3D texture; shaders recover stored value as `sample * 32767`.
    public let texture: MTLTexture
    /// Stored 16-bit values retained for CPU probing/measurement (HU = v*slope+intercept).
    public let stored: [Int16]

    /// Largest 3D texture dimension we will attempt (Apple GPUs support 2048).
    public static let maxDimension = 2048

    /// Build directly from an in-memory int16 buffer (the native decode path).
    public init?(meta: VolumeMeta, data: Data) {
        self.meta = meta
        let nx = meta.nx, ny = meta.ny, nz = meta.nz
        guard nx > 0, ny > 0, nz > 0,
              nx <= Self.maxDimension, ny <= Self.maxDimension, nz <= Self.maxDimension
        else { return nil }

        let count = nx * ny * nz
        guard data.count >= count * MemoryLayout<Int16>.size else { return nil }

        // Retain stored int16 for CPU probing.
        var stored = [Int16](repeating: 0, count: count)
        stored.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst, count: count * MemoryLayout<Int16>.size)
        }
        self.stored = stored

        // Upload the int16 buffer directly as r16Snorm (no float conversion).
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .r16Snorm
        desc.width = nx
        desc.height = ny
        desc.depth = nz
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = MetalContext.shared.device.makeTexture(descriptor: desc) else {
            return nil
        }
        stored.withUnsafeBytes { sb in
            tex.replace(region: MTLRegionMake3D(0, 0, 0, nx, ny, nz),
                        mipmapLevel: 0,
                        slice: 0,
                        withBytes: sb.baseAddress!,
                        bytesPerRow: nx * MemoryLayout<Int16>.size,
                        bytesPerImage: nx * ny * MemoryLayout<Int16>.size)
        }
        self.texture = tex
    }

    /// Physical extent of the volume in millimetres.
    public var physicalSize: SIMD3<Float> {
        SIMD3(Float(meta.nx) * meta.spacing[0],
              Float(meta.ny) * meta.spacing[1],
              Float(meta.nz) * meta.spacing[2])
    }

    /// HU (modality units) at integer voxel coordinates; nil if out of range.
    public func hu(x: Int, y: Int, z: Int) -> Float? {
        guard x >= 0, y >= 0, z >= 0, x < meta.nx, y < meta.ny, z < meta.nz else { return nil }
        let v = Float(stored[(z * meta.ny + y) * meta.nx + x])
        return v * meta.slope + meta.intercept
    }

    /// HU at normalized texture coordinates (0…1 each axis); nearest voxel.
    public func hu(tc: SIMD3<Float>) -> Float? {
        let x = Int((tc.x * Float(meta.nx - 1)).rounded())
        let y = Int((tc.y * Float(meta.ny - 1)).rounded())
        let z = Int((tc.z * Float(meta.nz - 1)).rounded())
        return hu(x: x, y: y, z: z)
    }

    public struct ROIStats {
        public let count: Int
        public let mean: Float
        public let min: Float
        public let max: Float
        public let sd: Float
        public let areaMM2: Float
        /// HU distribution across `min…max` (48 bins; empty when min == max).
        public let histogram: [Int]
    }

    /// Backward-compatible axial ROI.
    public func roiStats(a: SIMD2<Float>, b: SIMD2<Float>, zFrac: Float) -> ROIStats? {
        roiStats(axis: .axial, a: a, b: b, sliceFrac: zFrac)
    }

    /// HU statistics over a rectangle on any orthogonal plane (normalized plane
    /// corners `a`/`b`, slice fraction along the plane's axis). Exact voxel
    /// iteration over the stored int16.
    public func roiStats(axis: MPRAxis, a: SIMD2<Float>, b: SIMD2<Float>, sliceFrac: Float) -> ROIStats? {
        // Map both plane corners into the volume; the covered voxel box is the
        // component-wise min/max (the slice axis collapses to one index).
        let p = axis.toVolume(a, slice: sliceFrac)
        let q = axis.toVolume(b, slice: sliceFrac)
        func range(_ lo: Float, _ hi: Float, _ n: Int) -> ClosedRange<Int>? {
            let i0 = Swift.max(Int((Swift.min(lo, hi) * Float(n - 1)).rounded()), 0)
            let i1 = Swift.min(Int((Swift.max(lo, hi) * Float(n - 1)).rounded()), n - 1)
            return i1 >= i0 ? i0...i1 : nil
        }
        guard let xs = range(p.x, q.x, meta.nx),
              let ys = range(p.y, q.y, meta.ny),
              let zs = range(p.z, q.z, meta.nz) else { return nil }

        // Single voxel pass: collect HU values (bounded to the ROI box) while
        // accumulating stats, then bin from the buffer — no second scan of `stored`.
        var values = [Float]()
        values.reserveCapacity(xs.count * ys.count * zs.count)
        var sum = 0.0, sumSq = 0.0
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for z in zs {
            let plane = z * meta.ny * meta.nx
            for y in ys {
                let row = plane + y * meta.nx
                for x in xs {
                    let v = Float(stored[row + x]) * meta.slope + meta.intercept
                    values.append(v); sum += Double(v); sumSq += Double(v) * Double(v)
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                }
            }
        }
        let n = values.count
        guard n > 0 else { return nil }
        let mean = sum / Double(n)
        let variance = Swift.max(sumSq / Double(n) - mean * mean, 0)
        let (su, sv) = axis.planeSpacing(SIMD3(meta.spacing[0], meta.spacing[1], meta.spacing[2]))
        let (nu, nv) = axis.planeDims(nx: meta.nx, ny: meta.ny, nz: meta.nz)
        let du = abs(b.x - a.x) * Float(nu) * su
        let dv = abs(b.y - a.y) * Float(nv) * sv

        var bins = [Int]()
        if hi > lo {
            let nb = 48
            bins = [Int](repeating: 0, count: nb)
            let scale = Float(nb - 1) / (hi - lo)
            for v in values { bins[Int((v - lo) * scale)] += 1 }
        }
        return ROIStats(count: n, mean: Float(mean), min: lo, max: hi,
                        sd: Float(variance.squareRoot()), areaMM2: du * dv, histogram: bins)
    }
}
