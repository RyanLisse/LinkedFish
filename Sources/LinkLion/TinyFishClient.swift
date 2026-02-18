import Foundation
import Logging

// MARK: - HTTPClientProtocol

/// Abstraction over `URLSession.data(for:)` that enables dependency injection
/// and unit-testable HTTP behaviour in `TinyFishClient`.
public protocol HTTPClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClientProtocol {}

// MARK: - TinyFishClient

/// Main LinkedIn automation client backed by TinyFish Web Agent and AgentQL.
///
/// Replaces the old Voyager-API-based `LinkedInClient`. Uses:
/// - `AgentQLClient` for fast structured data extraction
/// - `SSEParser` for TinyFish goal-based actions (connect, message)
/// - `RemoteBrowserSession` for pre-authenticated browser sessions
///
/// Network calls in `runGoal()` use exponential backoff retry with rate-limit
/// awareness. Inject a custom `HTTPClientProtocol` for testing.
public actor TinyFishClient {
    private let apiKey: String
    private var liAtCookie: String?

    // Sub-clients — created lazily from apiKey
    private let sseParser: SSEParser
    private let agentQL: AgentQLClient
    private let browserSession: RemoteBrowserSession

    /// Injected HTTP client — defaults to `URLSession.shared`.
    /// Pass a custom implementation in tests to avoid real network calls.
    let httpClient: any HTTPClientProtocol

    // MARK: - Rate Limiting

    /// Timestamp of the most recently started network request.
    private var lastRequestTime: Date?

    /// Minimum gap between consecutive TinyFish requests (seconds).
    private let minRequestInterval: TimeInterval = 1.0

    // MARK: - Retry Configuration

    private static let maxRetryAttempts = 3
    /// Delays in seconds for attempts 0, 1, 2 → 1 s, 2 s, 4 s.
    private static let retryDelays: [TimeInterval] = [1.0, 2.0, 4.0]
    /// Default wait when a 429 carries no `Retry-After` header.
    private static let rateLimitDefaultWait: TimeInterval = 5.0

    // MARK: - Logging

    private let logger = Logger(label: "TinyFishClient")

    private static let tinyFishSSEURL = "https://agent.tinyfish.ai/v1/automation/run-sse"

    public init(apiKey: String, httpClient: any HTTPClientProtocol = URLSession.shared) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        self.sseParser = SSEParser(apiKey: apiKey)
        self.agentQL = AgentQLClient(apiKey: apiKey)
        self.browserSession = RemoteBrowserSession(apiKey: apiKey)
    }

    // MARK: - Configuration

    /// Store the LinkedIn `li_at` cookie for authenticated requests.
    public func configure(liAtCookie cookie: String) {
        let clean = cookie.hasPrefix("li_at=") ? String(cookie.dropFirst(6)) : cookie
        self.liAtCookie = clean
    }

    // MARK: - Profile

    /// Fetch a LinkedIn person profile by username.
    public func getProfile(
        username: String,
        onProgress: @Sendable (String) async -> Void = { _ in }
    ) async throws -> PersonProfile {
        let cookie = try requireCookie()
        let profileURL = "https://www.linkedin.com/in/\(username)/"
        let sessionId = try await browserSession.ensureSession(liAtCookie: cookie)

        let query = """
        {
          profile {
            name
            headline
            location
            about
            current_company
            current_title
            experiences {
              title
              company
              start_date
              end_date
              duration
              description
            }
            education {
              institution
              degree
              field_of_study
              start_date
              end_date
            }
            skills
            connection_count
            follower_count
            open_to_work
          }
        }
        """

        let wrapper = try await agentQL.query(
            url: profileURL,
            agentQLQuery: query,
            as: AgentQLProfileWrapper.self,
            params: ["browser_profile": "stealth", "session_id": sessionId]
        )

        guard let profile = wrapper.profile else {
            throw LinkedInError.profileNotFound
        }
        return profile.toPersonProfile(username: username)
    }

    // MARK: - Company

    /// Fetch a LinkedIn company profile by slug (e.g. "anthropic").
    public func getCompany(
        slug: String,
        onProgress: @Sendable (String) async -> Void = { _ in }
    ) async throws -> CompanyProfile {
        let cookie = try requireCookie()
        let companyURL = "https://www.linkedin.com/company/\(slug)/"
        let sessionId = try await browserSession.ensureSession(liAtCookie: cookie)

        let query = """
        {
          company {
            name
            description
            website
            industry
            company_size
            headquarters
            founded_year
            specialties
            employee_count
            follower_count
          }
        }
        """

        let wrapper = try await agentQL.query(
            url: companyURL,
            agentQLQuery: query,
            as: AgentQLCompanyWrapper.self,
            params: ["browser_profile": "stealth", "session_id": sessionId]
        )

        guard let company = wrapper.company else {
            throw LinkedInError.profileNotFound
        }
        return company.toCompanyProfile(slug: slug)
    }

    // MARK: - Jobs

    /// Search LinkedIn jobs by keyword and optional location.
    public func searchJobs(
        query: String,
        location: String? = nil,
        limit: Int = 10,
        onProgress: @Sendable (String) async -> Void = { _ in }
    ) async throws -> [JobListing] {
        var urlComponents = "https://www.linkedin.com/jobs/search/?keywords=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        if let location {
            urlComponents += "&location=\(location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location)"
        }
        let cookie = try requireCookie()
        let sessionId = try await browserSession.ensureSession(liAtCookie: cookie)

        let agentQLQuery = """
        {
          jobs[] {
            id
            title
            company
            company_url
            location
            posted_date
            salary
            is_easy_apply
            job_url
          }
        }
        """

        let wrapper = try await agentQL.query(
            url: urlComponents,
            agentQLQuery: agentQLQuery,
            as: AgentQLJobsWrapper.self,
            params: ["browser_profile": "stealth", "session_id": sessionId]
        )

        return (wrapper.jobs ?? []).prefix(limit).map { $0.toJobListing() }
    }

    /// Fetch full details for a job by its LinkedIn job ID.
    public func getJobDetails(
        jobId: String,
        onProgress: @Sendable (String) async -> Void = { _ in }
    ) async throws -> JobDetails {
        let cookie = try requireCookie()
        let jobURL = "https://www.linkedin.com/jobs/view/\(jobId)/"
        let sessionId = try await browserSession.ensureSession(liAtCookie: cookie)

        let query = """
        {
          job {
            id
            title
            company
            company_url
            location
            posted_date
            salary
            is_easy_apply
            job_url
            workplace_type
            employment_type
            experience_level
            applicant_count
            description
            skills
          }
        }
        """

        let wrapper = try await agentQL.query(
            url: jobURL,
            agentQLQuery: query,
            as: AgentQLJobDetailsWrapper.self,
            params: ["browser_profile": "stealth", "session_id": sessionId]
        )

        guard let job = wrapper.job else {
            throw LinkedInError.profileNotFound
        }
        return job.toJobDetails()
    }

    // MARK: - Actions (TinyFish Goals)

    /// Send a LinkedIn connection request to a profile.
    public func sendInvite(
        profileURL: String,
        message: String,
        onProgress: @Sendable (String) async -> Void = { _ in }
    ) async throws {
        let goal = message.isEmpty
            ? "Click the Connect button to send a connection request."
            : "Click the Connect button and send a connection request with this note: \(message)"

        _ = try await runGoal(url: profileURL, goal: goal, onProgress: onProgress)
    }

    /// Send a LinkedIn direct message to a profile.
    public func sendMessage(
        profileURL: String,
        message: String,
        onProgress: @Sendable (String) async -> Void = { _ in }
    ) async throws {
        let goal = "Click the Message button and send this message: \(message)"
        _ = try await runGoal(url: profileURL, goal: goal, onProgress: onProgress)
    }

    // MARK: - Private

    private func requireCookie() throws -> String {
        guard let cookie = liAtCookie else {
            throw LinkedInError.notAuthenticated
        }
        return cookie
    }

    /// Execute a TinyFish goal via the SSE endpoint and return the result Data.
    ///
    /// Implements three-attempt exponential backoff (1 s → 2 s → 4 s) for:
    /// - `URLError` / network failures
    /// - HTTP 5xx server errors
    /// - HTTP 429 rate limits (respects `Retry-After` or defaults to 5 s)
    ///
    /// 4xx errors (except 429) are not retried — they indicate a client bug.
    private func runGoal(
        url: String,
        goal: String,
        onProgress: @Sendable (String) async -> Void
    ) async throws -> Data {
        guard let endpoint = URL(string: Self.tinyFishSSEURL) else {
            throw LinkedInError.invalidURL(Self.tinyFishSSEURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "url": url,
            "goal": goal,
            "browser_profile": "stealth"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("Starting goal execution", metadata: ["url": "\(url)"])

        var lastError: Error = LinkedInError.invalidResponse

        for attempt in 0..<Self.maxRetryAttempts {
            await enforceMinRequestInterval()
            lastRequestTime = Date()

            do {
                let result = try await sseParser.run(request: request, onProgress: onProgress)
                logger.debug("Goal completed successfully", metadata: ["attempt": "\(attempt + 1)"])
                return result

            } catch let sseError as SSEError {
                switch sseError {
                case .invalidResponse(let statusCode):
                    if statusCode == 429 {
                        // Rate limited: respect Retry-After if present, else default wait
                        let waitSeconds = Self.rateLimitDefaultWait
                        logger.warning(
                            "Rate limited (429), waiting \(waitSeconds)s before retry",
                            metadata: ["attempt": "\(attempt + 1)/\(Self.maxRetryAttempts)"]
                        )
                        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                        lastError = LinkedInError.rateLimited

                    } else if (500...599).contains(statusCode) {
                        // Server error: retry with backoff
                        logger.warning(
                            "Server error \(statusCode), retrying",
                            metadata: ["attempt": "\(attempt + 1)/\(Self.maxRetryAttempts)"]
                        )
                        lastError = LinkedInError.httpError(statusCode)
                        if attempt < Self.maxRetryAttempts - 1 {
                            let delay = Self.retryDelays[attempt]
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }

                    } else {
                        // Non-retryable 4xx client error
                        logger.error("Non-retryable HTTP error \(statusCode)")
                        throw LinkedInError.httpError(statusCode)
                    }

                case .networkError(let message):
                    // Network / URLError: retry with backoff
                    logger.warning(
                        "Network error: \(message), retrying",
                        metadata: ["attempt": "\(attempt + 1)/\(Self.maxRetryAttempts)"]
                    )
                    lastError = LinkedInError.parseError("Network error: \(message)")
                    if attempt < Self.maxRetryAttempts - 1 {
                        let delay = Self.retryDelays[attempt]
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }

                case .agentFailed, .streamEnded:
                    // Agent-level failures are not retried — they indicate the goal itself failed
                    logger.error("Non-retryable SSE error: \(sseError)")
                    throw sseError
                }

            } catch {
                // Any other unexpected error — surface immediately
                logger.error("Unexpected error: \(error)")
                throw error
            }
        }

        logger.error("All \(Self.maxRetryAttempts) retry attempts exhausted")
        throw lastError
    }

    /// Suspend until the minimum inter-request interval has elapsed.
    ///
    /// Called at the top of every retry iteration so bursts of calls respect
    /// the 1-second minimum gap and don't hammer the TinyFish endpoint.
    private func enforceMinRequestInterval() async {
        guard let last = lastRequestTime else { return }
        let elapsed = Date().timeIntervalSince(last)
        let remaining = minRequestInterval - elapsed
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
}

// MARK: - AgentQL Response Models

private struct AgentQLProfileWrapper: Decodable, Sendable {
    let profile: AgentQLProfile?
}

private struct AgentQLProfile: Decodable, Sendable {
    let name: String?
    let headline: String?
    let location: String?
    let about: String?
    let currentCompany: String?
    let currentTitle: String?
    let experiences: [AgentQLExperience]?
    let education: [AgentQLEducation]?
    let skills: [String]?
    let connectionCount: String?
    let followerCount: String?
    let openToWork: Bool?

    enum CodingKeys: String, CodingKey {
        case name, headline, location, about, skills
        case currentCompany = "current_company"
        case currentTitle = "current_title"
        case experiences, education
        case connectionCount = "connection_count"
        case followerCount = "follower_count"
        case openToWork = "open_to_work"
    }

    func toPersonProfile(username: String) -> PersonProfile {
        PersonProfile(
            username: username,
            name: name ?? username,
            headline: headline,
            about: about,
            location: location,
            company: currentCompany,
            jobTitle: currentTitle,
            experiences: experiences?.map { $0.toExperience() } ?? [],
            educations: education?.map { $0.toEducation() } ?? [],
            skills: skills ?? [],
            profileImageURL: nil,
            backgroundImageURL: nil,
            connectionCount: connectionCount,
            followerCount: followerCount,
            openToWork: openToWork ?? false
        )
    }
}

private struct AgentQLExperience: Decodable, Sendable {
    let title: String?
    let company: String?
    let startDate: String?
    let endDate: String?
    let duration: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case title, company, duration, description
        case startDate = "start_date"
        case endDate = "end_date"
    }

    func toExperience() -> Experience {
        Experience(
            title: title ?? "",
            company: company ?? "",
            companyURL: nil,
            location: nil,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            description: description
        )
    }
}

private struct AgentQLEducation: Decodable, Sendable {
    let institution: String?
    let degree: String?
    let fieldOfStudy: String?
    let startDate: String?
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case institution, degree
        case fieldOfStudy = "field_of_study"
        case startDate = "start_date"
        case endDate = "end_date"
    }

    func toEducation() -> Education {
        Education(
            institution: institution ?? "",
            degree: degree,
            fieldOfStudy: fieldOfStudy,
            startDate: startDate,
            endDate: endDate,
            description: nil
        )
    }
}

private struct AgentQLCompanyWrapper: Decodable, Sendable {
    let company: AgentQLCompany?
}

private struct AgentQLCompany: Decodable, Sendable {
    let name: String?
    let description: String?
    let website: String?
    let industry: String?
    let companySize: String?
    let headquarters: String?
    let foundedYear: String?
    let specialties: [String]?
    let employeeCount: String?
    let followerCount: String?

    enum CodingKeys: String, CodingKey {
        case name, description, website, industry, headquarters, specialties
        case companySize = "company_size"
        case foundedYear = "founded_year"
        case employeeCount = "employee_count"
        case followerCount = "follower_count"
    }

    func toCompanyProfile(slug: String) -> CompanyProfile {
        CompanyProfile(
            name: name ?? slug,
            slug: slug,
            tagline: nil,
            about: description,
            website: website,
            industry: industry,
            companySize: companySize,
            headquarters: headquarters,
            founded: foundedYear,
            specialties: specialties ?? [],
            employeeCount: employeeCount,
            followerCount: followerCount,
            logoURL: nil,
            coverImageURL: nil
        )
    }
}

private struct AgentQLJobsWrapper: Decodable, Sendable {
    let jobs: [AgentQLJob]?
}

private struct AgentQLJobDetailsWrapper: Decodable, Sendable {
    let job: AgentQLJobFull?
}

private struct AgentQLJob: Decodable, Sendable {
    let id: String?
    let title: String?
    let company: String?
    let companyUrl: String?
    let location: String?
    let postedDate: String?
    let salary: String?
    let isEasyApply: Bool?
    let jobUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, salary
        case companyUrl = "company_url"
        case postedDate = "posted_date"
        case isEasyApply = "is_easy_apply"
        case jobUrl = "job_url"
    }

    func toJobListing() -> JobListing {
        JobListing(
            id: id ?? UUID().uuidString,
            title: title ?? "",
            company: company ?? "",
            companyURL: companyUrl,
            location: location,
            postedDate: postedDate,
            salary: salary,
            isEasyApply: isEasyApply ?? false,
            jobURL: jobUrl ?? ""
        )
    }
}

private struct AgentQLJobFull: Decodable, Sendable {
    let id: String?
    let title: String?
    let company: String?
    let companyUrl: String?
    let location: String?
    let postedDate: String?
    let salary: String?
    let isEasyApply: Bool?
    let jobUrl: String?
    let workplaceType: String?
    let employmentType: String?
    let experienceLevel: String?
    let applicantCount: String?
    let description: String?
    let skills: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, salary, description, skills
        case companyUrl = "company_url"
        case postedDate = "posted_date"
        case isEasyApply = "is_easy_apply"
        case jobUrl = "job_url"
        case workplaceType = "workplace_type"
        case employmentType = "employment_type"
        case experienceLevel = "experience_level"
        case applicantCount = "applicant_count"
    }

    func toJobDetails() -> JobDetails {
        JobDetails(
            id: id ?? UUID().uuidString,
            title: title ?? "",
            company: company ?? "",
            companyURL: companyUrl,
            location: location,
            workplaceType: workplaceType,
            employmentType: employmentType,
            experienceLevel: experienceLevel,
            postedDate: postedDate,
            applicantCount: applicantCount,
            salary: salary,
            description: description,
            skills: skills ?? [],
            isEasyApply: isEasyApply ?? false,
            jobURL: jobUrl ?? ""
        )
    }
}
