# Beads Status

Check the current state of the LinkedFish rebuild project.

```bash
echo "=== READY TO WORK ===" && bd ready && echo "" && echo "=== IN PROGRESS ===" && bd list --status=in_progress && echo "" && echo "=== STATS ===" && bd stats
```

## Useful Beads Commands

```bash
bd ready                          # Find available work (no blockers)
bd list --status=open             # All open issues
bd list --status=in_progress      # Active work
bd show <id>                      # Detailed issue view
bd blocked                        # Show blocked issues
bd stats                          # Project statistics
bd update <id> --status=in_progress   # Claim work
bd close <id>                     # Mark complete
bd sync                           # Sync with git remote
```

## Issue ID Prefixes

| Prefix | Epic |
|--------|------|
| `lf-b6q` | TinyFish Core Client |
| `lf-0s7` | LinkedInClient Replacement |
| `lf-ypr` | LinkedIn Method Implementations |
| `lf-xrh` | CLI Command Updates |
| `lf-1m3` | MCP Server Updates |
| `lf-gr3` | Testing |
| `lf-5o2` | Dependency Cleanup |
| `lf-k2v` | Demo & Application |
