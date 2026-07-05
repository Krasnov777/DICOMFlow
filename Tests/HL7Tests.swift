import XCTest

final class HL7Tests: XCTestCase {

    let adt = "MSH|^~\\&|DICOMBENCH|LAB|RIS|HOSP|20260701120000||ADT^A01|MSG42|P|2.3\r"
        + "PID|1||PID12345^^^HOSP^MR||Doe^John^A||19800101|M\r"

    func testFrameDeframeRoundtrip() {
        let framed = HL7.frame(adt)
        XCTAssertEqual(framed.first, HL7.VT)
        XCTAssertEqual(Array(framed.suffix(2)), [HL7.FS, HL7.CR])
        XCTAssertEqual(HL7.deframe(framed), HL7.normalize(adt).trimmingCharacters(in: .newlines))
    }

    func testNormalizeConvertsLineEndings() {
        XCTAssertEqual(HL7.normalize("A|1\nB|2"), "A|1\rB|2")
        XCTAssertEqual(HL7.normalize("A|1\r\nB|2"), "A|1\rB|2")
        XCTAssertEqual(HL7.normalize("A|1\rB|2"), "A|1\rB|2")
    }

    func testMSHFields() {
        let f = HL7.mshFields(adt)
        XCTAssertEqual(f[0], "MSH")
        XCTAssertEqual(f[2], "DICOMBENCH")   // sending app
        XCTAssertEqual(f[4], "RIS")          // receiving app
        XCTAssertEqual(f[8], "ADT^A01")      // message type
        XCTAssertEqual(f[9], "MSG42")        // control id
    }

    func testSummary() {
        XCTAssertEqual(HL7.summary(adt), "ADT^A01  ·  MSG42")
        XCTAssertEqual(HL7.summary("garbage"), "?")
    }

    func testACKEchoesControlIDAndSwapsApps() {
        let ack = HL7.buildACK(for: adt)
        XCTAssertTrue(ack.contains("MSA|AA|MSG42"), ack)
        let f = HL7.mshFields(ack)
        XCTAssertEqual(f[2], "RIS")          // reply sender = original receiver
        XCTAssertEqual(f[4], "DICOMBENCH")   // reply receiver = original sender
        XCTAssertEqual(f[8], "ACK")
    }

    func testACKErrorCode() {
        XCTAssertTrue(HL7.buildACK(for: adt, code: "AE").contains("MSA|AE|MSG42"))
    }

    // MARK: field-level parse

    func testParseSegmentsAndNames() {
        let segs = HL7.parse(adt)
        XCTAssertEqual(segs.map(\.name), ["MSH", "PID"])
        let pid = segs[1]
        let pid5 = pid.fields.first { $0.label == "PID-5" }
        XCTAssertEqual(pid5?.value, "Doe^John^A")
        XCTAssertEqual(pid5?.name, "Patient Name")
        XCTAssertEqual(pid.fields.first { $0.label == "PID-8" }?.value, "M")
    }

    /// MSH numbering is shifted: MSH-1 is the separator, MSH-2 the encoding chars.
    func testParseMSHNumbering() {
        let msh = HL7.parse(adt)[0]
        func v(_ l: String) -> String? { msh.fields.first { $0.label == l }?.value }
        XCTAssertEqual(v("MSH-1"), "|")
        XCTAssertEqual(v("MSH-2"), "^~\\&")
        XCTAssertEqual(v("MSH-3"), "DICOMBENCH")
        XCTAssertEqual(v("MSH-9"), "ADT^A01")
        XCTAssertEqual(v("MSH-10"), "MSG42")
        XCTAssertEqual(msh.fields.first { $0.label == "MSH-9" }?.name, "Message Type")
    }

    func testParseACKHasMSA() {
        let segs = HL7.parse(HL7.buildACK(for: adt))
        let msa = segs.first { $0.name == "MSA" }
        XCTAssertEqual(msa?.fields.first { $0.label == "MSA-1" }?.value, "AA")
        XCTAssertEqual(msa?.fields.first { $0.label == "MSA-2" }?.value, "MSG42")
        XCTAssertEqual(msa?.fields.first { $0.label == "MSA-1" }?.name, "Acknowledgment Code")
    }

    func testTemplatesFill() {
        for t in HL7.templates {
            let m = HL7.fill(t.message)
            XCTAssertFalse(m.contains("{TS}"), t.name)
            XCTAssertFalse(m.contains("{N}"), t.name)
            XCTAssertTrue(m.hasPrefix("MSH|^~\\&|"), t.name)
        }
    }
}
