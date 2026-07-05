import XCTest

final class PcapParserTests: XCTestCase {

    private func assertEchoExchange(_ pdus: [PcapPDU], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pdus.count, 6, file: file, line: line)
        XCTAssertEqual(pdus[0].kind, .associateRQ, file: file, line: line)
        XCTAssertTrue(pdus[0].title.contains("DICOMBENCH → ORTHANC"), pdus[0].title, file: file, line: line)
        XCTAssertTrue(pdus[0].detail.contains("Verification SOP Class"), file: file, line: line)
        XCTAssertTrue(pdus[0].detail.contains("Implicit VR Little Endian"), file: file, line: line)
        XCTAssertTrue(pdus[0].detail.contains("Max PDU length: 16384"), file: file, line: line)
        XCTAssertEqual(pdus[1].kind, .associateAC, file: file, line: line)
        XCTAssertTrue(pdus[1].detail.contains("[accepted]"), file: file, line: line)
        // The command PDV must be decoded down to the DIMSE command itself.
        XCTAssertEqual(pdus[2].kind, .echo, file: file, line: line)
        XCTAssertTrue(pdus[2].title.contains("C-ECHO-RQ"), pdus[2].title, file: file, line: line)
        XCTAssertTrue(pdus[2].title.contains("MsgID 1"), pdus[2].title, file: file, line: line)
        XCTAssertTrue(pdus[2].detail.contains("Verification SOP Class"), pdus[2].detail, file: file, line: line)
        XCTAssertEqual(pdus[4].kind, .release, file: file, line: line)
        XCTAssertEqual(pdus[5].kind, .release, file: file, line: line)
        // Direction endpoints survive into src/dst.
        XCTAssertTrue(pdus[0].src.hasPrefix("192.168.1.10:"), pdus[0].src, file: file, line: line)
        XCTAssertTrue(pdus[1].src.hasPrefix("192.168.1.52:"), pdus[1].src, file: file, line: line)
    }

    func testClassicPcap() throws {
        let pdus = try PcapParser.parse(PcapFixture.classicPcap(PcapFixture.exchange()))
        assertEchoExchange(pdus)
    }

    func testPcapng() throws {
        let pdus = try PcapParser.parse(PcapFixture.pcapng(PcapFixture.exchange()))
        assertEchoExchange(pdus)
    }

    /// TCP segments arriving out of order must still reassemble by sequence.
    func testOutOfOrderSegments() throws {
        var wires = PcapFixture.exchange()
        wires.swapAt(0, 4)   // RQ arrives after release-RQ in capture order
        wires.swapAt(1, 5)
        let pdus = try PcapParser.parse(PcapFixture.classicPcap(wires))
        XCTAssertEqual(pdus.count, 6)
        XCTAssertEqual(Set(pdus.map(\.kind)), [.associateRQ, .associateAC, .echo, .release])
    }

    func testBadMagicThrows() {
        XCTAssertThrowsError(try PcapParser.parse(Data(repeating: 0x42, count: 64))) {
            XCTAssertEqual($0 as? PcapError, .badMagic)
        }
    }

    func testTooShortThrows() {
        XCTAssertThrowsError(try PcapParser.parse(Data([0xa1, 0xb2]))) {
            XCTAssertEqual($0 as? PcapError, .tooShort)
        }
    }

    /// A valid capture whose TCP payloads aren't DICOM PDUs → .noDicom.
    func testNonDicomPayloadThrows() {
        let http = Array("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        let wires = PcapFixture.exchange(payloadOverride: [http])
        XCTAssertThrowsError(try PcapParser.parse(PcapFixture.classicPcap(wires))) {
            XCTAssertEqual($0 as? PcapError, .noDicom)
        }
    }
}

extension PcapError: Equatable {
    public static func == (l: PcapError, r: PcapError) -> Bool {
        switch (l, r) {
        case (.tooShort, .tooShort), (.badMagic, .badMagic), (.noDicom, .noDicom): return true
        default: return false
        }
    }
}
