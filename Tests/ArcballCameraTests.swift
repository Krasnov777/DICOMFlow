import XCTest
import simd

/// The turntable orbit must be deterministic (no drift) and roll-free.
final class ArcballCameraTests: XCTestCase {

    private func fwd(_ c: ArcballCamera) -> SIMD3<Float> { c.basis().forward }

    /// Dragging out and back by the same amount returns to exactly the start —
    /// the property the old incremental implementation lacked (it slipped).
    func testTurntableIsReversible() {
        var c = ArcballCamera(); c.set(.anterior)
        let start = fwd(c)
        for _ in 0..<50 { c.turntable(dx: 0.037, dy: 0.021) }
        for _ in 0..<50 { c.turntable(dx: -0.037, dy: -0.021) }
        let back = fwd(c)
        XCTAssertLessThan(simd_length(back - start), 1e-4, "turntable drifted after out-and-back")
    }

    /// Path independence: the resulting orientation depends only on the net
    /// azimuth/elevation, not on how you got there (many small vs one big drag).
    func testTurntablePathIndependent() {
        var a = ArcballCamera(); a.set(.anterior)
        var b = ArcballCamera(); b.set(.anterior)
        for _ in 0..<100 { a.turntable(dx: 0.01, dy: 0.005) }   // many small steps
        b.turntable(dx: 1.0, dy: 0.5)                           // one big step
        XCTAssertLessThan(simd_length(fwd(a) - fwd(b)), 1e-4, "turntable is path-dependent")
    }

    /// World-up stays in the screen's vertical plane → zero roll, no matter how
    /// far you spin (its projected screen-right component is ~0).
    func testTurntableHasNoRoll() {
        var c = ArcballCamera(); c.set(.anterior)
        for _ in 0..<40 { c.turntable(dx: 0.06, dy: 0.04) }   // repeated diagonal drags
        let roll = abs(simd_dot(SIMD3<Float>(0, 0, 1), c.basis().right))
        XCTAssertLessThan(roll, 0.02, "turntable introduced roll")
    }

    /// Elevation is clamped off the poles so you never flip over the top.
    func testElevationClamped() {
        var c = ArcballCamera(); c.set(.anterior)
        for _ in 0..<200 { c.turntable(dx: 0, dy: -0.1) }   // keep pitching up
        XCTAssertLessThan(abs(c.elevation), Float.pi / 2, "elevation crossed the pole")
    }
}
