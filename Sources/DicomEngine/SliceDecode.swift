import Foundation
import simd

/// One decoded slice: 16-bit pixels + the geometry needed to place it.
struct DecodedSlice {
    var pixels: Data            // rows*cols little-endian int16
    var rows: Int
    var cols: Int
    var position: [Double]      // ImagePositionPatient (3)
    var orientation: [Double]   // ImageOrientationPatient (6)
    var pixelSpacing: [Double]  // row, col
    var sliceThickness: Double
    var slope: Double
    var intercept: Double
    var windowCenter: Double
    var windowWidth: Double
    var modality: String
    var seriesUID: String

    init?(_ dict: [AnyHashable: Any]) {
        guard let px = dict["pixelData"] as? Data,
              let r = dict["rows"] as? NSNumber,
              let c = dict["columns"] as? NSNumber else { return nil }
        pixels = px
        rows = r.intValue
        cols = c.intValue
        position = (dict["position"] as? [NSNumber])?.map(\.doubleValue) ?? [0, 0, 0]
        orientation = (dict["orientation"] as? [NSNumber])?.map(\.doubleValue) ?? [1, 0, 0, 0, 1, 0]
        pixelSpacing = (dict["pixelSpacing"] as? [NSNumber])?.map(\.doubleValue) ?? [1, 1]
        sliceThickness = (dict["sliceThickness"] as? NSNumber)?.doubleValue ?? 1
        slope = (dict["slope"] as? NSNumber)?.doubleValue ?? 1
        intercept = (dict["intercept"] as? NSNumber)?.doubleValue ?? 0
        windowCenter = (dict["windowCenter"] as? NSNumber)?.doubleValue ?? 40
        windowWidth = (dict["windowWidth"] as? NSNumber)?.doubleValue ?? 400
        modality = (dict["modality"] as? String) ?? ""
        seriesUID = (dict["seriesUID"] as? String) ?? ""
        // Orientation may be all-zero if absent → fall back to axial identity.
        if orientation.allSatisfy({ $0 == 0 }) { orientation = [1, 0, 0, 0, 1, 0] }
    }

    /// Expand a multi-frame decode into one slice per frame. Frames get
    /// synthetic positions along the slice normal (frame order preserved) —
    /// right for US clips / basic enhanced objects; per-frame functional-group
    /// positions are not parsed (v1).
    static func expandFrames(_ dict: [AnyHashable: Any], frames: Int) -> [DecodedSlice] {
        guard let proto = DecodedSlice(dict), frames > 1 else {
            return DecodedSlice(dict).map { [$0] } ?? []
        }
        let bytesPerFrame = proto.rows * proto.cols * MemoryLayout<Int16>.size
        guard proto.pixels.count >= bytesPerFrame * frames else { return [proto] }
        let o = proto.orientation
        let normal = cross(SIMD3(o[0], o[1], o[2]), SIMD3(o[3], o[4], o[5]))
        let step = proto.sliceThickness > 0 ? proto.sliceThickness : 1
        return (0..<frames).map { i in
            var s = proto
            s.pixels = proto.pixels.subdata(in: i * bytesPerFrame..<(i + 1) * bytesPerFrame)
            s.position = [proto.position[0] + normal.x * step * Double(i),
                          proto.position[1] + normal.y * step * Double(i),
                          proto.position[2] + normal.z * step * Double(i)]
            return s
        }
    }
}

enum SliceStacker {
    /// Sort, stack, and resample slices into a uniform int16 volume.
    /// Returns (data, dims[nx,ny,nz], spacing[sx,sy,sz], origin, resampled?).
    static func buildVolume(_ slices: [DecodedSlice])
        -> (data: Data, nx: Int, ny: Int, nz: Int, sx: Float, sy: Float, sz: Float,
            origin: [Float], resampled: Bool)? {
        guard let first = slices.first else { return nil }
        let rows = first.rows, cols = first.cols
        let valid = slices.filter { $0.rows == rows && $0.cols == cols }

        // Slice normal from orientation row×col.
        let o = first.orientation
        let rc = SIMD3<Double>(o[0], o[1], o[2])
        let cc = SIMD3<Double>(o[3], o[4], o[5])
        let normal = cross(rc, cc)
        func proj(_ s: DecodedSlice) -> Double {
            dot(SIMD3<Double>(s.position[0], s.position[1], s.position[2]), normal)
        }
        let sorted = valid.sorted { proj($0) < proj($1) }
        let zpos = sorted.map(proj)

        let perFrame = rows * cols
        // Stack as float for optional resampling.
        var planes: [[Float]] = sorted.map { s in
            s.pixels.withUnsafeBytes { raw -> [Float] in
                let i16 = raw.bindMemory(to: Int16.self)
                return (0..<min(perFrame, i16.count)).map { Float(i16[$0]) }
            }
        }

        // z spacing + uniform resample.
        var sz = Float(first.sliceThickness)
        var resampled = false
        if zpos.count >= 2 {
            var diffs = [Double]()
            for i in 1..<zpos.count { diffs.append(zpos[i] - zpos[i - 1]) }
            let step = median(diffs)
            if step > 0 {
                sz = Float(step)
                let maxDev = diffs.map { abs($0 - step) }.max() ?? 0
                if maxDev > 0.01 * step {
                    (planes, resampled) = resampleZ(planes, zpos: zpos, step: step, perFrame: perFrame)
                }
            }
        }

        let nz = planes.count
        // Float planes -> contiguous int16 buffer.
        var out = Data(count: nz * perFrame * MemoryLayout<Int16>.size)
        out.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: Int16.self)
            var idx = 0
            for plane in planes {
                for v in plane {
                    dst[idx] = Int16(max(-32768, min(32767, v.rounded())))
                    idx += 1
                }
            }
        }

        let sx = Float(first.pixelSpacing.count > 1 ? first.pixelSpacing[1] : 1) // col
        let sy = Float(first.pixelSpacing.first ?? 1)                            // row
        let origin = sorted.first?.position.map { Float($0) } ?? [0, 0, 0]
        return (out, cols, rows, nz, sx, sy, sz, origin, resampled)
    }

    private static func median(_ a: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        let s = a.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private static func resampleZ(_ planes: [[Float]], zpos: [Double], step: Double,
                                  perFrame: Int) -> ([[Float]], Bool) {
        let z0 = zpos.first!, z1 = zpos.last!
        let n = max(2, Int(((z1 - z0) / step).rounded()) + 1)
        var out = [[Float]]()
        out.reserveCapacity(n)
        for i in 0..<n {
            let zt = z0 + step * Double(i)
            let j = zpos.firstIndex(where: { $0 >= zt }) ?? zpos.count
            if j <= 0 { out.append(planes[0]); continue }
            if j >= zpos.count { out.append(planes[planes.count - 1]); continue }
            let zlo = zpos[j - 1], zhi = zpos[j]
            let t = zhi == zlo ? 0 : Float((zt - zlo) / (zhi - zlo))
            let a = planes[j - 1], b = planes[j]
            var blended = [Float](repeating: 0, count: perFrame)
            for k in 0..<perFrame { blended[k] = a[k] * (1 - t) + b[k] * t }
            out.append(blended)
        }
        return (out, true)
    }
}
