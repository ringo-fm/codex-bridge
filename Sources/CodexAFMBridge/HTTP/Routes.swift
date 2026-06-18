import Foundation
import Hummingbird
import HummingbirdCore
import NIOCore
import HTTPTypes
import struct Logging.Logger

/// Shared services made available to every route handler.
public struct BridgeServices: Sendable {
    public let afm: AFMRuntime
    public let store: ResponseStore
    public let config: BridgeConfig
    public let profile: CompatibilityProfile
    public let logger: Logger

    public init(afm: AFMRuntime, store: ResponseStore, config: BridgeConfig, profile: CompatibilityProfile, logger: Logger) {
        self.afm = afm
        self.store = store
        self.config = config
        self.profile = profile
        self.logger = logger
    }
}

/// Builds the Hummingbird router with all MVP endpoints and the auth middleware.
public enum Routes {
    public static func build(services: BridgeServices) -> Router<BasicRequestContext> {
        let router = Router<BasicRequestContext>()
        router.add(middleware: AuthMiddleware<BasicRequestContext>(expectedToken: services.config.authToken))

        // GET /health
        router.get("health") { _, _ in
            let availability = services.afm.availability()
            let payload: [String: String] = [
                "status": availability.isAvailable ? "ok" : "unavailable",
                "model": SupportedModels.canonical,
                "available": availability.isAvailable ? "true" : "false"
            ]
            var headers = HTTPFields()
            headers[.contentType] = "application/json; charset=utf-8"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: try encodeBuffer(payload)))
        }

        // GET /v1/models
        router.get("v1/models") { _, _ in
            var headers = HTTPFields()
            headers[.contentType] = "application/json; charset=utf-8"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: try encodeBuffer(ModelsList.default)))
        }

        // POST /v1/responses
        router.post("v1/responses") { request, context in
            let body: ResponsesCreateRequest
            do {
                body = try await request.decode(as: ResponsesCreateRequest.self, context: context)
            } catch {
                throw BridgeError.invalidRequest("could not decode JSON body: \(error.localizedDescription)")
            }

            guard SupportedModels.isSupported(body.model) else {
                throw BridgeError.unsupportedModel(body.model)
            }

            try rejectUnsupportedInputTypes(body)

            var normalized = InputNormalizer.normalize(body)
            let prompt = PromptBuilder.build(from: normalized)

            let limit = services.afm.contextSize
            let inputTokens = await services.afm.inputTokenCount(for: prompt) ?? OutputMapper.estimateTokens(text: prompt)
            if inputTokens > limit {
                services.logger.warning("context_too_large: ~\(inputTokens) tokens > limit \(limit)")
                throw BridgeError.contextTooLarge(inputTokens: inputTokens, limit: limit)
            }

            let responseID = newID(prefix: "resp_afm_")
            let stream = body.stream ?? false

            let afmRequest = AFMGenerateRequest(
                responseID: responseID,
                model: body.model,
                instructions: normalized.instructions,
                prompt: prompt,
                stream: stream,
                temperature: body.temperature,
                maxOutputTokens: body.max_output_tokens,
                topP: body.top_p
            )

            if stream {
                return try await streamingResponse(
                    request: request,
                    services: services,
                    afmRequest: afmRequest,
                    responseID: responseID,
                    model: body.model,
                    diagnostics: normalized.diagnostics
                )
            } else {
                return try await nonStreamingResponse(
                    services: services,
                    afmRequest: afmRequest,
                    responseID: responseID,
                    model: body.model,
                    diagnostics: &normalized.diagnostics
                )
            }
        }

        // GET /v1/responses/{id}
        router.get("v1/responses/:id") { _, context in
            let id = context.parameters.get("id", as: String.self) ?? context.parameters.get("id")
            guard let id else {
                throw BridgeError.invalidRequest("missing response id in path")
            }
            guard let response = await services.store.get(id) else {
                throw BridgeError.invalidRequest("response '\(id)' not found")
            }
            var headers = HTTPFields()
            headers[.contentType] = "application/json; charset=utf-8"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: try encodeBuffer(response)))
        }

        return router
    }
}

// MARK: - Non-streaming response

private func nonStreamingResponse(
    services: BridgeServices,
    afmRequest: AFMGenerateRequest,
    responseID: String,
    model: String,
    diagnostics: inout Diagnostics
) async throws -> Response {
    let result = try await services.afm.generate(afmRequest)

    let inputTokens = await services.afm.inputTokenCount(for: afmRequest.prompt) ?? OutputMapper.estimateTokens(text: afmRequest.prompt)
    let enriched = AFMGenerateResult(
        text: result.text,
        inputTokens: inputTokens,
        outputTokens: result.outputTokens,
        finishReason: result.finishReason
    )

    let response = OutputMapper.toResponsesObject(
        responseID: responseID,
        model: model,
        result: enriched,
        diagnostics: &diagnostics
    )

    await services.store.store(response)

    var headers = HTTPFields()
    headers[.contentType] = "application/json; charset=utf-8"
    if diagnostics.estimatedUsage {
        headers[.init(afmUsageEstimatedHeader)!] = "true"
    }
    if services.config.debug, !diagnostics.isEmpty {
        injectDiagnosticsHeader(&headers, diagnostics)
    }
    return Response(status: .ok, headers: headers, body: .init(byteBuffer: try encodeBuffer(response)))
}

// MARK: - Streaming response (SSE)

private func streamingResponse(
    request: Request,
    services: BridgeServices,
    afmRequest: AFMGenerateRequest,
    responseID: String,
    model: String,
    diagnostics: Diagnostics
) async throws -> Response {
    let createdAt = Int(Date().timeIntervalSince1970)
    let messageID = newID(prefix: "msg_afm_")
    let logger = services.logger
    let afm = services.afm
    let store = services.store

    var headers = HTTPFields()
    headers[.contentType] = "text/event-stream; charset=utf-8"
    headers[.cacheControl] = "no-cache"
    headers[.connection] = "keep-alive"
    if diagnostics.estimatedUsage {
        headers[.init(afmUsageEstimatedHeader)!] = "true"
    }

    return Response(
        status: .ok,
        headers: headers,
        body: .init { writer in
            let sse = SSEWriter()
            let inProgress = OutputMapper.toInProgressObject(responseID: responseID, model: model, createdAt: createdAt)

            try await sse.write(.responseCreated(inProgress), to: &writer)
            try await sse.write(.responseInProgress(inProgress), to: &writer)

            let item = ResponsesOutputItem(
                id: messageID,
                type: "message",
                status: .in_progress,
                role: "assistant",
                content: []
            )
            try await sse.write(.responseOutputItemAdded(outputIndex: 0, item: item), to: &writer)

            let part = ResponsesOutputContent(type: "output_text", text: "")
            try await sse.write(.responseContentPartAdded(outputIndex: 0, contentIndex: 0, part: part), to: &writer)

            do {
                try await request.body.consumeWithCancellationOnInboundClose { _ in
                    let stream = try await afm.stream(afmRequest)
                    var lastLen = 0
                    var fullText = ""
                    do {
                        for try await snapshot in stream {
                            let cumulative = snapshot.cumulativeText
                            if cumulative.count > lastLen {
                                let delta = String(cumulative.dropFirst(lastLen))
                                fullText = cumulative
                                lastLen = cumulative.count
                                try await sse.write(
                                    .responseOutputTextDelta(outputIndex: 0, contentIndex: 0, delta: delta),
                                    to: &writer
                                )
                            }
                        }
                    } catch let error as BridgeError {
                        let failed = OutputMapper.toFailedObject(responseID: responseID, model: model, error: error, createdAt: createdAt)
                        try? await sse.write(.responseFailed(failed), to: &writer)
                        try? await sse.write(.error(error.errorObject), to: &writer)
                        return
                    } catch is CancellationError {
                        return
                    }

                    try await sse.write(.responseOutputTextDone(outputIndex: 0, contentIndex: 0, text: fullText), to: &writer)

                    var diags = diagnostics
                    let inputTokens = await afm.inputTokenCount(for: afmRequest.prompt) ?? OutputMapper.estimateTokens(text: afmRequest.prompt)
                    let outputTokens = await afm.inputTokenCount(for: fullText) ?? OutputMapper.estimateTokens(text: fullText)
                    let completed = OutputMapper.toCompletedObject(
                        responseID: responseID,
                        model: model,
                        text: fullText,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        createdAt: createdAt,
                        diagnostics: &diags
                    )
                    try await sse.write(.responseCompleted(completed), to: &writer)
                    await store.store(completed)
                }
            } catch is CancellationError {
                logger.debug("stream client disconnected: \(responseID)")
            }
            try await writer.finish(nil)
        }
    )
}

// MARK: - Helpers

private let afmUsageEstimatedHeader = "x-afm-usage-estimated"
private let afmDiagnosticsHeader = "x-afm-diagnostics"

/// Reject requests that contain hard-unsupported input content types (images,
/// files) so the client gets a clear 400 instead of silent dropping.
private func rejectUnsupportedInputTypes(_ request: ResponsesCreateRequest) throws {
    for item in request.input.asItems {
        guard let parts = item.content else { continue }
        for part in parts {
            switch part.type {
            case "input_image":
                throw BridgeError.unsupportedInputType("input_image")
            case "input_file":
                throw BridgeError.unsupportedInputType("input_file")
            default:
                break
            }
        }
    }
}

/// Encode diagnostics into a response header for debug builds.
private func injectDiagnosticsHeader(_ headers: inout HTTPFields, _ diagnostics: Diagnostics) {
    var bits: [String] = []
    if !diagnostics.ignoredFields.isEmpty {
        bits.append("ignored=" + diagnostics.ignoredFields.joined(separator: ","))
    }
    if !diagnostics.unsupportedInputTypes.isEmpty {
        bits.append("unsupported_input=" + diagnostics.unsupportedInputTypes.joined(separator: ","))
    }
    if !diagnostics.unsupportedToolTypes.isEmpty {
        bits.append("unsupported_tool=" + diagnostics.unsupportedToolTypes.joined(separator: ","))
    }
    if diagnostics.estimatedUsage {
        bits.append("usage=estimated")
    }
    if !bits.isEmpty {
        headers[.init(afmDiagnosticsHeader)!] = bits.joined(separator: "; ")
    }
}
