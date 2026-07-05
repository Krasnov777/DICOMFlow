import Foundation

/// Top-level mode the app is in. The whole UI swaps between these two.
enum AppMode: String, CaseIterable, Identifiable {
    case tester = "Tester"
    case viewer = "Viewer"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tester: return "network"
        case .viewer: return "cube.transparent"
        }
    }
}
