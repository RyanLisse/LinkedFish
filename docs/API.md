# 🔌 LinkLion API Reference

This document provides the complete API reference for the LinkLion library.

## Table of Contents

1. [Main Types](#main-types)
2. [Creating a Client](#creating-a-client)
3. [Authentication](#authentication)
4. [Profile Operations](#profile-operations)
5. [Company Operations](#company-operations)
6. [Job Operations](#job-operations)
7. [Post Creation](#post-creation)
8. [Image Upload](#image-upload)
9. [Messaging & Inbox](#messaging--inbox)
10. [Connections & Invitations](#connections--invitations)
11. [Error Handling](#error-handling)
12. [Model Reference](#model-reference)

---

## Main Types

### `LinkedInClient`

The main client for all LinkedIn operations. Thread-safe Swift `actor`.

```swift
public actor LinkedInClient {
    /// Creates a new client instance
    /// - Parameter browser: Browser name for PeekabooClient fallback (default: "Safari")
    public init(browser: String = "Safari")

    /// Configures the client with an authentication cookie
    public func configure(cookie: String)

    /// Whether the client is authenticated
    public var isAuthenticated: Bool

    /// Get the current cookie value
    public var cookie: String?

    /// Enable/disable Peekaboo fallback for failed scrapes (default: true)
    public var usePeekabooFallback: Bool
    public func setUsePeekabooFallback(_ enabled: Bool)

    /// Prefer browser-based messaging over Voyager API (default: false)
    public var preferPeekabooMessaging: Bool
    public func setPreferPeekabooMessaging(_ enabled: Bool)

    // --- Authentication ---
    public func verifyAuth() async throws -> AuthStatus

    // --- Profiles ---
    public func getProfile(username: String) async throws -> PersonProfile
    public func getProfileWithVision(username: String) async throws -> PersonProfile

    // --- Companies ---
    public func getCompany(name: String) async throws -> CompanyProfile

    // --- Jobs ---
    public func searchJobs(query: String, location: String?, limit: Int) async throws -> [JobListing]
    public func getJob(id: String) async throws -> JobDetails

    // --- Posts ---
    public func createTextPost(text: String, visibility: PostVisibility) async throws -> PostResult
    public func createArticlePost(text: String, url: String, title: String?, description: String?, visibility: PostVisibility) async throws -> PostResult
    public func createImagePost(text: String, imageData: Data, filename: String, visibility: PostVisibility) async throws -> PostResult

    // --- Media ---
    public func uploadImage(data: Data, filename: String) async throws -> MediaUploadResult
    public func getMyProfileURN() async throws -> String

    // --- Inbox & Messaging ---
    public func listConversations(limit: Int) async throws -> [Conversation]
    public func getMessages(conversationId: String, limit: Int) async throws -> [InboxMessage]

    // --- Connections ---
    public func sendInvite(profileUrn: String, message: String?) async throws
    public func sendMessage(profileUrn: String, message: String) async throws
    public func resolveURN(from username: String) async throws -> String
}
```

### `AuthStatus`

Authentication verification result.

```swift
public struct AuthStatus: Codable, Sendable {
    public let valid: Bool
    public let message: String
}
```

---

## Creating a Client

### Basic Setup

```swift
import LinkLion

// Create the client
let client = LinkedInClient()

// Configure with your li_at cookie
await client.configure(cookie: "your-li_at-cookie-here")

// Verify authentication
let status = try await client.verifyAuth()
print("Authenticated: \(status.valid)")  // true
print("Status: \(status.message)")       // "Authenticated"
```

### Using the Convenience Factory

```swift
import LinkLion

// Create and configure in one step
let client = await createClient(cookie: "your-li_at-cookie-here")
```

### Configuring Fallback Behavior

```swift
let client = LinkedInClient()
await client.configure(cookie: "...")

// Disable Peekaboo vision fallback
await client.setUsePeekabooFallback(false)

// Enable browser-based messaging (bypasses Voyager API)
await client.setPreferPeekabooMessaging(true)
```

---

## Authentication

### Configure with Cookie

```swift
// Set the li_at cookie for authentication
// Accepts "AQEDAQ..." or "li_at=AQEDAQ..." format
await client.configure(cookie: "AQEDAQ...")

// Verify it worked
let status = try await client.verifyAuth()
assert(status.valid)
```

### Verify Authentication Status

```swift
let status = try await client.verifyAuth()

print("Valid: \(status.valid)")    // true or false
print("Message: \(status.message)") // "Authenticated", "Cookie expired or invalid", etc.
```

---

## Profile Operations

### Get Profile by Username

```swift
let profile = try await client.getProfile(username: "satya-nadella")

print("Name: \(profile.name)")
print("Headline: \(profile.headline ?? "N/A")")
print("Location: \(profile.location ?? "N/A")")
print("Open to Work: \(profile.openToWork)")

if let connectionCount = profile.connectionCount {
    print("Connections: \(connectionCount)")
}

if let about = profile.about {
    print("About: \(about)")
}

print("Experience:")
for exp in profile.experiences {
    print("  - \(exp.title) at \(exp.company)")
    if let duration = exp.duration {
        print("    Duration: \(duration)")
    }
}

print("Education:")
for edu in profile.educations {
    print("  - \(edu.institution)")
    if let degree = edu.degree { print("    \(degree)") }
}

print("Skills: \(profile.skills.joined(separator: ", "))")
```

### Get Profile with Vision (Peekaboo + Gemini)

```swift
// Force vision-based scraping (captures screenshot, analyzes with Gemini)
let profile = try await client.getProfileWithVision(username: "johndoe")
```

> **Note:** Vision-based scraping requires Screen Recording permissions and a working Peekaboo + Gemini setup. By default, `getProfile(username:)` falls back to vision automatically when HTML parsing fails (controlled by `usePeekabooFallback`).

---

## Company Operations

### Get Company by Name/Slug

```swift
let company = try await client.getCompany(name: "microsoft")

print("Company: \(company.name)")
print("Slug: \(company.slug)")
print("Industry: \(company.industry ?? "N/A")")
print("Size: \(company.companySize ?? "N/A")")
print("Website: \(company.website ?? "N/A")")
print("Headquarters: \(company.headquarters ?? "N/A")")
print("Founded: \(company.founded ?? "N/A")")
print("Employees: \(company.employeeCount ?? "N/A")")
print("Followers: \(company.followerCount ?? "N/A")")

if let about = company.about {
    print("\nAbout:\n\(about)")
}

print("\nSpecialties:")
for specialty in company.specialties {
    print("  • \(specialty)")
}
```

---

## Job Operations

### Search Jobs

```swift
let jobs = try await client.searchJobs(
    query: "Swift Developer",
    location: "San Francisco",
    limit: 20
)

for job in jobs {
    print("[\(job.id)] \(job.title)")
    print("   \(job.company) • \(job.location ?? "N/A")")
    if let salary = job.salary { print("   💰 \(salary)") }
    if job.isEasyApply { print("   ⚡ Easy Apply") }
    print("   🔗 \(job.jobURL)")
}
```

### Get Job Details

```swift
let details = try await client.getJob(id: "1234567890")

print("Title: \(details.title)")
print("Company: \(details.company)")
print("Location: \(details.location ?? "N/A")")
print("Workplace: \(details.workplaceType ?? "N/A")")       // Remote, On-site, Hybrid
print("Employment: \(details.employmentType ?? "N/A")")     // Full-time, Part-time, Contract
print("Experience: \(details.experienceLevel ?? "N/A")")
print("Salary: \(details.salary ?? "N/A")")
print("Applicants: \(details.applicantCount ?? "N/A")")
print("Easy Apply: \(details.isEasyApply)")

if let desc = details.description {
    print("\nDescription:\n\(desc)")
}

if !details.skills.isEmpty {
    print("\nSkills: \(details.skills.joined(separator: ", "))")
}
```

---

## Post Creation

### Create a Text Post

```swift
let result = try await client.createTextPost(
    text: "Excited to share my latest project! 🚀",
    visibility: .public  // or .connections
)

if result.success {
    print("Posted! URN: \(result.postURN ?? "N/A")")
} else {
    print("Failed: \(result.message)")
}
```

### Create an Article/URL Share Post

```swift
let result = try await client.createArticlePost(
    text: "Great read on Swift concurrency!",
    url: "https://example.com/article",
    title: "Understanding Swift Actors",        // optional
    description: "A deep dive into actors...",  // optional
    visibility: .public
)
```

### Create an Image Post

```swift
let imageData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/image.jpg"))

let result = try await client.createImagePost(
    text: "Check out this screenshot!",
    imageData: imageData,
    filename: "screenshot.jpg",
    visibility: .public
)
```

---

## Image Upload

### Upload an Image (for later use)

```swift
let imageData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/image.jpg"))
let upload = try await client.uploadImage(data: imageData, filename: "image.jpg")

print("Media URN: \(upload.mediaURN)")
print("Upload URL: \(upload.uploadURL)")
```

### Get Current User Profile URN

```swift
// Needed internally for posting; also available publicly
let urn = try await client.getMyProfileURN()
print("My URN: \(urn)")
```

---

## Messaging & Inbox

### List Conversations

```swift
let conversations = try await client.listConversations(limit: 20)

for conv in conversations {
    let names = conv.participantNames.joined(separator: ", ")
    let status = conv.unread ? "🔵" : "  "
    print("\(status) \(names)")
    if let msg = conv.lastMessage {
        print("   \(msg)")
    }
    if let time = conv.lastMessageAt {
        print("   🕐 \(time)")
    }
    print("   ID: \(conv.id)")
}
```

### Get Messages from a Conversation

```swift
let messages = try await client.getMessages(conversationId: "some-conv-id", limit: 20)

for msg in messages {
    print("[\(msg.timestamp ?? "")] \(msg.senderName): \(msg.text)")
}
```

> **Note:** Messaging methods support automatic Peekaboo fallback when the Voyager API returns 401/403/404/429/5xx. Set `preferPeekabooMessaging` to force browser-based messaging.

---

## Connections & Invitations

### Send a Connection Invitation

```swift
// Resolve username to URN first
let urn = try await client.resolveURN(from: "johndoe")

// Send invite (with optional custom message)
try await client.sendInvite(
    profileUrn: urn,
    message: "Hi John, let's connect!"  // nil for no message
)
```

### Send a Direct Message

```swift
let urn = try await client.resolveURN(from: "johndoe")

try await client.sendMessage(
    profileUrn: urn,
    message: "Hey John, thanks for connecting!"
)
```

### URN Utilities

```swift
// Build a placeholder URN from a username
let urn = LinkedInClient.buildPlaceholderURN(from: "johndoe")
// → "urn:li:fsd_profile:johndoe"

// Validate a URN
let valid = LinkedInClient.isValidURN("urn:li:fsd_profile:ACoAA...")
// → true
```

---

## Error Handling

```swift
do {
    let profile = try await client.getProfile(username: "nonexistent-user")
} catch LinkedInError.notAuthenticated {
    print("Please configure authentication first")
} catch LinkedInError.profileNotFound {
    print("Profile not found")
} catch LinkedInError.rateLimited {
    print("Too many requests — please wait")
} catch LinkedInError.securityChallenge {
    print("LinkedIn requires a security challenge — complete in browser")
} catch LinkedInError.invalidResponse {
    print("Invalid response from LinkedIn")
} catch LinkedInError.httpError(let code) {
    print("HTTP error: \(code)")
} catch LinkedInError.parseError(let msg) {
    print("Parse error: \(msg)")
} catch LinkedInError.invalidURL(let url) {
    print("Invalid URL: \(url)")
} catch LinkedInError.invalidURN(let urn) {
    print("Invalid URN format: \(urn)")
} catch {
    print("Unexpected error: \(error)")
}
```

### `LinkedInError` Cases

| Case | Description |
|------|-------------|
| `.notAuthenticated` | No cookie configured |
| `.invalidURL(String)` | Malformed URL |
| `.invalidResponse` | Unexpected response from LinkedIn |
| `.httpError(Int)` | HTTP status code error |
| `.securityChallenge` | CAPTCHA/checkpoint triggered |
| `.parseError(String)` | HTML/JSON parsing failure |
| `.rateLimited` | HTTP 429 — too many requests |
| `.profileNotFound` | Profile does not exist |
| `.invalidURN(String)` | Invalid URN format |

---

## Model Reference

### `PersonProfile`

| Property | Type | Description |
|----------|------|-------------|
| `username` | `String` | LinkedIn username |
| `name` | `String` | Full name |
| `headline` | `String?` | Profile headline/tagline |
| `about` | `String?` | About section text |
| `location` | `String?` | Geographic location |
| `company` | `String?` | Current company |
| `jobTitle` | `String?` | Current job title |
| `experiences` | `[Experience]` | Work experience entries |
| `educations` | `[Education]` | Education history |
| `skills` | `[String]` | Listed skills |
| `profileImageURL` | `String?` | Profile photo URL |
| `backgroundImageURL` | `String?` | Background banner URL |
| `connectionCount` | `String?` | Connection count (e.g. "500+") |
| `followerCount` | `String?` | Follower count |
| `openToWork` | `Bool` | Whether "Open to Work" is enabled |

### `Experience`

| Property | Type | Description |
|----------|------|-------------|
| `title` | `String` | Job title |
| `company` | `String` | Company name |
| `companyURL` | `String?` | Company LinkedIn URL |
| `location` | `String?` | Job location |
| `startDate` | `String?` | Start date |
| `endDate` | `String?` | End date |
| `duration` | `String?` | Duration string |
| `description` | `String?` | Role description |

### `Education`

| Property | Type | Description |
|----------|------|-------------|
| `institution` | `String` | School/university name |
| `degree` | `String?` | Degree type |
| `fieldOfStudy` | `String?` | Field of study |
| `startDate` | `String?` | Start date |
| `endDate` | `String?` | End date |
| `description` | `String?` | Description |

### `CompanyProfile`

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` | Company name |
| `slug` | `String` | URL slug |
| `tagline` | `String?` | Company tagline |
| `about` | `String?` | Company description |
| `website` | `String?` | Company website |
| `industry` | `String?` | Industry classification |
| `companySize` | `String?` | Company size range |
| `headquarters` | `String?` | HQ location |
| `founded` | `String?` | Founded year |
| `specialties` | `[String]` | List of specialties |
| `employeeCount` | `String?` | Employee count |
| `followerCount` | `String?` | Follower count |
| `logoURL` | `String?` | Logo image URL |
| `coverImageURL` | `String?` | Cover image URL |

### `JobListing`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | LinkedIn job ID |
| `title` | `String` | Job title |
| `company` | `String` | Company name |
| `companyURL` | `String?` | Company LinkedIn URL |
| `location` | `String?` | Job location |
| `postedDate` | `String?` | When posted |
| `salary` | `String?` | Salary range |
| `isEasyApply` | `Bool` | Easy Apply available |
| `jobURL` | `String` | Full job URL |

### `JobDetails`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Job ID |
| `title` | `String` | Job title |
| `company` | `String` | Company name |
| `companyURL` | `String?` | Company LinkedIn URL |
| `location` | `String?` | Job location |
| `workplaceType` | `String?` | Remote, On-site, Hybrid |
| `employmentType` | `String?` | Full-time, Part-time, Contract |
| `experienceLevel` | `String?` | Seniority level |
| `postedDate` | `String?` | When posted |
| `applicantCount` | `String?` | Number of applicants |
| `salary` | `String?` | Salary information |
| `description` | `String?` | Full job description |
| `skills` | `[String]` | Required skills |
| `isEasyApply` | `Bool` | Easy Apply available |
| `jobURL` | `String` | Full job URL |

### `PostVisibility`

```swift
public enum PostVisibility: String, Codable, Sendable, CaseIterable {
    case `public` = "PUBLIC"
    case connections = "CONNECTIONS"
}
```

### `PostResult`

| Property | Type | Description |
|----------|------|-------------|
| `success` | `Bool` | Whether post was created |
| `postURN` | `String?` | URN of the created post |
| `message` | `String` | Status message |

### `MediaUploadResult`

| Property | Type | Description |
|----------|------|-------------|
| `mediaURN` | `String` | Media asset URN |
| `uploadURL` | `String` | Upload endpoint URL |

### `Conversation`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Conversation ID |
| `participantNames` | `[String]` | Participant names |
| `lastMessage` | `String?` | Last message preview |
| `lastMessageAt` | `String?` | ISO 8601 timestamp |
| `unread` | `Bool` | Has unread messages |

### `InboxMessage`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Message ID |
| `senderName` | `String` | Sender's name |
| `text` | `String` | Message text |
| `timestamp` | `String?` | ISO 8601 timestamp |

---

## Helper Functions

```swift
import LinkLion

/// Create a configured client (convenience)
public func createClient(cookie: String? = nil) async -> LinkedInClient

/// Extract username from a LinkedIn URL or plain username
public func extractUsername(from url: String) -> String?

/// Extract company slug from a LinkedIn URL or plain name
public func extractCompanyName(from url: String) -> String?

/// Extract job ID from a LinkedIn URL or plain numeric ID
public func extractJobId(from url: String) -> String?
```
