import simd

/// Arcball orbit camera. Rotation is applied about the current screen axes so the
/// grabbed surface follows the drag ("grab and turn"). Z-up presets keep
/// patient-superior up; a fixed world light makes the motion read clearly.
public struct ArcballCamera: Sendable {
    public var orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
    public var distance: Float = 500    // mm
    public var fovY: Float = .pi / 4    // 45°
    public var target = SIMD3<Float>(0, 0, 0)

    /// Turntable state: absolute angles about the world-up (patient-superior)
    /// axis. Storing angles (rather than composing incremental quaternions)
    /// makes the orbit deterministic — the same drag always maps to the same
    /// rotation, with zero roll and zero drift.
    public var azimuth: Float = 0       // radians, yaw about world up (Z)
    public var elevation: Float = 0     // radians, pitch, clamped near ±90°
    private static let worldUp = SIMD3<Float>(0, 0, 1)
    private static let maxElevation: Float = 1.5533   // 89°

    public init() { set(.anterior) }

    /// Free arcball — dx spins about the screen up axis, dy about screen right.
    /// The grabbed surface follows the cursor (can roll on diagonal drags).
    public mutating func orbit(dx: Float, dy: Float) {
        let b = basis()
        let q = simd_quatf(angle: -dx, axis: b.up) * simd_quatf(angle: -dy, axis: b.right)
        orientation = (q * orientation).normalized
    }

    /// Turntable — the recommended, predictable orbit. Horizontal drag yaws about
    /// the world-up (superior) axis; vertical drag pitches, clamped off the poles.
    /// World-up is fixed, so the volume never rolls and the motion is drift-free
    /// (angles are absolute, not accumulated).
    public mutating func turntable(dx: Float, dy: Float) {
        azimuth -= dx
        elevation = min(max(elevation - dy, -Self.maxElevation), Self.maxElevation)
        applyTurntable()
    }

    /// Rebuild the orientation from the absolute turntable angles.
    private mutating func applyTurntable() {
        let ce = cos(elevation), se = sin(elevation)
        // Eye direction (target → eye) on a sphere; azimuth 0 = anterior.
        let eyeDir = SIMD3<Float>(ce * sin(azimuth), -ce * cos(azimuth), se)
        orientation = Self.lookRotation(forward: -eyeDir, up: Self.worldUp)
    }
    public mutating func zoom(factor: Float) {
        distance = min(max(distance * factor, 1), 100_000)
    }
    /// Pan the look-at point in the image plane (screen-space deltas).
    public mutating func pan(dxRight: Float, dyUp: Float) {
        let b = basis()
        target += (-b.right * dxRight + b.up * dyUp) * distance * 0.0015
    }
    public mutating func resetTarget() { target = .zero }

    /// Standard anatomical views — (view direction, up) in volume axes (z = superior).
    public enum View: String, CaseIterable, Sendable {
        case anterior = "A", posterior = "P", left = "L", right = "R", superior = "S", inferior = "I"
        var forwardUp: (SIMD3<Float>, SIMD3<Float>) {
            switch self {
            case .anterior:  return (SIMD3(0, 1, 0),  SIMD3(0, 0, 1))
            case .posterior: return (SIMD3(0, -1, 0), SIMD3(0, 0, 1))
            case .left:      return (SIMD3(-1, 0, 0), SIMD3(0, 0, 1))
            case .right:     return (SIMD3(1, 0, 0),  SIMD3(0, 0, 1))
            case .superior:  return (SIMD3(0, 0, -1), SIMD3(0, -1, 0))
            case .inferior:  return (SIMD3(0, 0, 1),  SIMD3(0, 1, 0))
            }
        }
    }
    public mutating func set(_ v: View) {
        // Keep turntable angles in sync so a later drag continues smoothly from
        // the preset instead of jumping.
        switch v {
        case .anterior:  azimuth = 0;       elevation = 0
        case .posterior: azimuth = .pi;     elevation = 0
        case .left:      azimuth = .pi / 2; elevation = 0
        case .right:     azimuth = -.pi / 2; elevation = 0
        case .superior:  azimuth = 0;       elevation = Self.maxElevation
        case .inferior:  azimuth = 0;       elevation = -Self.maxElevation
        }
        let (f, u) = v.forwardUp
        orientation = Self.lookRotation(forward: f, up: u)
    }

    /// Quaternion whose camera-local -Z maps to `forward`, +Y to `up`.
    static func lookRotation(forward f: SIMD3<Float>, up u: SIMD3<Float>) -> simd_quatf {
        let fwd = simd_normalize(f)
        var up = simd_normalize(u)
        var right = simd_cross(fwd, up)
        if simd_length(right) < 1e-5 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        up = simd_cross(right, fwd)
        let m = simd_float3x3(columns: (right, up, -fwd))
        return simd_quatf(m).normalized
    }

    public struct Basis {
        public var eye: SIMD3<Float>
        public var forward: SIMD3<Float>
        public var right: SIMD3<Float>
        public var up: SIMD3<Float>
    }

    public func basis() -> Basis {
        let forward = orientation.act(SIMD3<Float>(0, 0, -1))
        let up = orientation.act(SIMD3<Float>(0, 1, 0))
        let right = orientation.act(SIMD3<Float>(1, 0, 0))
        let eye = target - forward * distance
        return Basis(eye: eye, forward: forward, right: right, up: up)
    }
}
