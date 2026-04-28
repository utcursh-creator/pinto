#!/bin/bash
# verify-memory-stop.sh
# Fires on Stop event. Checks if memory was updated this session.
# If not, blocks Claude from finishing until memory is updated.

set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Debug log — helps diagnose path issues on Windows/Git Bash
DEBUG_LOG="${TMPDIR:-/tmp}/verify-memory-stop.log"
{
  echo "---"
  echo "$(date -u +%FT%TZ) fired"
  echo "CWD raw: [$CWD]"
} >> "$DEBUG_LOG" 2>/dev/null || true

if [ -z "$CWD" ]; then
  echo "no CWD; allow stop" >> "$DEBUG_LOG" 2>/dev/null || true
  exit 0
fi

# Normalize backslash → forward-slash (Git Bash on Windows passes mixed separators)
CWD_NORM=$(echo "$CWD" | tr '\\' '/')
MEMORY_STATUS="$CWD_NORM/.claude/context/memory/work_status.md"

echo "resolved path: [$MEMORY_STATUS]" >> "$DEBUG_LOG" 2>/dev/null || true

if [ ! -f "$MEMORY_STATUS" ]; then
  # File missing — not our job to create; allow stop
  echo "file missing; allow stop" >> "$DEBUG_LOG" 2>/dev/null || true
  exit 0
fi

# Determine file mtime
if [ "$(uname)" = "Darwin" ]; then
  LAST_MODIFIED=$(stat -f %m "$MEMORY_STATUS" 2>/dev/null || echo 0)
else
  LAST_MODIFIED=$(stat -c %Y "$MEMORY_STATUS" 2>/dev/null || echo 0)
fi

NOW=$(date +%s)
DIFF=$((NOW - LAST_MODIFIED))

echo "mtime=$LAST_MODIFIED now=$NOW diff=${DIFF}s" >> "$DEBUG_LOG" 2>/dev/null || true

# Widen window to 30 minutes (1800s) so normal turn pacing doesn't falsely block
if [ "$DIFF" -lt 1800 ]; then
  echo "mtime fresh; allow stop" >> "$DEBUG_LOG" 2>/dev/null || true
  exit 0
fi

# Memory stale — block the stop
echo "mtime stale; BLOCK" >> "$DEBUG_LOG" 2>/dev/null || true
cat <<'EOF'
{
  "decision": "block",
  "reason": "MEMORY UPDATE REQUIRED: You must update context/memory/work_status.md before stopping. Review this conversation for: what was accomplished, what's pending, and what the next steps are. Also update other memory files (learnings.md, user_preferences.md, user_projects.md) if you learned anything new."
}
EOF

exit 0
