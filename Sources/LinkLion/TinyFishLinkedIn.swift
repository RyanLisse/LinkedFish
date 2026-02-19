import Foundation

/// LinkedIn-specific operations powered by TinyFish
extension TinyFishClient {

    // MARK: - Profile Operations

    /// Fetch a LinkedIn person profile
    public func getLinkedInProfile(username: String) async throws -> PersonProfile {
        let url = "https://www.linkedin.com/in/\(username)/"
        let goal = """
        Extract this person's complete LinkedIn profile as structured JSON with these exact fields:
        - name (full name)
        - headline (professional headline)
        - location (city, state/country)
        - about (summary/about section, full text)
        - currentCompany (current employer name)
        - currentTitle (current job title)
        - experiences: array of { title, company, duration, description, location }
        - educations: array of { school, degree, fieldOfStudy, dates }
        - skills: array of skill names
        - profileImageURL (profile photo URL)
        - connectionCount (e.g. "500+" or exact number)
        - followerCount
        - openToWork (boolean - is the "Open to work" badge visible?)
        Return ONLY the JSON, no other text.
        """

        let result = try await runAgent(url: url, goal: goal)
        return try mapToPersonProfile(result, username: username)
    }

    // MARK: - Company Operations

    public func getLinkedInCompany(name: String) async throws -> CompanyProfile {
        let url = "https://www.linkedin.com/company/\(name)/"
        let goal = """
        Extract this LinkedIn company profile as structured JSON with these exact fields:
        - name
        - tagline
        - about
        - website
        - industry
        - companySize
        - headquarters
        - founded
        - specialties (array of strings)
        - employeeCount
        - followerCount
        - logoURL
        Return ONLY the JSON, no other text.
        """

        let result = try await runAgent(url: url, goal: goal)
        return try mapToCompanyProfile(result, name: name)
    }

    // MARK: - Job Operations

    public func searchLinkedInJobs(query: String, location: String?, limit: Int = 10) async throws -> [JobListing] {
        let safeLimit = max(limit, 1)
        var components = URLComponents(string: "https://www.linkedin.com/jobs/search/")
        var items = [URLQueryItem(name: "keywords", value: query)]
        if let location, !location.isEmpty {
            items.append(URLQueryItem(name: "location", value: location))
        }
        components?.queryItems = items

        let url = components?.url?.absoluteString ?? "https://www.linkedin.com/jobs/search/?keywords=\(query)"

        let goal = """
        Find LinkedIn job results and return structured JSON with this shape:
        {
          "jobs": [
            {
              "id": "job id string",
              "title": "job title",
              "company": "company name",
              "companyURL": "company url if present",
              "location": "job location",
              "postedDate": "posted date text",
              "salary": "salary text",
              "isEasyApply": true/false,
              "jobURL": "absolute linkedin job URL"
            }
          ]
        }
        Return at most \(max(limit, 1)) jobs.
        Return ONLY the JSON, no other text.
        """

        let result = try await runAgent(url: url, goal: goal)
        var listings = try mapToJobListings(result)
        if listings.count > safeLimit {
            listings = Array(listings.prefix(safeLimit))
        }
        return listings
    }

    public func getLinkedInJob(id: String) async throws -> JobDetails {
        let url = "https://www.linkedin.com/jobs/view/\(id)/"
        let goal = """
        Extract this LinkedIn job's full details as JSON with these fields:
        - id
        - title
        - company
        - companyURL
        - location
        - workplaceType
        - employmentType
        - experienceLevel
        - postedDate
        - applicantCount
        - salary
        - description
        - skills (array of strings)
        - isEasyApply (boolean)
        - jobURL
        Return ONLY the JSON, no other text.
        """

        let result = try await runAgent(url: url, goal: goal)
        return try mapToJobDetails(result)
    }

    // MARK: - Authenticated Operations (require li_at cookie)

    public func sendLinkedInConnectionRequest(username: String, note: String?) async throws {
        let session = try await requireAuthenticatedSession()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteInstruction: String
        if let trimmedNote, !trimmedNote.isEmpty {
            noteInstruction = "Include this note exactly: \(trimmedNote)."
        } else {
            noteInstruction = "Do not add a note."
        }

        let url = "https://www.linkedin.com/in/\(username)/"
        let goal = """
        You are on a LinkedIn profile page. Send a connection request to this person. \(noteInstruction)
        Ensure the request is actually submitted.
        Return JSON: { "success": true }
        """

        _ = try await runAgent(url: url, goal: goal)
    }

    public func sendLinkedInMessage(username: String, message: String) async throws {
        _ = try await requireAuthenticatedSession()
        let url = "https://www.linkedin.com/in/\(username)/"
        let goal = """
        Open the message composer for this profile and send this exact message:
        \(message)
        Ensure the message is sent.
        Return JSON: { "success": true }
        """

        _ = try await runAgent(url: url, goal: goal)
    }

    public func createLinkedInPost(content: String, visibility: String) async throws {
        _ = try await requireAuthenticatedSession()
        let url = "https://www.linkedin.com/feed/"
        let goal = """
        Create a new LinkedIn post with the following content:
        \(content)

        Use visibility: \(visibility).
        Publish the post.
        Return JSON: { "success": true }
        """

        _ = try await runAgent(url: url, goal: goal)
    }

    public func getLinkedInInbox(limit: Int) async throws -> [Conversation] {
        _ = try await requireAuthenticatedSession()
        let safeLimit = max(limit, 1)
        let url = "https://www.linkedin.com/messaging/"
        let goal = """
        Read the LinkedIn inbox list and return JSON with this shape:
        {
          "conversations": [
            {
              "id": "conversation id",
              "participantNames": ["Person A", "Person B"],
              "lastMessage": "preview text",
              "lastMessageAt": "timestamp text",
              "unread": true/false
            }
          ]
        }
        Return at most \(safeLimit) conversations.
        Return ONLY the JSON.
        """

        let result = try await runAgent(url: url, goal: goal)
        var conversations = try mapToConversations(result)
        if conversations.count > safeLimit {
            conversations = Array(conversations.prefix(safeLimit))
        }
        return conversations
    }

    public func getLinkedInMessages(conversationId: String, limit: Int) async throws -> [InboxMessage] {
        _ = try await requireAuthenticatedSession()
        let safeLimit = max(limit, 1)
        let url = "https://www.linkedin.com/messaging/thread/\(conversationId)/"
        let goal = """
        Read this LinkedIn conversation and return JSON with this shape:
        {
          "messages": [
            {
              "id": "message id",
              "senderName": "sender full name",
              "text": "message text",
              "timestamp": "timestamp text"
            }
          ]
        }
        Return at most \(safeLimit) messages.
        Return ONLY the JSON.
        """

        let result = try await runAgent(url: url, goal: goal)
        var messages = try mapToMessages(result)
        if messages.count > safeLimit {
            messages = Array(messages.prefix(safeLimit))
        }
        return messages
    }

    // MARK: - Response Mapping (Private)

    private func mapToPersonProfile(_ json: [String: Any], username: String) throws -> PersonProfile {
        let name = firstString(in: json, keys: ["name", "fullName", "profileName"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else {
            throw LinkedInError.parseError("Missing required field: name")
        }

        let experiences = mapExperiences(anyArray(in: json, keys: ["experiences", "experience"]))
        let educations = mapEducations(anyArray(in: json, keys: ["educations", "education"]))

        return PersonProfile(
            username: username,
            name: name,
            headline: firstString(in: json, keys: ["headline"]),
            about: firstString(in: json, keys: ["about", "summary"]),
            location: firstString(in: json, keys: ["location"]),
            company: firstString(in: json, keys: ["currentCompany", "company"]),
            jobTitle: firstString(in: json, keys: ["currentTitle", "title", "jobTitle"]),
            experiences: experiences,
            educations: educations,
            skills: stringArray(in: json, keys: ["skills"]),
            profileImageURL: firstString(in: json, keys: ["profileImageURL", "profileImageUrl", "photoURL"]),
            backgroundImageURL: firstString(in: json, keys: ["backgroundImageURL", "backgroundImageUrl"]),
            connectionCount: firstString(in: json, keys: ["connectionCount"]),
            followerCount: firstString(in: json, keys: ["followerCount"]),
            openToWork: firstBool(in: json, keys: ["openToWork"]) ?? false
        )
    }

    private func mapToCompanyProfile(_ json: [String: Any], name: String) throws -> CompanyProfile {
        let companyName = firstString(in: json, keys: ["name", "companyName"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (companyName?.isEmpty == false) ? companyName! : name

        return CompanyProfile(
            name: resolvedName,
            slug: name,
            tagline: firstString(in: json, keys: ["tagline", "headline"]),
            about: firstString(in: json, keys: ["about", "description"]),
            website: firstString(in: json, keys: ["website"]),
            industry: firstString(in: json, keys: ["industry"]),
            companySize: firstString(in: json, keys: ["companySize", "size"]),
            headquarters: firstString(in: json, keys: ["headquarters"]),
            founded: firstString(in: json, keys: ["founded", "foundedYear"]),
            specialties: stringArray(in: json, keys: ["specialties"]),
            employeeCount: firstString(in: json, keys: ["employeeCount"]),
            followerCount: firstString(in: json, keys: ["followerCount"]),
            logoURL: firstString(in: json, keys: ["logoURL", "logoUrl"]),
            coverImageURL: firstString(in: json, keys: ["coverImageURL", "coverImageUrl"])
        )
    }

    private func mapToJobListings(_ json: [String: Any]) throws -> [JobListing] {
        let jobObjects = anyArray(in: json, keys: ["jobs", "results", "listings"])
        return jobObjects.compactMap { raw in
            guard let item = raw as? [String: Any] else { return nil }
            let title = firstString(in: item, keys: ["title"])
            let company = firstString(in: item, keys: ["company", "companyName"])

            guard let title, !title.isEmpty, let company, !company.isEmpty else {
                return nil
            }

            let id = firstString(in: item, keys: ["id", "jobId"]) ?? UUID().uuidString
            let jobURL = firstString(in: item, keys: ["jobURL", "jobUrl", "url"]) ?? "https://www.linkedin.com/jobs/view/\(id)/"

            return JobListing(
                id: id,
                title: title,
                company: company,
                companyURL: firstString(in: item, keys: ["companyURL", "companyUrl"]),
                location: firstString(in: item, keys: ["location"]),
                postedDate: firstString(in: item, keys: ["postedDate", "posted"]),
                salary: firstString(in: item, keys: ["salary"]),
                isEasyApply: firstBool(in: item, keys: ["isEasyApply", "easyApply"]) ?? false,
                jobURL: jobURL
            )
        }
    }

    private func mapToJobDetails(_ json: [String: Any]) throws -> JobDetails {
        let title = firstString(in: json, keys: ["title"])
        let company = firstString(in: json, keys: ["company", "companyName"])

        guard let title, !title.isEmpty else {
            throw LinkedInError.parseError("Missing required field: title")
        }
        guard let company, !company.isEmpty else {
            throw LinkedInError.parseError("Missing required field: company")
        }

        let id = firstString(in: json, keys: ["id", "jobId"]) ?? UUID().uuidString
        let jobURL = firstString(in: json, keys: ["jobURL", "jobUrl", "url"]) ?? "https://www.linkedin.com/jobs/view/\(id)/"

        return JobDetails(
            id: id,
            title: title,
            company: company,
            companyURL: firstString(in: json, keys: ["companyURL", "companyUrl"]),
            location: firstString(in: json, keys: ["location"]),
            workplaceType: firstString(in: json, keys: ["workplaceType"]),
            employmentType: firstString(in: json, keys: ["employmentType"]),
            experienceLevel: firstString(in: json, keys: ["experienceLevel"]),
            postedDate: firstString(in: json, keys: ["postedDate", "posted"]),
            applicantCount: firstString(in: json, keys: ["applicantCount"]),
            salary: firstString(in: json, keys: ["salary"]),
            description: firstString(in: json, keys: ["description"]),
            skills: stringArray(in: json, keys: ["skills"]),
            isEasyApply: firstBool(in: json, keys: ["isEasyApply", "easyApply"]) ?? false,
            jobURL: jobURL
        )
    }

    private func mapToConversations(_ json: [String: Any]) throws -> [Conversation] {
        let items = anyArray(in: json, keys: ["conversations", "threads"])
        return items.compactMap { raw in
            guard let item = raw as? [String: Any] else { return nil }
            let id = firstString(in: item, keys: ["id", "conversationId", "threadId"])
            guard let id, !id.isEmpty else { return nil }

            let participants = stringArray(in: item, keys: ["participantNames", "participants", "names"])
            return Conversation(
                id: id,
                participantNames: participants,
                lastMessage: firstString(in: item, keys: ["lastMessage", "preview"]),
                lastMessageAt: firstString(in: item, keys: ["lastMessageAt", "timestamp", "updatedAt"]),
                unread: firstBool(in: item, keys: ["unread", "hasUnread"]) ?? false
            )
        }
    }

    private func mapToMessages(_ json: [String: Any]) throws -> [InboxMessage] {
        let items = anyArray(in: json, keys: ["messages", "results"])
        return items.compactMap { raw in
            guard let item = raw as? [String: Any] else { return nil }
            let id = firstString(in: item, keys: ["id", "messageId"]) ?? UUID().uuidString
            let sender = firstString(in: item, keys: ["senderName", "sender", "from"]) ?? "Unknown"
            let text = firstString(in: item, keys: ["text", "message", "body"]) ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            return InboxMessage(
                id: id,
                senderName: sender,
                text: text,
                timestamp: firstString(in: item, keys: ["timestamp", "sentAt", "createdAt"])
            )
        }
    }

    private func mapExperiences(_ values: [Any]) -> [Experience] {
        values.compactMap { raw in
            guard let item = raw as? [String: Any] else { return nil }
            let title = firstString(in: item, keys: ["title"])
            let company = firstString(in: item, keys: ["company", "companyName"])
            guard let title, !title.isEmpty, let company, !company.isEmpty else { return nil }

            return Experience(
                title: title,
                company: company,
                companyURL: firstString(in: item, keys: ["companyURL", "companyUrl"]),
                location: firstString(in: item, keys: ["location"]),
                startDate: firstString(in: item, keys: ["startDate"]),
                endDate: firstString(in: item, keys: ["endDate"]),
                duration: firstString(in: item, keys: ["duration"]),
                description: firstString(in: item, keys: ["description"])
            )
        }
    }

    private func mapEducations(_ values: [Any]) -> [Education] {
        values.compactMap { raw in
            guard let item = raw as? [String: Any] else { return nil }
            let institution = firstString(in: item, keys: ["school", "institution"])
            guard let institution, !institution.isEmpty else { return nil }

            let dateRange = firstString(in: item, keys: ["dates"])
            let parsedDates = splitDateRange(dateRange)

            return Education(
                institution: institution,
                degree: firstString(in: item, keys: ["degree"]),
                fieldOfStudy: firstString(in: item, keys: ["fieldOfStudy", "field"]),
                startDate: firstString(in: item, keys: ["startDate"]) ?? parsedDates.start,
                endDate: firstString(in: item, keys: ["endDate"]) ?? parsedDates.end,
                description: firstString(in: item, keys: ["description"])
            )
        }
    }

    private func splitDateRange(_ input: String?) -> (start: String?, end: String?) {
        guard let input, !input.isEmpty else { return (nil, nil) }
        let separators = [" - ", " – ", " to "]
        for separator in separators {
            if input.contains(separator) {
                let parts = input.components(separatedBy: separator).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if parts.count >= 2 {
                    return (parts[0], parts[1])
                }
            }
        }
        return (input, nil)
    }

    private func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private func firstBool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let bool = value as? Bool {
                return bool
            }
            if let number = value as? NSNumber {
                return number.boolValue
            }
            if let string = value as? String {
                switch string.lowercased() {
                case "true", "yes", "1": return true
                case "false", "no", "0": return false
                default: continue
                }
            }
        }
        return nil
    }

    private func stringArray(in dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let strings = value as? [String] {
                return strings
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            if let array = value as? [Any] {
                let strings = array.compactMap { element -> String? in
                    if let string = element as? String {
                        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    if let object = element as? [String: Any] {
                        return firstString(in: object, keys: ["name", "title", "value"])
                    }
                    return nil
                }
                if !strings.isEmpty {
                    return strings
                }
            }
        }
        return []
    }

    private func anyArray(in dictionary: [String: Any], keys: [String]) -> [Any] {
        for key in keys {
            if let array = dictionary[key] as? [Any] {
                return array
            }
        }
        return []
    }

    private func requireAuthenticatedSession() async throws -> String {
        do {
            let session = try await getAuthenticatedSession()
            return session.sessionId
        } catch {
            throw LinkedInError.notAuthenticated
        }
    }
}
