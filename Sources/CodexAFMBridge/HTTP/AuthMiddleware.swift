import Foundation
import Hummingbird
import HummingbirdCore
import HTTPTypes

/// Middleware that enforces `Authorization: Bearer <AFM_BRIDGE_API_KEY>` on
/// every request. Returns an OpenAI-shaped 401 error on mismatch.
public struct AuthMiddleware<Context: RequestContext>: RouterMiddleware {
    private let expectedToken: String

    public init(expectedToken: String) {
        self.expectedToken = expectedToken
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Health endpoint is unauthenticated so process managers can probe it.
        if request.uri.path == "/health" || request.uri.path == "/health/" {
            return try await next(request, context)
        }

        guard let header = request.headers[.authorization] else {
            throw BridgeError.unauthorized
        }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bearer ") else {
            throw BridgeError.unauthorized
        }
        let token = trimmed.dropFirst("bearer ".count).trimmingCharacters(in: .whitespaces)
        guard !expectedToken.isEmpty, token == expectedToken else {
            throw BridgeError.unauthorized
        }
        return try await next(request, context)
    }
}
