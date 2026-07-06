import XCTest

/// Exercises the built-in Storage SCP end-to-end in one headless process (no
/// SwiftUI, so no `.task` multi-fire polluting DCMTK's global config state):
/// start → status → loopback C-ECHO → loopback C-STORE → a file lands.
final class SCPTests: XCTestCase {

    private let ae = "DICOMBENCH"
    private let port = 11255

    override func tearDown() {
        DCMTKNet.stopSCP()
        super.tearDown()
    }

    func testSCPStartsAndReceives() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-scp-test-\(port)"
        try? FileManager.default.removeItem(atPath: dir)

        DCMTKNet.stopSCP()   // clean slate
        _ = DCMTKNet.startSCP(withAETitle: ae, port: Int32(port), outputDir: dir, enforceCalledAE: true)

        // Give the listener a moment to bind.
        Thread.sleep(forTimeInterval: 1.0)
        let status = DCMTKNet.scpStatus()
        let running = (status["running"] as? NSNumber)?.boolValue ?? false
        let err = (status["error"] as? String) ?? "-"
        XCTAssertTrue(running, "SCP did not start. status.error=\(err)")
        guard running else { return }   // no point continuing if it never bound

        // Loopback C-ECHO to ourselves.
        let echo = DCMTKNet.echo(toHost: "127.0.0.1", port: Int32(port),
                                 calledAE: ae, callingAE: "TESTER")
        XCTAssertTrue((echo["success"] as? NSNumber)?.boolValue ?? false,
                      "loopback C-ECHO failed: \(echo["message"] ?? "-")")

        // Loopback C-STORE of a synthesized file.
        let file = try makeTinyDICOM(dir: NSTemporaryDirectory() + "dicomflow-scp-src")
        let store = DCMTKNet.storeFiles([file], toHost: "127.0.0.1", port: Int32(port),
                                        calledAE: ae, callingAE: "TESTER")
        XCTAssertTrue((store["success"] as? NSNumber)?.boolValue ?? false,
                      "loopback C-STORE failed: \(store["message"] ?? "-")")

        // A file should have landed in the output directory.
        Thread.sleep(forTimeInterval: 0.5)
        let received = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        XCTAssertFalse(received.isEmpty, "no file was written to the SCP output dir")
    }

    /// With Called-AE enforcement, an association addressed to the wrong Called
    /// AE is refused, while the correct one is accepted.
    func testSCPEnforcesCalledAE() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-scp-aecheck"
        _ = DCMTKNet.startSCP(withAETitle: ae, port: Int32(port), outputDir: dir, enforceCalledAE: true)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue((DCMTKNet.scpStatus()["running"] as? NSNumber)?.boolValue ?? false)

        let wrong = DCMTKNet.echo(toHost: "127.0.0.1", port: Int32(port), calledAE: "WRONGAE", callingAE: "TESTER")
        XCTAssertFalse((wrong["success"] as? NSNumber)?.boolValue ?? true,
                       "C-ECHO with a wrong Called AE should be refused")
        let right = DCMTKNet.echo(toHost: "127.0.0.1", port: Int32(port), calledAE: ae, callingAE: "TESTER")
        XCTAssertTrue((right["success"] as? NSNumber)?.boolValue ?? false,
                      "C-ECHO with the correct Called AE should be accepted: \(right["message"] ?? "-")")
    }

    /// The reviewer flagged "stop→start broken": restarting the SCP in one
    /// process must not accumulate DCMTK global config state.
    func testSCPRestartsCleanly() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-scp-restart"
        for cycle in 1...3 {
            _ = DCMTKNet.startSCP(withAETitle: ae, port: Int32(port), outputDir: dir, enforceCalledAE: true)
            Thread.sleep(forTimeInterval: 0.8)
            let status = DCMTKNet.scpStatus()
            let running = (status["running"] as? NSNumber)?.boolValue ?? false
            XCTAssertTrue(running, "cycle \(cycle): SCP failed to start. error=\(status["error"] as? String ?? "-")")
            let echo = DCMTKNet.echo(toHost: "127.0.0.1", port: Int32(port), calledAE: ae, callingAE: "TESTER")
            XCTAssertTrue((echo["success"] as? NSNumber)?.boolValue ?? false,
                          "cycle \(cycle): C-ECHO failed: \(echo["message"] ?? "-")")
            DCMTKNet.stopSCP()
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    /// With global TLS on, the SCP must present a cert and accept a TLS
    /// association (so C-MOVE-to-self can deliver). Verify a loopback C-ECHO
    /// succeeds over TLS, and that a plaintext echo to the TLS port is refused.
    func testSCPOverTLS() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-scp-tls-test"
        DCMTKNet.setTLSEnabled(true, verifyPeer: false, caFile: nil)
        defer { DCMTKNet.setTLSEnabled(false, verifyPeer: false, caFile: nil) }

        let start = DCMTKNet.startSCP(withAETitle: ae, port: Int32(port + 1), outputDir: dir, enforceCalledAE: true)
        XCTAssertTrue((start["running"] as? NSNumber)?.boolValue ?? false,
                      "TLS SCP start failed: \(start["message"] ?? "-")")
        Thread.sleep(forTimeInterval: 1.0)
        let status = DCMTKNet.scpStatus()
        XCTAssertTrue((status["running"] as? NSNumber)?.boolValue ?? false,
                      "TLS SCP not running: \(status["error"] as? String ?? "-")")

        // TLS client → TLS SCP: should verify.
        let tlsEcho = DCMTKNet.echo(toHost: "127.0.0.1", port: Int32(port + 1), calledAE: ae, callingAE: "TESTER")
        XCTAssertTrue((tlsEcho["success"] as? NSNumber)?.boolValue ?? false,
                      "loopback C-ECHO over TLS failed: \(tlsEcho["message"] ?? "-")")

        // Plaintext client → TLS port: should be refused.
        DCMTKNet.setTLSEnabled(false, verifyPeer: false, caFile: nil)
        let plainEcho = DCMTKNet.echo(toHost: "127.0.0.1", port: Int32(port + 1), calledAE: ae, callingAE: "TESTER")
        XCTAssertFalse((plainEcho["success"] as? NSNumber)?.boolValue ?? true,
                       "plaintext C-ECHO to the TLS port should have failed")
    }

    /// Host of a live Orthanc (or other PACS) to run the live tests against.
    /// Unset → the live tests are skipped, so the normal suite needs no network.
    private var liveHost: String? { ProcessInfo.processInfo.environment["ORTHANC_HOST"] }
    private var livePort: Int32 { Int32(ProcessInfo.processInfo.environment["ORTHANC_PORT"] ?? "") ?? 4242 }
    private var liveAE: String { ProcessInfo.processInfo.environment["ORTHANC_AE"] ?? "ORTHANC" }

    /// Live round trip against a real Orthanc. Gated behind ORTHANC_HOST so it
    /// never runs in the normal suite. Verifies C-GET (outbound, firewall-free)
    /// and C-MOVE-to-self (Orthanc → our SCP, inbound).
    func testLiveOrthancRoundTrip() throws {
        guard let host = liveHost else {
            throw XCTSkip("live test — set TEST_RUNNER_ORTHANC_HOST (xcodebuild) / ORTHANC_HOST (direct) to enable")
        }
        let oPort = livePort, orthancAE = liveAE
        let ourAE = "DICOMBENCH", ourPort: Int32 = 11112

        // 0. C-STORE a fresh test image to Orthanc (outbound store to a real PACS).
        let src = NSTemporaryDirectory() + "dicomflow-live-src/img.dcm"
        try FileManager.default.createDirectory(atPath: (src as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        XCTAssertTrue(DCMTKNet.writeTestImage(toPath: src), "could not synthesize test image")
        let store = DCMTKNet.storeFiles([src], toHost: host, port: oPort, calledAE: orthancAE, callingAE: ourAE)
        print("LIVE: C-STORE→Orthanc success=\((store["success"] as? NSNumber)?.boolValue ?? false) msg=\(store["message"] ?? "-")")
        XCTAssertTrue((store["success"] as? NSNumber)?.boolValue ?? false, "C-STORE to Orthanc failed")
        Thread.sleep(forTimeInterval: 0.5)

        // 1. C-FIND our just-stored study (filter by our test PatientID).
        let find = DCMTKNet.queryHost(host, port: oPort, calledAE: orthancAE, callingAE: ourAE,
                                      level: "STUDY", filters: ["PatientID": "SCP-TEST"])
        XCTAssertTrue((find["success"] as? NSNumber)?.boolValue ?? false, "C-FIND failed: \(find["message"] ?? "-")")
        let rows = find["results"] as? [[String: String]] ?? []
        print("LIVE: C-FIND returned \(rows.count) SCP-TEST studies")
        guard let study = rows.first?["StudyInstanceUID"], !study.isEmpty else {
            XCTFail("stored image not found by C-FIND"); return
        }

        // 2. C-GET (outbound — objects arrive on our own association, no SCP).
        let getDir = NSTemporaryDirectory() + "dicomflow-live-get"
        try? FileManager.default.removeItem(atPath: getDir)
        let get = DCMTKNet.retrieve(fromHost: host, port: oPort, calledAE: orthancAE, callingAE: ourAE,
                                    level: "STUDY", keys: ["StudyInstanceUID": study],
                                    method: "get", moveDest: nil, outputDir: getDir)
        let gotFiles = (try? FileManager.default.contentsOfDirectory(atPath: getDir))?.count ?? 0
        print("LIVE: C-GET success=\((get["success"] as? NSNumber)?.boolValue ?? false) files=\(gotFiles) msg=\(get["message"] ?? "-")")
        XCTAssertGreaterThan(gotFiles, 0, "C-GET received no files")

        // 3. C-MOVE-to-self — Orthanc opens an inbound association to OUR SCP.
        let moveDir = NSTemporaryDirectory() + "dicomflow-live-move"
        try? FileManager.default.removeItem(atPath: moveDir)
        _ = DCMTKNet.startSCP(withAETitle: ourAE, port: ourPort, outputDir: moveDir, enforceCalledAE: true)
        Thread.sleep(forTimeInterval: 1.0)
        defer { DCMTKNet.stopSCP() }
        let move = DCMTKNet.retrieve(fromHost: host, port: oPort, calledAE: orthancAE, callingAE: ourAE,
                                     level: "STUDY", keys: ["StudyInstanceUID": study],
                                     method: "move", moveDest: ourAE, outputDir: moveDir)
        Thread.sleep(forTimeInterval: 1.0)
        let movedFiles = (try? FileManager.default.contentsOfDirectory(atPath: moveDir))?.count ?? 0
        print("LIVE: C-MOVE success=\((move["success"] as? NSNumber)?.boolValue ?? false) files=\(movedFiles) msg=\(move["message"] ?? "-")")
        XCTAssertGreaterThan(movedFiles, 0, "C-MOVE-to-self received no files (firewall may block inbound :\(ourPort))")
    }

    /// Live negotiation probe against Orthanc (gated by ORTHANC_HOST).
    func testLiveNegotiationProbe() throws {
        guard let host = liveHost else {
            throw XCTSkip("live test — set TEST_RUNNER_ORTHANC_HOST (xcodebuild) / ORTHANC_HOST (direct) to enable")
        }
        let probe = DCMTKNet.probeContextsHost(host, port: livePort,
                                               calledAE: liveAE, callingAE: "DICOMBENCH")
        XCTAssertTrue((probe["success"] as? NSNumber)?.boolValue ?? false, "probe failed: \(probe["message"] ?? "-")")
        let rows = probe["results"] as? [[String: Any]] ?? []
        let accepted = rows.filter { ($0["accepted"] as? NSNumber)?.boolValue ?? false }
        print("LIVE PROBE: \(probe["message"] ?? "-")")
        for r in accepted {
            print("  ✓ \(r["sopName"] ?? "?") — \((r["transferSyntaxes"] as? [String] ?? []).joined(separator: ", "))")
        }
        // Orthanc accepts Verification + storage; at least Verification must be accepted.
        XCTAssertTrue(accepted.contains { ($0["sopName"] as? String)?.contains("Verification") ?? false },
                      "Verification SOP class should be accepted")
    }

    /// Minimal valid DICOM (SC image) so C-STORE has something to send.
    private func makeTinyDICOM(dir: String) throws -> String {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/tiny.dcm"
        // Build via the bridge's own writer if available; else a preformed fixture.
        // Reuse the test fixture generator the net tests use.
        let ok = DCMTKNet.writeTestImage(toPath: path)
        XCTAssertTrue(ok, "could not synthesize a test DICOM")
        return path
    }
}
