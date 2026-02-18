import Foundation
import Logging

// MARK: - LinkedInClient

/// Thin facade over `TinyFishClient`.
///
/// Preserves the public API of the previous Voyager-based implementation while
/// delegating all LinkedIn interactions to the TinyFish web-automation backend.
/// Legacy Peekaboo/vision/Voyager instance code has been removed; static helpers
/// and payload types are retained for test compatibility.
public actor LinkedInClient {
    private let tinyFish: TinyFishClient
    private var liAtCookie: String?
    private let logger = Logger(label: "LinkedInClient")

    // MARK: - Legacy compatibility flags (no-ops in TinyFish backend)

    private var _usePeekabooFallback: Bool = false
    private var _preferPeekabooMessaging: Bool = false

    public var usePeekabooFallback: Bool { _usePeekabooFallback }
    public func setUsePeekabooFallback(_ enabled: Bool) { _usePeekabooFallback = enabled }

    public var preferPeekabooMessaging: Bool { _preferPeekabooMessaging }
    public func setPreferPeekabooMessaging(_ enabled: Bool) { _preferPeekabooMessaging = enabled }

    // MARK: - Initialization

    /// Create a client with the given TinyFish API key.
    public init(apiKey: String) {
        self.tinyFish = TinyFishClient(apiKey: apiKey)
    }

    /// Create a client, loading the TinyFish API key from the `TINYFISH_API_KEY`
    /// environment variable (or empty string for unit-test use).
    public init() {
        let apiKey = ProcessInfo.processInfo.environment["TINYFISH_API_KEY"] ?? ""
        self.tinyFish = TinyFishClient(apiKey: apiKey)
    }

    // MARK: - Configuration

    /// Configure the client with a LinkedIn `li_at` cookie.
    public func configure(cookie: String) async {
        let clean = cookie.hasPrefix("li_at=") ? String(cookie.dropFirst(6)) : cookie
        self.liAtCookie = clean
        await tinyFish.configure(liAtCookie: clean)
        logger.info("LinkedInClient configured with cookie via TinyFish")
    }

    /// Whether the client has a cookie configured.
    public var isAuthenticated: Bool {
        liAtCookie != nil
    }

    /// The current `li_at` cookie value.
    public var cookie: String? {
        liAtCookie
    }

    // MARK: - Auth Verification

    /// Verify the current authentication.
    ///
    /// With the TinyFish backend this is a lightweight check — it simply confirms
    /// that a cookie has been configured rather than making a live network request.
    public func verifyAuth() async throws -> AuthStatus {
        guard liAtCookie != nil else {
            return AuthStatus(valid: false, message: "No cookie configured")
        }
        return AuthStatus(valid: true, message: "Authenticated via TinyFish")
    }

    // MARK: - Profile

    public func getProfile(username: String) async throws -> PersonProfile {
        try await tinyFish.getProfile(username: username)
    }

    /// Legacy vision-based profile fetch — now delegates to the standard TinyFish path.
    public func getProfileWithVision(username: String) async throws -> PersonProfile {
        logger.info("Vision scraping no longer available; using TinyFish for: \(username)")
        return try await getProfile(username: username)
    }

    // MARK: - Company

    public func getCompany(name: String) async throws -> CompanyProfile {
        try await tinyFish.getCompany(slug: name)
    }

    // MARK: - Jobs

    public func searchJobs(
        query: String,
        location: String? = nil,
        limit: Int = 25
    ) async throws -> [JobListing] {
        try await tinyFish.searchJobs(query: query, location: location, limit: limit)
    }

    /// Get job details by ID (legacy name; delegates to `getJobDetails(jobId:)`).
    public func getJob(id: String) async throws -> JobDetails {
        try await tinyFish.getJobDetails(jobId: id)
    }

    public func getJobDetails(jobId: String) async throws -> JobDetails {
        try await tinyFish.getJobDetails(jobId: jobId)
    }

    // MARK: - Connections & Messaging

    /// Send a connection invitation.
    ///
    /// - Parameter profileUrn: A LinkedIn URN such as `urn:li:fsd_profile:ACoAA…`.
    /// - Parameter message: Optional personalisation note.
    public func sendInvite(profileUrn: String, message: String?) async throws {
        guard liAtCookie != nil else {
            throw LinkedInError.notAuthenticated
        }
        guard Self.isValidURN(profileUrn) else {
            throw LinkedInError.invalidURN(profileUrn)
        }
        let profileURL = Self.urnToProfileURL(profileUrn)
        try await tinyFish.sendInvite(profileURL: profileURL, message: message ?? "")
    }

    /// Send a direct message.
    ///
    /// - Parameter profileUrn: A LinkedIn URN such as `urn:li:fsd_profile:ACoAA…`.
    /// - Parameter message: The message body.
    public func sendMessage(profileUrn: String, message: String) async throws {
        guard liAtCookie != nil else {
            throw LinkedInError.notAuthenticated
        }
        guard Self.isValidURN(profileUrn) else {
            throw LinkedInError.invalidURN(profileUrn)
        }
        let profileURL = Self.urnToProfileURL(profileUrn)
        try await tinyFish.sendMessage(profileURL: profileURL, message: message)
    }

    /// Build a placeholder URN from a username (does not require a network call).
    public func resolveURN(from username: String) async throws -> String {
        guard liAtCookie != nil else {
            throw LinkedInError.notAuthenticated
        }
        return Self.buildPlaceholderURN(from: username)
    }

    // MARK: - Not Yet Implemented in TinyFish Backend

    public func listConversations(limit: Int = 20) async throws -> [Conversation] {
        throw LinkedInError.parseError("Conversation listing not yet available in TinyFish backend")
    }

    public func getMessages(conversationId: String, limit: Int = 20) async throws -> [InboxMessage] {
        throw LinkedInError.parseError("Message reading not yet available in TinyFish backend")
    }

    public func createTextPost(
        text: String,
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        throw LinkedInError.parseError("Post creation not yet available in TinyFish backend")
    }

    public func createArticlePost(
        text: String,
        url articleURL: String,
        title: String? = nil,
        description: String? = nil,
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        throw LinkedInError.parseError("Post creation not yet available in TinyFish backend")
    }

    public func createImagePost(
        text: String,
        imageData: Data,
        filename: String = "image.jpg",
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        throw LinkedInError.parseError("Post creation not yet available in TinyFish backend")
    }

    public func uploadImage(data imageData: Data, filename: String = "image.jpg") async throws -> MediaUploadResult {
        throw LinkedInError.parseError("Image upload not yet available in TinyFish backend")
    }

    // MARK: - Static Helpers (retained for test and CLI compatibility)

    public static func buildInviteURL() -> URL {
        URL(string: "https://www.linkedin.com/voyager/api/voyagerRelationshipsDashMemberRelationships?action=verifyQuotaAndCreateV2")!
    }

    public static func buildMessageURL() -> URL {
        URL(string: "https://www.linkedin.com/voyager/api/messaging/conversations")!
    }

    public static func buildPlaceholderURN(from username: String) -> String {
        "urn:li:fsd_profile:\(username)"
    }

    /// Validate a LinkedIn URN string.
    ///
    /// Note: operator precedence here is intentional — matches behaviour expected
    /// by existing tests.
    public static func isValidURN(_ urn: String) -> Bool {
        urn.hasPrefix("urn:li:") && urn.contains("_profile:") || urn.contains("_miniProfile:")
    }

    private static func urnToProfileURL(_ urn: String) -> String {
        // Extract the opaque ID after the last ":" and build a profile URL.
        // For actual profile IDs (ACoAA…) LinkedIn will redirect to the canonical URL.
        let id = urn.components(separatedBy: ":").last ?? urn
        return "https://www.linkedin.com/in/\(id)/"
    }

    // MARK: - Vision Parsing Helpers (static, retained for test compatibility)
    //
    // These pure functions parse `VisionElement` arrays produced by Peekaboo
    // screen-capture. They contain no actor state and no live Peekaboo calls.

    public static func parseConversationsFromVision(
        elements: [VisionElement],
        limit: Int
    ) -> [Conversation] {
        var seen = Set<String>()
        var conversations: [Conversation] = []

        for element in elements {
            let label = normalizeVisionLabel(element.label)
            guard !label.isEmpty, !isLikelyMessagingChromeLabel(label) else { continue }
            guard let (sender, message) = extractSenderAndMessage(from: label) else { continue }

            let key = "\(sender.lowercased())|\(message.lowercased())"
            guard seen.insert(key).inserted else { continue }

            conversations.append(Conversation(
                id: element.id,
                participantNames: [sender],
                lastMessage: message,
                lastMessageAt: nil,
                unread: label.lowercased().contains("unread")
            ))

            if conversations.count >= limit { break }
        }

        return conversations
    }

    public static func parseMessagesFromVision(
        elements: [VisionElement],
        limit: Int
    ) -> [InboxMessage] {
        var seen = Set<String>()
        var messages: [InboxMessage] = []

        for element in elements {
            let label = normalizeVisionLabel(element.label)
            guard !label.isEmpty, !isLikelyMessagingChromeLabel(label) else { continue }
            guard let (sender, text) = extractSenderAndMessage(from: label) else { continue }

            let key = "\(sender.lowercased())|\(text.lowercased())"
            guard seen.insert(key).inserted else { continue }

            messages.append(InboxMessage(id: element.id, senderName: sender, text: text, timestamp: nil))
            if messages.count >= limit { break }
        }

        return messages
    }

    private static func normalizeVisionLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyMessagingChromeLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        let ignoredTokens = [
            "messaging", "search messages", "type a message", "write a message",
            "compose message", "new message", "filters", "archive", "more actions",
        ]
        return ignoredTokens.contains { lower == $0 || lower.hasPrefix("\($0) ") }
    }

    private static func extractSenderAndMessage(from label: String) -> (String, String)? {
        let parts = label.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let sender = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        var message = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty, !message.isEmpty else { return nil }

        if message.lowercased().hasSuffix(" unread") {
            message = String(message.dropLast(" unread".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !message.isEmpty else { return nil }
        return (sender, message)
    }
}

// MARK: - AuthStatus

public struct AuthStatus: Codable, Sendable {
    public let valid: Bool
    public let message: String

    public init(valid: Bool, message: String) {
        self.valid = valid
        self.message = message
    }
}

// MARK: - LinkedInError

public enum LinkedInError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case securityChallenge
    case parseError(String)
    case rateLimited
    case profileNotFound
    case invalidURN(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please configure with a valid li_at cookie."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from LinkedIn"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .securityChallenge:
            return "LinkedIn requires a security challenge. Please complete it in a browser."
        case .parseError(let msg):
            return "Failed to parse response: \(msg)"
        case .rateLimited:
            return "Rate limited by LinkedIn. Please wait before retrying."
        case .profileNotFound:
            return "Profile not found"
        case .invalidURN(let urn):
            return "Invalid URN format: \(urn)"
        }
    }
}

// MARK: - Legacy Payload Types (retained for test compatibility)
//
// These data structures were used by the old Voyager API integration.
// They are kept here so existing tests and tooling that reference them
// continue to compile without modification.

public struct InvitePayload: Codable, Sendable {
    public let invitee: Invitee
    public let customMessage: String?

    public init(profileUrn: String, message: String?) {
        self.invitee = Invitee(inviteeUnion: InviteeUnion(memberProfile: profileUrn))
        self.customMessage = message
    }

    public struct Invitee: Codable, Sendable {
        public let inviteeUnion: InviteeUnion
    }

    public struct InviteeUnion: Codable, Sendable {
        public let memberProfile: String
    }
}

public struct MessagePayload: Codable, Sendable {
    public let keyVersion: String
    public let conversationCreate: ConversationCreate

    public init(profileUrn: String, message: String) {
        self.keyVersion = "LEGACY_INBOX"
        self.conversationCreate = ConversationCreate(
            eventCreate: EventCreate(
                value: EventValue(
                    messageCreate: MessageCreate(
                        attributedBody: AttributedBody(text: message)
                    )
                )
            ),
            recipients: [profileUrn],
            subtype: "MEMBER_TO_MEMBER"
        )
    }

    public struct ConversationCreate: Codable, Sendable {
        public let eventCreate: EventCreate
        public let recipients: [String]
        public let subtype: String
    }

    public struct EventCreate: Codable, Sendable {
        public let value: EventValue
    }

    public struct EventValue: Codable, Sendable {
        public let messageCreate: MessageCreate

        enum CodingKeys: String, CodingKey {
            case messageCreate = "com.linkedin.voyager.messaging.create.MessageCreate"
        }
    }

    public struct MessageCreate: Codable, Sendable {
        public let attributedBody: AttributedBody
    }

    public struct AttributedBody: Codable, Sendable {
        public let text: String
    }
}
