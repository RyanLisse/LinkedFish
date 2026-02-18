---
title: "feat: LinkedFish TinyFish Rebuild — Replace Voyager API with TinyFish Web Agent"
type: feat
date: 2026-02-18
status: ready-to-build
beads_epics: [lf-b6q, lf-0s7, lf-ypr, lf-xrh, lf-1m3, lf-gr3, lf-5o2, lf-k2v]
---

# feat: LinkedFish TinyFish Rebuild

## Overview

Replace the LinkedIn Voyager API backend (undocumented, brittle, actively policed) with the TinyFish Web Agent API (enterprise-grade, 98.7% success rate, serverless). This is a surgical backend swap — the public CLI and MCP interfaces remain unchanged. New capabilities (messaging, connections, posts) become reliable enough to ship.

**Scope:** 5 files deleted, 5 files created, 4 files updated, 2 test files rewritten.
**Timeline:** 2–3 days of focused implementation.
**API key:** Load from `TINYFISH_API_KEY` env var or macOS Keychain.

---

## Architecture

### Current vs. Target

```
CURRENT (Voyager):
CLI/MCP → LinkedInClient → Voyager API (li_at cookie) → HTML → SwiftSoup → Models

TARGET (TinyFish):
CLI/MCP → LinkedInClient (facade) → TinyFishClient → TinyFish SSE API  → JSON → Models
                                                   └→ AgentQL REST API  → JSON → Models
                                                   └→ Remote Browser     → CDP  → Models
```

### File Map

| File | Action | Reason |
|------|--------|--------|
| `Sources/LinkLion/TinyFishClient.swift` | **CREATE** | New actor: SSE + AgentQL + remote browser |
| `Sources/LinkLion/SSEParser.swift` | **CREATE** | URLSession async bytes SSE parser |
| `Sources/LinkLion/AgentQLClient.swift` | **CREATE** | AgentQL REST wrapper |
| `Sources/LinkLion/RemoteBrowserSession.swift` | **CREATE** | CDP session lifecycle |
| `Sources/LinkLion/LinkedInClient.swift` | **REWRITE** | Thin facade over TinyFishClient |
| `Sources/LinkLion/LinkedInKit.swift` | **UPDATE** | createClient() → TinyFish API key |
| `Sources/LinkLion/CredentialStore.swift` | **UPDATE** | Add TinyFish API key methods |
| `Sources/LinkedInCLI/LinkedIn.swift` | **UPDATE** | Auth command → API key, add connect/message |
| `Sources/LinkedInMCP/LinkedInMCP.swift` | **UPDATE** | Add new MCP tools |
| `Sources/LinkLion/ProfileParser.swift` | **DELETE** | TinyFish returns JSON directly |
| `Sources/LinkLion/JobParser.swift` | **DELETE** | TinyFish returns JSON directly |
| `Sources/LinkLion/PeekabooClient.swift` | **DELETE** | TinyFish IS the browser |
| `Sources/LinkLion/GeminiVision.swift` | **DELETE** | TinyFish handles visual understanding |
| `Package.swift` | **UPDATE** | Remove SwiftSoup; keep SweetCookieKit for li_at extraction |

### Keep Untouched

- `Models.swift` — All data models are Codable/Sendable and perfectly correct
- `Tests/LinkedInKitTests/LinkedInKitTests.swift` — URL extractors, CredentialStore tests still valid
- `Tests/LinkedInKitTests/BrowserCookieExtractorTests.swift` — Browser cookie tests still valid
- `BrowserCookieExtractor.swift` — Still needed to extract `li_at` for authenticated sessions

---

## TinyFish API Reference

### TinyFish Web Agent (SSE Stream)

```
POST https://agent.tinyfish.ai/v1/automation/run-sse
Headers:
  X-API-Key: {TINYFISH_API_KEY}
  Content-Type: application/json

Body:
{
  "url": "https://linkedin.com/in/satya-nadella",
  "goal": "Extract: name, headline, location, about, company, title, experiences (title/company/dates), education (school/degree), skills, connections",
  "browser_profile": "stealth",        // optional - for bot-protected sites
  "proxy_config": { "enabled": true, "country_code": "US" }  // optional
}

SSE Line Format (all events come as data: lines with JSON payload):
  data: {"type":"PROGRESS","purpose":"Navigating to LinkedIn profile page"}
  data: {"type":"PROGRESS","purpose":"Scrolling to load all experience entries"}
  data: {"type":"COMPLETE","status":"COMPLETED","resultJson":{"name":"Satya Nadella",...}}
  data: {"type":"COMPLETE","status":"FAILED","error":{"message":"Profile not found"}}

Note: No `event:` field prefix. Type is inside the JSON payload.
Synchronous alternative: POST /v1/automation/run (no streaming, returns run object)
```

### AgentQL REST (Structured Queries)

```
POST https://api.agentql.com/v1/query-data
Headers:
  X-API-Key: {TINYFISH_API_KEY}   ← Same key
  Content-Type: application/json

Body:
{
  "url": "https://linkedin.com/company/anthropic",
  "query": "{ company { name description website industry size headquarters founded specialties[] } }",
  "params": { "browser_profile": "stealth" }
}

Response: { "data": { "company": {...} } }
```

### AgentQL Remote Browser (Authenticated Sessions)

```
POST https://api.agentql.com/v1/tetra/sessions
Headers:
  X-API-Key: {TINYFISH_API_KEY}
  Content-Type: application/json

Body:
{
  "cookies": [{"name": "li_at", "value": "{cookie}", "domain": ".linkedin.com"}]
}

Response: { "session_id": "...", "cdp_url": "ws://..." }
```

---

## Implementation Phases

### Phase 1 — TinyFish Core Client (P0, Day 1 morning)

**Goal:** Build the three networking primitives and assemble the actor.

#### 1.1 `SSEParser.swift` (bead: lf-b6q.1, ~120 min)

```swift
// Sources/LinkLion/SSEParser.swift

public struct SSEEvent: Sendable {
    public let type: String      // "progress", "result", "error"
    public let data: String
    public let id: String?
}

public enum SSEError: Error, Sendable {
    case connectionFailed(Error)
    case invalidResponse(Int)
    case streamTerminated
    case timeout
}

public struct SSEParser: Sendable {
    /// Returns AsyncThrowingStream<SSEEvent, Error> from a URL request
    public func events(from request: URLRequest) -> AsyncThrowingStream<SSEEvent, Error>
}
```

**Implementation notes:**
- Use `URLSession.shared.bytes(for: request)` for async streaming
- Parse line-by-line: all events are `data: {json}` — no `event:` field prefix
- Parse `type` from JSON payload: `"PROGRESS"` (intermediate) or `"COMPLETE"` (final)
- `COMPLETE` with `status: "COMPLETED"` → emit `resultJson` as final result
- `COMPLETE` with `status: "FAILED"` → throw `SSEError.agentFailed(error.message)`
- Include `Tests/Fixtures/sse-progress-stream.txt` and `Tests/Fixtures/sse-complete-success.json` for unit tests

#### 1.2 `AgentQLClient.swift` (bead: lf-b6q.2, ~90 min)

```swift
// Sources/LinkLion/AgentQLClient.swift

public actor AgentQLClient: Sendable {
    private let apiKey: String
    private static let baseURL = "https://api.agentql.com/v1"

    public func queryData<T: Decodable>(
        url: String,
        query: String,
        responseType: T.Type,
        params: [String: String] = ["browser_profile": "stealth"]
    ) async throws -> T
}
```

**Implementation notes:**
- `URLSession` + `JSONDecoder` — no third-party HTTP library
- Retry with exponential backoff (max 3 attempts, 1s / 2s / 4s)
- Rate limit: detect 429, respect `Retry-After` header
- Error mapping: auth failure (401) → `LinkedInError.notAuthenticated`

#### 1.3 `RemoteBrowserSession.swift` (bead: lf-b6q.3, ~150 min)

```swift
// Sources/LinkLion/RemoteBrowserSession.swift

public actor RemoteBrowserSession: Sendable {
    private let apiKey: String
    private var sessionId: String?
    private var cdpURL: String?

    /// Create session with injected li_at cookie
    public func create(liAtCookie: String) async throws

    /// Execute a goal in authenticated context
    public func runGoal(_ goal: String, on url: String) async throws -> [String: Any]

    /// Destroy session when done
    public func destroy() async throws
}
```

**Implementation notes:**
- POST to `https://api.agentql.com/v1/tetra/sessions` with cookie payload
- Session lifecycle: create on first use, destroy on deinit
- Keep-alive ping every 30s if session idle
- `li_at` loaded from `CredentialStore` (existing)
- Consider session pool for concurrent ops (start with single session for MVP)

#### 1.4 `TinyFishClient.swift` (bead: lf-b6q.4, ~180 min)

```swift
// Sources/LinkLion/TinyFishClient.swift

public actor TinyFishClient: Sendable {
    private let apiKey: String
    private let sseParser: SSEParser
    private let agentQL: AgentQLClient
    private var remoteBrowser: RemoteBrowserSession?
    private let logger = Logger(label: "TinyFishClient")

    private static let agentURL = "https://agent.tinyfish.ai/v1/automation/run-sse"

    public init(apiKey: String)

    // MARK: - Public Data (no auth needed)
    public func runAgent(url: String, goal: String) async throws -> [String: Any]
    public func queryData<T: Decodable>(url: String, query: String, as type: T.Type) async throws -> T

    // MARK: - Authenticated (needs li_at)
    public func withAuthSession<T>(_ work: (RemoteBrowserSession) async throws -> T) async throws -> T

    // MARK: - LinkedIn Methods
    public func getProfile(username: String) async throws -> PersonProfile
    public func getCompany(name: String) async throws -> CompanyProfile
    public func searchJobs(query: String, location: String?, limit: Int) async throws -> [JobListing]
    public func sendConnectionRequest(to username: String, note: String?) async throws
    public func sendMessage(to username: String, message: String) async throws
    public func createPost(content: String, visibility: PostVisibility) async throws -> PostResult
}
```

**Routing logic:**
- Public profiles, company info, job search → AgentQL (faster, no session overhead)
- Connection requests, messaging, posting → Remote browser session (requires li_at)
- Fallback: if AgentQL fails for a profile → retry via agent SSE stream

---

### Phase 2 — LinkedInClient Facade + LinkedIn Methods (P0, Day 1 afternoon)

**Goal:** Rewrite LinkedInClient as a thin delegation layer; implement profile/company fetching.

#### 2.1 Profile Fetching (bead: lf-ypr.1, ~150 min)

AgentQL query for profile:
```
{
  profile {
    name
    headline
    location
    about
    current_company
    current_title
    experiences[] {
      title
      company
      company_url
      location
      start_date
      end_date
      duration
      description
    }
    education[] {
      institution
      degree
      field_of_study
      start_date
      end_date
    }
    skills[]
    connection_count
    follower_count
    profile_image_url
    open_to_work
  }
}
```

**Response mapping:** JSON field names → `PersonProfile` Swift properties. Handle:
- Private profiles: partial data, no connections count → return with available fields
- "LinkedIn Member" placeholders → treat as private, return stub
- Not found → throw `LinkedInError.profileNotFound(username)`
- Rate limit → throw `LinkedInError.rateLimited`

#### 2.2 Company Fetching (bead: lf-ypr.2, ~120 min)

AgentQL query for company:
```
{
  company {
    name
    description
    website
    industry
    company_size
    headquarters
    founded_year
    specialties[]
    employee_count
    follower_count
    logo_url
  }
}
```

Handle company slug redirects (e.g., `open-ai` → `openai`).

#### 2.3 LinkedInClient Facade Rewrite (bead: lf-0s7.1, ~180 min)

```swift
// Sources/LinkLion/LinkedInClient.swift (rewritten)

public actor LinkedInClient: Sendable {
    private let tinyFish: TinyFishClient
    private let logger = Logger(label: "LinkedInKit")

    public init(apiKey: String, liAtCookie: String? = nil) {
        self.tinyFish = TinyFishClient(apiKey: apiKey)
        // Store li_at if provided
    }

    // Same public signatures as before — zero breaking changes
    public func configure(cookie: String) async  // Now stores li_at for auth sessions
    public func configure(apiKey: String) async   // New: TinyFish API key
    public var isAuthenticated: Bool              // true if API key is set
    public func verifyAuth() async throws -> AuthStatus
    public func getProfile(username: String) async throws -> PersonProfile
    public func getCompany(name: String) async throws -> CompanyProfile
    public func searchJobs(query: String, location: String?, limit: Int) async throws -> [JobListing]
    public func sendInvite(profileUrn: String, message: String?) async throws  // → sendConnectionRequest
    public func sendMessage(profileUrn: String, message: String) async throws
    public func createTextPost(text: String, visibility: PostVisibility) async throws -> PostResult
}
```

**CredentialStore updates:**
- Add `saveAPIKey(_ key: String) throws`
- Add `loadAPIKey() throws -> String?`
- Keep existing cookie methods (for li_at injection into remote browser)
- Service name stays the same, just add a second `kSecAttrAccount` key: `"tinyfish_api_key"`

---

### Phase 3 — CLI + MCP Updates (P1, Day 2 morning)

**Goal:** Update user-facing interfaces. Zero breaking changes to existing commands.

#### 3.1 Auth Command Update (bead: lf-xrh.1, ~90 min)

```bash
# New primary auth (TinyFish API key)
linkedin auth --api-key sk-tinyfish-...

# Supplementary auth (li_at for authenticated operations)
linkedin auth --cookie AQEDAQ...
linkedin auth --browser safari   # Auto-extract li_at

# Status
linkedin status  # Shows: API key ✓, LinkedIn cookie ✓/✗
```

The `Auth` struct gains:
```swift
@Option(name: .long, help: "TinyFish API key")
var apiKey: String?
```

#### 3.2 Profile/Company/Jobs Commands (beads: lf-xrh.2, lf-xrh.3, lf-xrh.4)

No CLI-visible changes. Just update `createClient()` calls to use API key from `CredentialStore`.

```swift
// Before
let client = LinkedInClient()
await client.configure(cookie: cookie)

// After
let apiKey = try store.loadAPIKey() ?? ""
let client = LinkedInClient(apiKey: apiKey, liAtCookie: try? store.loadCookie())
```

#### 3.3 New Commands — Connect + Message (beads: lf-xrh.5, lf-xrh.6)

```bash
# Connection request
linkedin connect johndoe --note "Loved your talk on AI agents"
linkedin connect "https://linkedin.com/in/johndoe"

# Direct message
linkedin message johndoe "Following up on our connection request..."
linkedin message johndoe --file message.txt  # Long messages from file
```

#### 3.4 MCP Tool Updates (bead: lf-1m3.1, ~120 min)

Add to existing 6 tools:
- `linkedin_connect` — Send connection request with optional note
- `linkedin_send_message` — Send DM to a profile
- Update `linkedin_configure` to accept `api_key` parameter alongside `cookie`
- Update `linkedin_status` to show both API key and cookie status

---

### Phase 4 — Testing (P1, Day 2 afternoon)

**Goal:** Comprehensive tests for new infrastructure.

#### 4.1 Unit Tests — SSE Parser (bead: lf-gr3.1)

```swift
// Tests/LinkedInKitTests/SSEParserTests.swift

class SSEParserTests: XCTestCase {
    func testParseProgressEvent() async throws  // Single event
    func testParseResultEvent() async throws    // Final result event
    func testParseMultilineData() async throws  // Multi-line data fields
    func testHandleReconnectionId() async throws
    func testHandleErrorEvent() async throws
    func testHandleEmptyStream() async throws
    func testHandleMalformedSSE() async throws  // Graceful degradation
}
```

Use fixture files:
- `Tests/Fixtures/sse-progress-stream.txt` — Sample SSE stream with progress events
- `Tests/Fixtures/sse-result-profile.json` — Final result JSON
- `Tests/Fixtures/sse-error.txt` — Error event

#### 4.2 Unit Tests — TinyFishClient (bead: lf-gr3.2)

```swift
// Tests/LinkedInKitTests/TinyFishClientTests.swift

class TinyFishClientTests: XCTestCase {
    func testGetProfilePublic() async throws     // Mocked AgentQL response
    func testGetProfileNotFound() async throws   // 404 handling
    func testGetCompany() async throws
    func testSearchJobs() async throws
    func testAPIKeyRequired() async throws       // Missing key → error
    func testRetryOnRateLimit() async throws     // 429 → retry behavior
}
```

Use `URLProtocol` mock to intercept HTTP without real network calls.

#### 4.3 E2E Tests — Profile & Company (bead: lf-gr3.3)

```swift
// Tests/LinkedInKitTests/E2ETests.swift
// Only run when TINYFISH_API_KEY env var is set

class E2ETests: XCTestCase {
    func testGetPublicProfile() async throws     // satya-nadella or known public profile
    func testGetCompanyProfile() async throws    // microsoft or anthropic
    func testSearchJobsReturnsResults() async throws
}
```

Skip if no API key: `guard let _ = ProcessInfo.processInfo.environment["TINYFISH_API_KEY"] else { throw XCTSkip("No API key") }`

#### 4.4 E2E Tests — Authenticated Operations (bead: lf-gr3.4)

```swift
// Only run when both TINYFISH_API_KEY + LINKEDIN_LI_AT are set
func testSendConnectionRequest() async throws  // Dry run / test account
func testSendMessage() async throws            // Test account
```

---

### Phase 5 — Dependency Cleanup (P1, Day 2 late)

#### 5.1 Remove SwiftSoup (bead: lf-5o2.1)

From `Package.swift`:
```diff
- .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),
```

From `LinkLion` target dependencies:
```diff
- .product(name: "SwiftSoup", package: "SwiftSoup"),
```

Fix any remaining SwiftSoup imports (should be none after ProfileParser/JobParser deletion).

#### 5.2 Remove Dead Code (bead: lf-5o2.2)

Delete files:
- `Sources/LinkLion/ProfileParser.swift` (446 lines)
- `Sources/LinkLion/JobParser.swift` (351 lines)
- `Sources/LinkLion/PeekabooClient.swift` (258 lines)
- `Sources/LinkLion/GeminiVision.swift` (246 lines)

Total: ~1,300 lines deleted, ~800 new lines added. Net reduction of ~500 lines.

---

### Phase 6 — Demo & Application (P1–P2, Day 3)

#### 6.1 Demo Video (bead: lf-k2v.1, ~60 min)

Script outline (2–3 min):
1. **Hook** (15s): "LinkedIn has 1 billion users and no real API. We fixed that."
2. **Auth** (15s): `linkedin auth --api-key $TINYFISH_API_KEY` → "✓ Authenticated"
3. **Profile** (30s): `linkedin profile satya-nadella` → structured JSON output
4. **Company** (15s): `linkedin company anthropic --json` → company data
5. **Jobs** (30s): `linkedin jobs "AI Engineer" --location "Remote"` → job list
6. **Claude Desktop** (30s): MCP demo — "Research the CTO of Anthropic"
7. **Outreach** (15s): `linkedin connect` + `linkedin message` demo
8. **Close** (15s): "LinkedIn's missing API — powered by TinyFish"

#### 6.2 Accelerator Application (bead: lf-k2v.3, ~45 min)

Key talking points:
- Working Swift native CLI + MCP (not another Python scraper)
- TinyFish-native: showcase of what TinyFish uniquely enables
- B2B SaaS path: $29/mo → $99/mo team plans
- Cohort members are ideal first customers (sales teams need this)

---

## AgentQL Query Patterns

### Profile (public, anonymous)

```
{
  profile {
    name headline location about
    current_company current_title
    experiences[] { title company location start_date end_date duration }
    education[] { institution degree field_of_study start_date end_date }
    skills[]
    connection_count follower_count
    open_to_work
  }
}
```

### Company

```
{
  company {
    name tagline about website
    industry company_size headquarters founded
    specialties[] employee_count follower_count
  }
}
```

### Job Search

```
{
  jobs[] {
    id title company company_url location
    posted_date salary easy_apply job_url
  }
}
```

### Job Detail

```
{
  job {
    id title company location
    workplace_type employment_type experience_level
    posted_date applicant_count salary
    description skills[] easy_apply
  }
}
```

---

## Error Handling Strategy

```swift
// Sources/LinkLion/LinkedInError.swift (update existing)

public enum LinkedInError: Error, Sendable {
    // Auth
    case notAuthenticated          // No API key configured
    case invalidAPIKey             // 401 from TinyFish
    case cookieExpired             // li_at expired

    // Data
    case profileNotFound(String)   // Username not found
    case companyNotFound(String)
    case rateLimited               // 429 — too many requests
    case timeout                   // Agent took too long

    // Network
    case networkError(Error)
    case invalidResponse           // Unexpected JSON shape

    // Agent
    case agentFailed(String)       // TinyFish returned error event
    case sessionExpired            // Remote browser session timed out
}
```

---

## Package.swift Changes

```swift
// Remove:
.package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),

// LinkLion target — remove:
.product(name: "SwiftSoup", package: "SwiftSoup"),

// Everything else stays the same
// SweetCookieKit stays (still needed for li_at browser extraction)
```

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| TinyFish blocks LinkedIn profiles | Fallback: run-sse agent mode (stealth browser) |
| AgentQL query syntax errors | Validate queries in unit tests before shipping |
| Remote browser session timeout | Auto-reconnect with exponential backoff |
| li_at cookie expired | Clear error message: "run `linkedin auth --browser safari`" |
| SSE stream cuts out mid-response | Timeout detection, retry with exponential backoff |
| Swift 6 actor isolation issues | Keep all mutable state within actors, use Sendable protocols |
| TinyFish API pricing | Free tier (~67 ops) sufficient for dev; $15/mo for demo |

---

## Swift 6 Compliance Requirements

- All new types: `Sendable` conformance
- All state mutations: inside `actor` boundaries
- No `@unchecked Sendable` — solve isolation properly
- `URLSession` usage: `async/await` only (no completion handlers)
- `AsyncThrowingStream` for SSE — proper cancellation support
- `Task` cancellation propagated through all async operations

---

## Acceptance Criteria

### Functional

- [ ] `linkedin profile <username>` returns a `PersonProfile` via TinyFish
- [ ] `linkedin company <name>` returns a `CompanyProfile` via AgentQL
- [ ] `linkedin jobs "<query>"` returns `[JobListing]` via AgentQL
- [ ] `linkedin connect <username> --note "..."` sends connection request via remote browser
- [ ] `linkedin message <username> "<text>"` sends DM via remote browser
- [ ] `linkedin auth --api-key` stores key in Keychain
- [ ] `linkedin status` shows API key + cookie status separately
- [ ] All 6 existing MCP tools work with TinyFish backend
- [ ] `linkedin_connect` and `linkedin_send_message` MCP tools work

### Non-Functional

- [ ] Profile fetch completes in < 30s (TinyFish SLA)
- [ ] No Voyager API code remains in codebase
- [ ] SwiftSoup removed from Package.swift
- [ ] All existing unit tests pass (URL extractors, CredentialStore, BrowserCookieExtractor)
- [ ] New unit tests for SSEParser and TinyFishClient pass (mocked network)
- [ ] `swift build -c release` produces clean binary with no warnings
- [ ] Swift 6 strict concurrency — zero compiler errors

### Quality Gates

- [ ] E2E: `linkedin profile satya-nadella` returns name + headline
- [ ] E2E: `linkedin company anthropic` returns industry + size
- [ ] Demo video recorded and ready for accelerator application
- [ ] `swift test` passes all tests (unit + integration where API key available)

---

## References

### Internal

- `Sources/LinkLion/CredentialStore.swift` — Keychain pattern to replicate for API key storage
- `Sources/LinkLion/Models.swift` — Target data models (keep unchanged)
- `Sources/LinkLion/LinkedInKit.swift:16` — `createClient()` factory to update
- `Sources/LinkedInCLI/LinkedIn.swift:38` — `Auth` command to extend with `--api-key`
- `Sources/LinkedInMCP/LinkedInMCP.swift:22` — `LinkedInToolHandler` to extend with new tools
- `Tests/LinkedInKitTests/LinkedInKitTests.swift` — Existing test patterns to follow

### External

- TinyFish Web Agent: `POST https://agent.tinyfish.ai/v1/automation/run-sse`
- AgentQL REST: `POST https://api.agentql.com/v1/query-data`
- AgentQL Remote Browser: `POST https://api.agentql.com/v1/tetra/sessions`
- PLAN.md — Full research, pricing, and business context

### Beads (Full Dependency Graph)

```
lf-b6q.1 (SSE Parser) ──┐
lf-b6q.2 (AgentQL)    ──┼→ lf-b6q.4 (TinyFishClient) ──┐
lf-b6q.3 (RemoteBrowser)┘                               ├→ lf-ypr.1 (Profile) ──┐
                                                        ├→ lf-ypr.2 (Company) ──┤→ lf-0s7.1 (Facade)
                                                        ├→ lf-ypr.3 (Jobs)    ──┤       ↓
                                                        ├→ lf-ypr.4 (Connect) ──┘   lf-xrh.*
                                                        └→ lf-ypr.5 (Message)      lf-1m3.*
                                                          lf-ypr.6 (Post)           lf-5o2.*
```
