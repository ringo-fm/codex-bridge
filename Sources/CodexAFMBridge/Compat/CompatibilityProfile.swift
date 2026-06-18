import Foundation

/// The compatibility profile describes which Responses API features the bridge
/// currently honors. v0 is `codex-minimal`: text-only, streaming, estimated
/// usage, no images/files/tools/shell.
public struct CompatibilityProfile: Sendable, Equatable {
    public var text: Bool
    public var stream: Bool
    public var usage: UsageMode
    public var images: Bool
    public var files: FileMode
    public var functionCall: Bool
    public var shellCall: Bool
    public var applyPatchCall: Bool
    public var mcp: Bool
    public var reasoningItems: Bool
    public var encryptedReasoning: Bool

    public enum UsageMode: String, Sendable, Equatable {
        case estimated
        case exact
    }

    public enum FileMode: String, Sendable, Equatable {
        case disabled
        case textOnly
    }

    public static let codexMinimal = CompatibilityProfile(
        text: true,
        stream: true,
        usage: .estimated,
        images: false,
        files: .textOnly,
        functionCall: false,
        shellCall: false,
        applyPatchCall: false,
        mcp: false,
        reasoningItems: false,
        encryptedReasoning: false
    )
}
