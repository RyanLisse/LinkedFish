# 🐟 LinkedFish

> **LinkedIn CLI + MCP server in Swift** — Scrape profiles, search jobs, create posts, send messages, and more!

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-black.svg?style=flat-square&logo=apple)](https://developer.apple.com/macos)
[![MCP Server](https://img.shields.io/badge/MCP-Server-blue.svg?style=flat-square)](https://modelcontextprotocol.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

## ✨ Features

- **👤 Profile Scraping** — Get detailed person profiles with experience, education, skills, and open-to-work status
- **🏢 Company Intelligence** — Extract company info, industry, headquarters, specialties, and employee counts
- **💼 Job Search** — Search jobs with location filtering, salary info, and Easy Apply detection
- **📝 Post Creation** — Create text posts, article/URL shares, and image posts
- **📸 Image Upload** — Upload images to LinkedIn for use in posts
- **📬 Inbox & Messaging** — List conversations, read messages, and send direct messages
- **🤝 Networking** — Send connection invitations with optional custom messages
- **🔐 Secure Auth** — Cookie-based auth stored safely in macOS Keychain, with automatic browser extraction
- **🤖 MCP Server** — 12 tools for Claude Desktop / AI assistant integration
- **📦 Swift Native** — Built 100% in Swift 6 with modern async/await and actor-based concurrency
- **🔄 Smart Fallback** — Peekaboo browser automation + Gemini Vision when HTML scraping fails

## 🚀 Quick Start

### Installation

```bash
# Clone the repo
git clone https://github.com/RyanLisse/LinkedFish.git
cd LinkedFish

# Build release
swift build -c release

# Install CLI tools
cp .build/release/linkedin /usr/local/bin/
cp .build/release/linkedin-mcp /usr/local/bin/
```

**Optional: [just](https://github.com/casey/just)** — A `justfile` is included for common tasks. Install with `brew install just`, then run `just` (build), `just test`, `just install`, etc.

### Authentication

```bash
# 🚀 EASIEST: Automatic browser extraction (recommended)
linkedin auth --browser safari
linkedin auth --browser chrome
linkedin auth --browser edge
linkedin auth --browser firefox

# List available browsers and profiles
linkedin auth --list-browsers

# Manual auth (if automatic extraction fails)
linkedin auth YOUR_LI_AT_COOKIE_HERE

# Interactive auth (shows detailed instructions)
linkedin auth

# Check authentication status
linkedin status
```

**Note**: Browser extraction may prompt for:
- **Safari**: Full Disk Access in System Settings → Privacy & Security
- **Chrome/Edge**: Keychain access (allow when prompted)

## 📖 Usage

### CLI Commands

```bash
# 👤 Get a profile
linkedin profile johndoe
linkedin profile "https://linkedin.com/in/johndoe" --json
linkedin profile johndoe --vision          # Force Peekaboo vision
linkedin profile johndoe --no-fallback     # Disable Peekaboo fallback

# 🏢 Get a company
linkedin company microsoft
linkedin company "https://linkedin.com/company/anthropic" --json

# 💼 Search jobs
linkedin jobs "Swift Developer" --location "Remote" --limit 10

# 📋 Get job details
linkedin job 1234567890 --json

# 📝 Create posts
linkedin post "Excited about our new release! 🚀"
linkedin post "Check this out" --url "https://example.com" --url-title "Great Article"
linkedin post "Screenshot of the day" --image ./screenshot.png
linkedin post "Connections only update" --visibility connections
linkedin post "Test message" --dry-run     # Preview without posting

# 🤝 Send connection request
linkedin connect johndoe
linkedin connect johndoe --message "Great to meet you!"
linkedin connect johndoe --dry-run
linkedin connect johndoe --force           # Skip confirmation

# ✉️ Send a message
linkedin send johndoe "Hey, thanks for connecting!"
linkedin send johndoe --message "Alternative syntax"
linkedin send johndoe "Hello" --dry-run
linkedin send johndoe "Hello" --force      # Skip confirmation

# 📬 Inbox
linkedin inbox                              # List conversations
linkedin inbox --limit 5                    # Limit results
linkedin inbox --unread-only               # Only unread
linkedin inbox --browser-mode              # Force Peekaboo/Safari

# 💬 Read messages
linkedin messages CONVERSATION_ID
linkedin messages CONVERSATION_ID --limit 50
linkedin messages CONVERSATION_ID --browser-mode

# 🔍 Auth management
linkedin auth --show                       # Show stored cookie
linkedin auth --clear                      # Clear stored auth
linkedin status --json                     # JSON status output
```

**Global flags** available on all commands: `--json` (JSON output), `--cookie <value>` (override stored cookie)

### MCP Server Setup

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

**12 MCP tools available:**
`linkedin_status`, `linkedin_configure`, `linkedin_get_profile`, `linkedin_get_company`, `linkedin_search_jobs`, `linkedin_get_job`, `linkedin_create_post`, `linkedin_upload_image`, `linkedin_list_conversations`, `linkedin_get_messages`, `linkedin_send_invite`, `linkedin_send_message`

See [docs/MCP.md](docs/MCP.md) for full tool schemas and examples.

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────┐
│  User Interfaces                                 │
│  • linkedin CLI   (swift-argument-parser)        │
│  • linkedin-mcp   (MCP server)                   │
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
│  • Gemini Vision API (screenshot analysis)       │
└──────────────────────────────────────────────────┘
```

## 🛠️ Library Usage

```swift
import LinkLion

// Create and configure client
let client = await createClient(cookie: "your-li_at-cookie")

// Get profile
let profile = try await client.getProfile(username: "satya-nadella")
print("Name: \(profile.name)")
print("Headline: \(profile.headline ?? "N/A")")
print("Experiences: \(profile.experiences.count)")

// Search jobs
let jobs = try await client.searchJobs(query: "iOS Developer", location: "SF")
for job in jobs {
    print("  \(job.title) @ \(job.company)")
}

// Create a post
let result = try await client.createTextPost(text: "Hello LinkedIn!", visibility: .public)
print("Posted: \(result.success)")

// List inbox
let conversations = try await client.listConversations(limit: 10)
for conv in conversations {
    print("\(conv.participantNames.joined(separator: ", ")): \(conv.lastMessage ?? "")")
}

// Send a connection request
let urn = try await client.resolveURN(from: "johndoe")
try await client.sendInvite(profileUrn: urn, message: "Let's connect!")
```

## 📚 Documentation

- [🏗️ Architecture](docs/ARCHITECTURE.md) — System design, data flow diagrams, & dependency tree
- [🔌 API Reference](docs/API.md) — Complete library API with all methods and models
- [🤖 MCP Integration](docs/MCP.md) — All 12 MCP tools with schemas and examples

## 🔧 Development

```bash
# Build
swift build

# Run tests
swift test

# Release build
swift build -c release

# Run specific tests
swift test --filter LinkedInKitTests
```

## ⚠️ Limitations

- Rate limiting may occur with frequent requests
- Cookie expires ~1 year (refresh when auth fails)
- LinkedIn may update HTML structure (parsers may need updates)
- CAPTCHA challenges may block requests (Peekaboo fallback helps)
- URN resolution uses placeholder format — real URNs require profile scraping

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.

## 🙏 Credits

Inspired by [linkedin-mcp-server](https://github.com/stickerdaniel/linkedin-mcp-server) (Python).

---

**Built with 🐟 by RyanLisse**
