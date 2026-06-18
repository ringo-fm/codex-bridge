import Foundation

// MARK: - Response object

/// The full Responses API object returned for a completed generation, and the
/// object embedded in `response.created` / `response.completed` SSE events.
public struct ResponsesResponse: Codable, Sendable, Equatable {
    public var id: String
    public var object: String
    public var created_at: Int
    public var status: ResponsesStatus
    public var model: String
    public var output: [ResponsesOutputItem]
    public var usage: ResponsesUsage?
    public var error: ResponsesErrorObject?

    public init(
        id: String,
        object: String = "response",
        created_at: Int,
        status: ResponsesStatus,
        model: String,
        output: [ResponsesOutputItem],
        usage: ResponsesUsage? = nil,
        error: ResponsesErrorObject? = nil
    ) {
        self.id = id
        self.object = object
        self.created_at = created_at
        self.status = status
        self.model = model
        self.output = output
        self.usage = usage
        self.error = error
    }
}

public enum ResponsesStatus: String, Codable, Sendable, Equatable {
    case completed
    case in_progress
    case failed
    case cancelled
    case incomplete
    case queued
}

// MARK: - Output items

/// One item in the `output` array. For v0 we only emit `message` items.
public struct ResponsesOutputItem: Codable, Sendable, Equatable {
    public var id: String
    public var type: String
    public var status: ResponsesStatus
    public var role: String
    public var content: [ResponsesOutputContent]
    public var call_id: String?
    public var name: String?
    public var arguments: String?

    public init(
        id: String,
        type: String,
        status: ResponsesStatus,
        role: String,
        content: [ResponsesOutputContent],
        call_id: String? = nil,
        name: String? = nil,
        arguments: String? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.role = role
        self.content = content
        self.call_id = call_id
        self.name = name
        self.arguments = arguments
    }

    /// Convenience constructor for a completed assistant text message.
    public static func assistantMessage(id: String, text: String) -> ResponsesOutputItem {
        ResponsesOutputItem(
            id: id,
            type: "message",
            status: .completed,
            role: "assistant",
            content: [.text(text)]
        )
    }
}

public struct ResponsesOutputContent: Codable, Sendable, Equatable {
    public var type: String
    public var text: String
    public var annotations: [ResponsesAnnotation]

    public init(type: String, text: String, annotations: [ResponsesAnnotation] = []) {
        self.type = type
        self.text = text
        self.annotations = annotations
    }

    public static func text(_ s: String) -> ResponsesOutputContent {
        ResponsesOutputContent(type: "output_text", text: s)
    }
}

public struct ResponsesAnnotation: Codable, Sendable, Equatable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

// MARK: - Usage

public struct ResponsesUsage: Codable, Sendable, Equatable {
    public var input_tokens: Int
    public var output_tokens: Int
    public var total_tokens: Int

    public init(input_tokens: Int, output_tokens: Int, total_tokens: Int? = nil) {
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.total_tokens = total_tokens ?? (input_tokens + output_tokens)
    }
}

// MARK: - Error object (embedded in body)

public struct ResponsesErrorObject: Codable, Sendable, Equatable {
    public var message: String
    public var type: String
    public var param: String?
    public var code: String

    public init(message: String, type: String, param: String? = nil, code: String) {
        self.message = message
        self.type = type
        self.param = param
        self.code = code
    }
}

/// Top-level error envelope: `{"error": {...}}`.
public struct ResponsesErrorEnvelope: Codable, Sendable, Equatable {
    public var error: ResponsesErrorObject

    public init(error: ResponsesErrorObject) {
        self.error = error
    }
}
