# Install LinkedFish CLIs

Build release binaries and install to `/usr/local/bin/`.

```bash
swift build -c release && cp .build/release/linkedin /usr/local/bin/ && cp .build/release/linkedin-mcp /usr/local/bin/ && echo "✅ Installed linkedin and linkedin-mcp to /usr/local/bin/"
```

## What Gets Installed

| Binary | Command | Purpose |
|--------|---------|---------|
| `linkedin` | `linkedin profile <user>` | CLI for LinkedIn operations |
| `linkedin-mcp` | (auto-started) | MCP server for Claude Desktop |

## Verify Installation

```bash
which linkedin          # Should show /usr/local/bin/linkedin
linkedin --version      # Show version
linkedin status         # Check auth status
```

## MCP Server Config

After installing, add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "linkedfish": {
      "command": "/usr/local/bin/linkedin-mcp"
    }
  }
}
```
