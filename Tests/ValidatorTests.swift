import XCTest

/// Verifies the dcmiod-backed IOD conformance checks in DCMTKBridge.validateFile.
final class ValidatorTests: XCTestCase {

    func testIODModuleChecks() throws {
        // A minimal SC image: has Patient Name/ID + Modality + pixel data, but is
        // missing several type-2 attributes (Study Date, Series Number, …).
        let path = NSTemporaryDirectory() + "dicomflow-validate/img.dcm"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        XCTAssertTrue(DCMTKNet.writeTestImage(toPath: path), "could not synthesize image")

        let d = DCMTKBridge.validateFile(path)
        let iod = d["iodModules"] as? [[String: Any]] ?? []
        XCTAssertFalse(iod.isEmpty, "no IOD module attributes were checked")

        // Modules covered.
        let modules = Set(iod.compactMap { $0["module"] as? String })
        print("IOD modules covered: \(modules.sorted().joined(separator: ", "))")
        XCTAssertTrue(modules.contains { $0.contains("Patient") }, "Patient module not checked")
        XCTAssertTrue(modules.contains { $0.contains("Series") }, "Series module not checked")

        // Present type-1/2 pass; genuinely-missing type-2 fail.
        func ok(_ m: [String: Any]) -> Bool { (m["ok"] as? NSNumber)?.boolValue ?? false }
        let fails = iod.filter { !ok($0) }
        print("IOD: \(iod.count) attrs checked, \(fails.count) failing")
        for f in fails { print("  ✗ [\(f["module"] ?? "")] \(f["name"] ?? "") type-\(f["type"] ?? "")") }

        // DCMTK reports tag keywords (no spaces). PatientName was set → passes.
        XCTAssertTrue(iod.contains { ($0["name"] as? String) == "PatientName" && ok($0) },
                      "PatientName should validate")
        // StudyDate was NOT set (type-2) → should fail.
        XCTAssertTrue(fails.contains { ($0["name"] as? String) == "StudyDate" },
                      "missing StudyDate should be flagged")
        // No false Frame-of-Reference failure on an SC image.
        XCTAssertFalse(fails.contains { ($0["module"] as? String) == "FrameOfReferenceModule" },
                       "FoR should not be enforced on non-spatial IODs")
    }
}
