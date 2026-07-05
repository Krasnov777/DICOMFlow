import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

/// Headless smoke test for the DCMTK bridge: `DICOMFLOW_NATIVE_TAGS=<file>`.
enum NativeTest {
    /// `DICOMFLOW_PERF=<dir>` — time the render hot paths and write a report.
    @MainActor
    static func runPerf(directory: String) async -> Never {
        func ms(_ iters: Int, _ block: () -> Void) -> Double {
            block()   // warm-up
            let t = CFAbsoluteTimeGetCurrent()
            for _ in 0..<iters { block() }
            return (CFAbsoluteTimeGetCurrent() - t) * 1000.0 / Double(iters)
        }
        var out = "DicomFlow perf report\n======================\n"
        do {
            let engine = DicomEngine()
            let t0 = CFAbsoluteTimeGetCurrent()
            let vol = try await engine.decodeVolume(directory: directory)
            let decodeMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let m = vol.meta
            let voxels = m.nx * m.ny * m.nz
            let texMB = Double(voxels) * 2.0 / 1_048_576.0      // r16Snorm = 2 B/voxel
            let cpuMB = Double(voxels) * 2.0 / 1_048_576.0      // retained int16 probe copy
            out += String(format: "volume      : %d×%d×%d (%d voxels)\n", m.nx, m.ny, m.nz, voxels)
            out += String(format: "memory      : texture %.0f MB (r16Snorm) + CPU probe %.0f MB\n", texMB, cpuMB)
            out += String(format: "decode+upload: %.0f ms (DCMTK serializes; ~1.05× even on all cores)\n", decodeMs)

            let wc = m.defaultWindowCenter, ww = m.defaultWindowWidth
            let mprMs = ms(30) {
                _ = MPRPlaneRenderer.renderOffscreen(volume: vol, axis: .axial, sliceFrac: 0.5,
                                                     winCenter: wc, winWidth: ww, size: 512)
            }
            out += String(format: "MPR plane   : %.2f ms/frame @512²\n", mprMs)

            let rc = RaycastRenderer(); rc.volume = vol
            rc.winCenter = wc; rc.winWidth = ww
            for mode in RenderMode.allCases {
                rc.mode = mode
                let r = ms(20) { _ = rc.renderOffscreen(size: 512) }
                out += "3D " + mode.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
                    + String(format: ": %.2f ms/frame @512²\n", r)
            }
            let lutMs = ms(50) { _ = TransferFunction.presets[0].tf.makeLUTTexture() }
            out += String(format: "LUT build   : %.3f ms (now cached per preset)\n", lutMs)
        } catch {
            out += "FAILED: \(error)\n"
        }
        print(out)
        if let dst = ProcessInfo.processInfo.environment["DICOMFLOW_PERF_OUT"] {
            try? out.write(toFile: dst, atomically: true, encoding: .utf8)
        }
        exit(0)
    }

    /// `DICOMFLOW_ROTATE=1` — verify the turntable keeps the volume upright
    /// (no roll) after diagonal drags, where the free arcball rolls.
    @MainActor
    static func runRotate() async -> Never {
        // World up (patient superior) should stay in the screen's vertical
        // plane under turntable → its projected screen-right component is ~0.
        func rollError(_ cam: ArcballCamera) -> Float {
            let b = cam.basis()
            let worldUp = SIMD3<Float>(0, 0, 1)
            return abs(simd_dot(worldUp, b.right))   // 0 = perfectly upright
        }
        var tt = ArcballCamera(); tt.set(.anterior)
        var ab = ArcballCamera(); ab.set(.anterior)
        for _ in 0..<40 {                    // repeated diagonal drags
            tt.turntable(dx: 0.06, dy: 0.04)
            ab.orbit(dx: 0.06, dy: 0.04)
        }
        var out = "ROTATE test\n"
        out += String(format: "turntable roll=%.4f (want ~0)\narcball roll=%.4f\n",
                      rollError(tt), rollError(ab))
        out += "verdict=\(rollError(tt) < 0.02 && rollError(ab) > rollError(tt) ? "PASS" : "FAIL")\n"
        print(out)
        if let dst = ProcessInfo.processInfo.environment["ROTATE_OUT"] {
            try? out.write(toFile: dst, atomically: true, encoding: .utf8)
        }
        exit(0)
    }

    /// `DICOMFLOW_MOVIE=<dir>` — decode a volume (multi-frame aware), export a
    /// slice-sweep + a MIP turntable movie, and report frame counts/sizes.
    @MainActor
    static func runMovie(directory: String) async -> Never {
        let env = ProcessInfo.processInfo.environment
        var out = "MOVIE test\n"
        do {
            let engine = DicomEngine()
            let vol = try await engine.decodeVolume(directory: directory)
            out += "volume dims=\(vol.meta.nx)x\(vol.meta.ny)x\(vol.meta.nz)\n"
            let sweepURL = URL(fileURLWithPath: env["MOVIE_SWEEP"] ?? "/tmp/dicomflow-sweep.mov")
            let n1 = try ExportMovie.sliceSweep(volume: vol, axis: .axial,
                                                winCenter: vol.meta.defaultWindowCenter, winWidth: vol.meta.defaultWindowWidth,
                                                invert: false, to: sweepURL)
            let sz1 = (try? FileManager.default.attributesOfItem(atPath: sweepURL.path)[.size] as? Int) ?? 0
            out += "sweep frames=\(n1) bytes=\(sz1)\n"
            let ttURL = URL(fileURLWithPath: env["MOVIE_TT"] ?? "/tmp/dicomflow-turntable.mov")
            let n2 = try ExportMovie.turntable(volume: vol, winCenter: vol.meta.defaultWindowCenter,
                                               winWidth: vol.meta.defaultWindowWidth, frames: 36, to: ttURL)
            let sz2 = (try? FileManager.default.attributesOfItem(atPath: ttURL.path)[.size] as? Int) ?? 0
            out += "turntable frames=\(n2) bytes=\(sz2)\n"
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = env["MOVIE_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_TLSTEST=1` + `TLS_HOST/TLS_PORT/TLS_AE/TLS_CA` — DICOM TLS:
    /// echo with TLS (no verify), with verification against the CA, and a
    /// plaintext-to-TLS-port negative check.
    @MainActor
    static func runTLS() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let host = env["TLS_HOST"] ?? "127.0.0.1"
        let port = Int(env["TLS_PORT"] ?? "4243") ?? 4243
        let ae = env["TLS_AE"] ?? "ORTHANC"
        let engine = DicomEngine()
        var out = "TLS test → \(host):\(port)\n"

        DCMTKNet.setTLSEnabled(true, verifyPeer: false, caFile: nil)
        let r1 = try? await engine.echo(host: host, port: port, aeTitle: ae, callingAE: "DICOMBENCH")
        out += "tls_noverify success=\(r1?.success ?? false) (\(r1?.message ?? "-"))\n"

        if let ca = env["TLS_CA"], !ca.isEmpty {
            DCMTKNet.setTLSEnabled(true, verifyPeer: true, caFile: ca)
            let r2 = try? await engine.echo(host: host, port: port, aeTitle: ae, callingAE: "DICOMBENCH")
            out += "tls_verified success=\(r2?.success ?? false) (\(r2?.message ?? "-"))\n"
        }

        DCMTKNet.setTLSEnabled(false, verifyPeer: false, caFile: nil)
        let r3 = try? await engine.echo(host: host, port: port, aeTitle: ae, callingAE: "DICOMBENCH")
        out += "plaintext_to_tls_port success=\(r3?.success ?? false) (expect false)\n"

        let ok = (r1?.success ?? false) && !(r3?.success ?? true)
        out += "verdict=\(ok ? "PASS" : "FAIL")\n"
        print(out)
        if let dst = env["TLS_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_ROI=<dir>` — decode a volume and sanity-check Volume.roiStats
    /// against known phantom regions (center sphere vs air corner).
    @MainActor
    static func runROI(directory: String) async -> Never {
        var out = "ROI test\n"
        do {
            let engine = DicomEngine()
            let vol = try await engine.decodeVolume(directory: directory)
            // Center of the phantom (sphere) — small rect around (0.5, 0.5).
            if let c = vol.roiStats(a: SIMD2(0.48, 0.48), b: SIMD2(0.52, 0.52), zFrac: 0.5) {
                out += String(format: "center: mean=%.1f sd=%.1f min=%.0f max=%.0f n=%d area=%.1fmm²\n",
                              c.mean, c.sd, c.min, c.max, c.count, c.areaMM2)
            }
            // Air corner.
            if let a = vol.roiStats(a: SIMD2(0.02, 0.02), b: SIMD2(0.08, 0.08), zFrac: 0.5) {
                out += String(format: "corner: mean=%.1f sd=%.1f\n", a.mean, a.sd)
            }
            // Degenerate rect must not crash; out-of-range must clamp.
            out += "degenerate=\(vol.roiStats(a: SIMD2(0.5, 0.5), b: SIMD2(0.5, 0.5), zFrac: 0.5) != nil)\n"
            out += "clamped=\(vol.roiStats(a: SIMD2(-1, -1), b: SIMD2(2, 2), zFrac: 0.5) != nil)\n"
            // Plane-generic: the phantom sphere center must read the same on
            // every orthogonal plane.
            for axis in MPRAxis.allCases {
                if let s = vol.roiStats(axis: axis, a: SIMD2(0.48, 0.48), b: SIMD2(0.52, 0.52), sliceFrac: 0.5) {
                    out += String(format: "%@ center: mean=%.1f sd=%.1f\n", axis.rawValue, s.mean, s.sd)
                }
            }
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = ProcessInfo.processInfo.environment["ROI_OUT"] {
            try? out.write(toFile: dst, atomically: true, encoding: .utf8)
        }
        exit(0)
    }

    /// `DICOMFLOW_DECODE=<file-or-dir>` — pixel-decode each DICOM file and
    /// report dimensions + sample range (exercises the codecs, incl. JPEG 2000).
    @MainActor
    static func runDecode(path: String) async -> Never {
        var files: [String] = []
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue {
            files = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
                .sorted().map { (path as NSString).appendingPathComponent($0) }
        } else { files = [path] }
        var out = "DECODE test\n"; var ok = 0, fail = 0
        for f in files {
            do {
                let d = try DCMTKBridge.decodeFile(f)
                let rows = (d["rows"] as? NSNumber)?.intValue ?? 0
                let cols = (d["columns"] as? NSNumber)?.intValue ?? 0
                let frames = (d["frames"] as? NSNumber)?.intValue ?? 1
                var minV = Int16.max, maxV = Int16.min
                if let data = d["pixelData"] as? Data {
                    data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                        for v in p.bindMemory(to: Int16.self) { minV = min(minV, v); maxV = max(maxV, v) }
                    }
                }
                ok += 1
                out += "  OK \((f as NSString).lastPathComponent): \(rows)x\(cols)"
                    + (frames > 1 ? "x\(frames)f" : "") + " px[\(minV)…\(maxV)]\n"
            } catch {
                fail += 1
                out += "  FAIL \((f as NSString).lastPathComponent): \(error.localizedDescription)\n"
            }
        }
        out += "decoded=\(ok) failed=\(fail)\n"
        print(out)
        if let dst = ProcessInfo.processInfo.environment["DECODE_OUT"] {
            try? out.write(toFile: dst, atomically: true, encoding: .utf8)
        }
        exit(0)
    }

    /// `DICOMFLOW_QR=1` — study C-FIND (no filters → return keys must still
    /// populate), then SERIES-level C-FIND on the first study.
    @MainActor
    static func runQR() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let engine = DicomEngine()
        let host = env["QR_HOST"] ?? "127.0.0.1"
        let port = Int(env["QR_PORT"] ?? "4242") ?? 4242
        let ae = env["QR_AE"] ?? "ORTHANC"
        var out = "QR test\n"
        do {
            let studies = try await engine.query(host: host, port: port, aeTitle: ae,
                                                 level: "STUDY", filters: [:], callingAE: "DICOMBENCH")
            out += "studies success=\(studies.success) count=\(studies.count ?? -1)\n"
            for s in (studies.results ?? []).prefix(3) {
                out += "  \(s["PatientName"] ?? "∅") | \(s["StudyDescription"] ?? "∅") | "
                    + "series=\(s["NumberOfStudyRelatedSeries"] ?? "∅")\n"
            }
            if let uid = studies.results?.first?["StudyInstanceUID"], !uid.isEmpty {
                let series = try await engine.query(host: host, port: port, aeTitle: ae, level: "SERIES",
                                                    filters: ["StudyInstanceUID": uid], callingAE: "DICOMBENCH")
                out += "series success=\(series.success) count=\(series.count ?? -1)\n"
                for s in (series.results ?? []).prefix(5) {
                    out += "  #\(s["SeriesNumber"] ?? "?") \(s["Modality"] ?? "?") | "
                        + "\(s["SeriesDescription"] ?? "∅") | inst=\(s["NumberOfSeriesRelatedInstances"] ?? "∅")\n"
                }
            }
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = env["QR_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_KEYCHAIN=1` — set/get/update/delete roundtrip.
    @MainActor
    static func runKeychain() async -> Never {
        let svc = "DicomBench.test", acct = "roundtrip"
        var out = "KEYCHAIN test\n"
        Keychain.delete(service: svc, account: acct)
        out += "set=\(Keychain.set("secret1", service: svc, account: acct))\n"
        out += "get1=\(Keychain.get(service: svc, account: acct) == "secret1")\n"
        out += "update=\(Keychain.set("secret2", service: svc, account: acct))\n"
        out += "get2=\(Keychain.get(service: svc, account: acct) == "secret2")\n"
        Keychain.delete(service: svc, account: acct)
        out += "deleted=\(Keychain.get(service: svc, account: acct) == nil)\n"
        print(out)
        if let dst = ProcessInfo.processInfo.environment["KEYCHAIN_OUT"] {
            try? out.write(toFile: dst, atomically: true, encoding: .utf8)
        }
        exit(0)
    }

    /// `DICOMFLOW_TIMEOUT=1` — verify the network timeout: echo a non-routable
    /// host and report the elapsed time (must be ≈ the configured timeout, not ∞).
    @MainActor
    static func runTimeout() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let seconds = Int(env["TIMEOUT_S"] ?? "5") ?? 5
        UserDefaults.standard.set(seconds, forKey: "networkTimeout")
        let engine = DicomEngine()   // applies the timeout to the bridge
        let t0 = Date()
        let r = try? await engine.echo(host: env["TIMEOUT_HOST"] ?? "10.255.255.1",
                                       port: 4242, aeTitle: "NOWHERE", callingAE: "DICOMBENCH")
        let dt = Date().timeIntervalSince(t0)
        let out = "TIMEOUT test\nconfigured=\(seconds)s elapsed=\(String(format: "%.1f", dt))s "
            + "success=\(r?.success ?? false)\nverdict=\(dt < Double(seconds) + 10 ? "PASS (bounded)" : "FAIL (hung)")\n"
        print(out)
        if let dst = env["TIMEOUT_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_PCAP=<file>` — parse a pcap capture and dump decoded PDUs.
    @MainActor
    static func runPcap(path: String) async -> Never {
        var out = "PCAP test\n"
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let pdus = try PcapParser.parse(data)
            out += "count=\(pdus.count)\n"
            for p in pdus {
                out += "[\(p.kind.rawValue)] \(p.src)→\(p.dst)  \(p.title)\n"
                if !p.detail.isEmpty { out += p.detail.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n") + "\n" }
            }
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = ProcessInfo.processInfo.environment["PCAP_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_FHIR=1` + `FHIR_URL` — ImagingStudy search.
    @MainActor
    static func runFHIR() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let c = FHIRClient(baseURL: env["FHIR_URL"] ?? "https://hapi.fhir.org/baseR4")
        var out = "FHIR test\n"
        do {
            let rows = try await c.searchImagingStudies(filters: [:])
            out += "count=\(rows.count)\n"
            for r in rows.prefix(5) {
                out += "  \(r["Patient"] ?? "") · \(r["Modality"] ?? "") · series=\(r["Series"] ?? "") · \(r["Description"] ?? "")\n"
            }
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = env["FHIR_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_VALIDATE=<file>` — run the conformance validator.
    @MainActor
    static func runValidate(path: String) async -> Never {
        let engine = DicomEngine()
        let r = await engine.validate(path: path)
        var out = "ok=\(r.ok) errors=\(r.errors.count) warnings=\(r.warnings.count)\ninfo=\(r.info)\n"
        for e in r.errors { out += "  E: \(e)\n" }
        for w in r.warnings.prefix(20) { out += "  W: \(w)\n" }
        print(out)
        if let dst = ProcessInfo.processInfo.environment["VALIDATE_OUT"] {
            try? out.write(toFile: dst, atomically: true, encoding: .utf8)
        }
        exit(0)
    }

    /// `DICOMFLOW_HL7=1` — loopback: listener + send + ACK round-trip.
    @MainActor
    static func runHL7() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let listener = HL7Listener()
        listener.port = 12575
        listener.start()
        try? await Task.sleep(nanoseconds: 400_000_000)
        var out = "HL7 test\n"
        let msg = HL7.fill(HL7.templates[0].message)
        do {
            let ack = try await HL7Client.send(host: "127.0.0.1", port: 12575, message: msg)
            out += "ACK is AA: \(ack.contains("|AA|"))\n"
            out += "ACK:\n" + ack.replacingOccurrences(of: "\r", with: "\n") + "\n"
        } catch { out += "SEND FAIL \(error)\n" }
        try? await Task.sleep(nanoseconds: 400_000_000)
        out += "listener received: \(listener.messages.count)"
        if let m = listener.messages.first { out += " (summary: \(m.summary))" }
        out += "\n"
        print(out)
        if let dst = env["HL7_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_MWL=1` + `MWL_HOST/MWL_PORT/MWL_AE` — Modality Worklist C-FIND.
    @MainActor
    static func runMWL() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let engine = DicomEngine()
        var out = "MWL test\n"
        do {
            let r = try await engine.worklistQuery(
                host: env["MWL_HOST"] ?? "127.0.0.1",
                port: Int(env["MWL_PORT"] ?? "4242") ?? 4242,
                aeTitle: env["MWL_AE"] ?? "ORTHANC",
                filters: [:], callingAE: "DICOMBENCH")
            out += "success=\(r.success) count=\(r.count ?? -1) msg=\(r.message ?? "nil")\n"
            for it in (r.results ?? []).prefix(8) {
                out += "  \(it["PatientName"] ?? "") | \(it["Modality"] ?? "") | "
                    + "\(it["ScheduledProcedureStepStartDate"] ?? "") | "
                    + "\(it["ScheduledProcedureStepDescription"] ?? "") | AE=\(it["ScheduledStationAETitle"] ?? "")\n"
            }
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = env["MWL_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_PROTO=1` — capture the protocol log during a C-ECHO.
    @MainActor
    static func runProto() async -> Never {
        let env = ProcessInfo.processInfo.environment
        ProtocolLog.shared.verbose = true
        ProtocolLog.shared.startCapture()
        let engine = DicomEngine()
        // Two echoes → the log must split into two association groups.
        for _ in 0..<2 {
            _ = try? await engine.echo(host: env["PROTO_HOST"] ?? "127.0.0.1",
                                       port: Int(env["PROTO_PORT"] ?? "4242") ?? 4242,
                                       aeTitle: env["PROTO_AE"] ?? "ORTHANC", callingAE: "DICOMBENCH")
        }
        try? await Task.sleep(nanoseconds: 800_000_000)   // let main-queue appends flush
        let groups = Set(ProtocolLog.shared.events.map(\.group)).sorted()
        var out = "PROTO events=\(ProtocolLog.shared.events.count) groups=\(groups)\n"
        for e in ProtocolLog.shared.events.prefix(30) { out += "[g\(e.group)][\(e.kind.rawValue)] \(e.title)\n" }
        if let a = ProtocolLog.shared.events.first(where: { $0.kind == .associateRQ || $0.kind == .associateAC }) {
            out += "\n---- \(a.kind.rawValue) (first 1400 chars) ----\n" + String(a.message.prefix(1400))
        }
        print(out)
        if let dst = env["PROTO_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    /// `DICOMFLOW_DICOMWEB=1` + `DWB_URL/DWB_USER/DWB_PASS` — exercise the client.
    @MainActor
    static func runDicomWeb() async -> Never {
        let env = ProcessInfo.processInfo.environment
        let c = DicomWebClient(baseURL: env["DWB_URL"] ?? "",
                               username: env["DWB_USER"] ?? "", password: env["DWB_PASS"] ?? "")
        var out = "DICOMweb test\n"
        do {
            let rows = try await c.queryStudies(filters: [:])
            out += "QIDO_OK studies=\(rows.count)\n"
            if let f = rows.first {
                out += "first: \(f["PatientName"] ?? "") · \(f["ModalitiesInStudy"] ?? "") · series=\(f["NumberOfStudyRelatedSeries"] ?? "")\n"
                let studyUID = f["StudyInstanceUID"] ?? ""
                let ser = try await c.querySeries(studyUID: studyUID)
                out += "QIDO_SERIES_OK count=\(ser.count)\n"
                for s in ser.prefix(3) {
                    out += "  #\(s["SeriesNumber"] ?? "?") \(s["Modality"] ?? "?") inst=\(s["NumberOfSeriesRelatedInstances"] ?? "?")\n"
                }
                if let s0 = ser.first, let sUID = s0["SeriesInstanceUID"], !sUID.isEmpty {
                    let sdir = NSTemporaryDirectory() + "dwbtest_series"
                    let ns = try await c.retrieveSeries(studyUID: studyUID, seriesUID: sUID, outDir: sdir)
                    out += "WADO_SERIES_OK instances=\(ns)\n"
                    let inst = try await c.queryInstances(studyUID: studyUID, seriesUID: sUID)
                    out += "QIDO_INSTANCES_OK count=\(inst.count)"
                    if let i0 = inst.first { out += " first=#\(i0["InstanceNumber"] ?? "?") \(i0["Rows"] ?? "?")x\(i0["Columns"] ?? "?")" }
                    out += "\n"
                    if let sop = inst.first?["SOPInstanceUID"], !sop.isEmpty {
                        let meta = try await c.instanceMetadata(studyUID: studyUID, seriesUID: sUID, sopUID: sop)
                        out += "METADATA_OK tags=\(meta.count)\n"
                        let img = try await c.renderedInstance(studyUID: studyUID, seriesUID: sUID, sopUID: sop)
                        out += "RENDERED_OK bytes=\(img.count) sig=\(img.prefix(2).map { String(format: "%02x", $0) }.joined())\n"
                    }
                }
                let dir = NSTemporaryDirectory() + "dwbtest"
                let n = try await c.retrieveStudy(studyUID: studyUID, outDir: dir)
                out += "WADO_OK instances=\(n) → \(dir)\n"
            }
        } catch { out += "FAIL \(error)\n" }
        print(out)
        if let dst = env["DWB_OUT"] { try? out.write(toFile: dst, atomically: true, encoding: .utf8) }
        exit(0)
    }

    @MainActor
    static func runSR(directory: String) async -> Never {
        let engine = DicomEngine()
        let series = await engine.scanSeries(directory: directory)
        guard let sr = series.first(where: { $0.modality == "SR" }), let f = sr.files.first else {
            FileHandle.standardError.write(Data("SR_NONE\n".utf8)); exit(1)
        }
        do {
            let text = try await engine.readReport(path: f)
            let out = "SR_OK series=\(sr.description) len=\(text.count)\n----\n\(text)"
            print(out)
            if let dst = ProcessInfo.processInfo.environment["DICOMFLOW_SR_OUT"] {
                try? out.write(toFile: dst, atomically: true, encoding: .utf8)
            }
            exit(0)
        } catch {
            let msg = "SR_FAIL \(error)"
            FileHandle.standardError.write(Data((msg + "\n").utf8))
            if let dst = ProcessInfo.processInfo.environment["DICOMFLOW_SR_OUT"] {
                try? msg.write(toFile: dst, atomically: true, encoding: .utf8)
            }
            exit(1)
        }
    }

    @MainActor
    static func runVolume(directory: String, outDir: String) async -> Never {
        do {
            let engine = DicomEngine()
            let vol = try await engine.decodeVolume(directory: directory)
            let m = vol.meta
            print("NATIVE_VOL_OK dims=\(m.dims) spacing=\(m.spacing) origin=\(m.origin) modality=\(m.modality) range=\(m.valueMin)...\(m.valueMax)")
            try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            // MPR planes
            for axis in MPRAxis.allCases {
                if let img = MPRPlaneRenderer.renderOffscreen(
                    volume: vol, axis: axis, sliceFrac: 0.5,
                    winCenter: m.defaultWindowCenter, winWidth: m.defaultWindowWidth, size: 256) {
                    write(img, "\(outDir)/native_\(axis.rawValue).png")
                }
            }
            // Rotation + flip sanity check (axial, 90° + flip H)
            if let img = MPRPlaneRenderer.renderOffscreen(
                volume: vol, axis: .axial, sliceFrac: 0.5,
                winCenter: m.defaultWindowCenter, winWidth: m.defaultWindowWidth, size: 256,
                quarter: 1, flipH: true) {
                write(img, "\(outDir)/native_axial_rot90_flipH.png")
            }
            // 3D MIP + volume
            let rc = RaycastRenderer(); rc.volume = vol
            for mode in RenderMode.allCases {
                rc.mode = mode
                rc.winCenter = m.defaultWindowCenter; rc.winWidth = m.defaultWindowWidth
                if let img = rc.renderOffscreen(size: 384) {
                    write(img, "\(outDir)/native_raycast_\(mode.rawValue).png")
                }
            }
            print("NATIVE_VOL_DONE")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("NATIVE_VOL_FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    static func write(_ image: CGImage, _ path: String) {
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("NATIVE_VOL_OK wrote \(path)")
    }

    @MainActor
    static func runEditAnon(directory: String) async -> Never {
        do {
            let engine = DicomEngine()
            let files = DicomEngine.enumerateFiles(directory).sorted()
            guard let first = files.first else { throw DicomEngine.EngineError.noImages }

            // Edit: change PatientName, attempt to change Rows (must be blocked).
            let outFile = NSTemporaryDirectory() + "edited.dcm"
            let e = try await engine.editTags(path: first, edits: [
                EditOp(keyword: "PatientName", value: "EDITED^NATIVE"),
                EditOp(keyword: "Rows", value: "999"),
            ], outputPath: outFile)
            let back = try await engine.readTags(path: outFile).tags
            let pn = back.first { $0.keyword == "PatientName" }?.value ?? "?"
            let rows = back.first { $0.keyword == "Rows" }?.value ?? "?"
            print("EDIT_OK applied=\(e.applied.count) skipped=\(e.skipped.count) PatientName=\(pn) Rows=\(rows)")

            // Anonymize the whole series.
            let anonDir = NSTemporaryDirectory() + "anon_native"
            let a = try await engine.anonymize(directory: directory, outputDir: anonDir,
                                               profile: AnonProfileDTO())
            let outs = DicomEngine.enumerateFiles(anonDir).sorted()
            let t0 = try await engine.readTags(path: outs[0]).tags
            let t1 = try await engine.readTags(path: outs[min(1, outs.count - 1)]).tags
            let orig = try await engine.readTags(path: first).tags
            func v(_ t: [TagItem], _ k: String) -> String { t.first { $0.keyword == k }?.value ?? "" }
            print("ANON_OK processed=\(a.processed) uidsRemapped=\(a.uidsRemapped)")
            print("  PatientName=\(v(t0, "PatientName")) (orig \(v(orig, "PatientName")))")
            print("  SeriesUID stable across slices: \(v(t0, "SeriesInstanceUID") == v(t1, "SeriesInstanceUID"))")
            print("  SeriesUID changed from orig: \(v(t0, "SeriesInstanceUID") != v(orig, "SeriesInstanceUID"))")
            print("  SOPClassUID preserved: \(v(t0, "SOPClassUID") == v(orig, "SOPClassUID"))")
            print("  SOPInstanceUID distinct: \(v(t0, "SOPInstanceUID") != v(t1, "SOPInstanceUID"))")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("EDITANON_FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    /// Scan a folder into series (Phase E). `DICOMFLOW_SCAN=<dir>`.
    @MainActor
    static func runScan(directory: String) async -> Never {
        let engine = DicomEngine()
        let series = await engine.scanSeries(directory: directory)
        print("SCAN_OK series=\(series.count)")
        for s in series {
            print("  [\(s.modality)] \(s.count) inst  #\(s.seriesNumber)  \(s.description)")
        }
        exit(0)
    }

    /// Full native round-trip against a real PACS: store → C-FIND → C-GET.
    /// `DICOMFLOW_ORTHANC=<host:port:AE>`, seed dir via DICOMFLOW_DIR.
    @MainActor
    static func runOrthanc(target: String, seedDir: String) async -> Never {
        do {
            let parts = target.split(separator: ":")
            let host = String(parts[0]); let port = Int(parts[1]) ?? 4242
            let ae = parts.count > 2 ? String(parts[2]) : "ORTHANC"
            let cae = "DICOMBENCH"
            let engine = DicomEngine()

            let e = try await engine.echo(host: host, port: port, aeTitle: ae, callingAE: cae)
            print("ORTHANC_ECHO success=\(e.success) status=\(e.echoStatus ?? -99)")

            let files = DicomEngine.enumerateFiles(seedDir)
            let s = try await engine.store(host: host, port: port, aeTitle: ae, paths: files, callingAE: cae)
            print("ORTHANC_STORE sent=\(s.sent ?? -1)/\(s.total ?? -1)")
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let q = try await engine.query(host: host, port: port, aeTitle: ae, level: "STUDY",
                                           filters: ["PatientName": "DicomFlow*"], callingAE: cae)
            print("ORTHANC_FIND success=\(q.success) studies=\(q.count ?? -1)")
            guard let uid = q.results?.first?["StudyInstanceUID"], !uid.isEmpty else {
                print("ORTHANC_DONE (no study UID to retrieve)"); exit(0)
            }
            let r = try await engine.retrieve(host: host, port: port, aeTitle: ae, level: "STUDY",
                                              keys: ["StudyInstanceUID": uid], method: "get",
                                              moveDestination: nil, callingAE: cae)
            print("ORTHANC_GET success=\(r.success) received=\(r.received ?? -1) dir=\(r.receivedDir ?? "")")
            print("ORTHANC_DONE")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("ORTHANC_FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    /// SCP-only: start the native SCP and idle, then report what arrived.
    @MainActor
    static func runScpOnly() async -> Never {
        do {
            DCMTKNet.enableVerboseLogging()
            try? FileManager.default.removeItem(atPath: DicomEngine.receivedDir)
            let engine = DicomEngine()
            let s = try await engine.scpStart(aeTitle: "DICOMBENCH", port: 11115)
            print("SCP_READY running=\(s.running) port=\(s.port)")
            try await Task.sleep(nanoseconds: 16_000_000_000)
            let rec = try await engine.scpReceived()
            print("SCP_FINAL_RECEIVED \(rec.items.count)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("SCPONLY_FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    /// SCU-only test against an external peer "host:port" (no local SCP).
    @MainActor
    static func runScu(target: String, directory: String) async -> Never {
        do {
            DCMTKNet.enableVerboseLogging()
            let parts = target.split(separator: ":")
            let host = String(parts[0]); let port = Int(parts[1]) ?? 11114
            let engine = DicomEngine()
            let e = try await engine.echo(host: host, port: port, aeTitle: "ANYSCP", callingAE: "TESTER")
            print("SCU_ECHO success=\(e.success) status=\(e.echoStatus ?? -99) msg=\(e.message ?? "")")
            let files = DicomEngine.enumerateFiles(directory)
            let s = try await engine.store(host: host, port: port, aeTitle: "ANYSCP", paths: Array(files.prefix(5)), callingAE: "TESTER")
            print("SCU_STORE sent=\(s.sent ?? -1)/\(s.total ?? -1) msg=\(s.message ?? "")")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("SCU_FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func runNet(directory: String) async -> Never {
        do {
            DCMTKNet.enableVerboseLogging()
            let engine = DicomEngine()
            _ = try await engine.scpStop()  // clean slate
            let started = try await engine.scpStart(aeTitle: "DICOMBENCH", port: 11113)
            print("SCP_START running=\(started.running) port=\(started.port)")
            try await Task.sleep(nanoseconds: 1_500_000_000)  // let the listener bind
            let raw = DCMTKNet.scpStatus()
            print("SCP_RAW \(raw)")
            let e = try await engine.echo(host: "127.0.0.1", port: 11113, aeTitle: "DICOMBENCH", callingAE: "TESTER")
            print("ECHO success=\(e.success) status=\(e.echoStatus ?? -99) msg=\(e.message ?? "")")
            let files = DicomEngine.enumerateFiles(directory)
            let s = try await engine.store(host: "127.0.0.1", port: 11113, aeTitle: "DICOMBENCH", paths: files, callingAE: "TESTER")
            print("STORE sent=\(s.sent ?? -1)/\(s.total ?? -1)")
            try await Task.sleep(nanoseconds: 500_000_000)
            let rec = try await engine.scpReceived()
            print("SCP_RECEIVED count=\(rec.items.count)")
            _ = try await engine.scpStop()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("NET_FAIL \(error)\n".utf8))
            exit(1)
        }
    }

    static func runTags(path: String) -> Never {
        do {
            let tags = try DCMTKBridge.readTags(path)
            let ts = DCMTKBridge.transferSyntaxName(path) ?? "?"
            print("NATIVE_TAGS_OK count=\(tags.count) transferSyntax=\(ts)")
            for t in tags.prefix(8) {
                print("  \(t["tag"] ?? "") \(t["vr"] ?? "") \(t["name"] ?? "") = \((t["value"] ?? "").prefix(40))")
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("NATIVE_TAGS_FAIL \(error)\n".utf8))
            exit(1)
        }
    }
}
