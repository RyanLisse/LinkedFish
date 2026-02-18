# Prime Session Context

Load project context at the start of a new session. Run this after `/clear` or when starting fresh.

```bash
echo "=== LinkedFish TinyFish Rebuild ===" && echo "" && echo "--- Project Status ---" && bd stats && echo "" && echo "--- Ready to Work ---" && bd ready && echo "" && echo "--- Recent Git Activity ---" && git log --oneline -5 && echo "" && echo "--- Build Status ---" && swift build 2>&1 | tail -5
```

## What This Does

1. Shows project stats (open/closed/blocked counts)
2. Lists available work with no blockers
3. Shows recent commits for context
4. Attempts a build to verify code is compilable

## Session Workflow

```bash
/prime              # Load context
bd show lf-b6q.1    # Review first task
bd update lf-b6q.1 --status=in_progress   # Claim it
# ... do the work ...
swift test          # Verify
bd close lf-b6q.1   # Complete
bd sync             # Push
```
