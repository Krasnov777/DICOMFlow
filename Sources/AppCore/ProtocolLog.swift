import Foundation
import SwiftUI

/// Captured DCMTK protocol events (association negotiation + DIMSE) for the
/// "Protocol" inspector — a decoded, Wireshark-style view of our own traffic.
@MainActor
public final class ProtocolLog: ObservableObject {
    public static let shared = ProtocolLog()

    public enum Kind: String {
        case associateRQ = "A-ASSOCIATE-RQ", associateAC = "A-ASSOCIATE-AC"
        case associateRJ = "A-ASSOCIATE-RJ", release = "A-RELEASE", abort = "A-ABORT"
        case echo = "C-ECHO", store = "C-STORE", find = "C-FIND", move = "C-MOVE", get = "C-GET"
        case dimse = "DIMSE", other = "LOG"
        var color: Color {
            switch self {
            case .associateRQ, .associateAC: return .blue
            case .associateRJ, .abort: return .red
            case .release: return .secondary
            case .echo, .find: return .teal
            case .store, .move, .get: return .green
            case .dimse: return .purple
            case .other: return .secondary
            }
        }
    }

    public struct Event: Identifiable {
        public let id = UUID()
        public let time: Date
        public let level: String
        public let logger: String
        public let message: String
        public let kind: Kind
        /// Association group — increments at every A-ASSOCIATE-RQ.
        public var group: Int = 0
        /// "→" from the association initiator, "←" from the acceptor (pcap only).
        public var direction: String = ""
        /// First meaningful line, for the collapsed row.
        public var title: String {
            message.split(whereSeparator: \.isNewline)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map(String.init) ?? kind.rawValue
        }
    }

    @Published public private(set) var events: [Event] = []
    @Published public var verbose = true { didSet { DCMTKLog.setVerbose(verbose) } }
    private var started = false
    private var currentGroup = 0

    /// Install the capture appender (safe to call repeatedly).
    public func startCapture() {
        guard !started else { return }
        started = true
        DCMTKLog.setVerbose(verbose)
        DCMTKLog.start { level, logger, message in
            // Called on DCMTK threads — hop to the main actor.
            DispatchQueue.main.async {
                ProtocolLog.shared.add(level: level, logger: logger, message: message)
            }
        }
    }

    public func clear() { events.removeAll(); currentGroup = 0 }

    /// Append decoded PDUs imported from a .pcap capture (chronological).
    public func importPDUs(_ pdus: [PcapPDU]) {
        // Track each stream pair's initiator so rows get direction arrows.
        var initiators: [String: String] = [:]   // normalized pair → initiator src
        for p in pdus.sorted(by: { $0.time < $1.time }) {
            let pair = [p.src, p.dst].sorted().joined(separator: "|")
            if p.kind == .associateRQ { currentGroup += 1; initiators[pair] = p.src }
            let dir = initiators[pair].map { $0 == p.src ? "→" : "←" } ?? ""
            let src = p.src.isEmpty ? "" : "\(p.src) → \(p.dst)\n"
            events.append(Event(time: p.time, level: "info", logger: "pcap",
                                message: src + p.title + (p.detail.isEmpty ? "" : "\n" + p.detail),
                                kind: p.kind, group: currentGroup, direction: dir))
        }
        events.sort { $0.time < $1.time }
        if events.count > 5000 { events.removeFirst(events.count - 5000) }
    }

    private func add(level: String, logger: String, message: String) {
        let kind = Self.classify(message)
        // One association emits several RQ-classified log lines ("Requesting
        // Association" + the PDU dump) — only consecutive-distinct RQs start a group.
        if kind == .associateRQ, events.last(where: { $0.kind != .other })?.kind != .associateRQ {
            currentGroup += 1
        }
        events.append(Event(time: Date(), level: level, logger: logger,
                            message: message, kind: kind, group: currentGroup))
        if events.count > 3000 { events.removeFirst(events.count - 3000) }
    }

    private static func classify(_ m: String) -> Kind {
        if m.contains("A-ASSOCIATE-RQ") || m.contains("Requesting Association") { return .associateRQ }
        if m.contains("A-ASSOCIATE-AC") || m.contains("Association Accepted") { return .associateAC }
        if m.contains("A-ASSOCIATE-RJ") || m.contains("Rejected") || m.contains("Association Rejected") { return .associateRJ }
        if m.contains("A-RELEASE") || m.contains("Releasing Association") { return .release }
        if m.contains("A-ABORT") || m.contains("Aborting") || m.contains("ABORT") { return .abort }
        if m.contains("C-ECHO") { return .echo }
        if m.contains("C-STORE") { return .store }
        if m.contains("C-FIND") { return .find }
        if m.contains("C-MOVE") { return .move }
        if m.contains("C-GET") { return .get }
        if m.contains("DIMSE") || m.contains("Command") { return .dimse }
        return .other
    }
}
