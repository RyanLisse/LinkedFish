# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LinkedFish (package: LinkedInKit) is a LinkedIn scraping system written in Swift 6 with three components:
1. **LinkLion** (library) — Core LinkedIn API client with HTML parsing, browser fallback, vision analysis, authentication, and data models
2. **LinkedInCLI** (`linkedin` binary) — Command-line interface for profile/company/job scraping, posting, messaging, and networking
3. **LinkedInMCP** (`linkedin-mcp` binary) — MCP server with 12 tools for Claude Desktop integration

## Build & Development Commands

### Build
```bash
# Development build
swift build

# Release build (optimized)
swift build -c release

# Install CLI tools to /usr/local/bin/
cp .build/release/linkedin /usr/local/bin/
cp .build/release/linkedin-mcp /usr/local/bin/
```

### Testing
```bash
# Run all tests
swift test

# Run specific test
swift test --filter LinkedInKitTests.testSendInvitePayloadConstruction

# Run tests with verbose output
swift test --verbose
```

### CLI Usage
```bash
# Authenticate (browser extraction or manual)
linkedin auth --browser safari
linkedin auth YOUR_LI_AT_COOKIE

# Profile & Company
linkedin profile johndoe --json
linkedin company microsoft --json

# Jobs
linkedin jobs "Swift Developer" --location "Remote" --limit 10
linkedin job 1234567890 --json

# Post creation
linkedin post "Hello LinkedIn!" --visibility public
linkedin post "Check this" --url "https://example.com"
linkedin post "Photo post" --image ./photo.jpg
linkedin post "Test" --dry-run

# Messaging & Inbox
linkedin inbox --limit 10
linkedin inbox --unread-only
linkedin messages CONVERSATION_ID --limit 20

# Connections
linkedin connect johndoe --message "Let's connect!"
linkedin send johndoe "Thanks for the article!"

# Status
linkedin status --json
```

## Architecture

### Three-Layer Design

```
┌──────────────────────────────────────────────────┐
│  User Interfaces                                 │
│  • LinkedInCLI (ArgumentParser commands)         │
│  • LinkedInMCP (MCP server handlers)             │
└────────────────┬─────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────┐
│  LinkLion Core Library                           │
│  • LinkedInClient (actor) — Main API client      │
│  • PeekabooClient — Browser automation fallback  │
│  • GeminiVision — Vision-based parsing           │
│  • ProfileParser / JobParser — HTML parsing      │
│  • CredentialStore — Keychain authentication     │
│  • BrowserCookieExtractor — Cookie extraction    │
└────────────────┬─────────────────────────────────┘
                 │
┌────────────────▼─────────────────────────────────┐
│  External Services                               │
│  • LinkedIn.com (Voyager API + HTML scraping)    │
│  • macOS Keychain (credential storage)           │
│  • Peekaboo (browser automation)                 │
│  • Gemini Vision API (vision parsing)            │
└──────────────────────────────────────────────────┘
```

### LinkedInClient (Core)

The `LinkedInClient` is an **actor** (thread-safe) that manages:

**Authentication:**
- Cookie-based auth via `li_at` cookie stored in Keychain
- `configure(cookie:)` — set auth cookie
- `verifyAuth()` → `AuthStatus` (`.valid: Bool`, `.message: String`)
- `isAuthenticated: Bool`, `cookie: String?`

**Profile & Company Scraping:**
- `getProfile(username:)` → `PersonProfile`
- `getProfileWithVision(username:)` → `PersonProfile` (Peekaboo + Gemini fallback)
- `getCompany(name:)` → `CompanyProfile`

**Job Search:**
- `searchJobs(query:location:limit:)` → `[JobListing]`
- `getJob(id:)` → `JobDetails`

**Post Creation:**
- `createTextPost(text:visibility:)` → `PostResult`
- `createArticlePost(text:url:title:description:visibility:)` → `PostResult`
- `createImagePost(text:imageData:filename:visibility:)` → `PostResult`
- `uploadImage(data:filename:)` → `MediaUploadResult`
- `getMyProfileURN()` → `String`

**Messaging & Inbox:**
- `listConversations(limit:)` → `[Conversation]`
- `getMessages(conversationId:limit:)` → `[InboxMessage]`

**Connections:**
- `sendInvite(profileUrn:message:)` — send connection request
- `sendMessage(profileUrn:message:)` — send DM
- `resolveURN(from:)` → `String` — resolve username to URN

**Fallback Control:**
- `usePeekabooFallback: Bool` / `setUsePeekabooFallback(_:)`
- `preferPeekabooMessaging: Bool` / `setPreferPeekabooMessaging(_:)`

### CLI Commands (11 subcommands)

| Command | Description |
|---------|-------------|
| `auth` | Configure/extract li_at cookie |
| `status` | Check authentication status |
| `profile` | Get person profile |
| `company` | Get company profile |
| `jobs` | Search for jobs |
| `job` | Get job details |
| `post` | Create a post (text/article/image) |
| `connect` | Send connection invitation |
| `send` | Send direct message |
| `inbox` | List inbox conversations |
| `messages` | Read conversation messages |

### MCP Server (12 tools)

| Tool | Description |
|------|-------------|
| `linkedin_status` | Check auth status |
| `linkedin_configure` | Set li_at cookie |
| `linkedin_get_profile` | Get person profile by `username` |
| `linkedin_get_company` | Get company profile by `company` |
| `linkedin_search_jobs` | Search jobs by `query`, `location`, `limit` |
| `linkedin_get_job` | Get job details by `job_id` |
| `linkedin_create_post` | Create post: `text`, `visibility`, `url`, `image_path` |
| `linkedin_upload_image` | Upload image by `image_path` |
| `linkedin_list_conversations` | List conversations: `limit`, `browser_mode` |
| `linkedin_get_messages` | Get messages: `conversation_id`, `limit`, `browser_mode` |
| `linkedin_send_invite` | Send invite: `username`, `message` |
| `linkedin_send_message` | Send message: `username`, `message` |

**Handler Pattern:** `LinkedInToolHandler` (actor) manages tool routing with `listTools()` and `callTool()` methods.

## Test-Driven Development

Test suite in `Tests/LinkedInKitTests/`:

**Test Categories:**
- **URL Extraction**: `testExtractUsername`, `testExtractCompanyName`, `testExtractJobId`
- **Authentication**: `testCredentialStore`, `testClientRequiresAuth*`
- **Payload Construction**: `testSendInvitePayloadConstruction`, `testSendMessagePayloadConstruction`
- **URN Validation**: `testURNValidation`, `testResolveURNFromUsername`
- **Data Models**: `testPersonProfileEncoding`, `testJobListingEncoding`
- **Vision Parsing**: `testParseConversationsFromVisionElements`, `testParseMessagesFromVision`

```bash
# Run specific test suites
swift test --filter testClientRequiresAuth
swift test --filter PayloadConstruction
swift test --filter Vision
```

## Key Files

| File | Description |
|------|-------------|
| `Sources/LinkLion/LinkedInClient.swift` | Main API client (actor-based) |
| `Sources/LinkLion/Models.swift` | All data models |
| `Sources/LinkLion/ProfileParser.swift` | HTML parsing for profiles |
| `Sources/LinkLion/JobParser.swift` | HTML parsing for jobs |
| `Sources/LinkLion/PeekabooClient.swift` | Browser automation client |
| `Sources/LinkLion/GeminiVision.swift` | Vision API integration |
| `Sources/LinkLion/CredentialStore.swift` | Keychain storage |
| `Sources/LinkLion/LinkedInKit.swift` | Version, factory, URL helpers |
| `Sources/LinkedInCLI/LinkedIn.swift` | CLI command definitions |
| `Sources/LinkedInCLI/BrowserCookieExtractor.swift` | Browser cookie extraction |
| `Sources/LinkedInMCP/LinkedInMCP.swift` | MCP server (12 tools) |
| `Tests/LinkedInKitTests/LinkedInKitTests.swift` | Test suite |

## Dependencies

| Package | Version | Used By | Purpose |
|---------|---------|---------|---------|
| swift-argument-parser | 1.5.0+ | LinkedInCLI | CLI framework |
| modelcontextprotocol/swift-sdk | 0.9.0+ | LinkedInMCP | MCP server |
| swift-log | 1.6.0+ | LinkLion, LinkedInMCP | Logging |
| SwiftSoup | 2.7.0+ | LinkLion | HTML parsing |
| SweetCookieKit | 0.3.0+ | LinkedInCLI | Browser cookie extraction |

## Data Models

All models are `Codable`, `Sendable`:

- `AuthStatus` — `valid: Bool`, `message: String`
- `PersonProfile` — username, name, headline, about, location, company, jobTitle, experiences, educations, skills, connectionCount, followerCount, openToWork, etc.
- `CompanyProfile` — name, slug, tagline, about, website, industry, companySize, headquarters, founded, specialties, employeeCount, followerCount, etc.
- `JobListing` — id, title, company, location, postedDate, salary, isEasyApply, jobURL
- `JobDetails` — extends JobListing with workplaceType, employmentType, experienceLevel, applicantCount, description, skills
- `PostVisibility` — `.public`, `.connections`
- `PostResult` — success, postURN, message
- `MediaUploadResult` — mediaURN, uploadURL
- `Conversation` — id, participantNames, lastMessage, lastMessageAt, unread
- `InboxMessage` — id, senderName, text, timestamp

## Authentication Flow

1. User provides `li_at` cookie via `linkedin auth` command (manual or browser extraction)
2. `BrowserCookieExtractor` (via SweetCookieKit) can auto-extract from Safari/Chrome/Edge/Firefox
3. `CredentialStore` saves to macOS Keychain (service: "LinkLion", account: "li_at")
4. `LinkedInClient` reads from Keychain on initialization
5. Cookie attached to all HTTP requests as `Cookie: li_at=...`
6. CSRF tokens generated per-request for Voyager API calls
7. Cookie expires after ~1 year, requiring re-authentication

## Anti-Bot Strategy

1. **Realistic User-Agent**: Mimics Chrome 120 on macOS
2. **Rate Limiting**: Built-in delays between requests
3. **Browser Fallback**: PeekabooClient uses real browser for hard cases
4. **Vision Parsing**: GeminiVision extracts data from screenshots when HTML fails
5. **Dual Messaging**: `preferPeekabooMessaging` flag for browser-based messaging vs Voyager API
6. **Cookie Extraction**: BrowserCookieExtractor pulls cookies directly from browser databases

## MCP Server Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "linkedin": {
      "command": "/usr/local/bin/linkedin-mcp",
      "args": [],
      "disabled": false
    }
  }
}
```

After configuration:
1. Restart Claude Desktop
2. Verify "linkedin" appears in MCP server list
3. Authenticate via `linkedin_configure` tool with your `li_at` cookie
4. Use any of the 12 tools for AI-powered LinkedIn research, posting, and networking
