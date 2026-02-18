# Run Tests

Run the LinkedFish test suite.

```bash
swift test $ARGUMENTS
```

## Examples

- `/test` — Run all tests
- `/test --filter SSEParser` — Run SSE parser tests only
- `/test --filter TinyFish` — Run TinyFishClient tests
- `/test --filter ProfileFetch` — Run profile fetching tests
- `/test --filter AuthCommand` — Run auth command tests
- `/test --verbose` — Verbose output
- `/test --filter LinkedInKitTests` — Run all LinkedInKit tests

## Common Test Categories

| Filter | Tests |
|--------|-------|
| `testSSE` | SSE stream parsing |
| `testTinyFish` | TinyFishClient actor |
| `testProfile` | Profile fetching |
| `testCompany` | Company info |
| `testJobs` | Job search |
| `testAuth` | Auth command |
| `testMCP` | MCP tool handlers |
