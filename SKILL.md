---
name: save-before-compact
description: 'Sweep the current conversation for anything important that is not yet saved to a file, save it, write a short RESUME.md handoff for the next session, and only then report, right before the conversation is compacted or cleared. Use when the user says they are about to compact or clear this chat, that context is nearly full, "save anything important before I compact", "get this chat ready to compact", when a hook or the user asks for a checkpoint of the session, or invokes /save-before-compact. Do not use for an ordinary request to summarize the conversation; that needs no files written.'
argument-hint: '[optional: a topic to focus the sweep on; blank = whole chat]'
license: MIT
---

# Save what the compaction is about to eat

Compaction keeps a summary of this conversation and drops detail. The things most likely to vanish are the ones decided or learned **after the main deliverable was written up**: the "oh, and afterwards we decided Y / found out Z" riders that live only in this chat and read as throwaway. This skill is a fast sweep for those. It is a bounded pass, not a research task.

You cannot compact, and you should not clear at a warm boundary either: continuing a session whose prompt cache is still warm costs very little and keeps the nuance, so you are getting the chat ready for whatever the user does next. Clearing is the pickup-time decision. A long session picked up after its prompt cache has expired re-processes its whole context on the first message, and starting fresh (`/clear`, or a new session if the user wants the old chat to stay visible) with a current RESUME.md is the cheap path then. If your environment gives you a tool that clears the session, use it only when the user explicitly asks you to wrap up. If the user only asked for a summary of the conversation, give them one and write nothing.

**Checkpoint mode.** When a hook or the user asks for a checkpoint mid-session (the session has grown since its last save, and RESUME.md should be made current while the cache is still warm), run the sweep below exactly as usual, with the scope always "since the last save point" (the previous RESUME.md write), never the whole chat, then stop.

**Order is load-bearing: files first, chat text last.** In an audit of my own transcripts, 5 of 6 compactions that fired while this skill was running cut it off before its closing chat text (the receipt and the resume block) was emitted; the file writes had already landed every time (n=6, one machine; EVIDENCE.md in the repo this skill came from). Files on disk are outside the context window. Chat text is not. So everything durable goes to disk before you say anything.

## Step 0 - write the stub before you scan

The scan itself costs context, and you are usually invoked when context is nearly full. So first:

1. The project root is `${CLAUDE_PROJECT_DIR}` (Claude Code fills that in when this skill loads; if it came through blank, use the git root, otherwise the working directory).
2. If `RESUME.md` already exists there and its first line does not start with `RESUME`, it is not ours (the name is also a common CV file). Leave it alone and use `.claude/RESUME.md` for everything below; say so in the receipt.
3. Write a one-line stub: `RESUME - <goal in a few words> - sweep in progress <date>`.

Then scan.

## Step 1 - sweep for load-bearing things that are not saved yet

Scan the chat (from the start, or from the last save point if there was one; a checkpoint run always starts from the last save point; if the user named a focus area, narrow to it: $ARGUMENTS) for:

- **Decisions and reversals**: "actually, go with X", a changed scope, a pick between options, a kill/keep call, a chosen next step. Post-deliverable ones are the most likely to be lost.
- **Verified facts that change the plan**: a confirmed price, deadline, constraint, or a "checked it, it's actually Z" a future session would otherwise re-derive or get wrong.
- **Feedback on how to work**: a correction the user gave, or an approach they confirmed, worth reusing next time. Capture the *why*, not just the rule.
- **Project state and next actions**: what is now done, which check or milestone passed, what the user will want teed up when they come back.
- **Anything the user explicitly said to remember.**
- **Questions you asked that are still unanswered**: an option you offered or a decision you asked for that the user has not answered. Record it as an explicit OPEN item (one line: what is pending, what unblocks it) so the thread survives instead of silently dropping. In the audit this was the one class found written down nowhere (n=1).

Deliberately skip what is already safe: it is in the repo, in a deliverable file, in a notes or memory file, or it only mattered to this turn. The goal is to close the gap between what this chat knows and what survives it, not to re-log the session. Do not duplicate, do not pad. Keep the sweep to roughly ten tool calls; if you are still finding things past that, save what you have and say the sweep was partial.

## Step 2 - route each item to the right home

- **Cross-session context, facts, feedback** go to memory:
  - if this setup has a memory system (for example Claude Code's auto memory under `~/.claude/projects/<project>/memory/`, or a memory MCP), use its conventions: update an existing entry that already covers the topic rather than adding a duplicate, and keep one topic per entry;
  - if it has none, write one short note file per topic in the project's existing notes or docs location, and update in place next time.
- **A durable project decision or artifact** goes to the relevant project file (a plan, a DECISIONS or state file, the active game plan), not to memory. If the decision contradicts what a file currently says, fix the file so the two do not disagree.

When it is unclear which home fits, prefer the smallest durable note a future session would actually find and trust.

## Step 3 - save, write RESUME.md, then give the receipt

1. Write the memory and project files from Step 2.
2. Overwrite the stub in `RESUME.md` (or `.claude/RESUME.md`, Step 0) with the resume block from Step 4. One block only, at most about 1,200 characters, the date on the first line. Delete any previous block rather than appending below it; history belongs in the project file, not here. If the work is genuinely finished and closed, make the first line `RESUME - CLOSED <date>: <one line>` (or delete the file) so the next session is not told to pick up a closed thread.
3. Only then report briefly in chat:
   - **Saved:** each item, one line, with a link to the file it went into.
   - **Left unsaved on purpose:** one line (already durable / ephemeral), so the user can see you looked and made a call.

If nothing needed saving, say so plainly: "nothing new to save, you're safe to compact" is a valid and expected outcome. Never invent something to save in order to look useful; a clean sweep is a real result. If nothing needed saving, remove the stub you wrote in Step 0 (or leave the previous RESUME.md untouched).

## Step 4 - the resume block

After compaction the next session starts from a lossy summary and does not know the files exist or where to pick up. The block is the handoff that points it at the state and the next move. Write it for a reader with zero memory of this chat who can open any file you name, so name files by path. It is a pointer, not a re-summary of what you just saved.

```
RESUME - <the task or goal in one line> - <date>
State: <where it stands right now: done, or in progress on what>
Read first:
- <path> - <what it holds / why it matters>
- <path> - <...>
Key context: <1-3 load-bearing facts or decisions a summary would blur>
Open: <questions you asked that are still unanswered, if any>
Next: <the immediate next action on resume, or "nothing pending, this thread is closed">
```

Only include the lines that apply. Echo the block in chat as the last thing in your response, in its own fenced code block, so the user can copy it; the durable copy is the file, and the chat copy is allowed to die.

## How the next session finds RESUME.md

Writing the file is the durable half. The other half is making sure it gets read. The portable way is one line in the project's `CLAUDE.md`, which Claude Code loads at every session start and re-injects after compaction:

```
If RESUME.md (or .claude/RESUME.md) exists in the project root, and its first line starts with RESUME and does not say CLOSED, read it first.
```

The repo this skill came from also ships optional hooks that surface RESUME.md automatically and archive the transcript before each compaction; they are an upgrade, not a requirement.
