import Foundation
import Network

/// HL7 v2 over MLLP (Minimal Lower Layer Protocol). Framing: <VT> message <FS><CR>.
public enum HL7 {
    public static let VT: UInt8 = 0x0B
    public static let FS: UInt8 = 0x1C
    public static let CR: UInt8 = 0x0D

    enum HL7Error: LocalizedError {
        case timeout, noResponse, badPort
        var errorDescription: String? {
            switch self { case .timeout: return "Timed out waiting for ACK."
                          case .noResponse: return "Connection closed with no ACK."
                          case .badPort: return "Invalid port (1–65535)." }
        }
    }

    /// HL7 segments are CR-separated; normalize any LF the user typed.
    public static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
    }
    public static func frame(_ message: String) -> Data {
        var d = Data([VT]); d.append(Data(normalize(message).utf8)); d.append(contentsOf: [FS, CR]); return d
    }
    public static func deframe(_ data: Data) -> String {
        var b = Array(data)
        if b.first == VT { b.removeFirst() }
        while let l = b.last, l == CR || l == FS { b.removeLast() }
        return String(decoding: b, as: UTF8.self)
    }

    /// MSH fields split by the message's field separator (index 0 = "MSH").
    public static func mshFields(_ message: String) -> [String] {
        guard let msh = normalize(message).split(separator: "\r").first(where: { $0.hasPrefix("MSH") })
        else { return [] }
        let arr = Array(msh)
        let sep = arr.count > 3 ? String(arr[3]) : "|"
        return String(msh).components(separatedBy: sep)
    }

    /// Short summary: message type + control id (for the received list).
    public static func summary(_ message: String) -> String {
        let f = mshFields(message)
        let type = f.count > 8 ? f[8] : "?"
        let ctrl = f.count > 9 ? f[9] : ""
        return ctrl.isEmpty ? type : "\(type)  ·  \(ctrl)"
    }

    // MARK: Field-level parsing

    public struct Field: Identifiable {
        public let id = UUID()
        public let label: String     // e.g. "PID-5"
        public let name: String      // e.g. "Patient Name" ("" if unknown)
        public let value: String
    }
    public struct Segment: Identifiable {
        public let id = UUID()
        public let name: String
        public let fields: [Field]
    }

    /// Common field names by segment/position (curated, not exhaustive).
    static let fieldNames: [String: [Int: String]] = [
        "MSH": [1: "Field Separator", 2: "Encoding Characters", 3: "Sending Application",
                4: "Sending Facility", 5: "Receiving Application", 6: "Receiving Facility",
                7: "Date/Time of Message", 9: "Message Type", 10: "Message Control ID",
                11: "Processing ID", 12: "Version ID"],
        "EVN": [1: "Event Type Code", 2: "Recorded Date/Time"],
        "PID": [1: "Set ID", 3: "Patient Identifier List", 5: "Patient Name",
                7: "Date/Time of Birth", 8: "Administrative Sex", 11: "Patient Address",
                13: "Phone Number — Home", 18: "Patient Account Number", 19: "SSN"],
        "PV1": [2: "Patient Class", 3: "Assigned Patient Location", 7: "Attending Doctor",
                10: "Hospital Service", 14: "Admit Source", 18: "Patient Type",
                19: "Visit Number", 44: "Admit Date/Time"],
        "ORC": [1: "Order Control", 2: "Placer Order Number", 3: "Filler Order Number",
                5: "Order Status", 9: "Date/Time of Transaction", 12: "Ordering Provider"],
        "OBR": [1: "Set ID", 2: "Placer Order Number", 3: "Filler Order Number",
                4: "Universal Service Identifier", 7: "Observation Date/Time",
                16: "Ordering Provider", 18: "Placer Field 1 (Accession)"],
        "OBX": [1: "Set ID", 2: "Value Type", 3: "Observation Identifier",
                5: "Observation Value", 6: "Units", 7: "References Range",
                8: "Abnormal Flags", 11: "Observation Result Status"],
        "MSA": [1: "Acknowledgment Code", 2: "Message Control ID", 3: "Text Message"],
        "NTE": [3: "Comment"],
        "AL1": [2: "Allergen Type", 3: "Allergen Description"],
        "DG1": [3: "Diagnosis Code", 4: "Diagnosis Description"],
    ]

    /// Parse a message into segments with HL7-numbered, named fields.
    /// MSH numbering follows the standard: MSH-1 is the field separator itself,
    /// so in `MSH|^~\&|APP|…` MSH-2 = `^~\&`, MSH-3 = APP, …
    public static func parse(_ message: String) -> [Segment] {
        normalize(message).split(separator: "\r").compactMap { line in
            let raw = String(line)
            guard raw.count >= 3 else { return nil }
            let seg = String(raw.prefix(3))
            var fields: [Field] = []
            func add(_ i: Int, _ v: String) {
                guard !v.isEmpty else { return }
                fields.append(Field(label: "\(seg)-\(i)", name: fieldNames[seg]?[i] ?? "", value: v))
            }
            if seg == "MSH" {
                let sep = raw.count > 3 ? String(Array(raw)[3]) : "|"
                add(1, sep)
                let toks = raw.components(separatedBy: sep)
                for (i, t) in toks.enumerated() where i >= 1 { add(i + 1, t) }
            } else {
                let toks = raw.components(separatedBy: "|")
                for (i, t) in toks.enumerated() where i >= 1 { add(i, t) }
            }
            return Segment(name: seg, fields: fields)
        }
    }

    /// Build an HL7 ACK (default AA) that echoes the original control id.
    public static func buildACK(for message: String, code: String = "AA") -> String {
        let f = mshFields(message)
        func g(_ i: Int) -> String { i < f.count ? f[i] : "" }
        let sendingApp = g(2), sendingFac = g(3), recvApp = g(4), recvFac = g(5), ctrl = g(9)
        let df = DateFormatter(); df.dateFormat = "yyyyMMddHHmmss"
        let now = df.string(from: Date())
        // Swap sending/receiving in the reply.
        return "MSH|^~\\&|\(recvApp)|\(recvFac)|\(sendingApp)|\(sendingFac)|\(now)||ACK|\(now)|P|2.3\r"
             + "MSA|\(code)|\(ctrl)\r"
    }

    /// Sample messages for the sender.
    public static let templates: [(name: String, message: String)] = [
        ("ADT^A01 (admit)", """
        MSH|^~\\&|DICOMBENCH|LAB|RIS|HOSP|{TS}||ADT^A01|MSG{N}|P|2.3
        EVN|A01|{TS}
        PID|1||PID12345^^^HOSP^MR||Doe^John^A||19800101|M|||123 Main St^^Metropolis^NY^10001
        PV1|1|I|W^389^1^HOSP||||1234^Attending^Doc|||SUR||||ADM|A0
        """),
        ("ORM^O01 (imaging order)", """
        MSH|^~\\&|RIS|HOSP|PACS|HOSP|{TS}||ORM^O01|MSG{N}|P|2.3
        PID|1||PID12345^^^HOSP^MR||Doe^John^A||19800101|M
        ORC|NW|ORD001|||SC
        OBR|1|ORD001||CT^CT Head^L|||{TS}|||||||||1234^Referring^Doc||ACC001
        """),
        ("ORU^R01 (result)", """
        MSH|^~\\&|LIS|HOSP|EMR|HOSP|{TS}||ORU^R01|MSG{N}|P|2.3
        PID|1||PID12345^^^HOSP^MR||Doe^John^A||19800101|M
        OBR|1|ORD001||GLU^Glucose|||{TS}
        OBX|1|NM|GLU^Glucose||99|mg/dL|70-110|N|||F
        """),
    ]

    /// Fill {TS}/{N} placeholders in a template.
    public static func fill(_ template: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyyMMddHHmmss"
        let n = String(Int(Date().timeIntervalSince1970) % 100000)
        return template.replacingOccurrences(of: "{TS}", with: df.string(from: Date()))
                       .replacingOccurrences(of: "{N}", with: n)
    }
}

/// Sends an HL7 message over MLLP and returns the ACK.
public struct HL7Client {
    public static func send(host: String, port: Int, message: String, timeout: TimeInterval = 10) async throws -> String {
        // UInt16(exactly:) — a plain UInt16(port) traps on out-of-range before
        // any `?? fallback` can run.
        guard let raw = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: raw) else {
            throw HL7.HL7Error.badPort
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        return try await withCheckedThrowingContinuation { cont in
            let lock = NSLock(); var done = false
            func finish(_ r: Result<String, Error>) {
                lock.lock(); defer { lock.unlock() }
                if done { return }; done = true
                conn.cancel(); cont.resume(with: r)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.failure(HL7.HL7Error.timeout)) }
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    conn.send(content: HL7.frame(message), completion: .contentProcessed { err in
                        if let err { finish(.failure(err)); return }
                        receiveACK(conn, Data(), finish)
                    })
                case .failed(let e): finish(.failure(e))
                case .waiting(let e): finish(.failure(e))
                default: break
                }
            }
            conn.start(queue: .global())
        }
    }

    private static func receiveACK(_ conn: NWConnection, _ acc: Data, _ finish: @escaping (Result<String, Error>) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
            var acc2 = acc
            if let data { acc2.append(data) }
            if acc2.contains(HL7.FS) { finish(.success(HL7.deframe(acc2))); return }
            if let err { finish(.failure(err)); return }
            if isComplete {
                finish(acc2.isEmpty ? .failure(HL7.HL7Error.noResponse) : .success(HL7.deframe(acc2)))
                return
            }
            receiveACK(conn, acc2, finish)
        }
    }
}
