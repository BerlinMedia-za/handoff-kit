#!/usr/bin/env bash
# handoff-kit · SessionStart hook: load the newest handoff note.
#
# A fresh session (startup, /clear, or after compaction) gets the newest
# handoff note of this project in its context, if it's recent. A resumed
# session already has its own context, so it's skipped.
#
# Settings: HANDOFF_DIR (default .handoff), HANDOFF_MAX_AGE_HOURS (default 72),
#           HANDOFF_MAX_LINES (default 200)
set -u
input=$(cat)
source=$(jq -r '.source // empty' <<<"$input")
[ "$source" = "resume" ] && exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
dir="${cwd:-.}/${HANDOFF_DIR:-.handoff}"
[ -d "$dir" ] || exit 0

note=$(ls -t "$dir"/HANDOFF-*.md 2>/dev/null | head -1)
[ -n "$note" ] || exit 0
age_h=$(( ( $(date +%s) - $(stat -f %m "$note" 2>/dev/null || stat -c %Y "$note") ) / 3600 ))
[ "$age_h" -le "${HANDOFF_MAX_AGE_HOURS:-72}" ] || exit 0

max=${HANDOFF_MAX_LINES:-200}
echo "A previous session left a handoff note ($note, ${age_h}h old). Read it and continue from it; confirm with the user before acting on anything that has changed since."
echo
head -n "$max" "$note"
[ "$(wc -l < "$note")" -gt "$max" ] && echo && echo "[note truncated at $max lines; read the full file: $note]"
exit 0
