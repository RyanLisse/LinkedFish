import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Main client for interacting with LinkedIn
public actor LinkedInClient {
    private let session: URLSession
    private var liAtCookie: String?
    private let logger = Logger(label: "LinkedInKit")
    private let peekaboo: PeekabooClient
    private let gemini: GeminiVision
    
    // MARK: - Rate Limiting
    private var lastRequestTime: ContinuousClock.Instant?
    private var minimumRequestInterval: Duration = .milliseconds(1500)  // 1.5s between requests
    private var consecutiveErrors: Int = 0
    private var backoffUntil: ContinuousClock.Instant?
    
    /// Enable Peekaboo fallback for failed scrapes
    private var _usePeekabooFallback: Bool = true
    
    /// Prefer browser-based messaging over Voyager API for deterministic anti-bot avoidance
    private var _preferPeekabooMessaging: Bool = false
    
    /// In-memory cache of username → resolved URN to avoid repeated API calls
    private var urnCache: [String: String] = [:]
    
    public var usePeekabooFallback: Bool {
        _usePeekabooFallback
    }
    
    public func setUsePeekabooFallback(_ enabled: Bool) {
        _usePeekabooFallback = enabled
    }
    
    public var preferPeekabooMessaging: Bool {
        _preferPeekabooMessaging
    }
    
    public func setPreferPeekabooMessaging(_ enabled: Bool) {
        _preferPeekabooMessaging = enabled
    }
    
    private static let baseURL = "https://www.linkedin.com"
    private static let apiURL = "https://www.linkedin.com/voyager/api"
    
    public init(browser: String = "Safari") {
        self.peekaboo = PeekabooClient(browser: browser)
        self.gemini = GeminiVision()
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate, br",
            "DNT": "1",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
        ]
        self.session = URLSession(configuration: config)
    }
    
    /// Configure the client with a li_at cookie
    public func configure(cookie: String) {
        // Accept either just the value or "li_at=value" format
        if cookie.hasPrefix("li_at=") {
            self.liAtCookie = String(cookie.dropFirst(6))
        } else {
            self.liAtCookie = cookie
        }
        logger.info("LinkedIn client configured with cookie")
    }
    
    /// Check if the client is authenticated
    public var isAuthenticated: Bool {
        liAtCookie != nil
    }
    
    /// Get the current cookie value
    public var cookie: String? {
        liAtCookie
    }
    
    /// Verify the current authentication is valid
    public func verifyAuth() async throws -> AuthStatus {
        guard let cookie = liAtCookie else {
            return AuthStatus(valid: false, message: "No cookie configured")
        }
        
        // Try to fetch the feed to verify auth
        let url = URL(string: "\(Self.baseURL)/feed/")!
        var request = URLRequest(url: url)
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        
        let (_, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return AuthStatus(valid: false, message: "Invalid response")
        }
        
        // If we get redirected to login, auth is invalid
        if httpResponse.url?.path.contains("login") == true || 
           httpResponse.url?.path.contains("checkpoint") == true {
            return AuthStatus(valid: false, message: "Cookie expired or invalid")
        }
        
        if httpResponse.statusCode == 200 {
            return AuthStatus(valid: true, message: "Authenticated")
        }
        
        return AuthStatus(valid: false, message: "HTTP \(httpResponse.statusCode)")
    }
    
    // MARK: - Profile Scraping
    
    /// Get a person's LinkedIn profile
    /// Uses HTML scraping first, falls back to Peekaboo vision if enabled
    public func getProfile(username: String) async throws -> PersonProfile {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let profileURL = "\(Self.baseURL)/in/\(username)/"
        logger.info("Fetching profile: \(username)")
        
        do {
            let html = try await fetchPage(url: profileURL, cookie: cookie)
            let profile = try ProfileParser.parsePersonProfile(html: html, username: username)
            
            // Check if we got meaningful data
            if !profile.name.isEmpty && profile.name != "LinkedIn" {
                return profile
            }
            
            // Data is incomplete, try Peekaboo if enabled
            if _usePeekabooFallback {
                logger.info("HTML parsing returned minimal data, trying Peekaboo vision...")
                return try await getProfileWithVision(username: username)
            }
            
            return profile
        } catch {
            // On error, try Peekaboo fallback
            if _usePeekabooFallback {
                logger.warning("HTML scraping failed: \(error). Trying Peekaboo fallback...")
                return try await getProfileWithVision(username: username)
            }
            throw error
        }
    }
    
    /// Get profile using Peekaboo browser automation and Gemini Vision
    public func getProfileWithVision(username: String) async throws -> PersonProfile {
        logger.info("Fetching profile with Peekaboo vision: \(username)")
        
        // Capture screenshot
        let capture = try await peekaboo.captureScreen()
        logger.info("Screenshot saved: \(capture.path)")
        
        // Analyze with Gemini Vision
        let analysis = try await gemini.analyzeProfile(imagePath: capture.path)
        logger.info("Gemini analysis complete")
        
        // Convert analysis to PersonProfile
        return PersonProfile(
            username: username,
            name: analysis.name ?? username,
            headline: analysis.headline,
            about: analysis.about,
            location: analysis.location,
            company: analysis.company,
            jobTitle: analysis.jobTitle,
            experiences: analysis.experiences.map { exp in
                Experience(
                    title: exp.title,
                    company: exp.company,
                    location: exp.location,
                    startDate: nil,
                    endDate: nil,
                    duration: exp.duration,
                    description: nil
                )
            },
            educations: analysis.educations.map { edu in
                Education(
                    institution: edu.institution,
                    degree: edu.degree,
                    startDate: nil,
                    endDate: edu.years
                )
            },
            skills: analysis.skills,
            connectionCount: analysis.connectionCount,
            followerCount: analysis.followerCount,
            openToWork: analysis.openToWork
        )
    }
    
    
    
    /// Get a company's LinkedIn profile
    public func getCompany(name: String) async throws -> CompanyProfile {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let companyURL = "\(Self.baseURL)/company/\(name)/"
        logger.info("Fetching company: \(name)")
        
        let html = try await fetchPage(url: companyURL, cookie: cookie)
        return try ProfileParser.parseCompanyProfile(html: html, companyName: name)
    }
    
    // MARK: - Job Search
    
    /// Search for jobs
    public func searchJobs(query: String, location: String? = nil, limit: Int = 25) async throws -> [JobListing] {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        var urlComponents = URLComponents(string: "\(Self.baseURL)/jobs/search/")!
        var queryItems = [
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "refresh", value: "true"),
        ]
        
        if let location = location {
            queryItems.append(URLQueryItem(name: "location", value: location))
        }
        
        urlComponents.queryItems = queryItems
        
        logger.info("Searching jobs: \(query)")
        
        let html = try await fetchPage(url: urlComponents.url!.absoluteString, cookie: cookie)
        return try JobParser.parseJobSearch(html: html, limit: limit)
    }
    
    /// Get details for a specific job
    public func getJob(id: String) async throws -> JobDetails {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        let jobURL = "\(Self.baseURL)/jobs/view/\(id)/"
        logger.info("Fetching job: \(id)")
        
        let html = try await fetchPage(url: jobURL, cookie: cookie)
        return try JobParser.parseJobDetails(html: html, jobId: id)
    }
    
    
// MARK: - Connections & Messaging
    
    /// Send a connection invitation to a LinkedIn profile
    /// - Parameters:
    ///   - profileUrn: The URN of the profile (e.g., "urn:li:fsd_profile:ACoAA...")
    ///   - message: Optional custom message to include with the invitation
    public func sendInvite(profileUrn: String, message: String?) async throws {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        guard Self.isValidURN(profileUrn) else {
            throw LinkedInError.invalidURN(profileUrn)
        }
        
        logger.info("Sending invite to: \(profileUrn)")
        
        let url = Self.buildInviteURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.linkedin.normalized+json+2.1", forHTTPHeaderField: "Accept")
        request.setValue("2.0.0", forHTTPHeaderField: "X-RestLi-Protocol-Version")
        request.setValue("en_US", forHTTPHeaderField: "X-Li-Lang")
        
        let payload = InvitePayload(profileUrn: profileUrn, message: message)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (_, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LinkedInError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }
        
        logger.info("Invite sent successfully")
    }
    
    /// Send a message to a LinkedIn profile
    /// - Parameters:
    ///   - profileUrn: The URN of the profile (e.g., "urn:li:fsd_profile:ACoAA...")
    ///   - message: The message content to send
    public func sendMessage(profileUrn: String, message: String) async throws {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        
        guard Self.isValidURN(profileUrn) else {
            throw LinkedInError.invalidURN(profileUrn)
        }
        
        logger.info("Sending message to: \(profileUrn)")
        
        let url = Self.buildMessageURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.linkedin.normalized+json+2.1", forHTTPHeaderField: "Accept")
        request.setValue("2.0.0", forHTTPHeaderField: "X-RestLi-Protocol-Version")
        request.setValue("en_US", forHTTPHeaderField: "X-Li-Lang")
        
        let payload = MessagePayload(profileUrn: profileUrn, message: message)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (_, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw LinkedInError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }
        
        logger.info("Message sent successfully")
    }
    
    /// Resolve a username to a real LinkedIn URN via the Voyager API
    /// Results are cached in-memory to avoid repeated API calls for the same username.
    public func resolveURN(from username: String) async throws -> String {
        guard liAtCookie != nil else {
            throw LinkedInError.notAuthenticated
        }
        
        // Check cache first
        if let cached = urnCache[username] {
            logger.info("Resolved URN from cache for \(username): \(cached)")
            return cached
        }
        
        logger.info("Resolving URN for username: \(username)")
        
        let request = try await voyagerRequest(path: "/identity/profiles/\(username)/profileView")
        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }
        
        // Handle specific error codes
        if httpResponse.statusCode == 404 {
            throw LinkedInError.parseError("Profile not found: \(username)")
        }
        if httpResponse.statusCode == 429 {
            throw LinkedInError.rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }
        
        // Parse JSON to find entityUrn
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinkedInError.parseError("Invalid JSON response for profile: \(username)")
        }
        
        // Try multiple paths — LinkedIn changes their response format
        // Path 1: data.profile.miniProfile.entityUrn
        if let profile = json["profile"] as? [String: Any],
           let miniProfile = profile["miniProfile"] as? [String: Any],
           let entityUrn = miniProfile["entityUrn"] as? String,
           Self.isValidURN(entityUrn) {
            logger.info("Resolved URN via miniProfile: \(entityUrn)")
            urnCache[username] = entityUrn
            return entityUrn
        }
        
        // Path 2: data.profile.entityUrn
        if let profile = json["profile"] as? [String: Any],
           let entityUrn = profile["entityUrn"] as? String,
           Self.isValidURN(entityUrn) {
            logger.info("Resolved URN via profile: \(entityUrn)")
            urnCache[username] = entityUrn
            return entityUrn
        }
        
        // Path 3: Search through included elements
        if let included = json["included"] as? [[String: Any]] {
            for element in included {
                if let entityUrn = element["entityUrn"] as? String,
                   entityUrn.contains("fsd_profile:") || entityUrn.contains("fs_miniProfile:") {
                    logger.info("Resolved URN via included: \(entityUrn)")
                    urnCache[username] = entityUrn
                    return entityUrn
                }
            }
        }
        
        // Path 4: data.entityUrn directly
        if let entityUrn = json["entityUrn"] as? String, Self.isValidURN(entityUrn) {
            logger.info("Resolved URN via root: \(entityUrn)")
            urnCache[username] = entityUrn
            return entityUrn
        }
        
        throw LinkedInError.parseError("Could not resolve URN for username: \(username). Profile may not exist or response format changed.")
    }
    
    // MARK: - Static Helpers
    
    public static func buildInviteURL() -> URL {
        URL(string: "\(apiURL)/voyagerRelationshipsDashMemberRelationships?action=verifyQuotaAndCreateV2")!
    }
    
    public static func buildMessageURL() -> URL {
        URL(string: "\(apiURL)/messaging/conversations")!
    }
    
    /// Build a placeholder URN from a username string.
    /// ⚠️ For testing only — these are NOT real LinkedIn URNs and will be rejected by the API.
    /// Use `resolveURN(from:)` to get a real URN via the Voyager API.
    public static func buildPlaceholderURN(from username: String) -> String {
        "urn:li:fsd_profile:\(username)"
    }
    
    public static func isValidURN(_ urn: String) -> Bool {
        urn.hasPrefix("urn:li:") && (urn.contains("_profile:") || urn.contains("_miniProfile:"))
    }
    
    
// MARK: - CSRF Token

    /// Generate a CSRF token for Voyager API requests.
    /// LinkedIn's CSRF protection just requires the csrf-token header to match a JSESSIONID cookie value.
    /// We generate a random one and send both.
    private func generateCSRFToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let token = String((0..<16).map { _ in chars.randomElement()! })
        return token
    }

    /// Build an authenticated Voyager API request
    private func voyagerRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }

        let csrfToken = generateCSRFToken()
        let url = URL(string: "\(Self.apiURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("li_at=\(cookie); JSESSIONID=\"\(csrfToken)\"", forHTTPHeaderField: "Cookie")
        request.setValue("ajax:\(csrfToken)", forHTTPHeaderField: "csrf-token")
        request.setValue("2.0.0", forHTTPHeaderField: "X-Restli-Protocol-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.linkedin.normalized+json+2.1", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    // MARK: - Get Current User URN

    /// Get the authenticated user's profile URN (needed for posting)
    public func getMyProfileURN() async throws -> String {
        let request = try await voyagerRequest(path: "/identity/profiles/me")
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LinkedInError.invalidResponse
        }

        // Parse the miniProfile or profile ID from response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Try multiple paths to find the profile ID
            if let miniProfile = json["miniProfile"] as? [String: Any],
               let entityUrn = miniProfile["entityUrn"] as? String {
                return entityUrn
            }
            if let entityUrn = json["entityUrn"] as? String {
                return entityUrn
            }
            if let plainId = json["plainId"] as? Int {
                return "urn:li:fsd_profile:\(plainId)"
            }
        }

        throw LinkedInError.parseError("Could not determine profile URN")
    }

    // MARK: - Post Creation

    /// Create a text-only LinkedIn post
    public func createTextPost(text: String, visibility: PostVisibility = .public) async throws -> PostResult {
        let connectionsOnly = visibility == .connections

        let payload: [String: Any] = [
            "visibleToConnectionsOnly": connectionsOnly,
            "externalAudienceProviders": [] as [Any],
            "commentaryV2": [
                "text": text,
                "attributes": [] as [Any]
            ] as [String: Any],
            "origin": "FEED",
            "allowedCommentersScope": "ALL",
            "postState": "PUBLISHED"
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await voyagerRequest(
            path: "/contentCreation/normShares",
            method: "POST",
            body: body
        )

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
            // Try to extract post URN from response or headers
            var postURN: String?
            if let restliId = httpResponse.value(forHTTPHeaderField: "X-RestLi-Id") {
                postURN = restliId
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                postURN = json["urn"] as? String ?? json["id"] as? String
            }
            return PostResult(success: true, postURN: postURN, message: "Post created successfully")
        }

        // Parse error
        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            errorMsg = msg
        } else {
            errorMsg = "HTTP \(httpResponse.statusCode)"
        }
        return PostResult(success: false, message: errorMsg)
    }

    /// Create an article/URL share post
    public func createArticlePost(
        text: String,
        url articleURL: String,
        title: String? = nil,
        description: String? = nil,
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        let connectionsOnly = visibility == .connections

        var mediaObj: [String: Any] = [
            "status": "READY",
            "originalUrl": articleURL
        ]
        if let title = title {
            mediaObj["title"] = ["text": title]
        }
        if let description = description {
            mediaObj["description"] = ["text": description]
        }

        let payload: [String: Any] = [
            "visibleToConnectionsOnly": connectionsOnly,
            "externalAudienceProviders": [] as [Any],
            "commentaryV2": [
                "text": text,
                "attributes": [] as [Any]
            ] as [String: Any],
            "origin": "FEED",
            "allowedCommentersScope": "ALL",
            "postState": "PUBLISHED",
            "media": [
                [
                    "category": "ARTICLE",
                    "data": mediaObj
                ] as [String: Any]
            ] as [Any]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await voyagerRequest(
            path: "/contentCreation/normShares",
            method: "POST",
            body: body
        )

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
            var postURN: String?
            if let restliId = httpResponse.value(forHTTPHeaderField: "X-RestLi-Id") {
                postURN = restliId
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                postURN = json["urn"] as? String ?? json["id"] as? String
            }
            return PostResult(success: true, postURN: postURN, message: "Article post created successfully")
        }

        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            errorMsg = msg
        } else {
            errorMsg = "HTTP \(httpResponse.statusCode)"
        }
        return PostResult(success: false, message: errorMsg)
    }

    // MARK: - Media Upload

    /// Upload an image and return the media URN for use in posts
    public func uploadImage(data imageData: Data, filename: String = "image.jpg") async throws -> MediaUploadResult {
        // Step 1: Register the upload
        let registerPayload: [String: Any] = [
            "mediaUploadType": "IMAGE_SHARING",
            "fileSize": imageData.count,
            "filename": filename
        ]

        let registerBody = try JSONSerialization.data(withJSONObject: registerPayload)
        let registerRequest = try await voyagerRequest(
            path: "/voyagerMediaUploadMetadata?action=upload",
            method: "POST",
            body: registerBody
        )

        let (registerData, registerResponse) = try await performRequest(registerRequest)

        guard let registerHttp = registerResponse as? HTTPURLResponse,
              registerHttp.statusCode == 200 || registerHttp.statusCode == 201 else {
            let code = (registerResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw LinkedInError.httpError(code)
        }

        guard let registerJson = try? JSONSerialization.jsonObject(with: registerData) as? [String: Any],
              let valueObj = registerJson["value"] as? [String: Any] ?? registerJson["data"] as? [String: Any] else {
            throw LinkedInError.parseError("Could not parse upload registration response")
        }

        // Extract upload URL and media URN from various response shapes
        let uploadURL: String
        let mediaURN: String

        if let singleUpload = valueObj["singleUploadUrl"] as? String {
            uploadURL = singleUpload
        } else if let uploadMech = valueObj["uploadMechanism"] as? [String: Any] {
            if let httpUpload = uploadMech["com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest"] as? [String: Any],
               let url = httpUpload["uploadUrl"] as? String {
                uploadURL = url
            } else {
                throw LinkedInError.parseError("No upload URL in response")
            }
        } else {
            throw LinkedInError.parseError("No upload URL in response")
        }

        if let urn = valueObj["urn"] as? String {
            mediaURN = urn
        } else if let asset = valueObj["asset"] as? String {
            mediaURN = asset
        } else if let mediaId = valueObj["mediaId"] as? String {
            mediaURN = mediaId
        } else {
            throw LinkedInError.parseError("No media URN in response")
        }

        // Step 2: Upload the binary
        guard let uploadURLObj = URL(string: uploadURL) else {
            throw LinkedInError.invalidURL(uploadURL)
        }

        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }

        let csrfToken = generateCSRFToken()
        var uploadRequest = URLRequest(url: uploadURLObj)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("li_at=\(cookie); JSESSIONID=\"\(csrfToken)\"", forHTTPHeaderField: "Cookie")
        uploadRequest.setValue("ajax:\(csrfToken)", forHTTPHeaderField: "csrf-token")
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = imageData

        let (_, uploadResponse) = try await performRequest(uploadRequest)

        guard let uploadHttp = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHttp.statusCode) else {
            let code = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw LinkedInError.httpError(code)
        }

        logger.info("Image uploaded successfully: \(mediaURN)")
        return MediaUploadResult(mediaURN: mediaURN, uploadURL: uploadURL)
    }

    /// Create a post with an uploaded image
    public func createImagePost(
        text: String,
        imageData: Data,
        filename: String = "image.jpg",
        visibility: PostVisibility = .public
    ) async throws -> PostResult {
        // Upload image first
        let upload = try await uploadImage(data: imageData, filename: filename)

        let connectionsOnly = visibility == .connections

        let payload: [String: Any] = [
            "visibleToConnectionsOnly": connectionsOnly,
            "externalAudienceProviders": [] as [Any],
            "commentaryV2": [
                "text": text,
                "attributes": [] as [Any]
            ] as [String: Any],
            "origin": "FEED",
            "allowedCommentersScope": "ALL",
            "postState": "PUBLISHED",
            "media": [
                [
                    "category": "IMAGE",
                    "data": [
                        "status": "READY",
                        "media": upload.mediaURN
                    ] as [String: Any]
                ] as [String: Any]
            ] as [Any]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await voyagerRequest(
            path: "/contentCreation/normShares",
            method: "POST",
            body: body
        )

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
            var postURN: String?
            if let restliId = httpResponse.value(forHTTPHeaderField: "X-RestLi-Id") {
                postURN = restliId
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                postURN = json["urn"] as? String ?? json["id"] as? String
            }
            return PostResult(success: true, postURN: postURN, message: "Image post created successfully")
        }

        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            errorMsg = msg
        } else {
            errorMsg = "HTTP \(httpResponse.statusCode)"
        }
        return PostResult(success: false, message: errorMsg)
    }


    // MARK: - Inbox

    /// List recent conversations from LinkedIn inbox
    public func listConversations(limit: Int = 20) async throws -> [Conversation] {
        if _preferPeekabooMessaging {
            logger.info("Messaging browser mode enabled. Using Peekaboo for conversation list.")
            return try await listConversationsWithPeekaboo(limit: limit)
        }
        
        if _usePeekabooFallback, liAtCookie == nil {
            logger.info("No API cookie configured. Using Peekaboo messaging fallback.")
            return try await listConversationsWithPeekaboo(limit: limit)
        }

        do {
            let request = try await voyagerRequest(
                path: "/messaging/conversations?keyVersion=LEGACY_INBOX&count=\(limit)"
            )

            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw LinkedInError.httpError(code)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LinkedInError.parseError("Could not parse conversations response")
            }

            var conversations: [Conversation] = []

            // Parse the included entities for participant info
            let included = json["included"] as? [[String: Any]] ?? []
            var profileNames: [String: String] = [:]
            for entity in included {
                if let entityUrn = entity["entityUrn"] as? String,
                   entityUrn.contains("fsd_profile") || entityUrn.contains("miniProfile") {
                    let first = (entity["firstName"] as? String) ?? ""
                    let last = (entity["lastName"] as? String) ?? ""
                    let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        profileNames[entityUrn] = name
                    }
                }
            }

            // Parse elements (conversations)
            let elements = json["elements"] as? [[String: Any]] ?? []
            for element in elements {
                let entityUrn = element["entityUrn"] as? String ?? ""
                // Extract conversation ID from URN
                let convId = entityUrn.components(separatedBy: ":").last ?? entityUrn

                // Get participant names
                var participantNames: [String] = []
                if let participants = element["participants"] as? [[String: Any]] {
                    for p in participants {
                        if let participantUrn = (p["participantType"] as? [String: Any])?["member"] as? String,
                           let name = profileNames[participantUrn] {
                            participantNames.append(name)
                        }
                    }
                }
                // Fallback: check "*participants" key
                if participantNames.isEmpty,
                   let starParticipants = element["*participants"] as? [String] {
                    for urn in starParticipants {
                        if let name = profileNames[urn] {
                            participantNames.append(name)
                        }
                    }
                }

                // Last message
                var lastMessage: String?
                var lastMessageAt: String?
                if let events = element["events"] as? [[String: Any]],
                   let lastEvent = events.first {
                    if let eventContent = lastEvent["eventContent"] as? [String: Any],
                       let msgEvent = eventContent["com.linkedin.voyager.messaging.event.MessageEvent"] as? [String: Any],
                       let body = msgEvent["attributedBody"] as? [String: Any] {
                        lastMessage = body["text"] as? String
                    }
                    // Fallback: direct body
                    if lastMessage == nil {
                        if let body = lastEvent["body"] as? String {
                            lastMessage = body
                        }
                    }
                    if let ts = lastEvent["createdAt"] as? Int {
                        let date = Date(timeIntervalSince1970: Double(ts) / 1000.0)
                        let formatter = ISO8601DateFormatter()
                        lastMessageAt = formatter.string(from: date)
                    }
                }

                // Last activity time fallback
                if lastMessageAt == nil, let lastActivity = element["lastActivityAt"] as? Int {
                    let date = Date(timeIntervalSince1970: Double(lastActivity) / 1000.0)
                    let formatter = ISO8601DateFormatter()
                    lastMessageAt = formatter.string(from: date)
                }

                let unread = (element["unreadCount"] as? Int ?? 0) > 0

                conversations.append(Conversation(
                    id: convId,
                    participantNames: participantNames,
                    lastMessage: lastMessage,
                    lastMessageAt: lastMessageAt,
                    unread: unread
                ))
            }

            return conversations
        } catch LinkedInError.httpError(let code) where _usePeekabooFallback && Self.shouldUsePeekabooMessagingFallback(httpStatusCode: code) {
            logger.warning("Voyager messaging API returned HTTP \(code). Using Peekaboo fallback.")
            return try await listConversationsWithPeekaboo(limit: limit)
        } catch LinkedInError.notAuthenticated where _usePeekabooFallback {
            logger.warning("Voyager messaging API authentication failed. Using Peekaboo fallback.")
            return try await listConversationsWithPeekaboo(limit: limit)
        }
    }

    /// Get messages from a specific conversation
    public func getMessages(conversationId: String, limit: Int = 20) async throws -> [InboxMessage] {
        if _preferPeekabooMessaging {
            logger.info("Messaging browser mode enabled. Using Peekaboo for conversation messages.")
            return try await getMessagesWithPeekaboo(conversationId: conversationId, limit: limit)
        }
        
        if _usePeekabooFallback, liAtCookie == nil {
            logger.info("No API cookie configured. Using Peekaboo fallback for conversation messages.")
            return try await getMessagesWithPeekaboo(conversationId: conversationId, limit: limit)
        }

        do {
            let request = try await voyagerRequest(
                path: "/messaging/conversations/\(conversationId)/events?keyVersion=LEGACY_INBOX&count=\(limit)"
            )

            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw LinkedInError.httpError(code)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LinkedInError.parseError("Could not parse messages response")
            }

            var messages: [InboxMessage] = []

            // Parse included profiles
            let included = json["included"] as? [[String: Any]] ?? []
            var profileNames: [String: String] = [:]
            for entity in included {
                if let entityUrn = entity["entityUrn"] as? String {
                    let first = (entity["firstName"] as? String) ?? ""
                    let last = (entity["lastName"] as? String) ?? ""
                    let name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        profileNames[entityUrn] = name
                    }
                }
            }

            let elements = json["elements"] as? [[String: Any]] ?? []
            for element in elements {
                let eventId = (element["entityUrn"] as? String)?
                    .components(separatedBy: ",")
                    .last?
                    .trimmingCharacters(in: CharacterSet(charactersIn: ")")) ?? UUID().uuidString

                // Extract message text
                var text: String?
                if let eventContent = element["eventContent"] as? [String: Any],
                   let msgEvent = eventContent["com.linkedin.voyager.messaging.event.MessageEvent"] as? [String: Any],
                   let body = msgEvent["attributedBody"] as? [String: Any] {
                    text = body["text"] as? String
                }
                if text == nil {
                    text = element["body"] as? String
                }

                guard let messageText = text, !messageText.isEmpty else { continue }

                // Sender
                var senderName = "Unknown"
                if let from = element["from"] as? [String: Any],
                   let memberUrn = (from["com.linkedin.voyager.messaging.MessagingMember"] as? [String: Any])?["miniProfile"] as? String {
                    senderName = profileNames[memberUrn] ?? "Unknown"
                }
                // Fallback sender
                if senderName == "Unknown", let fromUrn = element["*from"] as? String {
                    senderName = profileNames[fromUrn] ?? "Unknown"
                }

                // Timestamp
                var timestamp: String?
                if let ts = element["createdAt"] as? Int {
                    let date = Date(timeIntervalSince1970: Double(ts) / 1000.0)
                    let formatter = ISO8601DateFormatter()
                    timestamp = formatter.string(from: date)
                }

                messages.append(InboxMessage(
                    id: eventId,
                    senderName: senderName,
                    text: messageText,
                    timestamp: timestamp
                ))
            }

            return messages
        } catch LinkedInError.httpError(let code) where _usePeekabooFallback && Self.shouldUsePeekabooMessagingFallback(httpStatusCode: code) {
            logger.warning("Voyager messages API returned HTTP \(code). Using Peekaboo fallback.")
            return try await getMessagesWithPeekaboo(conversationId: conversationId, limit: limit)
        } catch LinkedInError.notAuthenticated where _usePeekabooFallback {
            logger.warning("Voyager messages API authentication failed. Using Peekaboo fallback.")
            return try await getMessagesWithPeekaboo(conversationId: conversationId, limit: limit)
        }
    }

    // MARK: - Private Helpers

    private func listConversationsWithPeekaboo(limit: Int) async throws -> [Conversation] {
        try await peekaboo.navigate(to: "\(Self.baseURL)/messaging/")
        let vision = try await peekaboo.see()
        let conversations = Self.parseConversationsFromVision(elements: vision.elements, limit: limit)
        guard !conversations.isEmpty else {
            throw LinkedInError.parseError("Peekaboo did not detect any visible conversations")
        }
        return conversations
    }

    private func getMessagesWithPeekaboo(conversationId: String, limit: Int) async throws -> [InboxMessage] {
        let encodedId = conversationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationId
        try await peekaboo.navigate(to: "\(Self.baseURL)/messaging/thread/\(encodedId)/")
        let vision = try await peekaboo.see()
        let messages = Self.parseMessagesFromVision(elements: vision.elements, limit: limit)
        guard !messages.isEmpty else {
            throw LinkedInError.parseError("Peekaboo did not detect any visible messages")
        }
        return messages
    }

    static func shouldUsePeekabooMessagingFallback(httpStatusCode: Int) -> Bool {
        [401, 403, 404, 429].contains(httpStatusCode) || (500...599).contains(httpStatusCode)
    }

    static func parseConversationsFromVision(elements: [VisionElement], limit: Int) -> [Conversation] {
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

            if conversations.count >= limit {
                break
            }
        }

        return conversations
    }

    static func parseMessagesFromVision(elements: [VisionElement], limit: Int) -> [InboxMessage] {
        var seen = Set<String>()
        var messages: [InboxMessage] = []

        for element in elements {
            let label = normalizeVisionLabel(element.label)
            guard !label.isEmpty, !isLikelyMessagingChromeLabel(label) else { continue }
            guard let (sender, text) = extractSenderAndMessage(from: label) else { continue }

            let key = "\(sender.lowercased())|\(text.lowercased())"
            guard seen.insert(key).inserted else { continue }

            messages.append(InboxMessage(id: element.id, senderName: sender, text: text, timestamp: nil))
            if messages.count >= limit {
                break
            }
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
            "messaging",
            "search messages",
            "type a message",
            "write a message",
            "compose message",
            "new message",
            "filters",
            "archive",
            "more actions"
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

    // MARK: - Rate Limiting

    /// Wait for any active backoff period and enforce minimum request interval with jitter
    private func throttle() async throws {
        // Check backoff
        if let backoff = backoffUntil {
            let now = ContinuousClock.now
            if now < backoff {
                let remaining = backoff - now
                logger.warning("Rate limited. Backing off for \(remaining)")
                try await Task.sleep(for: remaining)
            }
            backoffUntil = nil
        }

        // Enforce minimum interval with jitter
        if let lastTime = lastRequestTime {
            let elapsed = ContinuousClock.now - lastTime
            let jitter = Duration.milliseconds(Int.random(in: 0...500))
            let required = minimumRequestInterval + jitter
            if elapsed < required {
                try await Task.sleep(for: required - elapsed)
            }
        }

        lastRequestTime = .now
    }

    /// Track rate limit responses and apply exponential backoff
    private func handleResponseStatus(_ statusCode: Int) {
        if statusCode == 429 {
            consecutiveErrors += 1
            let backoffSeconds = min(pow(2.0, Double(consecutiveErrors)) * 5, 300)  // 10s, 20s, 40s... max 5min
            backoffUntil = .now + .seconds(Int(backoffSeconds))
            logger.warning("Rate limited (429). Backoff: \(Int(backoffSeconds))s. Consecutive: \(consecutiveErrors)")
        } else if (200...299).contains(statusCode) {
            consecutiveErrors = 0
        }
    }

    /// Throttled wrapper around session.data(for:) — enforces rate limits and tracks 429s
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await throttle()
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            handleResponseStatus(httpResponse.statusCode)
        }
        return (data, response)
    }

    /// Check current rate limit status (for CLI/MCP reporting)
    public var rateLimitStatus: (isLimited: Bool, retryAfter: Duration?) {
        guard let backoff = backoffUntil else { return (false, nil) }
        let now = ContinuousClock.now
        if now >= backoff { return (false, nil) }
        return (true, backoff - now)
    }

    private func fetchPage(url: String, cookie: String) async throws -> String {
        guard let url = URL(string: url) else {
            throw LinkedInError.invalidURL(url)
        }

        var request = URLRequest(url: url)
        request.setValue("li_at=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInError.invalidResponse
        }

        if httpResponse.url?.path.contains("login") == true {
            throw LinkedInError.notAuthenticated
        }

        if httpResponse.url?.path.contains("checkpoint") == true {
            throw LinkedInError.securityChallenge
        }

        guard httpResponse.statusCode == 200 else {
            throw LinkedInError.httpError(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw LinkedInError.invalidResponse
        }

        return html
    }
}

// MARK: - Types

public struct AuthStatus: Codable, Sendable {
    public let valid: Bool
    public let message: String

    public init(valid: Bool, message: String) {
        self.valid = valid
        self.message = message
    }
}

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

// MARK: - Invite Payload

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

// MARK: - Message Payload

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
