import Foundation

/// A normalized conversation message after flattening OpenAI Responses input.
public struct NormalizedMessage: Sendable, Equatable {
    public let role: Role
    public let text: String

    public enum Role: String, Sendable, Equatable {
        case system
        case developer
        case user
        case assistant
        case tool

        /// Map an OpenAI role string to a normalized role. Unknown roles fall
        /// back to `.user` (and are recorded as ignored by the caller).
        public static func from(_ raw: String?) -> Role {
            switch (raw ?? "").lowercased() {
            case "system": return .system
            case "developer": return .developer
            case "user": return .user
            case "assistant": return .assistant
            case "tool": return .tool
            default: return .user
            }
        }
    }

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// Result of normalizing a Responses API request.
public struct NormalizedInput: Sendable {
    public let instructions: String?
    public let messages: [NormalizedMessage]
    public var diagnostics: Diagnostics

    public init(instructions: String?, messages: [NormalizedMessage], diagnostics: Diagnostics) {
        self.instructions = instructions
        self.messages = messages
        self.diagnostics = diagnostics
    }
}

/// Converts an OpenAI Responses API request body into a normalized transcript.
/// Drops unsupported input types (images/files) and records diagnostics.
public enum InputNormalizer {
    public static func normalize(_ request: ResponsesCreateRequest) -> NormalizedInput {
        var diagnostics = Diagnostics()

        if request.tools?.isEmpty == false {
            for tool in request.tools! {
                diagnostics.unsupportedTool(tool.type)
            }
            diagnostics.ignore("tools", reason: "tools ignored in v0 text-only profile")
        }
        if request.reasoning != nil {
            diagnostics.ignore("reasoning", reason: "reasoning ignored in v0")
        }
        if request.previous_response_id != nil {
            diagnostics.ignore("previous_response_id", reason: "session not retained in MVP")
        }
        if request.store != nil {
            diagnostics.ignore("store", reason: "storage controlled by caller")
        }
        if request.metadata != nil {
            diagnostics.ignore("metadata")
        }

        var messages: [NormalizedMessage] = []
        for item in request.input.asItems {
            // Only "message" items carry conversation content in the MVP.
            let itemType = item.type ?? "message"
            if itemType != "message" {
                diagnostics.unsupportedInput(itemType)
                continue
            }

            let role = NormalizedMessage.Role.from(item.role)
            guard let parts = item.content, !parts.isEmpty else {
                continue
            }

            var textParts: [String] = []
            for part in parts {
                switch part.type {
                case "input_text":
                    if let t = part.text, !t.isEmpty {
                        textParts.append(t)
                    }
                case "input_image":
                    diagnostics.unsupportedInput("input_image")
                case "input_file":
                    diagnostics.unsupportedInput("input_file")
                case "text":
                    if let t = part.text, !t.isEmpty {
                        textParts.append(t)
                    }
                default:
                    diagnostics.unsupportedInput(part.type)
                }
            }

            let text = textParts.joined(separator: "\n")
            if !text.isEmpty {
                messages.append(NormalizedMessage(role: role, text: text))
            }
        }

        return NormalizedInput(
            instructions: request.instructions,
            messages: messages,
            diagnostics: diagnostics
        )
    }
}
