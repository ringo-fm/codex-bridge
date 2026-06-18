import Foundation

/// Per-request diagnostics. Records fields the bridge ignored or rejected so
/// callers can tune the compatibility profile. Not persisted; only surfaced
/// in debug logs and (optionally) in response headers.
public struct Diagnostics: Sendable {
    public var ignoredFields: [String]
    public var unsupportedInputTypes: [String]
    public var unsupportedToolTypes: [String]
    public var estimatedUsage: Bool
    public var notes: [String]

    public init(
        ignoredFields: [String] = [],
        unsupportedInputTypes: [String] = [],
        unsupportedToolTypes: [String] = [],
        estimatedUsage: Bool = false,
        notes: [String] = []
    ) {
        self.ignoredFields = ignoredFields
        self.unsupportedInputTypes = unsupportedInputTypes
        self.unsupportedToolTypes = unsupportedToolTypes
        self.estimatedUsage = estimatedUsage
        self.notes = notes
    }

    public mutating func ignore(_ field: String, reason: String = "") {
        ignoredFields.append(field)
        if !reason.isEmpty { notes.append("ignored \(field): \(reason)") }
    }

    public mutating func unsupportedInput(_ type: String) {
        unsupportedInputTypes.append(type)
    }

    public mutating func unsupportedTool(_ type: String) {
        unsupportedToolTypes.append(type)
    }

    public mutating func note(_ s: String) {
        notes.append(s)
    }

    public var isEmpty: Bool {
        ignoredFields.isEmpty && unsupportedInputTypes.isEmpty
            && unsupportedToolTypes.isEmpty && notes.isEmpty && !estimatedUsage
    }
}
