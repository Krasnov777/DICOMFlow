import simd

/// CPU mirror of `MPRUniforms` in MPR.metal. Layout must match exactly.
struct MPRUniforms {
    var originTC: SIMD4<Float> = .zero
    var uAxisTC: SIMD4<Float> = .zero
    var vAxisTC: SIMD4<Float> = .zero
    var fitScale: SIMD2<Float> = .one
    var slope: Float = 1
    var intercept: Float = 0
    var winCenter: Float = 40
    var winWidth: Float = 400
    var zoom: Float = 1
    var invert: UInt32 = 0
    var pan: SIMD2<Float> = .zero
    var quarter: UInt32 = 0      // 90° turns (0…3)
    var flipMask: UInt32 = 0     // bit0 = flip X, bit1 = flip Y
}

/// CPU mirror of `RaycastUniforms` in VolumeRaycast.metal.
struct RaycastUniforms {
    var camPos = SIMD4<Float>(0, 0, 0, 0)
    var camForward = SIMD4<Float>(0, 0, -1, 0)
    var camRight = SIMD4<Float>(1, 0, 0, 0)
    var camUp = SIMD4<Float>(0, 1, 0, 0)
    var boxHalf = SIMD4<Float>(1, 1, 1, 0)
    var clipMin = SIMD4<Float>(0, 0, 0, 0)   // normalized texcoord clip box
    var clipMax = SIMD4<Float>(1, 1, 1, 0)
    var tanHalfFov = SIMD2<Float>(1, 1)
    var slope: Float = 1
    var intercept: Float = 0
    var winCenter: Float = 40
    var winWidth: Float = 400
    var stepMM: Float = 1
    var lutMinHU: Float = -1000
    var lutMaxHU: Float = 3000
    var mode: UInt32 = 0
    var lightEnabled: UInt32 = 1
    var isoValue: Float = 300
}

/// 3D rendering mode.
public enum RenderMode: String, CaseIterable, Sendable {
    case mip = "MIP"          // maximum intensity (bone/contrast)
    case minip = "MinIP"      // minimum intensity (air/lung)
    case xray = "X-Ray"       // average / DRR-like
    case tf = "Volume"        // transfer-function with shading
    case surface = "Surface"  // iso-surface (threshold) with shading

    public var index: UInt32 {
        switch self {
        case .mip: return 0
        case .minip: return 1
        case .xray: return 2
        case .tf: return 3
        case .surface: return 4
        }
    }
    public var usesWindow: Bool { self == .mip || self == .minip || self == .xray }
}

/// Which orthogonal plane an MPR view shows.
public enum MPRAxis: String, CaseIterable, Sendable {
    case axial      // vary z; u = +x, v = +y
    case coronal    // vary y; u = +x, v = +z
    case sagittal   // vary x; u = +y, v = +z

    public var title: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        }
    }

    /// Plane (a,b) + slice fraction → normalized volume coordinates.
    /// Matches the MPR shader’s convention (v is flipped on coronal/sagittal so
    /// superior is up).
    public func toVolume(_ ab: SIMD2<Float>, slice: Float) -> SIMD3<Float> {
        switch self {
        case .axial: return SIMD3(ab.x, ab.y, slice)
        case .coronal: return SIMD3(ab.x, slice, 1 - ab.y)
        case .sagittal: return SIMD3(slice, ab.x, 1 - ab.y)
        }
    }

    /// In-plane voxel counts (nu, nv) for a volume of dims (nx, ny, nz).
    public func planeDims(nx: Int, ny: Int, nz: Int) -> (nu: Int, nv: Int) {
        switch self {
        case .axial: return (nx, ny)
        case .coronal: return (nx, nz)
        case .sagittal: return (ny, nz)
        }
    }

    /// In-plane voxel spacing (su, sv) for spacing (sx, sy, sz) in mm.
    public func planeSpacing(_ s: SIMD3<Float>) -> (su: Float, sv: Float) {
        switch self {
        case .axial: return (s.x, s.y)
        case .coronal: return (s.x, s.z)
        case .sagittal: return (s.y, s.z)
        }
    }

    /// Number of slices along this axis for dims (nx, ny, nz).
    public func sliceCount(nx: Int, ny: Int, nz: Int) -> Int {
        switch self {
        case .axial: return nz
        case .coronal: return ny
        case .sagittal: return nx
        }
    }
}
