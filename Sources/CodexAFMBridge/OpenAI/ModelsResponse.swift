import Foundation

/// GET /v1/models response. A small static list advertising the AFM model and
/// any aliases the bridge is willing to accept.
public struct ModelsList: Codable, Sendable, Equatable {
    public var object: String
    public var data: [Model]

    public init(object: String = "list", data: [Model]) {
        self.object = object
        self.data = data
    }

    public static let `default` = ModelsList(
        data: [
            Model(id: "apple-foundation-local", ownedBy: "apple-foundation-models-local"),
            Model(id: "apple-foundation-fast", ownedBy: "apple-foundation-models-local"),
            Model(id: "apple-foundation-structured", ownedBy: "apple-foundation-models-local")
        ]
    )
}

public struct Model: Codable, Sendable, Equatable {
    public var id: String
    public var object: String
    public var created: Int
    public var owned_by: String

    public init(id: String, object: String = "model", created: Int = 0, ownedBy: String) {
        self.id = id
        self.object = object
        self.created = created
        self.owned_by = ownedBy
    }

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case owned_by
    }
}

/// Models the bridge accepts (the canonical id plus aliases).
public enum SupportedModels {
    public static let canonical = "apple-foundation-local"
    public static let aliases: Set<String> = [
        "apple-foundation-local",
        "apple-foundation-fast",
        "apple-foundation-structured"
    ]

    public static func isSupported(_ model: String) -> Bool {
        aliases.contains(model)
    }
}
