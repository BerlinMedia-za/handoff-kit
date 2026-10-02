#!/usr/bin/env bash
# handoff-kit · PreCompact hook: keep a copy of the transcript before
# Claude Code compacts it. Copies go outside the project, so they're never
# committed by accident.
#
# Settings: HANDOFF_ARCHIVE (default ~/.local/state/handoff-kit/archive)
set -u
input=$(cat)
session=$(jq -r '.session_id // "unknown"' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
trigger=$(jq -r '.trigger // "unknown"' <<<"$input")
archive=${HANDOFF_ARCHIVE:-${XDG_STATE_HOME:-$HOME/.local/state}/handoff-kit/archive}
[ -f "$transcript" ] || exit 0
mkdir -p "$archive"
cp "$transcript" "$archive/$(date +%Y%m%d-%H%M%S)-${session:0:8}-${trigger}.jsonl"
exit 0
