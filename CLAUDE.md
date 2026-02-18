# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LinkLion is a LinkedIn scraping system written in Swift 6 with three components:
1. **LinkLion** (library) - Core LinkedIn API client with HTML parsing, authentication, and data models
2. **LinkedInCLI** (`linkedin` command) - Command-line interface for profile/company/job scraping
3. **LinkedInMCP** (`linkedin-mcp` server) - MCP server for Claude Desktop integration

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
# Authenticate
linkedin auth YOUR_LI_AT_COOKIE

# Get profile
linkedin profile johndoe
linkedin profile "https://linkedin.com/in/johndoe" --json

# Search jobs
linkedin jobs "Swift Developer" --location "Remote" --limit 10

# Check auth status
linkedin status
```

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────────┐
│  User Interfaces                                │
│  • LinkedInCLI (ArgumentParser commands)        │
│  • LinkedInMCP (MCP server handlers)            │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  LinkLion Core Library                          │
│  • LinkedInClient (actor) - Main API client     │
│  • PeekabooClient - Browser automation fallback │
│  • GeminiVision - Vision-based parsing          │
│  • ProfileParser/JobParser - HTML parsing       │
│  • CredentialStore - Keychain authentication    │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  External Services                              │
│  • LinkedIn.com (Voyager API + HTML scraping)   │
│  • macOS Keychain (credential storage)          │
│  • Agent Browser (Peekaboo automation)          │
│  • Gemini Vision API (vision parsing)           │
└─────────────────────────────────────────────────┘
```

### LinkedInClient (Core)

The `LinkedInClient` is an **actor** (thread-safe) that manages:
- **Authentication**: Cookie-based auth via `li_at` cookie stored in Keychain
- **API Modes**:
  - Primary: Direct LinkedIn Voyager API calls with HTML parsing
  - Fallback: PeekabooClient for browser automation when anti-bot detection triggers
- **Rate Limiting**: Built-in delays and user-agent rotation
- **Data Models**: `PersonProfile`, `CompanyProfile`, `JobListing`, `Experience`, `Education`

Key methods:
- `configure(cookie:)` - Set authentication cookie
- `getProfile(username:)` - Scrape person profile
- `getCompany(name:)` - Scrape company profile
- `searchJobs(query:location:)` - Search job listings
- `sendInvite(profileUrn:message:)` - Send connection request
- `sendMessage(profileUrn:message:)` - Send direct message

### Integration Layers

**PeekabooClient** (`PeekabooClient.swift`)
- Browser automation via `agent-browser` CLI (Chrome/Safari/Firefox)
- Activated when `usePeekabooFallback = true` (default)
- Handles CAPTCHA avoidance and session state

**GeminiVision** (`GeminiVision.swift`)
- Vision API integration for parsing LinkedIn screenshots
- Extracts UI elements when HTML parsing fails
- Used for message/conversation list parsing

**CredentialStore** (`CredentialStore.swift`)
- macOS Keychain integration for secure cookie storage
- Handles `li_at=` prefix normalization
- Service: "LinkLion", Account: "li_at"

### MCP Server Architecture

The MCP server (`LinkedInMCP.swift`) exposes six tools:
1. `linkedin_status` - Check authentication status
2. `linkedin_configure` - Set authentication cookie
3. `linkedin_get_profile` - Get person profile by username
4. `linkedin_get_company` - Get company profile by name
5. `linkedin_search_jobs` - Search jobs by query/location
6. `linkedin_get_job` - Get job details by ID

**Handler Pattern**: `LinkedInToolHandler` manages tool routing with `listTools()` and `callTool()` methods.

## Test-Driven Development

LinkLion follows TDD with comprehensive test coverage in `Tests/LinkedInKitTests/`:

**Test Categories**:
- **URL Extraction**: `testExtractUsername`, `testExtractCompanyName`, `testExtractJobId`
- **Authentication**: `testCredentialStore`, `testClientRequiresAuth*`
- **Payload Construction**: `testSendInvitePayloadConstruction`, `testSendMessagePayloadConstruction`
- **URN Validation**: `testURNValidation`, `testResolveURNFromUsername`
- **Data Models**: `testPersonProfileEncoding`, `testJobListingEncoding`
- **Vision Parsing**: `testParseConversationsFromVisionElements`, `testParseMessagesFromVision`

**Running specific test suites**:
```bash
# Test authentication flow
swift test --filter testClientRequiresAuth

# Test payload construction
swift test --filter PayloadConstruction

# Test vision parsing
swift test --filter Vision
```

## Key Files

- `Sources/LinkLion/LinkedInClient.swift` - Main API client (47KB, actor-based)
- `Sources/LinkLion/Models.swift` - Data models (PersonProfile, JobListing, etc.)
- `Sources/LinkLion/ProfileParser.swift` - HTML parsing for profiles (18KB)
- `Sources/LinkLion/JobParser.swift` - HTML parsing for jobs (14KB)
- `Sources/LinkLion/PeekabooClient.swift` - Browser automation client (9KB)
- `Sources/LinkLion/GeminiVision.swift` - Vision API integration (9KB)
- `Sources/LinkLion/CredentialStore.swift` - Keychain storage (3KB)
- `Sources/LinkedInCLI/LinkedIn.swift` - CLI command definitions
- `Sources/LinkedInMCP/LinkedInMCP.swift` - MCP server implementation
- `Tests/LinkedInKitTests/LinkedInKitTests.swift` - Comprehensive test suite (419 lines)

## Dependencies

- **swift-argument-parser** (1.5.0+) - CLI interface
- **modelcontextprotocol/swift-sdk** (0.9.0+) - MCP server
- **swift-log** (1.6.0+) - Logging infrastructure
- **SwiftSoup** (2.7.0+) - HTML parsing

## Authentication Flow

1. User provides `li_at` cookie via `linkedin auth` command
2. CredentialStore saves to macOS Keychain (service: "LinkLion", account: "li_at")
3. LinkedInClient reads from Keychain on initialization
4. Cookie attached to all HTTP requests as `Cookie: li_at=...`
5. Cookie expires after ~1 year, requiring re-authentication

## Anti-Bot Strategy

LinkLion uses multiple strategies to avoid LinkedIn bot detection:

1. **Realistic User-Agent**: Mimics Chrome 120 on macOS
2. **Rate Limiting**: Built-in delays between requests
3. **Browser Fallback**: PeekabooClient uses real browser for hard cases
4. **Vision Parsing**: GeminiVision extracts data from screenshots when HTML fails
5. **Dual Messaging**: `preferPeekabooMessaging` flag for browser-based messaging vs API

## MCP Server Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "linklion": {
      "command": "/usr/local/bin/linkedin-mcp",
      "args": [],
      "disabled": false
    }
  }
}
```

After configuration:
1. Restart Claude Desktop
2. Verify "linklion" appears in MCP server list
3. Authenticate via `linkedin_configure` tool with your `li_at` cookie
4. Use tools like `linkedin_get_profile` for AI-powered LinkedIn research
