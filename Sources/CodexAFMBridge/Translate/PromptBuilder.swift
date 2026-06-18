import Foundation

/// Builds a single AFM prompt string from a normalized input, preserving
/// OpenAI role priority semantics. AFM is not natively an OpenAI model, so the
/// bridge flattens system/developer/user/assistant into one transcript block
/// while making the priority rules explicit.
public enum PromptBuilder {
    /// The fixed preamble that tells the model it is behind a Responses API
    /// compatibility bridge.
    public static let preamble = """
    You are responding through an OpenAI Responses API compatibility bridge for Codex.

    Priority rules:
    1. System and developer instructions are higher priority than user instructions.
    2. Do not claim access to tools unless a tool is provided.
    3. If a tool call is needed but unsupported, explain the exact limitation.
    """

    public static func build(from normalized: NormalizedInput) -> String {
        var sections: [String] = [preamble]

        if let instructions = normalized.instructions?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instructions.isEmpty {
            sections.append("System instructions:\n\(instructions)")
        }

        var systemBlocks: [String] = []
        var developerBlocks: [String] = []
        var conversation: [String] = []

        for message in normalized.messages {
            switch message.role {
            case .system:
                systemBlocks.append(message.text)
            case .developer:
                developerBlocks.append(message.text)
            case .user:
                conversation.append("[user] \(message.text)")
            case .assistant:
                conversation.append("[assistant] \(message.text)")
            case .tool:
                conversation.append("[tool] \(message.text)")
            }
        }

        if !systemBlocks.isEmpty {
            sections.append("System instructions:\n" + systemBlocks.joined(separator: "\n\n"))
        }
        if !developerBlocks.isEmpty {
            sections.append("Developer instructions:\n" + developerBlocks.joined(separator: "\n\n"))
        }
        if !conversation.isEmpty {
            sections.append("Conversation:\n" + conversation.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
