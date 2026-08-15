# Hook tests

One test per script, run the way Claude Code calls the hook (a child PowerShell with the JSON event on stdin). Each test feeds the script a known-bad input first and requires the script to reject it, then checks the pass cases.

```
powershell -NoProfile -ExecutionPolicy Bypass -File precompact-checkpoint-test.ps1
```

Output is one line per check; the first word is the status:

| Line | Meaning |
|---|---|
| `PASS <name>` | a positive check passed |
| `FAIL <name>` | a positive check failed |
| `KNOWN-BAD-RED <name>` | a deliberately bad input was fed and the script rejected it (correct) |
| `KNOWN-BAD-GREEN <name>` | a deliberately bad input was fed and the script let it through (do not trust that install) |

Exit code 0 when everything is as expected, 1 otherwise. The tests use temp folders under `$env:TEMP`, clear `CLAUDE_PROJECT_DIR` while they run and restore it after, and never touch `~/.claude/settings.json`. They expect the scripts at `~/.claude/hooks/<name>.ps1`, which is where the install puts them.

A suite with zero `KNOWN-BAD-RED` lines has never shown it can fail, and should not be trusted; that is why the bad input goes first.
