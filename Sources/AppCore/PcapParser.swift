import Foundation

/// One decoded DICOM upper-layer PDU from a capture.
public struct PcapPDU {
    public let time: Date
    public let src: String
    public let dst: String
    public let kind: ProtocolLog.Kind
    public let title: String
    public let detail: String
}

public enum PcapError: LocalizedError {
    case tooShort, badMagic, noDicom
    public var errorDescription: String? {
        switch self {
        case .tooShort: return "File is too short to be a pcap capture."
        case .badMagic: return "Not a pcap/pcapng file (bad magic)."
        case .noDicom: return "No DICOM (upper-layer PDU) streams found in the capture."
        }
    }
}

/// Parses classic pcap and pcapng captures, reassembles TCP streams, and dissects
/// DICOM upper-layer PDUs (association negotiation, P-DATA, release, abort).
public enum PcapParser {

    // MARK: Public entry

    public static func parse(_ data: Data) throws -> [PcapPDU] {
        let b = [UInt8](data)
        guard b.count >= 24 else { throw PcapError.tooShort }
        let rawMagic = le32(b, 0)
        let packets: [Packet]
        if rawMagic == 0xa1b2_c3d4 || rawMagic == 0xd4c3_b2a1 {
            packets = parseClassic(b, swapped: rawMagic == 0xd4c3_b2a1)
        } else if rawMagic == 0x0a0d_0d0a {
            packets = parsePcapng(b)
        } else {
            throw PcapError.badMagic
        }

        // Reassemble per directional TCP stream.
        var streams: [String: Stream] = [:]
        for p in packets {
            guard let seg = tcpSegment(p) else { continue }
            let key = "\(seg.src)>\(seg.dst)"
            if streams[key] == nil { streams[key] = Stream(src: seg.src, dst: seg.dst) }
            streams[key]!.segments.append(seg)
        }

        var pdus: [PcapPDU] = []
        for stream in streams.values {
            let (bytes, offTimes) = stream.reassemble()
            guard bytes.count >= 6, (1...7).contains(bytes[0]) else { continue }
            pdus.append(contentsOf: dissect(bytes, offTimes: offTimes, src: stream.src, dst: stream.dst))
        }
        if pdus.isEmpty { throw PcapError.noDicom }
        return pdus.sorted { $0.time < $1.time }
    }

    // MARK: pcap file formats

    private struct Packet { let time: Double; let link: Int; let data: [UInt8] }

    private static func parseClassic(_ b: [UInt8], swapped: Bool) -> [Packet] {
        let link = Int(u32(b, 20, swapped))
        var out: [Packet] = []; var o = 24
        while o + 16 <= b.count {
            let tsSec = u32(b, o, swapped), tsUsec = u32(b, o + 4, swapped)
            let inclLen = Int(u32(b, o + 8, swapped)); o += 16
            guard o + inclLen <= b.count, inclLen >= 0, inclLen < 10_000_000 else { break }
            out.append(Packet(time: Double(tsSec) + Double(tsUsec) / 1_000_000,
                              link: link, data: Array(b[o..<o + inclLen])))
            o += inclLen
        }
        return out
    }

    private static func parsePcapng(_ b: [UInt8]) -> [Packet] {
        // Byte-order from the section header block's magic.
        let swapped = le32(b, 8) != 0x1a2b_3c4d
        var out: [Packet] = []; var links: [Int] = []; var o = 0
        while o + 12 <= b.count {
            let type = u32(b, o, swapped)
            let total = Int(u32(b, o + 4, swapped))
            guard total >= 12, o + total <= b.count else { break }
            let body = o + 8
            switch type {
            case 0x0000_0001: // Interface Description Block
                links.append(Int(u16(b, body, swapped)))
            case 0x0000_0006: // Enhanced Packet Block
                let ifID = Int(u32(b, body, swapped))
                let tsHigh = u32(b, body + 4, swapped), tsLow = u32(b, body + 8, swapped)
                let capLen = Int(u32(b, body + 12, swapped))
                let start = body + 20
                guard start + capLen <= o + total else { break }
                let ts = (UInt64(tsHigh) << 32 | UInt64(tsLow))
                out.append(Packet(time: Double(ts) / 1_000_000,
                                  link: links.indices.contains(ifID) ? links[ifID] : 1,
                                  data: Array(b[start..<start + capLen])))
            case 0x0000_0003: // Simple Packet Block
                let origLen = Int(u32(b, body, swapped))
                let start = body + 4
                guard start + origLen <= o + total else { break }
                out.append(Packet(time: 0, link: links.first ?? 1, data: Array(b[start..<start + origLen])))
            default: break
            }
            o += total
        }
        return out
    }

    // MARK: Link / IP / TCP

    private struct Segment { let src: String; let dst: String; let seq: UInt32; let time: Double; let payload: [UInt8] }

    private final class Stream {
        let src: String; let dst: String
        var segments: [Segment] = []
        init(src: String, dst: String) { self.src = src; self.dst = dst }

        /// Concatenate payloads in sequence order; return bytes + (offset→time) marks.
        func reassemble() -> ([UInt8], [(off: Int, time: Double)]) {
            let sorted = segments.sorted { $0.seq < $1.seq }
            var bytes: [UInt8] = []; var marks: [(Int, Double)] = []
            var next: UInt32? = nil
            for s in sorted {
                if let n = next, s.seq < n {                 // overlap / retransmit
                    let skip = Int(n &- s.seq)
                    if skip >= s.payload.count { continue }
                    marks.append((bytes.count, s.time)); bytes.append(contentsOf: s.payload[skip...])
                    next = s.seq &+ UInt32(s.payload.count)
                } else {
                    marks.append((bytes.count, s.time)); bytes.append(contentsOf: s.payload)
                    next = s.seq &+ UInt32(s.payload.count)
                }
            }
            return (bytes, marks)
        }
    }

    private static func tcpSegment(_ p: Packet) -> Segment? {
        guard let (ipOff, ipVer) = ipStart(p) else { return nil }
        let d = p.data
        var proto = 0, srcIP = "", dstIP = "", tcpOff = 0, ipEnd = d.count
        if ipVer == 4 {
            guard ipOff + 20 <= d.count else { return nil }
            let ihl = Int(d[ipOff] & 0x0F) * 4
            proto = Int(d[ipOff + 9])
            srcIP = "\(d[ipOff+12]).\(d[ipOff+13]).\(d[ipOff+14]).\(d[ipOff+15])"
            dstIP = "\(d[ipOff+16]).\(d[ipOff+17]).\(d[ipOff+18]).\(d[ipOff+19])"
            let total = be16(d, ipOff + 2)
            if total > 0 && ipOff + total <= d.count { ipEnd = ipOff + total }
            tcpOff = ipOff + ihl
        } else if ipVer == 6 {
            guard ipOff + 40 <= d.count else { return nil }
            proto = Int(d[ipOff + 6])
            srcIP = ipv6(d, ipOff + 8); dstIP = ipv6(d, ipOff + 24)
            tcpOff = ipOff + 40
        } else { return nil }
        guard proto == 6, tcpOff + 20 <= d.count else { return nil }
        let srcPort = be16(d, tcpOff), dstPort = be16(d, tcpOff + 2)
        let seq = be32(d, tcpOff + 4)
        let dataOff = Int((d[tcpOff + 12] >> 4)) * 4
        let payStart = tcpOff + dataOff
        guard payStart <= ipEnd, payStart <= d.count else { return nil }
        let end = min(ipEnd, d.count)
        let payload = payStart < end ? Array(d[payStart..<end]) : []
        guard !payload.isEmpty else { return nil }
        return Segment(src: "\(srcIP):\(srcPort)", dst: "\(dstIP):\(dstPort)", seq: seq, time: p.time, payload: payload)
    }

    /// Returns (offset of IP header, IP version) after stripping the link layer.
    private static func ipStart(_ p: Packet) -> (Int, Int)? {
        let d = p.data
        func ver(_ o: Int) -> Int { o < d.count ? Int(d[o] >> 4) : 0 }
        switch p.link {
        case 1: // Ethernet
            guard d.count >= 14 else { return nil }
            var eth = be16(d, 12); var off = 14
            if eth == 0x8100, d.count >= 18 { eth = be16(d, 16); off = 18 } // VLAN
            if eth == 0x0800 { return (off, 4) }
            if eth == 0x86DD { return (off, 6) }
            return nil
        case 0: // BSD loopback (NULL) — 4-byte host-endian family
            guard d.count >= 4 else { return nil }
            let fam = Int(d[0]) | Int(d[1]) << 8
            return (4, fam == 2 ? 4 : 6)
        case 108: // OpenBSD loopback — 4-byte big-endian family
            guard d.count >= 4 else { return nil }
            return (4, Int(d[3]) == 2 ? 4 : 6)
        case 101: // RAW IP
            return (0, ver(0))
        case 113: // Linux cooked v1
            guard d.count >= 16 else { return nil }
            return (16, be16(d, 14) == 0x86DD ? 6 : 4)
        default:
            return (0, ver(0))   // best effort: assume the payload begins with IP
        }
    }

    // MARK: DICOM PDU dissection

    private static func dissect(_ a: [UInt8], offTimes: [(off: Int, time: Double)],
                                src: String, dst: String) -> [PcapPDU] {
        var out: [PcapPDU] = []; var off = 0; let n = a.count
        func timeAt(_ o: Int) -> Date {
            var t = offTimes.first?.time ?? 0
            for m in offTimes where m.off <= o { t = m.time }
            return Date(timeIntervalSince1970: t)
        }
        while off + 6 <= n {
            let type = a[off]
            guard (1...7).contains(type) else { break }
            let len = Int(be32(a, off + 2))
            let bodyStart = off + 6, bodyEnd = bodyStart + len
            guard bodyEnd <= n, len >= 0 else { break }
            let body = Array(a[bodyStart..<bodyEnd])
            let decoded = decodePDU(type: type, body: body)
            out.append(PcapPDU(time: timeAt(off), src: src, dst: dst,
                               kind: decoded.kind, title: decoded.title, detail: decoded.detail))
            off = bodyEnd
        }
        return out
    }

    private static func decodePDU(type: UInt8, body: [UInt8]) -> (kind: ProtocolLog.Kind, title: String, detail: String) {
        switch type {
        case 1, 2: return decodeAssociate(body, request: type == 1)
        case 3:    return decodeReject(body)
        case 4:    return decodePData(body)
        case 5:    return (.release, "A-RELEASE-RQ", "")
        case 6:    return (.release, "A-RELEASE-RP", "")
        case 7:    return decodeAbort(body)
        default:   return (.other, "PDU type \(type)", "")
        }
    }

    private static func decodeAssociate(_ b: [UInt8], request: Bool) -> (ProtocolLog.Kind, String, String) {
        guard b.count >= 68 else { return (request ? .associateRQ : .associateAC, request ? "A-ASSOCIATE-RQ" : "A-ASSOCIATE-AC", "") }
        let called = ascii(b, 4, 16), calling = ascii(b, 20, 16)
        var lines: [String] = []
        var contexts = 0
        var o = 68
        while o + 4 <= b.count {
            let item = b[o]; let ilen = be16(b, o + 2); let iStart = o + 4
            guard iStart + ilen <= b.count else { break }
            let idata = Array(b[iStart..<iStart + ilen])
            switch item {
            case 0x10:
                lines.append("App context: \(uidName(String(decoding: idata, as: UTF8.self)))")
            case 0x20, 0x21: // presentation context (RQ / AC)
                contexts += 1
                let pcID = idata.first ?? 0
                var abs = "", ts: [String] = [], result = ""
                var so = (item == 0x20) ? 4 : 4
                if item == 0x21, idata.count >= 3 { result = pcResult(idata[2]) }
                while so + 4 <= idata.count {
                    let sub = idata[so]; let slen = be16(idata, so + 2); let sStart = so + 4
                    guard sStart + slen <= idata.count else { break }
                    let uid = String(decoding: idata[sStart..<sStart + slen], as: UTF8.self)
                    if sub == 0x30 { abs = uid } else if sub == 0x40 { ts.append(uid) }
                    so = sStart + slen
                }
                var line = "PC \(pcID): "
                if !abs.isEmpty { line += uidName(abs) }
                if !result.isEmpty { line += " [\(result)]" }
                if !ts.isEmpty { line += " · " + ts.map(uidName).joined(separator: ", ") }
                lines.append(line)
            case 0x50: // user information
                var so = 0
                while so + 4 <= idata.count {
                    let sub = idata[so]; let slen = be16(idata, so + 2); let sStart = so + 4
                    guard sStart + slen <= idata.count else { break }
                    if sub == 0x51, slen == 4 { lines.append("Max PDU length: \(be32(idata, sStart))") }
                    if sub == 0x52 { lines.append("Impl class UID: \(String(decoding: idata[sStart..<sStart+slen], as: UTF8.self))") }
                    if sub == 0x55 { lines.append("Impl version: \(String(decoding: idata[sStart..<sStart+slen], as: UTF8.self))") }
                    so = sStart + slen
                }
            default: break
            }
            o = iStart + ilen
        }
        let title = (request ? "A-ASSOCIATE-RQ" : "A-ASSOCIATE-AC") + "  \(calling) → \(called)  (\(contexts) PC)"
        return (request ? .associateRQ : .associateAC, title, lines.joined(separator: "\n"))
    }

    private static func decodeReject(_ b: [UInt8]) -> (ProtocolLog.Kind, String, String) {
        guard b.count >= 4 else { return (.associateRJ, "A-ASSOCIATE-RJ", "") }
        let result = b[1] == 1 ? "rejected-permanent" : "rejected-transient"
        let source = ["", "service-user", "service-provider (ACSE)", "service-provider (presentation)"]
        let src = Int(b[2]) < source.count ? source[Int(b[2])] : "source \(b[2])"
        return (.associateRJ, "A-ASSOCIATE-RJ  (\(result))", "Source: \(src)\nReason code: \(b[3])")
    }

    private static func decodeAbort(_ b: [UInt8]) -> (ProtocolLog.Kind, String, String) {
        guard b.count >= 4 else { return (.abort, "A-ABORT", "") }
        let source = b[2] == 0 ? "service-user" : "service-provider"
        let reasons = ["not-specified", "unrecognized-PDU", "unexpected-PDU", "", "unrecognized-PDU-parameter", "unexpected-PDU-parameter", "invalid-PDU-parameter"]
        let reason = Int(b[3]) < reasons.count ? reasons[Int(b[3])] : "reason \(b[3])"
        return (.abort, "A-ABORT  (\(source))", "Reason: \(reason)")
    }

    private static let commandNames: [Int: String] = [
        0x0001: "C-STORE-RQ", 0x8001: "C-STORE-RSP",
        0x0010: "C-GET-RQ", 0x8010: "C-GET-RSP",
        0x0020: "C-FIND-RQ", 0x8020: "C-FIND-RSP",
        0x0021: "C-MOVE-RQ", 0x8021: "C-MOVE-RSP",
        0x0030: "C-ECHO-RQ", 0x8030: "C-ECHO-RSP",
        0x0FFF: "C-CANCEL-RQ",
        0x0100: "N-EVENT-REPORT-RQ", 0x8100: "N-EVENT-REPORT-RSP",
        0x0110: "N-GET-RQ", 0x8110: "N-GET-RSP",
        0x0120: "N-SET-RQ", 0x8120: "N-SET-RSP",
        0x0130: "N-ACTION-RQ", 0x8130: "N-ACTION-RSP",
        0x0140: "N-CREATE-RQ", 0x8140: "N-CREATE-RSP",
        0x0150: "N-DELETE-RQ", 0x8150: "N-DELETE-RSP",
    ]

    private static func statusName(_ s: Int) -> String {
        switch s {
        case 0x0000: return "Success"
        case 0xFF00, 0xFF01: return "Pending"
        case 0xFE00: return "Cancel"
        case 0x0107: return "Attribute List Error"
        default: return s < 0x1000 ? String(format: "0x%04X", s)
                                   : String(format: "Failure (0x%04X)", s)
        }
    }

    private static func kindForCommand(_ name: String) -> ProtocolLog.Kind {
        if name.hasPrefix("C-ECHO") { return .echo }
        if name.hasPrefix("C-STORE") { return .store }
        if name.hasPrefix("C-FIND") { return .find }
        if name.hasPrefix("C-MOVE") { return .move }
        if name.hasPrefix("C-GET") { return .get }
        return .dimse
    }

    private static func decodePData(_ b: [UInt8]) -> (ProtocolLog.Kind, String, String) {
        var o = 0, pdvs = 0, dataPDVs = 0
        var pcID: UInt8 = 0
        var cmdBytes: [UInt8] = []
        while o + 4 <= b.count {
            let plen = Int(be32(b, o)); let start = o + 4
            guard plen >= 2, start + plen <= b.count else { break }
            pdvs += 1; pcID = b[start]
            let mch = b[start + 1]
            let frag = Array(b[(start + 2)..<(start + plen)])
            if mch & 0x01 != 0 { cmdBytes += frag } else { dataPDVs += 1 }
            o = start + plen
        }
        guard !cmdBytes.isEmpty else {
            return (.dimse, "P-DATA-TF  (\(pdvs) PDV, PC \(pcID), data)", "")
        }

        // The command set is always Implicit VR Little Endian — walk group 0000.
        var field: Int?, msgID: Int?, respTo: Int?, status: Int?
        var sop = "", moveDest = ""
        var i = 0
        while i + 8 <= cmdBytes.count {
            let g = Int(cmdBytes[i]) | Int(cmdBytes[i + 1]) << 8
            let e = Int(cmdBytes[i + 2]) | Int(cmdBytes[i + 3]) << 8
            let len = Int(le32(cmdBytes, i + 4))
            i += 8
            guard len >= 0, i + len <= cmdBytes.count else { break }
            if g == 0x0000 {
                let val = Array(cmdBytes[i..<i + len])
                func u16v() -> Int? { val.count >= 2 ? Int(val[0]) | Int(val[1]) << 8 : nil }
                func str() -> String {
                    String(decoding: val, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                }
                switch e {
                case 0x0002: sop = str()          // Affected SOP Class UID
                case 0x0100: field = u16v()       // Command Field
                case 0x0110: msgID = u16v()       // Message ID
                case 0x0120: respTo = u16v()      // Message ID Being Responded To
                case 0x0600: moveDest = str()     // Move Destination
                case 0x0900: status = u16v()      // Status
                default: break
                }
            }
            i += len
        }

        let name = field.flatMap { commandNames[$0] }
            ?? field.map { String(format: "command 0x%04X", $0) } ?? "command"
        var title = "\(name)"
        if let m = msgID { title += "  ·  MsgID \(m)" }
        if let r = respTo { title += "  ·  re MsgID \(r)" }
        if let s = status { title += "  ·  \(statusName(s))" }
        if dataPDVs > 0 { title += "  ·  +\(dataPDVs) data PDV" }
        var detail: [String] = ["Presentation context \(pcID)"]
        if !sop.isEmpty { detail.append("SOP Class: \(uidName(sop))") }
        if !moveDest.isEmpty { detail.append("Move destination: \(moveDest)") }
        return (kindForCommand(name), title, detail.joined(separator: "\n"))
    }

    // MARK: Helpers

    private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24
    }
    private static func u32(_ b: [UInt8], _ o: Int, _ swap: Bool) -> UInt32 {
        let v = le32(b, o); return swap ? v.byteSwapped : v
    }
    private static func u16(_ b: [UInt8], _ o: Int, _ swap: Bool) -> UInt16 {
        guard o + 2 <= b.count else { return 0 }
        let v = UInt16(b[o]) | UInt16(b[o+1]) << 8; return swap ? v.byteSwapped : v
    }
    private static func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) << 24 | UInt32(b[o+1]) << 16 | UInt32(b[o+2]) << 8 | UInt32(b[o+3])
    }
    private static func be16(_ b: [UInt8], _ o: Int) -> Int {
        guard o + 2 <= b.count else { return 0 }
        return Int(b[o]) << 8 | Int(b[o+1])
    }
    private static func ascii(_ b: [UInt8], _ o: Int, _ len: Int) -> String {
        guard o + len <= b.count else { return "" }
        return String(decoding: b[o..<o+len], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
    private static func ipv6(_ b: [UInt8], _ o: Int) -> String {
        guard o + 16 <= b.count else { return "::" }
        return stride(from: 0, to: 16, by: 2).map { String(format: "%x", Int(u16(b, o + $0, false).byteSwapped)) }
            .joined(separator: ":")
    }
    private static func pcResult(_ v: UInt8) -> String {
        ["accepted", "user-rejection", "no-reason", "abstract-syntax-not-supported", "transfer-syntaxes-not-supported"]
            .indices.contains(Int(v)) ? ["accepted", "user-rejection", "no-reason", "abstract-syntax-not-supported", "transfer-syntaxes-not-supported"][Int(v)] : "result \(v)"
    }

    /// Friendly name for the most common DICOM UIDs (falls back to the raw UID).
    private static func uidName(_ uid: String) -> String {
        let u = uid.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        return uidMap[u] ?? u
    }
    private static let uidMap: [String: String] = [
        "1.2.840.10008.1.1": "Verification SOP Class",
        "1.2.840.10008.1.2": "Implicit VR Little Endian",
        "1.2.840.10008.1.2.1": "Explicit VR Little Endian",
        "1.2.840.10008.1.2.2": "Explicit VR Big Endian",
        "1.2.840.10008.1.2.4.50": "JPEG Baseline",
        "1.2.840.10008.1.2.4.57": "JPEG Lossless",
        "1.2.840.10008.1.2.4.70": "JPEG Lossless SV1",
        "1.2.840.10008.1.2.4.90": "JPEG 2000 Lossless",
        "1.2.840.10008.1.2.4.91": "JPEG 2000",
        "1.2.840.10008.1.2.5": "RLE Lossless",
        "1.2.840.10008.5.1.4.1.1.2": "CT Image Storage",
        "1.2.840.10008.5.1.4.1.1.4": "MR Image Storage",
        "1.2.840.10008.5.1.4.1.1.6.1": "US Image Storage",
        "1.2.840.10008.5.1.4.1.1.7": "Secondary Capture Image Storage",
        "1.2.840.10008.5.1.4.1.1.1": "CR Image Storage",
        "1.2.840.10008.5.1.4.1.1.128": "PET Image Storage",
        "1.2.840.10008.5.1.4.1.2.1.1": "Patient Root Q/R FIND",
        "1.2.840.10008.5.1.4.1.2.1.2": "Patient Root Q/R MOVE",
        "1.2.840.10008.5.1.4.1.2.2.1": "Study Root Q/R FIND",
        "1.2.840.10008.5.1.4.1.2.2.2": "Study Root Q/R MOVE",
        "1.2.840.10008.5.1.4.1.2.2.3": "Study Root Q/R GET",
        "1.2.840.10008.5.1.4.31": "Modality Worklist FIND",
        "1.2.840.10008.3.1.2.3.3": "Modality Performed Procedure Step",
        "1.2.840.10008.1.20.1": "Storage Commitment Push Model",
    ]
}
