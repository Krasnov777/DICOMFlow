// CPU slice renderer for the MCP server. Renders a decoded DICOM frame to a
// windowed grayscale PNG with no Metal — so it works in a plain command-line tool
// (a CLI has no app bundle to load a Metal shader library from).

import Foundation
import CoreGraphics
import ImageIO

struct RenderedSlice {
    let png: Data
    let info: [String: Any]
}

enum SliceRender {
    /// Decode one file (a given frame) and window it into a grayscale PNG.
    /// `window`/`level` override the file's WC/WW when provided. The image is
    /// downscaled so its longest side ≤ `maxSize` (agents don't need full res).
    static func render(path: String, frame: Int, window: Double?, level: Double?, maxSize: Int) throws -> RenderedSlice {
        let d = try DCMTKBridge.decodeFile(path)
        guard let pixels = d["pixelData"] as? Data,
              let rows = (d["rows"] as? NSNumber)?.intValue,
              let cols = (d["columns"] as? NSNumber)?.intValue,
              rows > 0, cols > 0 else {
            throw NSError(domain: "mcp", code: 1, userInfo: [NSLocalizedDescriptionKey: "no image pixels in \(path)"])
        }
        let frames = (d["frames"] as? NSNumber)?.intValue ?? 1
        let slope = (d["slope"] as? NSNumber)?.doubleValue ?? 1
        let intercept = (d["intercept"] as? NSNumber)?.doubleValue ?? 0
        let wc = level ?? (d["windowCenter"] as? NSNumber)?.doubleValue ?? 40
        let ww = max(window ?? (d["windowWidth"] as? NSNumber)?.doubleValue ?? 400, 1)

        let f = min(max(frame, 0), frames - 1)
        let perFrame = rows * cols

        // Color image (US Doppler / RGB) → render the RGB directly, not the luma.
        if (d["samplesPerPixel"] as? NSNumber)?.intValue == 3, let rgb = d["rgb"] as? Data,
           rgb.count >= (f + 1) * perFrame * 3 {
            let frameRGB = [UInt8](rgb[f * perFrame * 3 ..< (f + 1) * perFrame * 3])
            let (outW, outH, bytes) = downscaleRGB(frameRGB, w: cols, h: rows, maxSize: maxSize)
            guard let png = rgbPNG(bytes, width: outW, height: outH) else {
                throw NSError(domain: "mcp", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
            }
            let info: [String: Any] = ["color": true, "renderedWidth": outW, "renderedHeight": outH,
                                       "sourceRows": rows, "sourceColumns": cols, "frame": f, "frames": frames,
                                       "modality": d["modality"] as? String ?? ""]
            return RenderedSlice(png: png, info: info)
        }

        // pixelData is Int16 for every frame concatenated (8-bit widened, mono/luma).
        let samples: [Int16] = pixels.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: Int16.self)
            let start = f * perFrame
            guard start + perFrame <= base.count else { return [] }
            return Array(base[start ..< start + perFrame])
        }
        guard samples.count == perFrame else {
            throw NSError(domain: "mcp", code: 2, userInfo: [NSLocalizedDescriptionKey: "frame \(f) out of range"])
        }

        // Window/level in modality (HU) units → 8-bit gray.
        let lo = wc - ww / 2, hi = wc + ww / 2, span = hi - lo
        var gray = [UInt8](repeating: 0, count: perFrame)
        for i in 0 ..< perFrame {
            let hu = Double(samples[i]) * slope + intercept
            let t = span > 0 ? (hu - lo) / span : 0
            gray[i] = UInt8(min(max(t, 0), 1) * 255)
        }

        // Nearest-neighbor downscale so the longest side ≤ maxSize.
        var outW = cols, outH = rows, outBytes = gray
        let longest = max(rows, cols)
        if maxSize > 0, longest > maxSize {
            let scale = Double(maxSize) / Double(longest)
            outW = max(Int(Double(cols) * scale), 1)
            outH = max(Int(Double(rows) * scale), 1)
            outBytes = [UInt8](repeating: 0, count: outW * outH)
            for y in 0 ..< outH {
                let sy = min(Int(Double(y) / scale), rows - 1)
                for x in 0 ..< outW {
                    let sx = min(Int(Double(x) / scale), cols - 1)
                    outBytes[y * outW + x] = gray[sy * cols + sx]
                }
            }
        }

        guard let png = grayscalePNG(outBytes, width: outW, height: outH) else {
            throw NSError(domain: "mcp", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
        }
        let info: [String: Any] = [
            "renderedWidth": outW, "renderedHeight": outH,
            "sourceRows": rows, "sourceColumns": cols, "frame": f, "frames": frames,
            "windowCenter": wc, "windowWidth": ww,
            "modality": d["modality"] as? String ?? "",
        ]
        return RenderedSlice(png: png, info: info)
    }

    // MARK: - Reslice (coronal / sagittal / oblique) from a stacked volume

    /// A stacked int16 volume in voxel order data[(z*ny + y)*nx + x], with mm spacing.
    struct DVolume {
        var data: [Int16]
        var nx: Int, ny: Int, nz: Int
        var sx: Double, sy: Double, sz: Double   // mm per voxel along x/y/z
        var slope: Double, intercept: Double, wc: Double, ww: Double
    }

    /// Decode every file in a series and stack it into a 3D volume, sorting slices
    /// by their position along the slice normal and deriving the through-plane
    /// spacing from consecutive positions.
    static func buildVolume(_ files: [String]) throws -> DVolume {
        func cross(_ a: [Double], _ b: [Double]) -> [Double] {
            [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]]
        }
        func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).map(*).reduce(0, +) }
        func darr(_ d: [AnyHashable: Any], _ k: String) -> [Double] {
            (d[k] as? [NSNumber])?.map { $0.doubleValue } ?? []
        }

        var rows = 0, cols = 0
        var slope = 1.0, intercept = 0.0, wc = 40.0, ww = 400.0, sx = 1.0, sy = 1.0
        var normal = [0.0, 0.0, 1.0]
        struct Slice { let pixels: [Int16]; let proj: Double }
        var slices: [Slice] = []

        for (i, f) in files.enumerated() {
            guard let d = try? DCMTKBridge.decodeFile(f),
                  let pd = d["pixelData"] as? Data,
                  let r = (d["rows"] as? NSNumber)?.intValue,
                  let c = (d["columns"] as? NSNumber)?.intValue, r > 0, c > 0 else { continue }
            if rows == 0 {
                rows = r; cols = c
                slope = (d["slope"] as? NSNumber)?.doubleValue ?? 1
                intercept = (d["intercept"] as? NSNumber)?.doubleValue ?? 0
                wc = (d["windowCenter"] as? NSNumber)?.doubleValue ?? 40
                ww = max((d["windowWidth"] as? NSNumber)?.doubleValue ?? 400, 1)
                let ps = darr(d, "pixelSpacing")        // [rowSpacing, colSpacing]
                sy = ps.count > 0 ? ps[0] : 1
                sx = ps.count > 1 ? ps[1] : 1
                let ori = darr(d, "orientation")         // 6 direction cosines
                if ori.count == 6 { normal = cross(Array(ori[0...2]), Array(ori[3...5])) }
            } else if r != rows || c != cols { continue }  // skip odd-sized slices

            let perFrame = r * c
            let px: [Int16] = pd.withUnsafeBytes { raw in
                let b = raw.bindMemory(to: Int16.self)
                return Array(b[0 ..< min(perFrame, b.count)])
            }
            guard px.count == perFrame else { continue }
            let pos = darr(d, "position")
            let proj = pos.count == 3 ? dot(pos, normal) : Double(i)
            slices.append(Slice(pixels: px, proj: proj))
        }
        guard rows > 0, cols > 0, slices.count >= 2 else {
            throw NSError(domain: "mcp", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "need ≥2 same-sized slices to reslice (got \(slices.count))"])
        }
        slices.sort { $0.proj < $1.proj }
        // Through-plane spacing = median of consecutive position deltas.
        var diffs = (1 ..< slices.count).map { abs(slices[$0].proj - slices[$0 - 1].proj) }.filter { $0 > 1e-4 }
        diffs.sort()
        let sz = diffs.isEmpty ? 1.0 : diffs[diffs.count / 2]

        let nz = slices.count
        var data = [Int16](repeating: 0, count: cols * rows * nz)
        for (z, s) in slices.enumerated() {
            let off = z * rows * cols
            data.replaceSubrange(off ..< off + rows * cols, with: s.pixels)
        }
        return DVolume(data: data, nx: cols, ny: rows, nz: nz,
                       sx: sx, sy: sy, sz: sz, slope: slope, intercept: intercept, wc: wc, ww: ww)
    }

    /// Reslice a volume along an orthogonal or oblique plane and window to a PNG.
    /// `plane`: coronal | sagittal | oblique | axial. `position` (0…1) picks the
    /// slice for orthogonal planes; `angle` (deg) rotates the oblique vertical
    /// plane in the axial (x-y) plane about the volume centre.
    static func reslice(_ v: DVolume, plane: String, position: Double, angle: Double,
                        window: Double?, level: Double?, maxSize: Int) -> RenderedSlice {
        let nx = Double(v.nx - 1), ny = Double(v.ny - 1), nz = Double(v.nz - 1)
        let pos = min(max(position, 0), 1)
        var origin = [0.0, 0.0, 0.0], uAxis = [0.0, 0.0, 0.0], vAxis = [0.0, 0.0, 0.0]

        switch plane {
        case "sagittal":                         // Y×Z plane at x = pos, superior up
            origin = [pos * nx, 0, nz]; uAxis = [0, ny, 0]; vAxis = [0, 0, -nz]
        case "oblique":                          // vertical plane through centre, rotated by `angle`
            let t = angle * .pi / 180, c = cos(t), s = sin(t)
            let cx = nx / 2, cy = ny / 2
            let half = 0.5 * (Double(v.nx) * abs(c) + Double(v.ny) * abs(s))   // covers the section
            origin = [cx - half * c, cy - half * s, nz]
            uAxis = [2 * half * c, 2 * half * s, 0]; vAxis = [0, 0, -nz]
        case "axial":
            origin = [0, 0, pos * nz]; uAxis = [nx, 0, 0]; vAxis = [0, ny, 0]
        default:                                 // coronal: X×Z plane at y = pos, superior up
            origin = [0, pos * ny, nz]; uAxis = [nx, 0, 0]; vAxis = [0, 0, -nz]
        }

        // Output dims from physical proportions (square voxels), long side ≤ maxSize.
        func mm(_ a: [Double]) -> Double { sqrt(pow(a[0]*v.sx, 2) + pow(a[1]*v.sy, 2) + pow(a[2]*v.sz, 2)) }
        let pw = max(mm(uAxis), 1e-6), ph = max(mm(vAxis), 1e-6)
        let cap = maxSize > 0 ? maxSize : 512
        let outW = pw >= ph ? cap : max(Int(Double(cap) * pw / ph), 1)
        let outH = ph > pw ? cap : max(Int(Double(cap) * ph / pw), 1)

        let wc = level ?? v.wc, ww = max(window ?? v.ww, 1)
        let lo = wc - ww / 2, hi = wc + ww / 2, span = hi - lo
        var gray = [UInt8](repeating: 0, count: outW * outH)
        for j in 0 ..< outH {
            let fv = outH > 1 ? Double(j) / Double(outH - 1) : 0
            for i in 0 ..< outW {
                let fu = outW > 1 ? Double(i) / Double(outW - 1) : 0
                let x = origin[0] + fu * uAxis[0] + fv * vAxis[0]
                let y = origin[1] + fu * uAxis[1] + fv * vAxis[1]
                let z = origin[2] + fu * uAxis[2] + fv * vAxis[2]
                let hu = trilinear(v, x, y, z) * v.slope + v.intercept
                let t = span > 0 ? (hu - lo) / span : 0
                gray[j * outW + i] = UInt8(min(max(t, 0), 1) * 255)
            }
        }
        let png = grayscalePNG(gray, width: outW, height: outH) ?? Data()
        let info: [String: Any] = [
            "plane": plane, "position": pos, "angle": angle,
            "renderedWidth": outW, "renderedHeight": outH,
            "volume": ["nx": v.nx, "ny": v.ny, "nz": v.nz,
                       "spacing": [v.sx, v.sy, v.sz]],
            "windowCenter": wc, "windowWidth": ww,
        ]
        return RenderedSlice(png: png, info: info)
    }

    /// Trilinear sample of the raw int16 value at fractional voxel coords (clamped).
    private static func trilinear(_ v: DVolume, _ x: Double, _ y: Double, _ z: Double) -> Double {
        func clampIdx(_ f: Double, _ n: Int) -> (Int, Int, Double) {
            let c = min(max(f, 0), Double(n - 1))
            let i0 = Int(floor(c)), i1 = min(i0 + 1, n - 1)
            return (i0, i1, c - Double(i0))
        }
        let (x0, x1, fx) = clampIdx(x, v.nx)
        let (y0, y1, fy) = clampIdx(y, v.ny)
        let (z0, z1, fz) = clampIdx(z, v.nz)
        @inline(__always) func at(_ xi: Int, _ yi: Int, _ zi: Int) -> Double {
            Double(v.data[(zi * v.ny + yi) * v.nx + xi])
        }
        let c00 = at(x0, y0, z0) * (1 - fx) + at(x1, y0, z0) * fx
        let c10 = at(x0, y1, z0) * (1 - fx) + at(x1, y1, z0) * fx
        let c01 = at(x0, y0, z1) * (1 - fx) + at(x1, y0, z1) * fx
        let c11 = at(x0, y1, z1) * (1 - fx) + at(x1, y1, z1) * fx
        let c0 = c00 * (1 - fy) + c10 * fy
        let c1 = c01 * (1 - fy) + c11 * fy
        return c0 * (1 - fz) + c1 * fz
    }

    /// Nearest-neighbor downscale of an interleaved RGB8 frame so the long side ≤ maxSize.
    private static func downscaleRGB(_ rgb: [UInt8], w: Int, h: Int, maxSize: Int) -> (Int, Int, [UInt8]) {
        let longest = max(w, h)
        guard maxSize > 0, longest > maxSize else { return (w, h, rgb) }
        let scale = Double(maxSize) / Double(longest)
        let outW = max(Int(Double(w) * scale), 1), outH = max(Int(Double(h) * scale), 1)
        var out = [UInt8](repeating: 0, count: outW * outH * 3)
        for y in 0 ..< outH {
            let sy = min(Int(Double(y) / scale), h - 1)
            for x in 0 ..< outW {
                let sx = min(Int(Double(x) / scale), w - 1)
                let s = (sy * w + sx) * 3, d = (y * outW + x) * 3
                out[d] = rgb[s]; out[d + 1] = rgb[s + 1]; out[d + 2] = rgb[s + 2]
            }
        }
        return (outW, outH, out)
    }

    private static func rgbPNG(_ bytes: [UInt8], width: Int, height: Int) -> Data? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                               bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, cg, nil)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return data as Data
    }

    private static func grayscalePNG(_ bytes: [UInt8], width: Int, height: Int) -> Data? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, cg, nil)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return data as Data
    }
}
