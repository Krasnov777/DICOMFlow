import XCTest

final class CurrentStudyTests: XCTestCase {
    func testRoundTrip() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-current-study/\(UUID().uuidString)"
        let url = URL(fileURLWithPath: dir + "/current-study.json")
        let s = CurrentStudy(kind: "series", directory: "/scans/ct",
                             files: ["/scans/ct/1.dcm", "/scans/ct/2.dcm"],
                             seriesUID: "1.2.3.4", seriesDescription: "AX HEAD",
                             modality: "CT", patient: "DOE^JANE",
                             studyDescription: "HEAD W/O")
        s.write(to: url)
        let back = try XCTUnwrap(CurrentStudy.read(from: url))
        XCTAssertEqual(back.kind, "series")
        XCTAssertEqual(back.files.count, 2)
        XCTAssertEqual(back.seriesUID, "1.2.3.4")
        XCTAssertEqual(back.modality, "CT")
        XCTAssertEqual(back.patient, "DOE^JANE")
        // ISO8601 round trip is second-precision
        XCTAssertEqual(back.updatedAt.timeIntervalSince1970,
                       s.updatedAt.timeIntervalSince1970, accuracy: 1.0)
    }

    /// Overwrite = the manifest always reflects the latest load.
    func testOverwrite() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()
            + "dicomflow-current-study/\(UUID().uuidString)/current-study.json")
        CurrentStudy(kind: "file", files: ["/a.dcm"]).write(to: url)
        CurrentStudy(kind: "sr", files: ["/b.dcm"]).write(to: url)
        let back = try XCTUnwrap(CurrentStudy.read(from: url))
        XCTAssertEqual(back.kind, "sr")
        XCTAssertEqual(back.files, ["/b.dcm"])
    }

    /// The un-sandboxed reader checks the sandbox container first, then plain home.
    func testReadCandidatesOrder() {
        let c = CurrentStudy.readCandidates(home: "/Users/x")
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c[0].path.contains("Containers/com.dicombench.app/Data"))
        XCTAssertTrue(c[1].path.hasSuffix("Library/Application Support/DicomFlow/current-study.json"))
    }

    func testReadMissingReturnsNil() {
        XCTAssertNil(CurrentStudy.read(from: URL(fileURLWithPath: "/nonexistent/x.json")))
    }
}

final class ControlEndpointTests: XCTestCase {
    func testRoundTripAndPermissions() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()
            + "dicomflow-control/\(UUID().uuidString)/control.json")
        let ep = ControlEndpoint(port: 54321, token: "secret-token")
        ep.write(to: url)
        let back = try XCTUnwrap(ControlEndpoint.read(from: url))
        XCTAssertEqual(back.port, 54321)
        XCTAssertEqual(back.token, "secret-token")
        XCTAssertEqual(back.pid, ProcessInfo.processInfo.processIdentifier)
        // The token is a local credential — file must be owner-only.
        let perms = try XCTUnwrap(FileManager.default
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        XCTAssertEqual(perms, 0o600)
    }

    /// readLatest ignores endpoints whose process is gone (stale file after a crash).
    func testStaleEndpointIgnored() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-control-stale/\(UUID().uuidString)"
        let url = URL(fileURLWithPath: dir + "/Library/Application Support/DicomFlow/control.json")
        ControlEndpoint(port: 1, token: "t", pid: 999_999_9).write(to: url)
        XCTAssertNil(ControlEndpoint.readLatest(home: dir))
    }
}
