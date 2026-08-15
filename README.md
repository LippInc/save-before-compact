# save-before-compact: save what the compaction is about to eat

A small Claude Code skill. Right before you compact or clear a long chat, it sweeps the conversation for decisions, facts, corrections and open questions that are not yet in any file, saves them, writes a short `RESUME.md` handoff for the next session, and only then tells you what it did. When there is nothing to save, it says so and writes nothing.

## Install (two minutes)

Copy the folder containing `SKILL.md` to `~/.claude/skills/save-before-compact/`, so that `~/.claude/skills/save-before-compact/SKILL.md` exists (create the folders if they do not). Restart Claude Code once if `~/.claude/skills/` did not exist before. Then `/save-before-compact` runs it, and Claude will also pick it up on its own when you say you are about to compact or clear.

Add one line to the project's `CLAUDE.md` so the next session actually reads the handoff (Claude Code loads `CLAUDE.md` at every start and re-injects the project-root copy after compaction):

```
If RESUME.md (or .claude/RESUME.md) exists in the project root, and its first line starts with RESUME and does not say CLOSED, read it first.
```

Add `RESUME.md` and `.claude/checkpoints/` to your `.gitignore` unless you want the handoff committed.

Optional: [hooks/](hooks/) has three PowerShell scripts that surface `RESUME.md` automatically, archive the transcript before each compaction, and tell a session that was auto-compacted to run a recovery sweep. Windows-tested only; read the disclosure in that folder before installing the archive hook.

## Why it exists

I audited my own Claude Code transcripts in August 2026 expecting to find leaks, things I had said in chat that never made it to disk. Mostly there were none: across three projects, 6 of 6 traced decisions in one corpus and 8 of 8 in another were already in a file, usually within minutes, and the third ran about 85 to 90 percent. What was consistently getting lost was narrower and a little embarrassing: the output of the save-what-matters skill itself. In 5 of the 6 compactions I found that had fired while the skill was running, the file writes had already landed and the compaction ate the closing chat text, the receipt and the resume block, the part that tells the next session where to pick up. The tool was reliably saving everything except the note explaining what it had saved. Once I pasted the block back in by hand.

So the order in this skill is deliberate. Files first, chat text last, because the chat text is what got eaten. The second thing the audit turned up was the only class of information I could not find written down anywhere: questions the assistant had asked me that I had not answered yet, sitting as the last line of a session. The sweep has an explicit line for those now.

Numbers, selection conditions and caveats are in [EVIDENCE.md](EVIDENCE.md). Six compactions on one machine is a small n; it decided a design, not a claim about your setup.

## What it does

1. Writes a one-line `RESUME.md` stub first, before scanning, because the scan itself costs context and you usually run this when context is nearly full.
2. Sweeps the chat for six things: decisions and reversals, verified facts that change the plan, feedback on how to work, project state and next actions, anything you said to remember, and questions it asked you that are still open.
3. Routes each item: cross-session facts to whatever memory system you have (Claude Code's auto memory, a memory MCP, or plain note files), project decisions to the project file they belong in.
4. Overwrites `RESUME.md` with a short block (one block, roughly 1,200 characters, dated) that a session with zero memory of this chat can act on.
5. Only then reports in chat: what it saved, what it left unsaved on purpose, or "nothing new to save, you're safe to compact".

It is not a memory system and it does not run on its own. It also does not replace `/compact`; it is the write step that fresh-session workflows assume and do not provide.

## Check it works before you trust it

Two runs, ninety seconds, one of them has to come back red.

1. Known-bad. Open a fresh session in any project, exchange two trivial turns, run `/save-before-compact`. A correct run answers "nothing new to save" and writes no files. If it manufactures something to save, it will also manufacture receipts, and you should not trust it.
2. Known-good. State a decision in one turn ("actually, go with option B, not A"), then run it. That decision must appear in `RESUME.md`. If it does not, the sweep is not reaching the whole chat.

## What Claude Code already does, and when that is enough

`/compact <instructions>` steers what the summary keeps, and a `# Compact instructions` section in `CLAUDE.md` does the same for automatic compaction. Auto memory saves things Claude decides are worth remembering, and is re-injected after compaction. `/rewind` can summarize from a checkpoint into a handoff message. Anthropic's own advice for a new task is a fresh session with a note about what matters. All of that is real and I use it.

Where it stops: a steered summary is still a summary you do not control, and it is gone the moment you `/clear` or close the terminal. Auto memory is opportunistic, not a sweep, and nothing in it ledgers a question you left unanswered. Files survive all of that. If you only ever compact mid-task and never clear, `/compact focus on X` may be all you need.

## Neighbours

The same moment has a small ecosystem: plugins that have a separate Claude process write a full state file on every compaction and inject it back; skills that write a chained handoff document from a checklist; hooks that capture the whole transcript into a searchable archive; memory servers that answer "where does it go" continuously. This skill is deliberately smaller: a manual, bounded sweep for what is not yet saved, a fixed handoff file, and an explicit "nothing to save" answer. If you already run one of those, the two things worth taking from here are the write-order rule and the open-questions line.

## Limits

One person, one Windows machine, Claude Code 2.1.226, one plan tier. The 5-of-6 figure is six compactions selected for having the skill running when they fired; it is not a compaction loss rate, and no before/after measurement of the reordered skill exists. The open-questions rule rests on one traced case. I have not compared this against a plain "save what matters before I compact" prompt; that would be the most useful thing to add. The hooks are PowerShell 5.1 and untested elsewhere. Not affiliated with Anthropic.

## License

MIT, Martin Lipp ([lippinc](https://github.com/lippinc)). If you run the two checks above on your setup and one of them goes the other way, an issue with what happened is the most useful thing you can send.
