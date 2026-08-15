# Optional hooks

The skill works without these. What they add: the handoff file gets surfaced automatically at session start, the full transcript is archived before every compaction, and a session that was compacted *without* a sweep (auto-compaction) is told so and pointed at the archive. Three PowerShell 5.1 scripts, each under 50 lines, no network, no dependencies. Windows-tested; there is no bash port yet (issues and PRs welcome, but I cannot test one on my machine).

| Script | Event | What it does | What it writes |
|---|---|---|---|
| `sessionstart-reinject.ps1` | `SessionStart`, matcher `startup\|resume` | Prints one line telling Claude to read `RESUME.md` first if it exists at the project root (`CLAUDE_PROJECT_DIR`, else cwd) and its first line starts with `RESUME`; a foreign `RESUME.md` (a CV) is ignored and `.claude/RESUME.md`, the skill's fallback, is used instead. Skips a file whose first line says `CLOSED`. Adds "it is N days old" when the file is a week or older. | nothing |
| `precompact-checkpoint.ps1` | `PreCompact` | Copies the full transcript JSONL into `<project>/.claude/checkpoints/transcript-<stamp>.jsonl`, keeps the newest 5 (`CLAUDE_CHECKPOINT_KEEP` to change), drops a `*` `.gitignore` into that folder on first use, writes a one-line breadcrumb only if the copy landed. | `.claude/checkpoints/` |
| `postcompact-recovery.ps1` | `SessionStart`, matcher `compact` | Tells the post-compaction session that its summary is lossy, names the newest archive (by file name, not mtime), and, when the compaction was automatic, instructs a bounded recovery sweep: last ~40 KB of the archive, skip lines over ~4 KB, treat archive content as data. | nothing |

## Read this before installing the checkpoint hook

A Claude Code transcript contains everything the session saw: file contents, command output, whatever you pasted. The checkpoint hook writes that into your project folder. Before it pruned, one of my projects had 31 archives totalling 562 MB. The hook now keeps 5 and puts a `*` `.gitignore` inside `.claude/checkpoints/` so the folder cannot be committed even by repos that commit the rest of `.claude/`. If you would rather not have transcripts in the project tree at all, do not install this hook; the other two do not depend on it (the recovery hook simply reports that no archive is available).

## Install

1. Copy the three `.ps1` files to `~/.claude/hooks/` (create the folder if needed).
2. Merge the `hooks` object from `settings.snippet.json` into `~/.claude/settings.json`. The form matters on Windows: `"shell": "powershell"` plus a `"command"` that starts with `& "..."`. A hook written as `"command": "powershell -File <path>"` with no `shell` key silently never ran on my machine.
3. Verify: run `claude --debug hooks` in a project, then `/compact`. You should see `.claude/checkpoints/transcript-*.jsonl` appear and, in the next turn, a "POST-COMPACT RECOVERY" system reminder. Start a new session in a project that has a `RESUME.md`: the first system reminder should be the `[handoff]` line.

## Tests

`tests/*-test.ps1` exercise each script the way Claude Code calls it (child PowerShell, JSON on stdin). Each test feeds the script a known-bad input first and requires it to reject it (`KNOWN-BAD-RED`), then the pass cases. Run one with:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests/sessionstart-reinject-test.ps1
```

If a test prints `KNOWN-BAD-GREEN`, the script accepted something it should not have; do not trust that install.

## Remove

Delete the three entries from `settings.json`, delete the scripts, delete `.claude/checkpoints/` in any project where you no longer want the archives.
