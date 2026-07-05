import XCTest

/// Parses a real DICOMDIR (pydicom's dicomdirtests fixture) and resolves its
/// referenced files. Gated on the fixture existing (copied to /tmp for the run).
final class DicomDirTests: XCTestCase {

    func testReadsHierarchyAndResolvesFiles() throws {
        let path = "/tmp/dicomflow-dcmdir-fixture/DICOMDIR"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("no DICOMDIR fixture at \(path)")
        }
        let d = DCMTKBridge.readDicomDir(path)
        XCTAssertTrue((d["success"] as? NSNumber)?.boolValue ?? false, "\(d["message"] ?? "-")")

        let patients = d["patients"] as? [[String: Any]] ?? []
        XCTAssertFalse(patients.isEmpty, "no patients parsed")

        var studyCount = 0, seriesCount = 0, referenced = 0, resolved = 0
        let fm = FileManager.default
        for p in patients {
            for st in (p["studies"] as? [[String: Any]] ?? []) {
                studyCount += 1
                for se in (st["series"] as? [[String: Any]] ?? []) {
                    seriesCount += 1
                    for f in (se["files"] as? [String] ?? []) {
                        referenced += 1
                        if fm.fileExists(atPath: f) { resolved += 1 }
                    }
                }
            }
        }
        print("DICOMDIR: \(patients.count) patient(s), \(studyCount) study(ies), \(seriesCount) series, \(resolved)/\(referenced) files resolved")
        XCTAssertGreaterThan(seriesCount, 0, "no series parsed")
        XCTAssertGreaterThan(referenced, 0, "no referenced instances parsed")
        // Every referenced file must resolve to a real path on the media.
        XCTAssertEqual(resolved, referenced, "some ReferencedFileID paths did not resolve")
    }

    func testRejectsNonDicomDir() {
        // A regular DICOM instance (any file) is not a DICOMDIR.
        let tmp = NSTemporaryDirectory() + "not-a-dicomdir.txt"
        try? "hello".write(toFile: tmp, atomically: true, encoding: .utf8)
        let d = DCMTKBridge.readDicomDir(tmp)
        XCTAssertFalse((d["success"] as? NSNumber)?.boolValue ?? true)
    }
}
