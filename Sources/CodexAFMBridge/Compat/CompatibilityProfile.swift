import Foundation

/// The compatibility profile describes which Responses API features the bridge
/// currently honors. It combines a named profile with runtime feature flags.
public struct CompatibilityProfile: Sendable, Equatable {
    public var name: String
    public var flags: FeatureFlags
    public var usage: UsageMode
    public var files: FileMode

    public enum UsageMode: String, Sendable, Equatable {
        case estimated
        case exact
    }

    public enum FileMode: String, Sendable, Equatable {
        case disabled
        case textOnly
    }

    public init(name: String, flags: FeatureFlags, usage: UsageMode, files: FileMode) {
        self.name = name
        self.flags = flags
        self.usage = usage
        self.files = files
    }

    /// v0: text-only, no tools, estimated usage.
    public static let codexMinimal = CompatibilityProfile(
        name: "codex-minimal",
        flags: .codexMinimal,
        usage: .estimated,
        files: .textOnly
    )

    /// v1: adds function-call support.
    public static let codexTools = CompatibilityProfile(
        name: "codex-tools",
        flags: .codexTools,
        usage: .estimated,
        files: .textOnly
    )

    /// Load a profile from environment overrides.
    public static func loadFromEnv() -> CompatibilityProfile {
        let env = ProcessInfo.processInfo.environment
        let profileName = env["AFM_BRIDGE_PROFILE"] ?? "codex-minimal"
        let base: CompatibilityProfile
        switch profileName {
        case "codex-tools": base = .codexTools
        default: base = .codexMinimal
        }
        let flags = FeatureFlags.loadOverrides(base: base.flags)
        return CompatibilityProfile(name: profileName, flags: flags, usage: base.usage, files: base.files)
    }
}
