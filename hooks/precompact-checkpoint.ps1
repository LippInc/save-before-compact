# PreCompact hook - snapshots the full transcript to disk BEFORE Claude Code compacts, so the lossy summary is
# never the only copy. rev 2026-08-15: keeps only the newest N snapshots (default 5), drops a '*' .gitignore into
# the checkpoint dir so transcripts (which contain everything pasted into the chat) never get committed, and only
# writes the breadcrumb when the copy actually succeeded (a silent failed copy used to leave a breadcrumb that
# pointed the recovery hook at an OLDER session's archive); checkpoint dir resolved under CLAUDE_PROJECT_DIR when
# the cwd is inside it, so a session started in a subdirectory still archives at the project root.
# ASCII-only on purpose: PS 5.1 mangles non-ASCII in a no-BOM .ps1 into parse errors.
$ErrorActionPreference = 'SilentlyContinue'
try { $in = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { exit 0 }
$cwd = if ($in.cwd) { $in.cwd } else { (Get-Location).Path }
# project root = CLAUDE_PROJECT_DIR when the session cwd sits inside it (session started in a subdirectory); else the cwd
$root = if ($env:CLAUDE_PROJECT_DIR -and $cwd.StartsWith($env:CLAUDE_PROJECT_DIR, [StringComparison]::OrdinalIgnoreCase)) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$dir = Join-Path $root '.claude\checkpoints'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# never commit transcripts: a '*' .gitignore inside the checkpoint dir protects even repos that commit .claude/
$gi = Join-Path $dir '.gitignore'
if (-not (Test-Path $gi)) { [System.IO.File]::WriteAllText($gi, "*`n") }

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$tp = $in.transcript_path
$dest = Join-Path $dir "transcript-$stamp.jsonl"
$ok = $false
if ($tp -and (Test-Path $tp)) {
  Copy-Item $tp $dest -Force
  if (Test-Path $dest) { $ok = $true }
}

# keep only the newest N snapshots (by NAME: yyyyMMdd-HHmmss sorts correctly; LastWriteTime does not, because
# Copy-Item preserves the SOURCE file's mtime)
$keep = 5
if ($env:CLAUDE_CHECKPOINT_KEEP -match '^\d+$') { $keep = [int]$env:CLAUDE_CHECKPOINT_KEEP }
if ($keep -lt 1) { $keep = 1 }
Get-ChildItem $dir -Filter 'transcript-*.jsonl' | Sort-Object Name -Descending | Select-Object -Skip $keep | Remove-Item -Force

# breadcrumb for the SessionStart(compact) recovery hook: snapshot=<file> only when the copy really landed
$snap = if ($ok) { "snapshot .claude/checkpoints/transcript-$stamp.jsonl" } else { 'snapshot NONE (transcript copy failed)' }
"compaction $stamp (trigger=$($in.trigger)); $snap" | Out-File (Join-Path $dir 'last-compaction.txt') -Encoding utf8
exit 0
