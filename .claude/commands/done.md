# Session Complete - Land the Plane

Run this when ending a work session. Ensures all work is committed and pushed.

```bash
echo "=== Git Status ===" && git status && echo "" && echo "=== Beads Sync ===" && bd sync && echo "" && echo "=== Push ===" && git push && echo "" && echo "=== Verify ===" && git status && echo "" && echo "✅ Session complete. All work pushed."
```

## Manual Steps (if needed)

```bash
# 1. Check what changed
git status

# 2. Stage code changes
git add Sources/ Tests/ Package.swift

# 3. Sync beads (commits beads changes)
bd sync

# 4. Commit code
git commit -m "feat: implement TinyFishClient SSE parser"

# 5. Sync beads again (pick up any new beads changes)
bd sync

# 6. Push everything
git push

# 7. Verify
git status   # Must show "up to date with origin"
```

## Closing Issues

```bash
# Close individual
bd close lf-b6q.1

# Close multiple at once (more efficient)
bd close lf-b6q.1 lf-b6q.2 lf-b6q.3

# Close with reason
bd close lf-b6q.1 --reason="Replaced by TinyFishClient actor"
```
