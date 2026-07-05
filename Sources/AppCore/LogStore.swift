import Foundation
import SwiftUI

/// In-memory activity log for DIMSE operations, shown in the tester console.
@MainActor
public final class LogStore: ObservableObject {
    public static let shared = LogStore()

    public struct Line: Identifiable {
        public let id = UUID()
        public let time: Date
        public let level: Level
        public let text: String
    }
    public enum Level { case info, ok, warn, error
        var color: Color { switch self { case .info: .secondary; case .ok: .green; case .warn: .orange; case .error: .red } }
        var symbol: String { switch self { case .info: "info.circle"; case .ok: "checkmark.circle"; case .warn: "exclamationmark.triangle"; case .error: "xmark.octagon" } }
    }

    @Published public private(set) var lines: [Line] = []

    public func log(_ text: String, _ level: Level = .info) {
        lines.append(Line(time: Date(), level: level, text: text))
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }
    public func clear() { lines.removeAll() }
}
