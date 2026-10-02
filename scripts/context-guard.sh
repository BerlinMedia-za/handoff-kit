#!/usr/bin/env bash
# handoff-kit · Stop hook: the context guard.
#
# After every turn, estimate how full this session's context window is, from
# the session's own transcript. The first time it crosses the threshold, tell
# Claude (once) to write a handoff note so a fresh session can take over.
#
# Settings (env, e.g. in settings.json "env"):
#   HANDOFF_THRESHOLD  percent at which to hand off            (default 85)
#   HANDOFF_WINDOW     context window size in tokens           (default 200000)
#   HANDOFF_DIR        where notes go, relative to the project (default .handoff)
#   HANDOFF_DEBUG=1    log each run to ~/.local/state/handoff-kit/debug.log
set -u
input=$(cat)
state=${XDG_STATE_HOME:-$HOME/.local/state}/handoff-kit
debug() { [ "${HANDOFF_DEBUG:-}" = 1 ] && { mkdir -p "$state"; echo "$(date +%T) $*" >> "$state/debug.log"; }; return 0; }
debug "stop hook input: $(jq -c '{session_id, transcript_path, stop_hook_active}' <<<"$input" 2>/dev/null || echo unparsable)"

# Never re-trigger from inside a continuation this hook caused.
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0

session=$(jq -r '.session_id // empty' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$session" ] && [ -f "$transcript" ] || exit 0

threshold=${HANDOFF_THRESHOLD:-85}
window=${HANDOFF_WINDOW:-200000}
marker="$state/$session.fired"
[ -f "$marker" ] && exit 0

# Context = the last main-thread reply's input + cache + output tokens.
# Only the tail is read: transcripts grow to tens of MB.
used=$(tail -n 4000 "$transcript" | jq -s -r '
  [ .[] | select(.type == "assistant" and (.isSidechain | not) and .message.usage != null) ]
  | last
  | if . == null then 0 else
      (.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
                      + (.cache_read_input_tokens // 0) + (.output_tokens // 0))
    end' 2>/dev/null)
[ -n "$used" ] || { debug "no usage found in transcript"; exit 0; }
pct=$(( used * 100 / window ))
debug "used=$used window=$window pct=$pct threshold=$threshold"
[ "$pct" -ge "$threshold" ] || exit 0

mkdir -p "$state" && : > "$marker"
dir=${HANDOFF_DIR:-.handoff}
note="$dir/HANDOFF-$(date +%Y-%m-%d-%H%M).md"

reason="Your context window is about ${pct}% full (${used} of ${window} tokens). Before doing anything else, write a handoff note for a fresh session to ${note} (relative to ${cwd:-the project root}; create the folder if needed). Include: the goal and current state, what is done, what is in progress and the exact next step, decisions made and why, open questions for the user, files and commands that matter, and anything you were about to do. Keep it factual and complete enough that a new session with no memory of this one can continue. If this project uses git and committing notes is normal here, commit it. Then tell the user in one line that the handoff note is ready and that they can type /clear to continue in a fresh session, and stop."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
