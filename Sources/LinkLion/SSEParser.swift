import Foundation

// MARK: - Errors

public enum SSEError: Error, Sendable {
    case agentFailed(String)
    case invalidResponse(statusCode: Int)
    case streamEnded
    case networkError(String)
}

// MARK: - Parser

/// Parses Server-Sent Events from the TinyFish Web Agent API.
///
/// All events arrive as `data: {json}` lines. The `type` field inside the
/// JSON payload identifies the event kind (`PROGRESS` or `COMPLETE`).
public struct SSEParser: Sendable {
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Stream events from a TinyFish SSE endpoint.
    ///
    /// Calls `onProgress` for each `PROGRESS` event and returns the raw
    /// JSON `Data` of the `resultJson` field when a `COMPLETE/COMPLETED`
    /// event arrives. Throws `SSEError.agentFailed` for FAILED or TIMEOUT.
    public func run(
        request: URLRequest,
        onProgress: @Sendable (String) async -> Void
    ) async throws -> Data {
        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse

        do {
            (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw SSEError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SSEError.invalidResponse(statusCode: 0)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SSEError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let lineData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String
            else {
                continue
            }

            switch type {
            case "PROGRESS":
                let purpose = json["purpose"] as? String ?? ""
                await onProgress(purpose)

            case "COMPLETE":
                let status = json["status"] as? String ?? ""
                switch status {
                case "COMPLETED":
                    if let resultJson = json["resultJson"],
                       JSONSerialization.isValidJSONObject(resultJson) {
                        return try JSONSerialization.data(withJSONObject: resultJson)
                    }
                    return Data("{}".utf8)
                case "FAILED", "TIMEOUT":
                    let errorDict = json["error"] as? [String: Any]
                    let message = errorDict?["message"] as? String ?? "Unknown agent error"
                    throw SSEError.agentFailed(message)
                default:
                    let errorDict = json["error"] as? [String: Any]
                    let message = errorDict?["message"] as? String ?? "Unknown status: \(status)"
                    throw SSEError.agentFailed(message)
                }

            default:
                continue
            }
        }

        throw SSEError.streamEnded
    }
}
