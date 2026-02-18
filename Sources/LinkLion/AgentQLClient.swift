import Foundation

/// Client for the AgentQL structured web data extraction API.
public actor AgentQLClient: Sendable {
    private let apiKey: String
    private static let baseURL = "https://api.agentql.com/v1"
    private static let maxRetries = 3

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Execute an AgentQL query and decode the `data` field as `T`.
    public func query<T: Decodable & Sendable>(
        url: String,
        agentQLQuery: String,
        as type: T.Type,
        params: [String: String] = ["browser_profile": "stealth"]
    ) async throws -> T {
        let data = try await executeQuery(url: url, agentQLQuery: agentQLQuery, params: params)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LinkedInError.parseError("Failed to decode AgentQL response: \(error.localizedDescription)")
        }
    }

    /// Execute an AgentQL query returning the raw `data` dictionary.
    public func queryRaw(
        url: String,
        agentQLQuery: String,
        params: [String: String] = ["browser_profile": "stealth"]
    ) async throws -> [String: Any] {
        let data = try await executeQuery(url: url, agentQLQuery: agentQLQuery, params: params)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinkedInError.invalidResponse
        }
        return dict
    }

    // MARK: - Private

    /// Builds and sends the request with retry logic for 429 responses.
    /// Returns the raw JSON `Data` for the `data` key in the response.
    private func executeQuery(
        url: String,
        agentQLQuery: String,
        params: [String: String]
    ) async throws -> Data {
        guard let endpoint = URL(string: "\(Self.baseURL)/query-data") else {
            throw LinkedInError.invalidURL("\(Self.baseURL)/query-data")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "url": url,
            "query": agentQLQuery,
            "params": params
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = LinkedInError.invalidResponse

        for attempt in 0..<Self.maxRetries {
            let responseData: Data
            let response: URLResponse

            do {
                (responseData, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw LinkedInError.parseError("Network error: \(error.localizedDescription)")
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LinkedInError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                return try extractDataField(from: responseData)
            case 401:
                throw LinkedInError.notAuthenticated
            case 429:
                lastError = LinkedInError.rateLimited
                if attempt < Self.maxRetries - 1 {
                    let delay = UInt64(1 << attempt) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
            default:
                throw LinkedInError.httpError(httpResponse.statusCode)
            }
        }

        throw lastError
    }

    /// Extracts the `data` field from the top-level JSON and re-serializes it.
    private func extractDataField(from responseData: Data) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let dataValue = json["data"] else {
            throw LinkedInError.invalidResponse
        }
        if JSONSerialization.isValidJSONObject(dataValue) {
            return try JSONSerialization.data(withJSONObject: dataValue)
        }
        // For primitive values, wrap and unwrap isn't needed — this shouldn't happen
        // with AgentQL but handle gracefully
        throw LinkedInError.invalidResponse
    }
}
