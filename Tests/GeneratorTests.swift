import XCTest

/// The synthetic generator must produce a decodable, stackable, conformant series.
final class GeneratorTests: XCTestCase {

    func testGeneratesConformantVolume() throws {
        let dir = NSTemporaryDirectory() + "dicomflow-gen-test"
        try? FileManager.default.removeItem(atPath: dir)
        let d = DCMTKBridge.generateDataset(toDir: dir, sopClass: "1.2.840.10008.5.1.4.1.1.2",
                                            rows: 64, columns: 64, slices: 16, pattern: "sphere")
        XCTAssertTrue((d["success"] as? NSNumber)?.boolValue ?? false)
        XCTAssertEqual((d["count"] as? NSNumber)?.intValue, 16)
        let files = d["files"] as? [String] ?? []
        XCTAssertEqual(files.count, 16)

        // Every slice decodes with the requested pixel dimensions.
        let slice = try DCMTKBridge.decodeFile(files[0])
        XCTAssertEqual((slice["rows"] as? NSNumber)?.intValue, 64)
        XCTAssertEqual((slice["columns"] as? NSNumber)?.intValue, 64)

        // A slice validates as conformant (no type-1 IOD violations).
        let v = DCMTKBridge.validateFile(files[0])
        XCTAssertTrue((v["ok"] as? NSNumber)?.boolValue ?? false,
                      "generated file not conformant: \(v["errors"] ?? "-")")

        // Shared study/series UID across slices → stacks as one volume.
        func seriesUID(_ path: String) throws -> String? {
            try DCMTKBridge.readTags(path).first { ($0["keyword"] ?? "") == "SeriesInstanceUID" }?["value"]
        }
        let a = try seriesUID(files[0]), b = try seriesUID(files[15])
        XCTAssertNotNil(a); XCTAssertEqual(a, b, "slices should share one SeriesInstanceUID")
    }

    func testDumpContainsElements() throws {
        let path = NSTemporaryDirectory() + "dicomflow-dump/img.dcm"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        XCTAssertTrue(DCMTKNet.writeTestImage(toPath: path))
        let dump = DCMTKBridge.dumpFile(path)
        XCTAssertNotNil(dump)
        XCTAssertTrue(dump?.contains("PatientName") ?? false, "dump missing PatientName")
        XCTAssertTrue(dump?.contains("Modality") ?? false, "dump missing Modality")
        XCTAssertNil(DCMTKBridge.dumpFile(NSTemporaryDirectory() + "does-not-exist.dcm"))
    }

    func testBasicProfileAnonymization() throws {
        // A CT slice with StudyDate + SeriesDescription set by the generator.
        let src = NSTemporaryDirectory() + "dicomflow-anon-src"
        try? FileManager.default.removeItem(atPath: src)
        let g = DCMTKBridge.generateDataset(toDir: src, sopClass: "1.2.840.10008.5.1.4.1.1.2",
                                            rows: 32, columns: 32, slices: 1, pattern: "solid")
        let files = g["files"] as? [String] ?? []
        XCTAssertEqual(files.count, 1)

        let outDir = NSTemporaryDirectory() + "dicomflow-anon-out"
        try? FileManager.default.removeItem(atPath: outDir)
        let prof: [String: Any] = [
            "replacePatientName": "ANON", "replacePatientID": "ANON-ID",
            "clearDates": false, "clearIdentifiers": false,
            "removePrivateTags": true, "regenerateUIDs": true,
            "basicProfile": true, "retainDates": false, "retainDeviceIdentity": false,
            "retainPatientChars": false, "cleanDescriptors": true,
        ]
        let r = try DCMTKBridge.anonymize(files, outputDir: outDir, profile: prof)
        XCTAssertEqual((r["processed"] as? NSNumber)?.intValue, 1)

        let outFiles = (try? FileManager.default.contentsOfDirectory(atPath: outDir)) ?? []
        let outPath = outDir + "/" + (outFiles.first ?? "")
        let tags = try DCMTKBridge.readTags(outPath)
        func val(_ kw: String) -> String? { tags.first { $0["keyword"] == kw }?["value"] }

        XCTAssertEqual(val("PatientName"), "ANON", "patient name not replaced")
        XCTAssertEqual(val("StudyDate"), "", "StudyDate should be zeroed by the profile")
        XCTAssertEqual(val("SeriesDescription"), "", "descriptor should be cleaned")
        XCTAssertEqual(val("PatientIdentityRemoved"), "YES", "de-id flag not set")
        XCTAssertNotNil(val("DeidentificationMethod"), "de-id method not recorded")
    }

    func testRedactionZeroesRegion() throws {
        // A gradient CT (varies across x, so every pixel is non-zero).
        let src = NSTemporaryDirectory() + "dicomflow-redact-src"
        try? FileManager.default.removeItem(atPath: src)
        let g = DCMTKBridge.generateDataset(toDir: src, sopClass: "1.2.840.10008.5.1.4.1.1.2",
                                            rows: 64, columns: 64, slices: 1, pattern: "gradient")
        let file = (g["files"] as? [String] ?? []).first
        XCTAssertNotNil(file)
        let out = NSTemporaryDirectory() + "dicomflow-redact-out.dcm"
        try? FileManager.default.removeItem(atPath: out)

        // Redact the top-left quarter.
        let rect = [0.0, 0.0, 0.5, 0.5].map { NSNumber(value: $0) }
        let r = DCMTKBridge.redactFile(file!, rects: [rect], outputPath: out)
        XCTAssertTrue((r["success"] as? NSNumber)?.boolValue ?? false, "\(r["message"] ?? "-")")

        let d = try DCMTKBridge.decodeFile(out)
        let cols = (d["columns"] as? NSNumber)?.intValue ?? 0
        let px: [Int16] = (d["pixelData"] as? Data ?? Data()).withUnsafeBytes {
            Array($0.bindMemory(to: Int16.self))
        }
        XCTAssertGreaterThan(px.count, 64 * 64 - 1)
        XCTAssertEqual(px[2 * cols + 2], 0, "redacted region should be black")
        XCTAssertNotEqual(px[62 * cols + 62], 0, "region outside the redaction was altered")
        // Redaction records that burned-in annotation is gone.
        let tags = try DCMTKBridge.readTags(out)
        XCTAssertEqual(tags.first { $0["keyword"] == "BurnedInAnnotation" }?["value"], "NO")
    }

    func testSecondaryCaptureIsSingleFrame() {
        let dir = NSTemporaryDirectory() + "dicomflow-gen-sc"
        try? FileManager.default.removeItem(atPath: dir)
        let d = DCMTKBridge.generateDataset(toDir: dir, sopClass: "1.2.840.10008.5.1.4.1.1.7",
                                            rows: 128, columns: 128, slices: 1, pattern: "gradient")
        XCTAssertEqual((d["count"] as? NSNumber)?.intValue, 1)
    }
}
