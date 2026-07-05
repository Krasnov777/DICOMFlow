import Foundation

public struct TagItem: Decodable, Sendable {
    public let tag: String
    public let keyword: String
    public let name: String
    public let vr: String
    public let value: String
}

public struct ReadTagsResponse: Decodable, Sendable {
    public let path: String
    public let transferSyntax: String?
    public let count: Int
    public let tags: [TagItem]
    public init(path: String, transferSyntax: String?, count: Int, tags: [TagItem]) {
        self.path = path; self.transferSyntax = transferSyntax
        self.count = count; self.tags = tags
    }
}
