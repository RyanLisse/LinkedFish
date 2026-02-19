import Foundation
import LinkLion
import Logging
import MCP

@main
struct LinkedInMCPMain {
    static func main() async throws {
        var logger = Logger(label: "linkedin.mcp")
        logger.logLevel = .info

        let server = Server(
            name: "linkedin",
            version: LinkLion.version,
            capabilities: .init(
                logging: .init(),
                tools: .init()
            )
        )

        let handler = LinkedInToolHandler(server: server, logger: logger)

        await server.withMethodHandler(ListTools.self) { _ in
            await handler.listTools()
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handler.callTool(params)
        }

        logger.info("Starting LinkedIn MCP Server v\(LinkLion.version)")
        logger.info("Tools: linkedin_status, linkedin_configure, linkedin_get_profile, linkedin_get_company, linkedin_search_jobs, linkedin_get_job, linkedin_send_invite, linkedin_send_message")

        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)

        await server.waitUntilCompleted()
    }
}

// MARK: - MCP Logging

public struct LoggingMessageNotification: MCP.Notification {
    public static let name = "notifications/message"

    public struct Parameters: Hashable, Codable, Sendable {
        public let level: String
        public let logger: String?
        public let data: Value

        public init(level: String, logger: String? = nil, data: Value) {
            self.level = level
            self.logger = logger
            self.data = data
        }
    }
}

public enum LogLevel: String {
    case debug, info, notice, warning, error, critical
}

extension Server {
    func log(_ level: LogLevel, _ message: String, logger: String? = nil) async {
        do {
            let params = LoggingMessageNotification.Parameters(
                level: level.rawValue,
                logger: logger,
                data: .string(message)
            )
            let msg: Message<LoggingMessageNotification> = LoggingMessageNotification.message(params)
            try await self.notify(msg)
        } catch {
            // Silently fail - logging shouldn't crash the server
        }
    }
}

// MARK: - Tool Handler

actor LinkedInToolHandler {
    private var client: LinkedInClient?
    private let credentialStore: CredentialStore
    private let server: Server
    private let logger: Logger

    init(server: Server, logger: Logger) {
        self.server = server
        self.logger = logger
        self.credentialStore = CredentialStore()
    }

    func listTools() -> ListTools.Result {
        ListTools.Result(tools: Self.tools)
    }

    func callTool(_ params: CallTool.Parameters) async -> CallTool.Result {
        let toolName = params.name
        let args = params.arguments ?? [:]

        await server.log(.debug, "Calling tool: \(toolName)", logger: "linkedin")

        switch toolName {
        case "linkedin_status":
            return await handleStatus()
        case "linkedin_configure":
            return await handleConfigure(args)
        case "linkedin_get_profile":
            return await handleGetProfile(args)
        case "linkedin_get_company":
            return await handleGetCompany(args)
        case "linkedin_search_jobs":
            return await handleSearchJobs(args)
        case "linkedin_get_job":
            return await handleGetJob(args)
        case "linkedin_create_post":
            return await handleCreatePost(args)
        case "linkedin_upload_image":
            return await handleUploadImage(args)
        case "linkedin_list_conversations":
            return await handleListConversations(args)
        case "linkedin_get_messages":
            return await handleGetMessages(args)
        case "linkedin_send_invite":
            return await handleSendInvite(args)
        case "linkedin_send_message":
            return await handleSendMessage(args)
        default:
            return CallTool.Result(
                content: [.text("Unknown tool: \(toolName)")],
                isError: true
            )
        }
    }

    // MARK: - Client Management

    private func getClient() async throws -> LinkedInClient {
        if let client = self.client {
            return client
        }
        
        let cookie = try credentialStore.loadCookie()
        let hasTinyFish = (try credentialStore.loadTinyFishAPIKey()) != nil
        
        guard cookie != nil || hasTinyFish else {
            throw LinkedInMCPError.notAuthenticated(
                "Not authenticated. Use linkedin_configure to set the li_at cookie or tinyfish_api_key."
            )
        }

        let client = LinkedInClient()
        if let cookie {
            await client.configure(cookie: cookie)
        }
        self.client = client

        await server.log(.info, "Client initialized with stored credentials", logger: "linkedin")
        return client
    }
    
    private func getMessagingClient(browserMode: Bool) async throws -> LinkedInClient {
        if !browserMode {
            return try await getClient()
        }
        
        let client = LinkedInClient()
        if let cookie = try credentialStore.loadCookie() {
            await client.configure(cookie: cookie)
        }
        await client.setPreferPeekabooMessaging(true)
        return client
    }

    // MARK: - Tool Implementations

    private func handleStatus() async -> CallTool.Result {
        do {
            let client = try await getClient()
            let status = try await client.verifyAuth()
            let hasTinyFish = (try? credentialStore.loadTinyFishAPIKey()) != nil
            let response = MCPStatusResponse(
                authenticated: status.valid,
                message: status.message,
                tinyfishConfigured: hasTinyFish
            )
            await server.log(.info, "Auth status: \(status.valid ? "valid" : "invalid")", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(response))])
        } catch {
            let hasTinyFish = (try? credentialStore.loadTinyFishAPIKey()) != nil
            let response = MCPStatusResponse(
                authenticated: false,
                message: error.localizedDescription,
                tinyfishConfigured: hasTinyFish
            )
            return CallTool.Result(content: [.text(toJSON(response))])
        }
    }

    private func handleConfigure(_ args: [String: Value]) async -> CallTool.Result {
        let cookie = args["cookie"]?.stringValue
        let tinyFishAPIKey = args["tinyfish_api_key"]?.stringValue
        
        guard cookie != nil || tinyFishAPIKey != nil else {
            return CallTool.Result(
                content: [.text("Missing required parameter: cookie or tinyfish_api_key")],
                isError: true
            )
        }

        do {
            if let cookie {
                try credentialStore.saveCookie(cookie)
            }
            
            if let tinyFishAPIKey {
                try credentialStore.saveTinyFishAPIKey(tinyFishAPIKey)
            }
            
            self.client = nil
            let client = try await getClient()

            let status = try await client.verifyAuth()
            let hasTinyFish = (try credentialStore.loadTinyFishAPIKey()) != nil

            await server.log(.info, "Cookie configured, auth: \(status.valid ? "valid" : "invalid")", logger: "linkedin")

            if status.valid {
                return CallTool.Result(content: [.text(
                    #"{"success": true, "message": "Credentials saved and verified successfully", "tinyfish_configured": \#(hasTinyFish)}"#
                )])
            } else {
                return CallTool.Result(content: [.text(
                    #"{"success": true, "warning": "\#(status.message)", "message": "Credentials saved but verification failed", "tinyfish_configured": \#(hasTinyFish)}"#
                )])
            }
        } catch {
            return CallTool.Result(
                content: [.text("Failed to save credentials: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func handleGetProfile(_ args: [String: Value]) async -> CallTool.Result {
        guard let usernameOrURL = args["username"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: username")],
                isError: true
            )
        }

        guard let username = extractUsername(from: usernameOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid username or URL: \(usernameOrURL)")],
                isError: true
            )
        }

        do {
            let client = try await getClient()
            await server.log(.info, "Fetching profile: \(username)", logger: "linkedin")

            let profile = try await client.getProfile(username: username)

            await server.log(.notice, "Profile fetched: \(profile.name)", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(profile))])
        } catch {
            await server.log(.error, "Failed to fetch profile: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to fetch profile: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func handleGetCompany(_ args: [String: Value]) async -> CallTool.Result {
        guard let nameOrURL = args["company"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: company")],
                isError: true
            )
        }

        guard let companyName = extractCompanyName(from: nameOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid company name or URL: \(nameOrURL)")],
                isError: true
            )
        }

        do {
            let client = try await getClient()
            await server.log(.info, "Fetching company: \(companyName)", logger: "linkedin")

            let company = try await client.getCompany(name: companyName)

            await server.log(.notice, "Company fetched: \(company.name)", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(company))])
        } catch {
            await server.log(.error, "Failed to fetch company: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to fetch company: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func handleSearchJobs(_ args: [String: Value]) async -> CallTool.Result {
        guard let query = args["query"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: query")],
                isError: true
            )
        }

        let location = args["location"]?.stringValue
        let limit = Int(args["limit"] ?? .int(25), strict: false) ?? 25

        do {
            let client = try await getClient()
            await server.log(.info, "Searching jobs: '\(query)' location=\(location ?? "any") limit=\(limit)", logger: "linkedin")

            let jobs = try await client.searchJobs(query: query, location: location, limit: limit)

            await server.log(.notice, "Found \(jobs.count) jobs", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(jobs))])
        } catch {
            await server.log(.error, "Job search failed: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Job search failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func handleGetJob(_ args: [String: Value]) async -> CallTool.Result {
        guard let jobIdOrURL = args["job_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: job_id")],
                isError: true
            )
        }

        guard let jobId = extractJobId(from: jobIdOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid job ID or URL: \(jobIdOrURL)")],
                isError: true
            )
        }

        do {
            let client = try await getClient()
            await server.log(.info, "Fetching job: \(jobId)", logger: "linkedin")

            let job = try await client.getJob(id: jobId)

            await server.log(.notice, "Job fetched: \(job.title) at \(job.company)", logger: "linkedin")
            return CallTool.Result(content: [.text(toJSON(job))])
        } catch {
            await server.log(.error, "Failed to fetch job: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to fetch job: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func handleCreatePost(_ args: [String: Value]) async -> CallTool.Result {
        guard let text = args["text"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: text")], isError: true)
        }
        let visStr = args["visibility"]?.stringValue ?? "public"
        let vis: PostVisibility = visStr.lowercased() == "connections" ? .connections : .public

        do {
            let client = try await getClient()
            let result: PostResult

            if let imagePath = args["image_path"]?.stringValue {
                let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
                let filename = URL(fileURLWithPath: imagePath).lastPathComponent
                result = try await client.createImagePost(text: text, imageData: imageData, filename: filename, visibility: vis)
            } else if let articleURL = args["url"]?.stringValue {
                let title = args["url_title"]?.stringValue
                let desc = args["url_description"]?.stringValue
                result = try await client.createArticlePost(text: text, url: articleURL, title: title, description: desc, visibility: vis)
            } else {
                result = try await client.createTextPost(text: text, visibility: vis)
            }
            return CallTool.Result(content: [.text(toJSON(result))])
        } catch {
            return CallTool.Result(content: [.text("Post failed: \(error.localizedDescription)")], isError: true)
        }
    }

    private func handleUploadImage(_ args: [String: Value]) async -> CallTool.Result {
        guard let imagePath = args["image_path"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: image_path")], isError: true)
        }
        do {
            let client = try await getClient()
            let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            let filename = URL(fileURLWithPath: imagePath).lastPathComponent
            let result = try await client.uploadImage(data: imageData, filename: filename)
            return CallTool.Result(content: [.text(toJSON(result))])
        } catch {
            return CallTool.Result(content: [.text("Upload failed: \(error.localizedDescription)")], isError: true)
        }
    }

    private func handleListConversations(_ args: [String: Value]) async -> CallTool.Result {
        let limit = Int(args["limit"] ?? .int(20), strict: false) ?? 20
        let browserMode = args["browser_mode"]?.boolValue ?? false
        do {
            let client = try await getMessagingClient(browserMode: browserMode)
            let conversations = try await client.listConversations(limit: limit)
            return CallTool.Result(content: [.text(toJSON(conversations))])
        } catch {
            return CallTool.Result(content: [.text("Failed to list conversations: \(error.localizedDescription)")], isError: true)
        }
    }

    private func handleGetMessages(_ args: [String: Value]) async -> CallTool.Result {
        guard let convId = args["conversation_id"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: conversation_id")], isError: true)
        }
        let limit = Int(args["limit"] ?? .int(20), strict: false) ?? 20
        let browserMode = args["browser_mode"]?.boolValue ?? false
        do {
            let client = try await getMessagingClient(browserMode: browserMode)
            let messages = try await client.getMessages(conversationId: convId, limit: limit)
            return CallTool.Result(content: [.text(toJSON(messages))])
        } catch {
            return CallTool.Result(content: [.text("Failed to get messages: \(error.localizedDescription)")], isError: true)
        }
    }

    private func handleSendInvite(_ args: [String: Value]) async -> CallTool.Result {
        guard let usernameOrURL = args["username"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: username")],
                isError: true
            )
        }

        guard let username = extractUsername(from: usernameOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid username or URL: \(usernameOrURL)")],
                isError: true
            )
        }

        let message = args["message"]?.stringValue

        do {
            let client = try await getClient()
            await server.log(.info, "Sending invite to: \(username)", logger: "linkedin")

            let urn = try await client.resolveURN(from: username)
            try await client.sendInvite(profileUrn: urn, message: message)

            await server.log(.notice, "Invite sent to: \(username)", logger: "linkedin")
            return CallTool.Result(content: [.text(
                #"{"success": true, "message": "Connection invitation sent to \#(username)"}"#
            )])
        } catch {
            await server.log(.error, "Failed to send invite: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to send invite: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func handleSendMessage(_ args: [String: Value]) async -> CallTool.Result {
        guard let usernameOrURL = args["username"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: username")],
                isError: true
            )
        }

        guard let username = extractUsername(from: usernameOrURL) else {
            return CallTool.Result(
                content: [.text("Invalid username or URL: \(usernameOrURL)")],
                isError: true
            )
        }

        guard let message = args["message"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameter: message")],
                isError: true
            )
        }

        do {
            let client = try await getClient()
            await server.log(.info, "Sending message to: \(username)", logger: "linkedin")

            let urn = try await client.resolveURN(from: username)
            try await client.sendMessage(profileUrn: urn, message: message)

            await server.log(.notice, "Message sent to: \(username)", logger: "linkedin")
            return CallTool.Result(content: [.text(
                #"{"success": true, "message": "Message sent to \#(username)"}"#
            )])
        } catch {
            await server.log(.error, "Failed to send message: \(error.localizedDescription)", logger: "linkedin")
            return CallTool.Result(
                content: [.text("Failed to send message: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Helpers

    private func toJSON<T: Codable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private struct MCPStatusResponse: Codable {
    let authenticated: Bool
    let message: String
    let tinyfishConfigured: Bool
}

// MARK: - Tool Definitions

extension LinkedInToolHandler {
    static var tools: [Tool] {
        [
            Tool(
                name: "linkedin_status",
                description: "Check LinkedIn authentication status. Returns whether the current session is valid and whether TinyFish is configured.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([:])
                ]),
                annotations: .init(
                    title: "Check Auth Status",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "linkedin_configure",
                description: """
                    Configure LinkedIn authentication with a li_at cookie and/or TinyFish API key.

                    To get the cookie:
                    1. Open LinkedIn in your browser and log in
                    2. Open Developer Tools (F12 or Cmd+Option+I)
                    3. Go to Application → Cookies → linkedin.com
                    4. Find the 'li_at' cookie and copy its value

                    Credentials are stored securely in the macOS Keychain.
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "cookie": .object([
                            "type": "string",
                            "description": "The li_at cookie value from LinkedIn"
                        ]),
                        "tinyfish_api_key": .object([
                            "type": "string",
                            "description": "TinyFish API key for web agent backend"
                        ])
                    ])
                ]),
                annotations: .init(
                    title: "Configure Authentication",
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: false
                )
            ),
            Tool(
                name: "linkedin_get_profile",
                description: """
                    Get a person's LinkedIn profile. Returns structured data including:
                    - Name, headline, location
                    - About/summary section
                    - Work experience history
                    - Education background
                    - Skills
                    - Open to work status
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "username": .object([
                            "type": "string",
                            "description": "LinkedIn username (e.g., 'johndoe') or full profile URL (https://linkedin.com/in/johndoe)"
                        ])
                    ]),
                    "required": .array(["username"])
                ]),
                annotations: .init(
                    title: "Get Person Profile",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_get_company",
                description: """
                    Get a company's LinkedIn profile. Returns structured data including:
                    - Company name and tagline
                    - About/description section
                    - Industry and company size
                    - Headquarters location
                    - Website URL
                    - Specialties/focus areas
                    - Employee and follower counts
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "company": .object([
                            "type": "string",
                            "description": "Company name/slug (e.g., 'microsoft', 'anthropic') or full company URL"
                        ])
                    ]),
                    "required": .array(["company"])
                ]),
                annotations: .init(
                    title: "Get Company Profile",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_search_jobs",
                description: """
                    Search for jobs on LinkedIn. Returns a list of job postings matching the search criteria.

                    Each result includes:
                    - Job ID and URL
                    - Title and company
                    - Location
                    - Posted date
                    - Salary (if shown)
                    - Easy Apply availability
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "query": .object([
                            "type": "string",
                            "description": "Search query - job title, skills, keywords, etc."
                        ]),
                        "location": .object([
                            "type": "string",
                            "description": "Location filter - city, state, country, or 'Remote'"
                        ]),
                        "limit": .object([
                            "type": "integer",
                            "description": "Maximum number of results to return (default: 25, max: 100)"
                        ])
                    ]),
                    "required": .array(["query"])
                ]),
                annotations: .init(
                    title: "Search Jobs",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_get_job",
                description: """
                    Get detailed information about a specific job posting. Returns:
                    - Full job title and company
                    - Complete job description
                    - Workplace type (Remote/On-site/Hybrid)
                    - Employment type (Full-time/Part-time/Contract)
                    - Experience level required
                    - Salary information (if available)
                    - Required skills
                    - Application count
                    - Easy Apply availability
                    """,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "job_id": .object([
                            "type": "string",
                            "description": "LinkedIn job ID (numeric) or full job URL (https://linkedin.com/jobs/view/1234567890)"
                        ])
                    ]),
                    "required": .array(["job_id"])
                ]),
                annotations: .init(
                    title: "Get Job Details",
                    readOnlyHint: true,
                    destructiveHint: false,
                    idempotentHint: true,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_create_post",
                description: "Create a LinkedIn post. Text-only, article/URL share, or image post.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "text": .object(["type": "string", "description": "Post text content"]),
                        "visibility": .object(["type": "string", "description": "'public' or 'connections'", "enum": .array(["public", "connections"])]),
                        "url": .object(["type": "string", "description": "URL to share as article"]),
                        "url_title": .object(["type": "string", "description": "Article title"]),
                        "url_description": .object(["type": "string", "description": "Article description"]),
                        "image_path": .object(["type": "string", "description": "Local image file path"])
                    ]),
                    "required": .array(["text"])
                ]),
                annotations: .init(title: "Create Post", readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
            ),
            Tool(
                name: "linkedin_upload_image",
                description: "Upload an image to LinkedIn and return the media URN.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "image_path": .object(["type": "string", "description": "Local image file path"])
                    ]),
                    "required": .array(["image_path"])
                ]),
                annotations: .init(title: "Upload Image", readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
            ),
            Tool(
                name: "linkedin_list_conversations",
                description: "List recent LinkedIn inbox conversations with participant names, last message preview, and unread status.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "limit": .object(["type": "integer", "description": "Max conversations (default 20)"]),
                        "browser_mode": .object(["type": "boolean", "description": "Force browser mode (Peekaboo/Safari) and bypass Voyager API"])
                    ])
                ]),
                annotations: .init(title: "List Conversations", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true)
            ),
            Tool(
                name: "linkedin_get_messages",
                description: "Read messages from a LinkedIn conversation.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "conversation_id": .object(["type": "string", "description": "Conversation ID"]),
                        "limit": .object(["type": "integer", "description": "Max messages (default 20)"]),
                        "browser_mode": .object(["type": "boolean", "description": "Force browser mode (Peekaboo/Safari) and bypass Voyager API"])
                    ]),
                    "required": .array(["conversation_id"])
                ]),
                annotations: .init(title: "Get Messages", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true)
            ),
            Tool(
                name: "linkedin_send_invite",
                description: "Send a connection invitation to a LinkedIn user.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "username": .object([
                            "type": "string",
                            "description": "LinkedIn username (e.g., 'johndoe') or full profile URL (https://linkedin.com/in/johndoe)"
                        ]),
                        "message": .object([
                            "type": "string",
                            "description": "Optional custom invitation note"
                        ])
                    ]),
                    "required": .array(["username"])
                ]),
                annotations: .init(title: "Send Invite", readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
            ),
            Tool(
                name: "linkedin_send_message",
                description: "Send a direct message to a LinkedIn user.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "username": .object([
                            "type": "string",
                            "description": "LinkedIn username (e.g., 'johndoe') or full profile URL (https://linkedin.com/in/johndoe)"
                        ]),
                        "message": .object([
                            "type": "string",
                            "description": "Message text to send"
                        ])
                    ]),
                    "required": .array(["username", "message"])
                ]),
                annotations: .init(title: "Send Message", readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
            ),
        ]
    }
}

// MARK: - Value Extensions

extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

func Int(_ value: Value, strict: Bool) -> Int? {
    switch value {
    case .int(let i): return i
    case .string(let s) where !strict: return Int(s)
    default: return nil
    }
}

// MARK: - Errors

enum LinkedInMCPError: Error, LocalizedError {
    case internalError(String)
    case methodNotFound(String)
    case invalidParams(String)
    case notAuthenticated(String)

    var errorDescription: String? {
        switch self {
        case .internalError(let msg): return "Internal error: \(msg)"
        case .methodNotFound(let msg): return "Method not found: \(msg)"
        case .invalidParams(let msg): return "Invalid parameters: \(msg)"
        case .notAuthenticated(let msg): return "Not authenticated: \(msg)"
        }
    }
}
