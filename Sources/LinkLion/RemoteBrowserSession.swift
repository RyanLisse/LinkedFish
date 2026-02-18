import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors specific to remote browser session management
public enum SessionError: Error, Sendable, LocalizedError {
    case createFailed(String)
    case sessionNotFound
    case destroyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .createFailed(let reason):
            return "Failed to create remote browser session: \(reason)"
        case .sessionNotFound:
            return "No active remote browser session"
        case .destroyFailed(let reason):
            return "Failed to destroy remote browser session: \(reason)"
        }
    }
}

/// Manages authenticated remote browser sessions via AgentQL Tetra.
///
/// Creates pre-authenticated Chrome sessions that can be used with TinyFish
/// goal execution for LinkedIn automation without the Voyager API.
public actor RemoteBrowserSession {
    private static let baseURL = "https://api.agentql.com/v1/tetra/sessions"

    private let apiKey: String
    private var sessionId: String?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// The current session ID, if a session has been created.
    public var currentSessionId: String? {
        sessionId
    }

    /// Create an authenticated session with a LinkedIn cookie.
    ///
    /// Posts to the AgentQL Tetra API to spin up a remote browser
    /// pre-loaded with the provided `li_at` cookie so the session
    /// is already logged into LinkedIn.
    ///
    /// - Parameter liAtCookie: The raw `li_at` cookie value.
    /// - Returns: The session ID for use with TinyFish goals.
    @discardableResult
    public func createSession(liAtCookie: String) async throws -> String {
        let url = URL(string: Self.baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "cookies": [
                [
                    "name": "li_at",
                    "value": liAtCookie,
                    "domain": ".linkedin.com",
                    "path": "/",
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.createFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw LinkedInError.notAuthenticated
        default:
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SessionError.createFailed(message)
        }

        let decoded = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
        self.sessionId = decoded.sessionId
        return decoded.sessionId
    }

    /// Destroy the current session, releasing the remote browser.
    public func destroySession() async throws {
        guard let id = sessionId else {
            throw SessionError.sessionNotFound
        }

        let url = URL(string: "\(Self.baseURL)/\(id)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.destroyFailed("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SessionError.destroyFailed(message)
        }

        self.sessionId = nil
    }

    /// Ensure a session exists, creating one if needed.
    ///
    /// - Parameter liAtCookie: The raw `li_at` cookie value used when creating a new session.
    /// - Returns: The session ID (existing or newly created).
    @discardableResult
    public func ensureSession(liAtCookie: String) async throws -> String {
        if let existing = sessionId {
            return existing
        }
        return try await createSession(liAtCookie: liAtCookie)
    }
}

// MARK: - Response Models

private struct CreateSessionResponse: Decodable, Sendable {
    let sessionId: String
    let cdpUrl: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cdpUrl = "cdp_url"
    }
}
