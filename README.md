# handoff-kit

**Hand a Claude Code session off before its context fills up.**

Long Claude Code sessions eventually fill their context window. Then Claude Code compacts the conversation, and details get lost. handoff-kit makes the session write a proper handoff note *before* that happens, and gives the next session that note automatically.

- **Context guard:** after each turn, it estimates how full the context is. At 85% (configurable) it tells Claude, once, to write a handoff note (goal, state, next step, decisions, open questions, key files) to `.handoff/HANDOFF-<date>-<time>.md`, then to tell you it's ready.
- **Handoff loader:** when a fresh session starts in that project (a new `claude`, or `/clear`), the newest note (up to 72 hours old) is put into its context, so it picks up where the last one stopped.
- **Safety net:** before Claude Code compacts a conversation, a copy of the full transcript is saved to `~/.local/state/handoff-kit/archive/`.

The everyday loop: **work → Claude says "handoff note is ready" → you type `/clear` → the fresh session continues from the note.**

## Install (2 minutes)

You need [Claude Code](https://claude.com/claude-code) and `jq` (`brew install jq` on macOS, `apt install jq` on Debian/Ubuntu).

In Claude Code:
```
/plugin marketplace add BerlinMedia-za/handoff-kit
```
```
/plugin install handoff-kit@handoff-kit
```
Or from a terminal: `claude plugin marketplace add BerlinMedia-za/handoff-kit`, then `claude plugin install handoff-kit@handoff-kit`.

The hooks are active in new sessions. `/plugin` shows the plugin; disable or uninstall it there.

**Read the scripts before you install** (`scripts/`, under 100 lines in total, commented). Hooks run shell commands on your machine with your permissions. That's true of any hook from anyone.

## Settings

Set these in the `env` block of `~/.claude/settings.json` (all projects) or `.claude/settings.json` (one project):

```json
{
  "env": {
    "HANDOFF_WINDOW": "200000",
    "HANDOFF_THRESHOLD": "85"
  }
}
```

| Variable | Default | What it does |
|---|---|---|
| `HANDOFF_WINDOW` | `200000` | **Your model's context window, in tokens.** Set it to match your session: run `/context` in Claude Code to see it. If your session has a 1M window, set `1000000`, or the guard fires far too early. |
| `HANDOFF_THRESHOLD` | `85` | Percent at which the handoff is triggered. |
| `HANDOFF_DIR` | `.handoff` | Where notes go, relative to the project. Avoid `.claude/`: Claude Code protects it and asks permission for every write there. |
| `HANDOFF_MAX_AGE_HOURS` | `72` | A new session only loads a note this recent. |
| `HANDOFF_MAX_LINES` | `200` | How much of the note is loaded (longer notes say where the full file is). |
| `HANDOFF_ARCHIVE` | `~/.local/state/handoff-kit/archive` | Where pre-compaction transcript copies go. |
| `HANDOFF_DEBUG` | unset | `1` logs every guard run to `~/.local/state/handoff-kit/debug.log`. |

**Commit the notes or not?** Up to you. Add `.handoff/` to `.gitignore` to keep them local, or commit them so they travel with the repo. The guard tells Claude to commit only if committing notes is normal in that project.

## Check it works

**Self-test** (runs every hook on sample data in a temp folder, touches nothing else):
```
git clone https://github.com/BerlinMedia-za/handoff-kit && bash handoff-kit/test/selftest.sh
```
Expect `10 passed, 0 failed`.

**Live test:** in a throwaway folder, set `"HANDOFF_THRESHOLD": "1"`, ask Claude two short questions, and it will write a note on the second turn and tell you to `/clear`. After `/clear`, ask "is there a handoff note in your context?" Then set the threshold back.

## How it works, and its limits

- **Where the estimate comes from:** the guard reads your session's transcript (the `.jsonl` file Claude Code keeps under `~/.claude/projects/`) and adds up the token usage of the last main-thread reply: input + cache reads + cache writes + output. It's an estimate, not your plan's quota.
- **One turn behind:** Claude Code writes the current reply to the transcript just after the Stop hook runs, so the guard sees the previous turn's size. In a long session that's harmless; it means a handoff can't trigger on the very first turn.
- **The transcript format is internal to Claude Code** and can change between versions. If an update breaks parsing, the guard simply stays silent (turn on `HANDOFF_DEBUG` to see "no usage found"). It never blocks your session.
- **Fires once per session.** It won't nag, and it can't loop: it stays quiet inside the continuation it caused.
- **It doesn't restart the session for you.** No official way exists for a hook to end or restart Claude Code. Typing `/clear` is the one manual step.

## Uninstall

`/plugin` → handoff-kit → uninstall. Notes in `.handoff/` and archives in `~/.local/state/handoff-kit/` are yours to keep or delete.

## License

MIT. Made by [Berlin Media](https://berlin-media.net) while building Friday.
