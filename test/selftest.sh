#!/usr/bin/env bash
# handoff-kit self-test: runs each hook on sample input in a temp folder.
# Touches nothing outside that folder. Usage: bash test/selftest.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
export XDG_STATE_HOME="$tmp/state"
pass=0; fail=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi; }

command -v jq >/dev/null || { echo "FAIL  jq is not installed (brew install jq / apt install jq)"; exit 1; }

# A fake transcript: one main-thread reply using 180k tokens, one subagent reply that must be ignored.
t="$tmp/t.jsonl"
cat > "$t" <<J
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":999999}}}
{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":10000,"cache_creation_input_tokens":20000,"cache_read_input_tokens":149000,"output_tokens":1000}}}
J
mkdir -p "$tmp/project"
stop() { echo "{\"session_id\":\"$1\",\"transcript_path\":\"$t\",\"cwd\":\"$tmp/project\",\"stop_hook_active\":${2:-false}}"; }

# 180k of 200k = 90%: above 85, so it fires once.
out=$(stop s1 | HANDOFF_WINDOW=200000 "$root/scripts/context-guard.sh")
check "fires at 90% with a block decision" '[ "$(jq -r .decision <<<"$out")" = block ]'
check "the instruction names the note path" 'grep -q "HANDOFF-" <<<"$out"'
out2=$(stop s1 | HANDOFF_WINDOW=200000 "$root/scripts/context-guard.sh")
check "fires only once per session" '[ -z "$out2" ]'
out3=$(stop s2 true | HANDOFF_WINDOW=200000 "$root/scripts/context-guard.sh")
check "never fires inside its own continuation (stop_hook_active)" '[ -z "$out3" ]'
out4=$(stop s3 | HANDOFF_WINDOW=1000000 "$root/scripts/context-guard.sh")
check "silent below the threshold (18% of 1M)" '[ -z "$out4" ]'
out5=$(stop s4 | HANDOFF_WINDOW=1000000 HANDOFF_THRESHOLD=15 "$root/scripts/context-guard.sh")
check "threshold is configurable (fires at 15%)" '[ "$(jq -r .decision <<<"$out5")" = block ]'

out6=$(stop s5 | HANDOFF_WINDOW=200000 HANDOFF_EXTRA="Also message Edith." "$root/scripts/context-guard.sh")
check "HANDOFF_EXTRA is added to the instruction" 'grep -q "Also message Edith." <<<"$(jq -r .reason <<<"$out6")"'

# Start hook: loads the newest note on startup and /clear, skips resume.
mkdir -p "$tmp/project/.handoff"
echo "old note" > "$tmp/project/.handoff/HANDOFF-2026-01-01-0900.md"; sleep 1
printf '# Handoff\nnext step: ship it\n' > "$tmp/project/.handoff/HANDOFF-2026-01-02-0900.md"
s=$(echo "{\"source\":\"clear\",\"cwd\":\"$tmp/project\"}" | "$root/scripts/handoff-start.sh")
check "start hook loads the newest note on /clear" 'grep -q "next step: ship it" <<<"$s" && ! grep -q "old note" <<<"$s"'
r=$(echo "{\"source\":\"resume\",\"cwd\":\"$tmp/project\"}" | "$root/scripts/handoff-start.sh")
check "start hook stays silent on resume" '[ -z "$r" ]'
o=$(echo "{\"source\":\"startup\",\"cwd\":\"$tmp/project\"}" | HANDOFF_MAX_AGE_HOURS=-1 "$root/scripts/handoff-start.sh")
check "start hook ignores notes older than the max age" '[ -z "$o" ]'

# PreCompact: copies the transcript into the archive.
echo "{\"session_id\":\"abcdef123456\",\"transcript_path\":\"$t\",\"trigger\":\"auto\"}" | "$root/scripts/precompact-archive.sh"
check "precompact archives the transcript" 'ls "$tmp/state/handoff-kit/archive/"*abcdef12-auto.jsonl >/dev/null 2>&1'

rm -rf "$tmp"
echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
