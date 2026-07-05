import XCTest

final class DicomWebClientTests: XCTestCase {

    // MARK: boundary parsing

    func testBoundaryPlain() {
        XCTAssertEqual(DicomWebClient.boundary(
            from: "multipart/related; type=\"application/dicom\"; boundary=abc123"), "abc123")
    }

    func testBoundaryQuoted() {
        XCTAssertEqual(DicomWebClient.boundary(
            from: "multipart/related; boundary=\"quoted-b\"; type=\"application/dicom\""), "quoted-b")
    }

    func testBoundaryMissing() {
        XCTAssertNil(DicomWebClient.boundary(from: "application/dicom+json"))
    }

    // MARK: multipart splitting

    func testMultipartBodiesSplitsAndStripsHeaders() {
        let b = "XYZ"
        var data = Data()
        data.append("--\(b)\r\nContent-Type: application/dicom\r\n\r\n".data(using: .utf8)!)
        data.append(Data([0x01, 0x02, 0x03]))
        data.append("\r\n--\(b)\r\nContent-Type: application/dicom\r\n\r\n".data(using: .utf8)!)
        data.append(Data([0x04, 0x05]))
        data.append("\r\n--\(b)--\r\n".data(using: .utf8)!)

        let parts = DicomWebClient.multipartBodies(data, boundary: b)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(Array(parts[0]), [0x01, 0x02, 0x03])
        XCTAssertEqual(Array(parts[1]), [0x04, 0x05])
    }

    // MARK: DICOM-JSON value extraction

    func testValueString() {
        let obj: [String: Any] = ["00080020": ["vr": "DA", "Value": ["20260701"]]]
        XCTAssertEqual(DicomWebClient.value(obj, "00080020"), "20260701")
    }

    func testValuePersonName() {
        let obj: [String: Any] = ["00100010": ["vr": "PN", "Value": [["Alphabetic": "DOE^JOHN"]]]]
        XCTAssertEqual(DicomWebClient.value(obj, "00100010"), "DOE^JOHN")
    }

    func testValueNumber() {
        let obj: [String: Any] = ["00201206": ["vr": "IS", "Value": [4]]]
        XCTAssertEqual(DicomWebClient.value(obj, "00201206"), "4")
    }

    func testValueMultiValueJoined() {
        let obj: [String: Any] = ["00080061": ["vr": "CS", "Value": ["CT", "SR"]]]
        XCTAssertEqual(DicomWebClient.value(obj, "00080061"), "CT\\SR")
    }

    func testValueAbsentTag() {
        XCTAssertEqual(DicomWebClient.value([:], "00100010"), "")
    }
}
