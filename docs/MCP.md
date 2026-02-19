# 🤖 LinkedIn MCP Integration

This document describes how to use the LinkedIn MCP server for AI assistants like Claude Desktop.

## Overview

The MCP server exposes all LinkedIn functionality as 12 tools that AI assistants can call directly, enabling natural language LinkedIn research, posting, messaging, and networking.

## Configuration

### Claude Desktop Setup

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

**Or with development build path:**

```json
{
  "mcpServers": {
    "linkedin": {
      "command": "/path/to/LinkedFish/.build/release/linkedin-mcp",
      "args": [],
      "disabled": false
    }
  }
}
```

### Restart Claude Desktop

After updating the config, restart Claude Desktop to load the MCP server.

---

## Available Tools (12 total)

| # | Tool | Description | Read-Only |
|---|------|-------------|-----------|
| 1 | [`linkedin_status`](#linkedin_status) | Check authentication status | ✅ |
| 2 | [`linkedin_configure`](#linkedin_configure) | Set li_at cookie | ❌ |
| 3 | [`linkedin_get_profile`](#linkedin_get_profile) | Get person profile | ✅ |
| 4 | [`linkedin_get_company`](#linkedin_get_company) | Get company profile | ✅ |
| 5 | [`linkedin_search_jobs`](#linkedin_search_jobs) | Search job listings | ✅ |
| 6 | [`linkedin_get_job`](#linkedin_get_job) | Get job details | ✅ |
| 7 | [`linkedin_create_post`](#linkedin_create_post) | Create a post | ❌ |
| 8 | [`linkedin_upload_image`](#linkedin_upload_image) | Upload an image | ❌ |
| 9 | [`linkedin_list_conversations`](#linkedin_list_conversations) | List inbox conversations | ✅ |
| 10 | [`linkedin_get_messages`](#linkedin_get_messages) | Read conversation messages | ✅ |
| 11 | [`linkedin_send_invite`](#linkedin_send_invite) | Send connection request | ❌ |
| 12 | [`linkedin_send_message`](#linkedin_send_message) | Send direct message | ❌ |

---

### `linkedin_status`

Check the current authentication status.

**Input:** `{}` (no parameters)

**Output:**
```json
{
  "message": "Authenticated",
  "valid": true
}
```

**Example Prompt:**
> "Is LinkedIn authenticated?"

---

### `linkedin_configure`

Configure the LinkedIn authentication cookie.

**Input:**
```json
{
  "cookie": "AQEDAQ..."
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `cookie` | string | ✅ | The `li_at` cookie value from LinkedIn |

**Output:**
```json
{
  "success": true,
  "message": "Cookie saved and verified successfully"
}
```

**Example Prompt:**
> "Configure LinkedIn with my li_at cookie: AQEDAQ..."

---

### `linkedin_get_profile`

Fetch a person's LinkedIn profile. Accepts a username or full profile URL.

**Input:**
```json
{
  "username": "satya-nadella"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `username` | string | ✅ | LinkedIn username (e.g., `johndoe`) or full profile URL |

**Output:**
```json
{
  "about": "...",
  "company": "Microsoft",
  "connectionCount": "500+",
  "educations": [
    {
      "degree": "M.S. in Computer Science",
      "institution": "University of Wisconsin–Milwaukee"
    }
  ],
  "experiences": [
    {
      "company": "Microsoft",
      "duration": "Feb 2014 - Present",
      "title": "Chairman and Chief Executive Officer"
    }
  ],
  "followerCount": "10M+",
  "headline": "Chairman and Chief Executive Officer at Microsoft",
  "jobTitle": "Chairman and CEO",
  "location": "Redmond, Washington",
  "name": "Satya Nadella",
  "openToWork": false,
  "skills": ["Leadership", "Cloud Computing", "Enterprise Software"],
  "username": "satya-nadella"
}
```

**Example Prompts:**
> "Get the LinkedIn profile for Satya Nadella"
> "Show me the profile at https://linkedin.com/in/johndoe"

---

### `linkedin_get_company`

Fetch a company's LinkedIn profile. Accepts a company slug or full URL.

**Input:**
```json
{
  "company": "microsoft"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `company` | string | ✅ | Company name/slug (e.g., `microsoft`) or full company URL |

**Output:**
```json
{
  "about": "Every company has a mission...",
  "companySize": "10,001+ employees",
  "employeeCount": "228,000",
  "followerCount": "22M",
  "founded": "1975",
  "headquarters": "Redmond, Washington",
  "industry": "Software Development",
  "name": "Microsoft",
  "slug": "microsoft",
  "specialties": ["Cloud Computing", "AI", "Productivity Software"],
  "website": "https://www.microsoft.com"
}
```

**Example Prompts:**
> "What does Anthropic do according to LinkedIn?"
> "Get information about the Tesla company"

---

### `linkedin_search_jobs`

Search for jobs on LinkedIn.

**Input:**
```json
{
  "query": "iOS Developer",
  "location": "San Francisco",
  "limit": 10
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | ✅ | Search query — job title, skills, keywords |
| `location` | string | ❌ | Location filter — city, state, country, or "Remote" |
| `limit` | integer | ❌ | Max results (default: 25, max: 100) |

**Output:**
```json
[
  {
    "company": "TechCorp Inc.",
    "id": "1234567890",
    "isEasyApply": true,
    "jobURL": "https://www.linkedin.com/jobs/view/1234567890/",
    "location": "San Francisco, CA",
    "postedDate": "2 days ago",
    "salary": "$150,000 - $200,000",
    "title": "Senior iOS Engineer"
  }
]
```

**Example Prompts:**
> "Search for Swift Developer jobs in Remote"
> "Find Machine Learning Engineer positions in New York"

---

### `linkedin_get_job`

Get detailed information about a specific job posting.

**Input:**
```json
{
  "job_id": "1234567890"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `job_id` | string | ✅ | Job ID (numeric) or full job URL |

**Output:**
```json
{
  "applicantCount": "47 applicants",
  "company": "TechCorp Inc.",
  "description": "We are looking for a senior iOS engineer...",
  "employmentType": "Full-time",
  "experienceLevel": "Mid-Senior level",
  "id": "1234567890",
  "isEasyApply": true,
  "jobURL": "https://www.linkedin.com/jobs/view/1234567890/",
  "location": "San Francisco, CA",
  "salary": "$150,000 - $200,000",
  "skills": ["Swift", "iOS", "UIKit", "CI/CD"],
  "title": "Senior iOS Engineer",
  "workplaceType": "Hybrid"
}
```

**Example Prompts:**
> "Get details for job 1234567890"
> "What are the requirements for this iOS position?"

---

### `linkedin_create_post`

Create a LinkedIn post. Supports text-only, article/URL share, and image posts.

**Input (text post):**
```json
{
  "text": "Excited to announce our new product launch! 🚀",
  "visibility": "public"
}
```

**Input (article share):**
```json
{
  "text": "Great article on Swift concurrency!",
  "url": "https://example.com/article",
  "url_title": "Understanding Swift Actors",
  "url_description": "A deep dive into actors..."
}
```

**Input (image post):**
```json
{
  "text": "Check out this screenshot!",
  "image_path": "/path/to/image.jpg"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | string | ✅ | Post text content |
| `visibility` | string | ❌ | `"public"` (default) or `"connections"` |
| `url` | string | ❌ | URL to share as article |
| `url_title` | string | ❌ | Article title (used with `url`) |
| `url_description` | string | ❌ | Article description (used with `url`) |
| `image_path` | string | ❌ | Local image file path |

**Output:**
```json
{
  "message": "Post created successfully",
  "postURN": "urn:li:share:1234567890",
  "success": true
}
```

**Example Prompts:**
> "Post on LinkedIn: Excited about our new release!"
> "Share this article on LinkedIn: https://example.com/article"

---

### `linkedin_upload_image`

Upload an image to LinkedIn and return the media URN for use in posts.

**Input:**
```json
{
  "image_path": "/path/to/image.jpg"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `image_path` | string | ✅ | Local image file path |

**Output:**
```json
{
  "mediaURN": "urn:li:digitalmediaAsset:C4D22AQHH...",
  "uploadURL": "https://www.linkedin.com/dms-uploads/..."
}
```

---

### `linkedin_list_conversations`

List recent LinkedIn inbox conversations.

**Input:**
```json
{
  "limit": 10,
  "browser_mode": false
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | ❌ | Max conversations (default: 20) |
| `browser_mode` | boolean | ❌ | Force Peekaboo/Safari browser mode, bypass Voyager API |

**Output:**
```json
[
  {
    "id": "2-YTgxMT...",
    "lastMessage": "Thanks for connecting!",
    "lastMessageAt": "2026-02-18T14:30:00Z",
    "participantNames": ["Jane Doe"],
    "unread": true
  }
]
```

**Example Prompts:**
> "Show my LinkedIn inbox"
> "List my recent LinkedIn conversations"

---

### `linkedin_get_messages`

Read messages from a specific LinkedIn conversation.

**Input:**
```json
{
  "conversation_id": "2-YTgxMT...",
  "limit": 20,
  "browser_mode": false
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `conversation_id` | string | ✅ | Conversation ID (from `linkedin_list_conversations`) |
| `limit` | integer | ❌ | Max messages (default: 20) |
| `browser_mode` | boolean | ❌ | Force Peekaboo/Safari browser mode, bypass Voyager API |

**Output:**
```json
[
  {
    "id": "event-123",
    "senderName": "Jane Doe",
    "text": "Thanks for connecting!",
    "timestamp": "2026-02-18T14:30:00Z"
  }
]
```

**Example Prompts:**
> "Read messages from conversation 2-YTgxMT..."
> "Show messages from my chat with Jane"

---

### `linkedin_send_invite`

Send a connection invitation to a LinkedIn user.

**Input:**
```json
{
  "username": "johndoe",
  "message": "Hi John, great to connect!"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `username` | string | ✅ | LinkedIn username or full profile URL |
| `message` | string | ❌ | Optional custom invitation note |

**Output:**
```json
{
  "success": true,
  "message": "Connection invitation sent to johndoe"
}
```

**Example Prompts:**
> "Send a connection request to johndoe"
> "Connect with johndoe and say 'Great to meet you!'"

---

### `linkedin_send_message`

Send a direct message to a LinkedIn user.

**Input:**
```json
{
  "username": "johndoe",
  "message": "Hey John, thanks for the great article!"
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `username` | string | ✅ | LinkedIn username or full profile URL |
| `message` | string | ✅ | Message text to send |

**Output:**
```json
{
  "success": true,
  "message": "Message sent to johndoe"
}
```

**Example Prompts:**
> "Send a message to johndoe saying thanks for the article"
> "Message johndoe: Are you free for a call next week?"

---

## Complete Example Session

```
User: "Research Microsoft's leadership on LinkedIn"

Claude → linkedin_get_company:
  { "company": "microsoft" }
→ Returns company info (industry, size, about, specialties)

User: "Who is the CEO and what's their background?"

Claude → linkedin_get_profile:
  { "username": "satya-nadella" }
→ Returns Satya's profile with experiences and educations

User: "Are they hiring Swift developers?"

Claude → linkedin_search_jobs:
  { "query": "Swift Developer", "location": "Redmond", "limit": 5 }
→ Returns matching job listings

User: "Get details on the first one"

Claude → linkedin_get_job:
  { "job_id": "1234567890" }
→ Returns full job description, requirements, and skills

User: "Post about our research findings"

Claude → linkedin_create_post:
  { "text": "Excited to share our latest research findings on...", "visibility": "public" }
→ Returns post URN confirming creation

User: "Check my messages"

Claude → linkedin_list_conversations:
  { "limit": 5 }
→ Returns recent conversations with previews
```

---

## Error Handling

The MCP server returns errors in the standard MCP format with `isError: true`:

```json
{
  "content": [{ "type": "text", "text": "Failed to fetch profile: Not authenticated..." }],
  "isError": true
}
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| Not authenticated | No cookie configured | Use `linkedin_configure` to set cookie |
| Cookie expired or invalid | `li_at` cookie has expired | Get fresh cookie from browser |
| HTTP 429 | Rate limited by LinkedIn | Wait before retrying |
| Security challenge | CAPTCHA triggered | Complete challenge in browser |
| Parse error | LinkedIn HTML structure changed | Update parsers / report issue |
| Invalid URN format | Bad profile URN for messaging | Use username, not raw URN |

---

## Security Notes

- The `li_at` cookie provides full access to your LinkedIn account
- Stored securely in macOS Keychain (handled automatically)
- Never share your `li_at` cookie with others
- The cookie expires periodically (typically ~1 year)
- Post creation and messaging actions are irreversible

---

## Troubleshooting

### Server Won't Start

1. Check the executable path is correct
2. Ensure executable permissions: `chmod +x /usr/local/bin/linkedin-mcp`
3. Verify Swift runtime is installed

### Authentication Failures

1. Get a fresh `li_at` cookie from your browser
2. Ensure cookie hasn't expired
3. Try reconfiguring: `linkedin auth --clear && linkedin auth NEW_COOKIE`

### Rate Limiting

LinkedIn may block frequent requests. Wait a few minutes before retrying.

### Missing Data

If profiles/jobs return incomplete data, LinkedIn may have updated their HTML structure. The system will automatically fall back to Peekaboo vision-based scraping when enabled.

### Messaging Issues

If Voyager API messaging fails (401/403/429), the system automatically falls back to Peekaboo browser-based messaging. You can force browser mode with the `browser_mode` parameter.
