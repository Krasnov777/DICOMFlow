import Foundation

// Result DTOs shared by the native DicomEngine and the tester views. (The old
// *RequestBody types that serialized calls to the removed Python sidecar were
// deleted — the engine now calls DCMTK in-process.)

// MARK: - Responses

public struct EchoResult: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let echoStatus: Int?
    public let supportedSOPClasses: [String]?
    public init(success: Bool, message: String?, echoStatus: Int?, supportedSOPClasses: [String]?) {
        self.success = success; self.message = message
        self.echoStatus = echoStatus; self.supportedSOPClasses = supportedSOPClasses
    }
}

public struct StoreItem: Decodable, Sendable {
    public let file: String
    public let ok: Bool
    public let status: Int?
    public let error: String?
}
public struct StoreResult: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let sent: Int?
    public let total: Int?
    public let results: [StoreItem]?
    public init(success: Bool, message: String?, sent: Int?, total: Int?, results: [StoreItem]?) {
        self.success = success; self.message = message
        self.sent = sent; self.total = total; self.results = results
    }
}

public struct QueryResult: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let count: Int?
    public let results: [[String: String]]?
    public init(success: Bool, message: String?, count: Int?, results: [[String: String]]?) {
        self.success = success; self.message = message; self.count = count; self.results = results
    }
}

/// One row of a negotiation probe: a SOP class and the transfer syntaxes the
/// peer accepted for it (empty = context rejected).
public struct ProbeContext: Decodable, Sendable, Identifiable {
    public let sopClass: String
    public let sopName: String
    public let accepted: Bool
    public let transferSyntaxes: [String]
    public var id: String { sopClass }
    public init(sopClass: String, sopName: String, accepted: Bool, transferSyntaxes: [String]) {
        self.sopClass = sopClass; self.sopName = sopName
        self.accepted = accepted; self.transferSyntaxes = transferSyntaxes
    }
}

public struct ProbeResult: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let contexts: [ProbeContext]
    public init(success: Bool, message: String?, contexts: [ProbeContext]) {
        self.success = success; self.message = message; self.contexts = contexts
    }
}

// --- DICOMDIR (media directory) hierarchy ---
public struct DicomDirSeries: Sendable, Identifiable {
    public let uid, modality, number, description: String
    public let files: [String]
    public var id: String { uid }
    public var count: Int { files.count }
    public init(uid: String, modality: String, number: String, description: String, files: [String]) {
        self.uid = uid; self.modality = modality; self.number = number
        self.description = description; self.files = files
    }
}
public struct DicomDirStudy: Sendable, Identifiable {
    public let uid, date, description: String
    public let series: [DicomDirSeries]
    public var id: String { uid }
    public init(uid: String, date: String, description: String, series: [DicomDirSeries]) {
        self.uid = uid; self.date = date; self.description = description; self.series = series
    }
}
public struct DicomDirPatient: Sendable, Identifiable {
    public let name, patientID: String
    public let studies: [DicomDirStudy]
    public var id: String { name + "|" + patientID }
    public init(name: String, patientID: String, studies: [DicomDirStudy]) {
        self.name = name; self.patientID = patientID; self.studies = studies
    }
}
public struct DicomDirResult: Sendable {
    public let success: Bool
    public let message: String
    public let baseDir: String
    public let patients: [DicomDirPatient]
    public init(success: Bool, message: String, baseDir: String, patients: [DicomDirPatient]) {
        self.success = success; self.message = message; self.baseDir = baseDir; self.patients = patients
    }
}

public struct RetrieveResult: Decodable, Sendable {
    public let success: Bool
    public let message: String?
    public let method: String?
    public let received: Int?
    public let receivedDir: String?
    public init(success: Bool, message: String?, method: String?, received: Int?, receivedDir: String?) {
        self.success = success; self.message = message
        self.method = method; self.received = received; self.receivedDir = receivedDir
    }
}

public struct SCPStatus: Decodable, Sendable {
    public let running: Bool
    public let aeTitle: String
    public let port: Int
    public let receivedCount: Int
    public let receivedDir: String
    public init(running: Bool, aeTitle: String, port: Int, receivedCount: Int, receivedDir: String) {
        self.running = running; self.aeTitle = aeTitle; self.port = port
        self.receivedCount = receivedCount; self.receivedDir = receivedDir
    }
}

public struct ReceivedItem: Decodable, Sendable, Identifiable {
    public let path: String
    public let patient: String
    public let studyUID: String
    public let seriesUID: String
    public let sopUID: String
    public let modality: String
    public var id: String { sopUID }
    public init(path: String, patient: String, studyUID: String,
                seriesUID: String, sopUID: String, modality: String) {
        self.path = path; self.patient = patient; self.studyUID = studyUID
        self.seriesUID = seriesUID; self.sopUID = sopUID; self.modality = modality
    }
}
public struct ReceivedList: Decodable, Sendable {
    public let receivedDir: String
    public let items: [ReceivedItem]
    public init(receivedDir: String, items: [ReceivedItem]) {
        self.receivedDir = receivedDir; self.items = items
    }
}
