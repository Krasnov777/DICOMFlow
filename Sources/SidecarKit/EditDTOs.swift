import Foundation

public struct EditOp: Encodable, Sendable {
    public let keyword: String
    public let value: String?     // nil = delete
    public init(keyword: String, value: String?) { self.keyword = keyword; self.value = value }
}

public struct EditTagsResult: Decodable, Sendable {
    public let success: Bool
    public let outputPath: String
    public let applied: [[String: String]]
    public let skipped: [[String: String]]
    public init(success: Bool, outputPath: String,
                applied: [[String: String]], skipped: [[String: String]]) {
        self.success = success; self.outputPath = outputPath
        self.applied = applied; self.skipped = skipped
    }
}

public struct AnonProfileDTO: Encodable, Sendable {
    public var replacePatientName: String?
    public var replacePatientID: String?
    public var clearDates: Bool
    public var clearIdentifiers: Bool
    public var removePrivateTags: Bool
    public var regenerateUIDs: Bool
    // PS3.15 Basic Application Level Confidentiality Profile + retain/clean options.
    public var basicProfile: Bool
    public var retainDates: Bool
    public var retainDeviceIdentity: Bool
    public var retainPatientChars: Bool
    public var cleanDescriptors: Bool
    public init(replacePatientName: String? = "ANON", replacePatientID: String? = "ANON-ID",
                clearDates: Bool = true, clearIdentifiers: Bool = true,
                removePrivateTags: Bool = true, regenerateUIDs: Bool = true,
                basicProfile: Bool = true, retainDates: Bool = false,
                retainDeviceIdentity: Bool = false, retainPatientChars: Bool = false,
                cleanDescriptors: Bool = true) {
        self.replacePatientName = replacePatientName
        self.replacePatientID = replacePatientID
        self.clearDates = clearDates
        self.clearIdentifiers = clearIdentifiers
        self.removePrivateTags = removePrivateTags
        self.regenerateUIDs = regenerateUIDs
        self.basicProfile = basicProfile
        self.retainDates = retainDates
        self.retainDeviceIdentity = retainDeviceIdentity
        self.retainPatientChars = retainPatientChars
        self.cleanDescriptors = cleanDescriptors
    }
}

public struct AnonResult: Decodable, Sendable {
    public let success: Bool
    public let processed: Int
    public let outputDir: String
    public let uidsRemapped: Int
    public let warnings: [String]
    public init(success: Bool, processed: Int, outputDir: String,
                uidsRemapped: Int, warnings: [String]) {
        self.success = success; self.processed = processed; self.outputDir = outputDir
        self.uidsRemapped = uidsRemapped; self.warnings = warnings
    }
}
