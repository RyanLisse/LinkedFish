# LinkLion × TinyFish Rebuild Plan

**Created:** 2026-02-18
**Status:** Research Complete → Ready to Build

---

## 1. TinyFish Platform Research

### What TinyFish Actually Is
TinyFish is **two products** under one company:
1. **AgentQL** — Query language + SDK (Python/JS) for structured web data extraction via Playwright. Open-source, 1.2k stars.
2. **TinyFish Web Agent** — Serverless agentic web automation API. Goal-based natural language instructions. Enterprise-grade.

**For LinkLion, we want the TinyFish Web Agent API** (not AgentQL SDK directly, though AgentQL powers it under the hood).

### TinyFish Web Agent API

**Single endpoint:**
```
POST https://agent.tinyfish.ai/v1/automation/run-sse
Headers: X-API-Key, Content-Type: application/json
Body: { "url": "...", "goal": "...", "proxy_config": { "enabled": false } }
Response: SSE stream with real-time progress + final JSON result
```

**Key capabilities:**
- Natural language goals → structured JSON output
- Handles auth, forms, dynamic content, multi-step flows
- Built-in stealth mode (anti-bot, rotating proxies)
- 1,000 parallel operations
- 98.7% success rate (claimed)
- SOTA: 90% on Mind2Web benchmark

### AgentQL REST API (Alternative/Complementary)
```
POST https://api.agentql.com/v1/query-data
- query or prompt + url → structured JSON
- Stealth browser profiles, proxy support
- Remote browser sessions via CDP (Chrome DevTools Protocol)
```

**Remote browser sessions** (useful for authenticated LinkedIn):
```
POST https://api.agentql.com/v1/tetra/sessions
→ Returns CDP URL for Playwright connection
→ Can inject cookies/auth into remote browser
```

### Pricing (TinyFish)
| Plan | Monthly | Per Step | Included Steps | Concurrency |
|------|---------|----------|----------------|-------------|
| Pay As You Go | $0 | $0.015 | Pay per use | 2 agents |
| Standard | $15/mo | $0.014 overage | 1,650/mo | 4 agents |
| Pro | $150/mo | $0.012 overage | 16,500/mo | 20 agents |

**All-inclusive:** LLM costs, browser infra, proxies, anti-bot — all included. No hidden fees.

**For MVP/demo:** Free tier (Pay As You Go) is sufficient. ~67 operations free at $1 spend.

### Accelerator Program
- **$2M seed funding pool** via Mango Capital
- 9-week remote program (started Feb 17, 2026 — **JUST STARTED**)
- Free API credits, engineering support, business mentorship
- Direct investor access (Robin Vasan, Mango Capital)
- B2B focus — cohort members become first customers

---

## 2. Current LinkLion Architecture

### Codebase Structure
```
Sources/
├── LinkLion/              # Core library
│   ├── LinkedInClient.swift    # Main client — Voyager API + HTML scraping
│   ├── LinkedInKit.swift       # Public API (createClient, URL extractors)
│   ├── Models.swift            # Data models (PersonProfile, CompanyProfile, JobListing, etc.)
│   ├── ProfileParser.swift     # SwiftSoup HTML → PersonProfile/CompanyProfile
│   ├── JobParser.swift         # SwiftSoup HTML → JobListing/JobDetails
│   ├── CredentialStore.swift   # macOS Keychain for li_at cookie
│   ├── PeekabooClient.swift    # Browser automation fallback via Peekaboo CLI
│   └── GeminiVision.swift      # Screenshot → profile data via Gemini 2.0 Flash
├── LinkedInCLI/           # CLI executable
│   ├── LinkedIn.swift          # ArgumentParser commands (auth, profile, company, jobs, etc.)
│   └── BrowserCookieExtractor.swift  # SweetCookieKit browser cookie extraction
└── LinkedInMCP/           # MCP server
    └── LinkedInMCP.swift       # MCP tools for Claude Desktop
```

### What Uses Voyager API (MUST CHANGE)
- `LinkedInClient.swift` — Direct HTTP calls to `linkedin.com/voyager/api/*` with li_at cookie
- `ProfileParser.swift` — Parses HTML responses from LinkedIn pages
- `JobParser.swift` — Parses job HTML/JSON-LD from LinkedIn
- Cookie-based auth via `CredentialStore.swift`

### What's Pure Swift / Can Stay As-Is
- ✅ `Models.swift` — Data models (PersonProfile, Experience, Education, etc.) — **keep entirely**
- ✅ `LinkedInKit.swift` — URL extractors, createClient helper — **keep, adapt**
- ✅ `CredentialStore.swift` — Repurpose for TinyFish API key storage
- ✅ `LinkedIn.swift` (CLI) — ArgumentParser commands — **keep structure, update implementations**
- ✅ `LinkedInMCP.swift` — MCP server shell — **keep, update tool implementations**
- ✅ `BrowserCookieExtractor.swift` — Still useful for getting li_at for TinyFish auth sessions

### What Gets Replaced
- ❌ `LinkedInClient.swift` → New `TinyFishClient.swift` (HTTP → TinyFish API)
- ❌ `ProfileParser.swift` → TinyFish returns structured JSON directly (no HTML parsing needed)
- ❌ `JobParser.swift` → Same — TinyFish extracts structured data
- ❌ `PeekabooClient.swift` → No longer needed (TinyFish IS the browser)
- ❌ `GeminiVision.swift` → No longer needed (TinyFish handles visual understanding)

### Dependencies to Remove
- `SwiftSoup` — No more HTML parsing
- `SweetCookieKit` — Maybe keep for cookie extraction for auth sessions

### Dependencies to Add
- None needed! TinyFish is a pure HTTP API. Swift's built-in `URLSession` + `JSONDecoder` is sufficient.

---

## 3. Rebuild Plan

### Architecture: TinyFish Replaces Voyager

```
OLD: CLI/MCP → LinkedInClient → Voyager API (li_at cookie) → HTML → SwiftSoup parse
NEW: CLI/MCP → TinyFishClient → TinyFish API (API key) → JSON → Decode directly
```

**Auth flow change:**
- Old: Extract li_at cookie from browser → attach to HTTP requests
- New: Two options:
  1. **Simple:** TinyFish API key only — TinyFish navigates LinkedIn as anonymous (limited data)
  2. **Full:** TinyFish API key + li_at cookie injected into remote browser session via AgentQL's Tetra sessions → full authenticated access

**Recommended approach:** Use AgentQL remote browser + li_at cookie for authenticated operations (profile viewing, messaging, connections). Use TinyFish Web Agent for public operations (job search, company info).

### New Core: `TinyFishClient.swift`
```swift
public actor TinyFishClient {
    private let apiKey: String
    private var linkedInCookie: String?  // For authenticated sessions
    
    // Simple goal-based automation
    func runAgent(url: String, goal: String) async throws -> [String: Any]
    
    // Structured query via AgentQL
    func queryData(url: String, query: String) async throws -> Codable
    
    // Remote browser for authenticated flows
    func createAuthSession() async throws -> BrowserSession
    
    // LinkedIn-specific methods
    func getProfile(username: String) async throws -> PersonProfile
    func getCompany(name: String) async throws -> CompanyProfile
    func searchJobs(query: String, location: String?) async throws -> [JobListing]
    func sendMessage(to: String, message: String) async throws
    func sendConnectionRequest(to: String, note: String?) async throws
    func createPost(content: String) async throws
}
```

### MVP Feature Priority

| Priority | Feature | Approach | Effort |
|----------|---------|----------|--------|
| 🔴 P0 | Profile viewing | TinyFish agent: "Extract profile data from linkedin.com/in/{username}" | 2-3 hours |
| 🔴 P0 | Company info | TinyFish agent: "Extract company info from linkedin.com/company/{name}" | 1-2 hours |
| 🟡 P1 | Job search | TinyFish agent: "Search for {query} jobs in {location}" | 2-3 hours |
| 🟡 P1 | Connection requests | Remote browser session + goal: "Send connection request with note" | 3-4 hours |
| 🟡 P1 | Messaging | Remote browser session + goal: "Send message to {user}" | 3-4 hours |
| 🟢 P2 | Posting | Remote browser session + goal: "Create post with content" | 2-3 hours |
| 🟢 P2 | Feed reading | AgentQL query on feed page | 2-3 hours |

**Total MVP estimate: 2-3 days** (vs weeks for Voyager reverse-engineering)

### Implementation Steps

1. **Create `TinyFishClient.swift`** (Day 1 morning)
   - SSE stream parsing for `run-sse` endpoint
   - AgentQL `query-data` wrapper
   - Remote browser session management
   
2. **Adapt `LinkedInClient.swift`** (Day 1 afternoon)
   - Replace Voyager calls with TinyFish calls
   - Keep same public interface
   - Map TinyFish JSON responses to existing Models
   
3. **Update CLI commands** (Day 2 morning)
   - Add `--api-key` option
   - Update `auth` command for TinyFish key
   - Keep same UX
   
4. **Update MCP tools** (Day 2 afternoon)
   - Same tool names, updated implementations
   - Add new tools: `linkedin_send_message`, `linkedin_connect`, `linkedin_post`
   
5. **Test & polish** (Day 3)
   - End-to-end testing
   - Error handling
   - Demo recording

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| LinkedIn blocks TinyFish IPs | Medium | High | TinyFish has built-in proxy rotation + stealth. Their enterprise customers include companies doing similar scraping. |
| Rate limiting on free tier | Low | Medium | 2 concurrent agents is enough for CLI use. Upgrade to $15/mo for demo. |
| Authenticated operations fail | Medium | High | Fallback: keep li_at cookie + browser cookie approach as Plan B. TinyFish remote browser sessions support cookie injection. |
| TinyFish API changes/breaks | Low | Medium | Pin to v1 endpoints. Simple HTTP API = easy to adapt. |
| Data extraction quality | Low | Low | TinyFish is SOTA (90% Mind2Web). AgentQL queries can be tuned. |
| Swift ↔ SSE complexity | Low | Low | SSE parsing in Swift is straightforward with `URLSession` async bytes. |

---

## 4. TinyFish Accelerator Application

### What Makes LinkLion Compelling

**Problem:** LinkedIn has no public API for the data professionals need most — profile intelligence, automated outreach, pipeline management. The Voyager API is undocumented, unstable, and aggressively policed. Existing tools (Phantombuster, Dux-Soup) are browser extensions — fragile, manual, and can't scale.

**Solution:** LinkLion is a **native CLI + MCP server** that turns LinkedIn into a programmable API. With TinyFish as the web agent backbone, it becomes the most reliable, scalable LinkedIn automation platform — operable from the terminal, AI assistants, or any workflow.

**Why TinyFish specifically:**
- Eliminates the entire Voyager API reverse-engineering problem
- Built-in stealth = no more anti-bot cat-and-mouse
- Serverless architecture = no browser management
- MCP integration = AI agents can use LinkedIn natively
- TinyFish's 98.7% success rate means production-grade reliability

### B2B Positioning

**Primary segments:**
1. **Sales teams** — Automated prospect research, connection requests, follow-up sequences
2. **Recruiters** — Candidate sourcing, bulk profile analysis, outreach automation
3. **Growth hackers** — Content posting, engagement automation, network expansion
4. **Developer tools** — LinkedIn as a data source for AI agents and workflows

**Positioning:** "LinkedIn's missing API — powered by AI agents"

### Revenue Model

| Tier | Price | Target |
|------|-------|--------|
| Free | 50 ops/day | Individual users, developers |
| Pro | $29/mo | Freelancers, small teams |
| Team | $99/mo per seat | Sales teams, recruiting agencies |
| Enterprise | Custom | Large orgs, API access |

**Unit economics:** At $0.015/step (TinyFish cost), a profile fetch ~5-10 steps = $0.075-0.15 COGS. At $29/mo for ~1000 operations, margin is ~75%.

### Demo Video Outline (2-3 min)

1. **Hook** (15s): "LinkedIn has 1 billion users and no real API. We fixed that."
2. **CLI demo** (45s):
   - `linklion auth --api-key $TINYFISH_KEY`
   - `linklion profile satya-nadella` → structured JSON in seconds
   - `linklion jobs "AI Engineer" --location "SF"` → job listings
3. **MCP demo** (45s):
   - Claude Desktop: "Research the CTO of Anthropic on LinkedIn"
   - Shows real-time TinyFish agent executing, structured data returned
4. **Outreach automation** (30s):
   - `linklion connect johndoe --note "Loved your talk on AI agents"`
   - `linklion message johndoe "Following up on our connection..."`
5. **Scale story** (15s): "1,000 profiles in parallel. Same API. $0.04 per operation."
6. **CTA** (10s): "LinkLion — LinkedIn's missing API. Built on TinyFish."

### Application Talking Points
- **Technical founder** with working prototype (CLI + MCP already built in Swift)
- **Clear revenue path** — B2B SaaS with proven demand (Phantombuster does $10M+ ARR in this space)
- **TinyFish-native** — LinkLion is a showcase of what TinyFish enables that wasn't possible before
- **Network effects** — accelerator cohort members are ideal first customers (everyone needs LinkedIn automation)
- **Fast to market** — 2-3 day rebuild from Voyager to TinyFish, then iterate on GTM

---

## 5. Quick Start Commands

```bash
# Get TinyFish API key
# Sign up at https://tinyfish.ai → grab API key

# Test TinyFish API directly
curl -N -X POST https://agent.tinyfish.ai/v1/automation/run-sse \
  -H "X-API-Key: $TINYFISH_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://linkedin.com/in/satya-nadella",
    "goal": "Extract this persons full profile: name, headline, location, about section, current company, job title, experience history, education, skills, connection count"
  }'

# Test AgentQL structured query
curl -X POST https://api.agentql.com/v1/query-data \
  -H "X-API-Key: $AGENTQL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://linkedin.com/in/satya-nadella",
    "query": "{ profile { name headline location about company job_title experiences[] { title company duration } educations[] { school degree } skills[] } }",
    "params": { "browser_profile": "stealth" }
  }'
```

---

## Next Steps
1. [ ] Sign up for TinyFish API key
2. [ ] Test API with a LinkedIn profile fetch
3. [ ] Create `TinyFishClient.swift` 
4. [ ] Apply to accelerator (deadline TBD — program already started Feb 17)
5. [ ] Record 2-3 min demo video
