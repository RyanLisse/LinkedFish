import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for TinyFish API access
public struct TinyFishConfig: Sendable {
    public let apiKey: String
    public let linkedInCookie: String?
    public let agentQLEndpoint: String
    public let webAgentEndpoint: String
    public let proxyEnabled: Bool

    public init(
        apiKey: String,
        linkedInCookie: String? = nil,
        agentQLEndpoint: String = "https://api.agentql.com/v1",
        webAgentEndpoint: String = "https://agent.tinyfish.ai/v1",
        proxyEnabled: Bool = false
    ) {
        self.apiKey = apiKey
        self.linkedInCookie = linkedInCookie
        self.agentQLEndpoint = agentQLEndpoint
        self.webAgentEndpoint = webAgentEndpoint
        self.proxyEnabled = proxyEnabled
    }
}

/// SSE event from TinyFish Web Agent
public enum TinyFishEvent: @unchecked Sendable {
    case status(String)
    case result([String: Any])
    case error(String)
    case unknown(String)
}

/// Errors from TinyFish operations
public enum TinyFishError: LocalizedError, @unchecked Sendable {
    case invalidAPIKey
    case rateLimited(retryAfter: Int?)
    case agentFailed(String)
    case networkError(Error)
    case parseError(String)
    case sessionError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid TinyFish/AgentQL API key"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited. Retry after \(retryAfter) seconds"
            }
            return "Rate limited"
        case .agentFailed(let message):
            return "Agent failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .sessionError(let message):
            return "Session error: \(message)"
        case .timeout:
            return "Operation timed out"
        }
    }
}

/// Remote browser session for authenticated LinkedIn operations
public struct BrowserSession: Sendable {
    public let sessionId: String
    public let cdpURL: String
    public var isAuthenticated: Bool

    public init(sessionId: String, cdpURL: String, isAuthenticated: Bool) {
        self.sessionId = sessionId
        self.cdpURL = cdpURL
        self.isAuthenticated = isAuthenticated
    }
}

/// Core TinyFish client - handles all API communication
public actor TinyFishClient {
    private let config: TinyFishConfig
    private let session: URLSession
    private let logger: Logger
    private var browserSession: BrowserSession?

    public init(config: TinyFishConfig) {
        self.config = config

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120
        sessionConfig.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: sessionConfig)

        self.logger = Logger(label: "LinkLion.TinyFishClient")
    }

    // MARK: - Web Agent (SSE)

    /// Run a TinyFish web agent with a goal, returning the final result.
    /// Parses the SSE stream internally and yields status updates via callback.
    public func runAgent(
        url: String,
        goal: String,
        onStatus: ((String) -> Void)? = nil
    ) async throws -> [String: Any] {
        logger.info("Starting TinyFish web agent", metadata: [
            "url": .string(url),
            "goal": .string(goal)
        ])

        let stream = runAgentStream(url: url, goal: goal)
        var finalResult: [String: Any]?

        do {
            for try await event in stream {
                switch event {
                case .status(let message):
                    onStatus?(message)
                case .result(let data):
                    finalResult = data
                case .error(let message):
                    throw TinyFishError.agentFailed(message)
                case .unknown:
                    continue
                }
            }
        } catch let error as TinyFishError {
            logger.error("Web agent failed", metadata: ["error": .string(error.localizedDescription)])
            throw error
        } catch {
            logger.error("Web agent failed", metadata: ["error": .string(error.localizedDescription)])
            throw TinyFishError.networkError(error)
        }

        guard let finalResult else {
            throw TinyFishError.parseError("No result event received from SSE stream")
        }

        logger.info("Web agent completed successfully")
        return finalResult
    }

    /// Run agent and return the full SSE event stream as AsyncSequence.
    public func runAgentStream(
        url: String,
        goal: String
    ) -> AsyncThrowingStream<TinyFishEvent, Error> {
        struct ProxyConfig: Encodable, Sendable {
            let enabled: Bool
        }

        struct RunAgentRequest: Encodable, Sendable {
            let url: String
            let goal: String
            let proxy_config: ProxyConfig
        }

        do {
            let requestBody = RunAgentRequest(
                url: url,
                goal: goal,
                proxy_config: ProxyConfig(enabled: config.proxyEnabled)
            )

            let request = try buildRequest(
                endpoint: config.webAgentEndpoint,
                path: "/automation/run-sse",
                method: "POST",
                body: requestBody
            )

            let session = self.session
            let logger = self.logger
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw TinyFishError.parseError("Invalid HTTP response")
                        }

                        try Self.validateHTTPResponse(httpResponse)

                        logger.debug("Connected to TinyFish SSE stream", metadata: [
                            "statusCode": .stringConvertible(httpResponse.statusCode)
                        ])

                        let parsedStream = Self.parseSSEStream(bytes, logger: logger)
                        for try await event in parsedStream {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        logger.error("SSE stream failed", metadata: ["error": .string(error.localizedDescription)])
                        continuation.finish(throwing: error)
                    }
                }
            }
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - AgentQL Queries

    /// Query structured data from a URL using AgentQL query language.
    public func queryData(
        url: String,
        query: String,
        sessionId: String? = nil
    ) async throws -> [String: Any] {
        struct QueryBody: Encodable, Sendable {
            let url: String
            let query: String
            let params: [String: String]?
            let session_id: String?
        }

        logger.info("Running AgentQL query", metadata: ["url": .string(url)])

        let body = QueryBody(
            url: url,
            query: query,
            params: sessionId == nil ? ["browser_profile": "stealth"] : nil,
            session_id: sessionId
        )

        let request = try buildRequest(
            endpoint: config.agentQLEndpoint,
            path: "/query-data",
            method: "POST",
            body: body
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyFishError.parseError("Invalid HTTP response")
            }

            try Self.validateHTTPResponse(httpResponse)
            logger.debug("AgentQL query response", metadata: [
                "statusCode": .stringConvertible(httpResponse.statusCode),
                "bytes": .stringConvertible(data.count)
            ])

            return try Self.extractJSONObject(from: data)
        } catch let error as TinyFishError {
            logger.error("AgentQL query failed", metadata: ["error": .string(error.localizedDescription)])
            throw error
        } catch {
            logger.error("AgentQL query failed", metadata: ["error": .string(error.localizedDescription)])
            throw TinyFishError.networkError(error)
        }
    }

    /// Query with a natural language prompt instead of AgentQL syntax.
    public func queryWithPrompt(
        url: String,
        prompt: String,
        sessionId: String? = nil
    ) async throws -> [String: Any] {
        // AgentQL accepts query strings, so we pass prompt directly as the query payload.
        try await queryData(url: url, query: prompt, sessionId: sessionId)
    }

    // MARK: - Remote Browser Sessions

    /// Create an authenticated browser session with LinkedIn cookies.
    public func createAuthenticatedSession() async throws -> BrowserSession {
        struct CreateSessionRequest: Encodable, Sendable {
            let browser_profile: String
        }

        struct CreateSessionResponse: Decodable, Sendable {
            let session_id: String
            let cdp_url: String
        }

        struct SessionCookie: Encodable, Sendable {
            let name: String
            let value: String
            let domain: String
            let path: String
            let secure: Bool
            let httpOnly: Bool
        }

        struct CookieInjectionRequest: Encodable, Sendable {
            let cookies: [SessionCookie]
        }

        logger.info("Creating remote browser session")

        let createRequest = try buildRequest(
            endpoint: config.agentQLEndpoint,
            path: "/tetra/sessions",
            method: "POST",
            body: CreateSessionRequest(browser_profile: "stealth")
        )

        do {
            let (data, response) = try await session.data(for: createRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyFishError.parseError("Invalid HTTP response")
            }

            try Self.validateHTTPResponse(httpResponse)

            let createdSession: CreateSessionResponse
            do {
                createdSession = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
            } catch {
                throw TinyFishError.parseError("Failed to parse session response: \(error.localizedDescription)")
            }

            var session = BrowserSession(
                sessionId: createdSession.session_id,
                cdpURL: createdSession.cdp_url,
                isAuthenticated: false
            )

            if let cookie = config.linkedInCookie, !cookie.isEmpty {
                let normalizedCookie: String
                if cookie.hasPrefix("li_at=") {
                    normalizedCookie = String(cookie.dropFirst(6))
                } else {
                    normalizedCookie = cookie
                }

                let cookieRequest = CookieInjectionRequest(cookies: [
                    SessionCookie(
                        name: "li_at",
                        value: normalizedCookie,
                        domain: ".linkedin.com",
                        path: "/",
                        secure: true,
                        httpOnly: true
                    )
                ])

                let injectRequest = try buildRequest(
                    endpoint: config.agentQLEndpoint,
                    path: "/tetra/sessions/\(session.sessionId)/cookies",
                    method: "POST",
                    body: cookieRequest
                )

                let (_, injectResponse) = try await self.session.data(for: injectRequest)
                guard let injectHTTPResponse = injectResponse as? HTTPURLResponse else {
                    throw TinyFishError.parseError("Invalid cookie injection response")
                }
                try Self.validateHTTPResponse(injectHTTPResponse)
                session.isAuthenticated = true

                logger.info("Injected LinkedIn cookie into session", metadata: [
                    "sessionId": .string(session.sessionId)
                ])
            }

            self.browserSession = session
            logger.info("Browser session created", metadata: ["sessionId": .string(session.sessionId)])
            return session
        } catch let error as TinyFishError {
            logger.error("Failed to create browser session", metadata: ["error": .string(error.localizedDescription)])
            throw error
        } catch {
            logger.error("Failed to create browser session", metadata: ["error": .string(error.localizedDescription)])
            throw TinyFishError.networkError(error)
        }
    }

    /// Close a browser session.
    public func closeSession(_ session: BrowserSession) async throws {
        logger.info("Closing browser session", metadata: ["sessionId": .string(session.sessionId)])

        let noBody: String? = nil
        let request = try buildRequest(
            endpoint: config.agentQLEndpoint,
            path: "/tetra/sessions/\(session.sessionId)",
            method: "DELETE",
            body: noBody
        )

        do {
            let (_, response) = try await self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TinyFishError.parseError("Invalid HTTP response")
            }

            try Self.validateHTTPResponse(httpResponse)

            if browserSession?.sessionId == session.sessionId {
                browserSession = nil
            }

            logger.info("Browser session closed", metadata: ["sessionId": .string(session.sessionId)])
        } catch let error as TinyFishError {
            logger.error("Failed to close browser session", metadata: ["error": .string(error.localizedDescription)])
            throw error
        } catch {
            logger.error("Failed to close browser session", metadata: ["error": .string(error.localizedDescription)])
            throw TinyFishError.networkError(error)
        }
    }

    /// Get or create the shared authenticated session.
    public func getAuthenticatedSession() async throws -> BrowserSession {
        if let session = browserSession, session.isAuthenticated {
            return session
        }

        return try await createAuthenticatedSession()
    }

    // MARK: - Internal

    /// Parse SSE text/event-stream into events.
    private static func parseSSEStream(
        _ bytes: URLSession.AsyncBytes,
        logger: Logger
    ) -> AsyncThrowingStream<TinyFishEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var currentEventName = "message"
                var dataLines: [String] = []

                func emitCurrentEventIfNeeded() throws {
                    guard !dataLines.isEmpty else { return }

                    let dataPayload = dataLines.joined(separator: "\n")
                    let event = try decodeSSEEvent(name: currentEventName, data: dataPayload)
                    logger.debug("SSE event received", metadata: [
                        "event": .string(currentEventName),
                        "payload": .string(dataPayload)
                    ])
                    continuation.yield(event)

                    currentEventName = "message"
                    dataLines.removeAll(keepingCapacity: true)
                }

                do {
                    for try await rawLine in bytes.lines {
                        if rawLine.isEmpty {
                            try emitCurrentEventIfNeeded()
                            continue
                        }

                        if rawLine.hasPrefix(":") {
                            continue
                        }

                        if rawLine.hasPrefix("event:") {
                            currentEventName = rawLine.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if rawLine.hasPrefix("data:") {
                            let dataValue = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            dataLines.append(String(dataValue))
                        }
                    }

                    try emitCurrentEventIfNeeded()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Build an API request with auth headers.
    private func buildRequest<Body: Encodable>(
        endpoint: String,
        path: String,
        method: String = "POST",
        body: Body? = nil
    ) throws -> URLRequest {
        guard let baseURL = URL(string: endpoint) else {
            throw TinyFishError.parseError("Invalid endpoint URL: \(endpoint)")
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let finalURL = URL(string: normalizedPath, relativeTo: baseURL)?.absoluteURL else {
            throw TinyFishError.parseError("Invalid request path: \(path)")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")

        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw TinyFishError.parseError("Failed to encode request body: \(error.localizedDescription)")
            }
        }

        return request
    }

    private static func decodeSSEEvent(name: String, data: String) throws -> TinyFishEvent {
        guard let jsonData = data.data(using: .utf8) else {
            throw TinyFishError.parseError("SSE data is not valid UTF-8")
        }

        let parsedObject = try JSONSerialization.jsonObject(with: jsonData)
        guard let payload = parsedObject as? [String: Any] else {
            return .unknown(data)
        }

        let declaredType = payload["type"] as? String
        let effectiveType = declaredType ?? name

        switch effectiveType {
        case "status":
            let message = payload["message"] as? String ?? ""
            return .status(message)
        case "result":
            if let result = payload["data"] as? [String: Any] {
                return .result(result)
            }
            if let result = payload["result"] as? [String: Any] {
                return .result(result)
            }
            return .result(payload)
        case "error":
            let message = payload["message"] as? String ?? "Unknown error"
            return .error(message)
        default:
            return .unknown(data)
        }
    }

    private static func validateHTTPResponse(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw TinyFishError.invalidAPIKey
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw TinyFishError.rateLimited(retryAfter: retryAfter)
        case 500 ... 599:
            throw TinyFishError.agentFailed("Server error HTTP \(response.statusCode)")
        default:
            throw TinyFishError.agentFailed("HTTP \(response.statusCode)")
        }
    }

    private static func extractJSONObject(from data: Data) throws -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let json = object as? [String: Any] else {
                throw TinyFishError.parseError("Expected JSON object but got \(type(of: object))")
            }
            return json
        } catch let error as TinyFishError {
            throw error
        } catch {
            throw TinyFishError.parseError("Failed to parse JSON: \(error.localizedDescription)")
        }
    }
}
