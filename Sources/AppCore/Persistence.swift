import Foundation
import SwiftUI

/// A saved remote DICOM node.
public struct PacsProfile: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var host: String
    public var port: Int
    public var aeTitle: String
    public var callingAE: String
}

/// Persists PACS profiles to UserDefaults (JSON).
@MainActor
public final class PacsProfileStore: ObservableObject {
    @Published public private(set) var profiles: [PacsProfile] = []
    private let key = "pacsProfiles"

    public init() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PacsProfile].self, from: data) {
            profiles = decoded
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    public func add(_ p: PacsProfile) { profiles.append(p); persist() }
    public func update(_ p: PacsProfile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p; persist() }
    }
    public func delete(_ p: PacsProfile) { profiles.removeAll { $0.id == p.id }; persist() }
}

/// Pointing device used to drive the viewer, so gestures adapt appropriately.
public enum InputDevice: String, CaseIterable, Sendable, Identifiable {
    case auto, mouse, trackpad
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto: return "Automatic"
        case .mouse: return "Mouse"
        case .trackpad: return "Trackpad"
        }
    }
    /// Whether to treat scroll as a high-resolution (pixel) stream vs. wheel notches.
    /// `.auto` defers to the event's own `hasPreciseScrollingDeltas`.
    public func precise(eventHasPrecise: Bool) -> Bool {
        switch self {
        case .auto: return eventHasPrecise
        case .mouse: return false
        case .trackpad: return true
        }
    }
}

/// How 3D volume rotation maps drag/scroll to camera motion.
public enum RotationMode: String, CaseIterable, Sendable, Identifiable {
    case arcball, turntable
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .arcball: return "Arcball (free)"
        case .turntable: return "Turntable (upright)"
        }
    }
}

/// App-wide defaults (also editable in Settings).
public enum Defaults {
    @AppStorage("defaultCallingAE") public static var callingAE = "DICOMBENCH"
    @AppStorage("defaultSCPAETitle") public static var scpAETitle = "DICOMBENCH"
    @AppStorage("defaultSCPPort") public static var scpPort = 11112
    @AppStorage("defaultHost") public static var host = "127.0.0.1"
    @AppStorage("defaultPort") public static var port = 4242
    @AppStorage("defaultCalledAE") public static var calledAE = "ORTHANC"
    @AppStorage("inputDevice") public static var inputDevice = InputDevice.auto
    @AppStorage("naturalScroll") public static var naturalScroll = true
    @AppStorage("rotationMode") public static var rotationMode = RotationMode.arcball
    @AppStorage("dicomWebURL") public static var dicomWebURL = "http://127.0.0.1:8042/dicom-web"
    @AppStorage("dicomWebUser") public static var dicomWebUser = "admin"
    /// Timeout (s) for connect / association / each DIMSE message and web requests.
    @AppStorage("networkTimeout") public static var networkTimeout = 15
    /// DIMSE TLS: use TLS for outgoing SCU connections.
    @AppStorage("dimseTLS") public static var dimseTLS = false
    /// DIMSE TLS: verify the peer certificate (against tlsCAPath if set).
    @AppStorage("tlsVerify") public static var tlsVerify = false
    /// PEM file with trusted CA / self-signed server certificate(s).
    @AppStorage("tlsCAPath") public static var tlsCAPath = ""
}
