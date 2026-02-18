# Check Source Files

List all Swift source files with sizes for quick overview of the codebase.

```bash
echo "=== Sources/LinkLion ===" && ls -lh Sources/LinkLion/*.swift && echo "" && echo "=== Sources/LinkedInCLI ===" && ls -lh Sources/LinkedInCLI/*.swift && echo "" && echo "=== Sources/LinkedInMCP ===" && ls -lh Sources/LinkedInMCP/*.swift && echo "" && echo "=== Tests ===" && ls -lh Tests/LinkedInKitTests/*.swift
```

## Key Files

| File | Status | Description |
|------|--------|-------------|
| `Sources/LinkLion/LinkedInClient.swift` | REWRITE → facade | Was Voyager API client |
| `Sources/LinkLion/TinyFishClient.swift` | CREATE | New TinyFish actor |
| `Sources/LinkLion/Models.swift` | KEEP | Data models |
| `Sources/LinkLion/CredentialStore.swift` | ADAPT | Store TinyFish API key |
| `Sources/LinkLion/ProfileParser.swift` | DELETE | No more HTML parsing |
| `Sources/LinkLion/JobParser.swift` | DELETE | No more HTML parsing |
| `Sources/LinkLion/PeekabooClient.swift` | DELETE | TinyFish IS the browser |
| `Sources/LinkLion/GeminiVision.swift` | DELETE | TinyFish handles vision |
| `Sources/LinkedInCLI/LinkedIn.swift` | UPDATE | Add --api-key, update auth |
| `Sources/LinkedInMCP/LinkedInMCP.swift` | UPDATE | Add new tools |
