# Build LinkedFish

Build the Swift project. Use `release` for optimized binaries.

```bash
swift build $ARGUMENTS
```

## Examples

- `/build` — Development build
- `/build -c release` — Release build (optimized, for installation)
- `/build --target LinkedInCLI` — Build CLI only
- `/build --target LinkedInMCP` — Build MCP server only

## After Release Build

To install to `/usr/local/bin/`:
```bash
cp .build/release/linkedin /usr/local/bin/
cp .build/release/linkedin-mcp /usr/local/bin/
```
