# Evidence behind the claims in this repo

One person, one Windows machine, Claude Code 2.1.226, August 2026. Numbers below are what the audit actually recorded, with the selection conditions stated. Re-measure on your own transcripts before trusting any of it.

## 1. The audit (2026-08-10)

Question I was trying to answer: does chat-only information leak past my own state discipline, and where?

Method: three Sonnet subagents read real Claude Code transcripts (`~/.claude/projects/<project>/*.jsonl`) from three corpora and traced user statements forward to see whether they landed in a file. About 44 compactions were counted across the corpora and 14 were inspected individually. Coverage per corpus: 10 of 15 sessions (a build project), 10 of 53 (a strategy/research project), 8 of 19 (three small app projects). This is a strong sample, not an exhaustive sweep, and the samplers said so.

### 1a. The null result (most of the discipline works)

- Build project: 6 of 6 traced decisions were on disk in the same session or earlier (one landed 80 seconds after being said). Every inspected compaction was `"trigger":"manual"` and preceded by a `/prep-compact` sweep with an itemized receipt.
- Strategy project: 8 of 8 traced statements persisted, typically 1 to 30 minutes after the chat moment. Only 1 real compaction in 53 session files.
- App projects: 6 of 6 inspected compactions showed writes landing before the compaction fired; roughly 85 to 90 percent decision-persistence on traced candidates.
- Sweeps for "you already told me that" / "no, I said X" language around compaction boundaries came back clean everywhere.

### 1b. The receipt finding (why this skill writes files first)

Selection condition: compactions that fired **while `/prep-compact` was itself running** (`/prep-compact` is what this skill was called on my machine when the audit ran; the public version is `/save-before-compact`). Six such boundaries were found in the app-project corpus, in five sessions:

| Session (id prefix) | Project (anonymized) | Boundary line in the transcript |
|---|---|---|
| 9e68446a | app A (a Forge app) | 495 |
| 0d458901 | app B (a small business site) | 1283 |
| 911026fe | app B (a small business site) | 1060 |
| 911026fe | app B (a small business site) | 2854 |
| 30ee72bb | app C (a web app) | 1174 |
| 677faf5e | app A (a Forge app) | 1027 |

Result, in the sampler's own words:

> In every one of 5 compactions that fired while the /prep-compact skill was mid-execution, the skill's own Steps 3-4 (a human-readable "receipt" of what was saved, and a fenced RESUME block meant to orient the next session) were cut off by the auto-compact before the assistant emitted them as chat text. [...] In every traced case the underlying data (git commits, memory-file edits) had already landed before the interruption, so no decision or fact was actually lost, but the convenience artifact the skill exists to produce (a quick paste-in orientation block for the resumed session) was reliably absent.

The compaction summaries themselves carried the tell, near-verbatim across those five: "The only unfinished piece is the final prep-compact text output." Once, the user pasted the resume block back by hand.

Severity as recorded: LOW but structural. What it decided: the skill now writes the resume block to `RESUME.md` before it says anything in chat. Files on disk are outside the context window; chat text is not. That is a design rationale, not a measured improvement: no before/after comparison of the reordered skill exists.

### 1c. The open-questions finding

One traced case (n=1): a session ended on an offer to the user ("if you'd rather he ships fully solo, that's a one-line change, say the word"), the user never answered, and the offer was searched for across all 11 memory files of that project and never found as an open item. It is the only class of information the audit could not find written down anywhere, and it is why the sweep has an explicit "questions you asked that are still unanswered" line. One case is one case; treat the rule as a plausible fix, not a measured pattern.

## 2. The compaction spike (2026-08-10, headless rig, Claude Code 2.1.226)

Verified live, in a throwaway session driven with `claude -p --resume`:

- `SessionStart` fires with `source: "compact"` immediately after every compaction, and its `hookSpecificOutput.additionalContext` reliably reaches the model (a probe quoted an injected marker verbatim). This is the channel the optional recovery hook uses.
- A `PreCompact` hook returning exit code 2 did **not** stop auto-compaction in 8 of 8 attempts across 2 sessions, with real token drops each time (for example pre 59,515 to post 6,548). The block's stderr text appeared nowhere in the transcript, and the model, asked directly, said it had not seen it. Two caveats that must travel with this: the test ran headless only, and my own always-exit-0 checkpoint hook ran alongside, so "any hook allows means allow" semantics were not ruled out. The official hooks reference documents PreCompact as able to block compaction; I am reporting what my rig did, not contradicting the docs.
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW` + `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` fire auto-compaction aggressively even in `-p` mode.
- `/compact` on a session with fewer than 2 turns returns "Not enough messages to compact." inside a success envelope.
- Windows hook registration: a hook written as `"command": "powershell -NoProfile -File <path>"` with no `shell` key silently never ran on this machine. The form that works, and that the docs describe: `"shell": "powershell"` plus `"command": "& '<path>'"`. (The docs' exec form with `"args": [...]` is a separate valid path.)

## 3. Measured on 2026-08-15, while preparing this repo

- The transcript archive written by the checkpoint hook, before it pruned: one project had 31 archives totalling 562.5 MB, the largest 53.9 MB. Transcripts contain everything the session saw. The hook now keeps 5 and drops a `*` `.gitignore` into the checkpoint folder.
- "Read the last 80 lines" of a transcript JSONL is the wrong unit: the last 80 lines of one archive were 250,139 characters (about 62,500 tokens); one single line was 344,727 characters. The recovery hook now says "the last ~40 KB, skip lines over ~4 KB".
- `Copy-Item` preserves the source file's modification time, so "newest archive by LastWriteTime" picked the wrong file after a failed copy. The hooks now sort by name (`yyyyMMdd-HHmmss`).
- The two checks in the README, run on the finished skill in two throwaway projects (headless `claude -p`, Sonnet, 2026-08-15): known-bad (a "say hi" exchange, then the skill) answered "Nothing new to save, you're safe to compact" and left the directory empty; known-good (one turn stating "go with option B, not A" plus an unanswered date-filter question, then the skill) wrote a 645-character `RESUME.md` carrying the decision and the question as an `Open:` line, and wrote no memory file ("project-specific state, not a cross-session fact"). Two runs, one setup; a demonstration that the text does what it says, not a rate.

## 4. Where the raw material is

The audit and spike were run as Claude Code workflows; their journals are on a transcript-retention timer, so the relevant journal was copied out on 2026-08-15 and is kept with the author's private notes. The session ids and line numbers above are the pointers into it. Nothing in this file is reproducible by a reader without those transcripts, which is why every number carries its n and its selection condition.
