import Foundation

/// Builds synthetic captures of a DICOM echo association (RQ → AC → two
/// P-DATA → release) for PcapParser tests — classic pcap and pcapng.
enum PcapFixture {
    // MARK: byte helpers
    static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }
    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    static func le32(_ v: Int) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    // MARK: DICOM upper-layer PDUs
    static func pdu(_ t: UInt8, _ body: [UInt8]) -> [UInt8] { [t, 0] + be32(body.count) + body }
    static func item(_ t: UInt8, _ d: [UInt8]) -> [UInt8] { [t, 0] + be16(d.count) + d }
    static func ae(_ s: String) -> [UInt8] {
        Array(s.padding(toLength: 16, withPad: " ", startingAt: 0).utf8)
    }
    static func uid(_ s: String) -> [UInt8] { Array(s.utf8) }

    struct Association {
        let rq: [UInt8], ac: [UInt8], pdata: [UInt8], relRQ: [UInt8], relRP: [UInt8]
    }

    static func echoAssociation(calling: String = "DICOMBENCH", called: String = "ORTHANC") -> Association {
        let appctx = item(0x10, uid("1.2.840.10008.3.1.1.1"))
        let absyn = item(0x30, uid("1.2.840.10008.1.1"))          // Verification
        let tsyn = item(0x40, uid("1.2.840.10008.1.2"))           // Implicit VR LE
        let pcRQ = item(0x20, [1, 0, 0, 0] + absyn + tsyn)
        let pcAC = item(0x21, [1, 0, 0, 0] + tsyn)                // result 0 = accepted
        let uinfo = item(0x50, item(0x51, be32(16384))
            + item(0x52, uid("1.2.276.0.7230010.3.0.3.6.4"))
            + item(0x55, Array("OFFIS_DCMTK_364".utf8)))
        let head = be16(1) + [0, 0] + ae(called) + ae(calling) + [UInt8](repeating: 0, count: 32) + appctx
        // A real C-ECHO-RQ command set (Implicit VR LE) in a single command PDV.
        func el(_ elem: Int, _ value: [UInt8]) -> [UInt8] { le16(0) + le16(elem) + le32(value.count) + value }
        var cmd = el(0x0002, uid("1.2.840.10008.1.1\0"))   // Affected SOP Class (even length)
        cmd += el(0x0100, le16(0x0030))                     // Command Field = C-ECHO-RQ
        cmd += el(0x0110, le16(1))                          // Message ID
        cmd += el(0x0800, le16(0x0101))                     // No data set
        let cmdSet = el(0x0000, le32(cmd.count)) + cmd      // Command Group Length
        let pdv: [UInt8] = be32(cmdSet.count + 2) + [1, 0x03] + cmdSet  // PC1, command+last
        return Association(rq: pdu(0x01, head + pcRQ + uinfo),
                           ac: pdu(0x02, head + pcAC + uinfo),
                           pdata: pdu(0x04, pdv),
                           relRQ: pdu(0x05, [0, 0, 0, 0]),
                           relRP: pdu(0x06, [0, 0, 0, 0]))
    }

    // MARK: Ethernet / IPv4 / TCP framing

    static func packet(srcIP: [UInt8], dstIP: [UInt8], srcPort: Int, dstPort: Int,
                       seq: Int, payload: [UInt8]) -> [UInt8] {
        let tcp: [UInt8] = be16(srcPort) + be16(dstPort) + be32(seq) + be32(0)
            + [5 << 4, 0x18] + be16(65535) + be16(0) + be16(0) + payload
        let ip: [UInt8] = [0x45, 0] + be16(20 + tcp.count) + be16(0) + be16(0x4000)
            + [64, 6] + be16(0) + srcIP + dstIP + tcp
        let eth: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x08, 0x00]
        return eth + ip
    }

    struct Wire { let time: Double; let bytes: [UInt8] }

    /// The six packets of the echo association, in order. `payloadOverride`
    /// swaps in arbitrary TCP payloads (e.g. non-DICOM) for negative tests.
    static func exchange(payloadOverride: [[UInt8]]? = nil) -> [Wire] {
        let a = echoAssociation()
        let scu: [UInt8] = [192, 168, 1, 10], scp: [UInt8] = [192, 168, 1, 52]
        let flows: [(up: Bool, data: [UInt8])] = [
            (true, a.rq), (false, a.ac), (true, a.pdata), (false, a.pdata), (true, a.relRQ), (false, a.relRP),
        ]
        var cs = 1000, ss = 5000
        var out: [Wire] = []
        for (i, f) in flows.enumerated() {
            let data = payloadOverride.map { $0[i % $0.count] } ?? f.data
            let p: [UInt8]
            if f.up {
                p = packet(srcIP: scu, dstIP: scp, srcPort: 50000, dstPort: 4242, seq: cs, payload: data)
                cs += data.count
            } else {
                p = packet(srcIP: scp, dstIP: scu, srcPort: 4242, dstPort: 50000, seq: ss, payload: data)
                ss += data.count
            }
            out.append(Wire(time: 1_000_000_000.0 + Double(i) / 10, bytes: p))
        }
        return out
    }

    // MARK: capture files

    static func classicPcap(_ wires: [Wire]) -> Data {
        var out = le32(0xa1b2_c3d4) + le16(2) + le16(4) + le32(0) + le32(0) + le32(65535) + le32(1)
        for w in wires {
            out += le32(Int(w.time)) + le32(Int(w.time.truncatingRemainder(dividingBy: 1) * 1_000_000))
                + le32(w.bytes.count) + le32(w.bytes.count) + w.bytes
        }
        return Data(out)
    }

    static func pcapng(_ wires: [Wire]) -> Data {
        func block(_ type: Int, _ body: [UInt8]) -> [UInt8] {
            let pad = [UInt8](repeating: 0, count: (4 - body.count % 4) % 4)
            let total = 12 + body.count + pad.count
            return le32(type) + le32(total) + body + pad + le32(total)
        }
        var out = block(0x0A0D_0D0A, le32(0x1A2B_3C4D) + le16(1) + le16(0) + le32(0xffff_ffff) + le32(0xffff_ffff))
        out += block(0x0000_0001, le16(1) + le16(0) + le32(65535))   // IDB: Ethernet
        for w in wires {
            let ts = Int(w.time * 1_000_000)
            out += block(0x0000_0006, le32(0) + le32(ts >> 32) + le32(ts & 0xffff_ffff)
                + le32(w.bytes.count) + le32(w.bytes.count) + w.bytes)
        }
        return Data(out)
    }
}
