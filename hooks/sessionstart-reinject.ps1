# SessionStart hook - surfaces the RESUME.md handoff file (written by the save-before-compact skill) so a fresh or resumed
# session picks up where the last one left off without re-carrying the old chat.
# rev 2026-08-15: fires only for source=startup|resume (register it with "matcher": "startup|resume" too - the guard
# here is belt-and-braces); resolves the project root via CLAUDE_PROJECT_DIR when set; ignores a RESUME.md whose
# first line marks the thread CLOSED; reports the file's age so a stale handoff is read as history, not as the
# current state; ignores a foreign RESUME.md (first line not RESUME, e.g. a CV) and falls back to .claude/RESUME.md, the
# skill's own fallback; the 15-minute post-compaction breadcrumb is gone (postcompact-recovery.ps1 owns source=compact).
# ASCII-only on purpose: PS 5.1 mangles non-ASCII in a no-BOM .ps1 into parse errors.
$ErrorActionPreference = 'SilentlyContinue'
try { $in = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { exit 0 }
if ($in.source -and ($in.source -ne 'startup') -and ($in.source -ne 'resume')) { exit 0 }
$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } elseif ($in.cwd) { $in.cwd } else { (Get-Location).Path }
# ours = first line starts with RESUME (the skill's stub/block/CLOSED forms). A RESUME.md that does not is a foreign file
# (the name is a common CV file) - the skill then writes .claude/RESUME.md instead, so look there second.
$resume = $null; $label = ''
foreach ($cand in @(@{ p = (Join-Path $root 'RESUME.md'); l = 'RESUME.md' }, @{ p = (Join-Path $root '.claude\RESUME.md'); l = '.claude/RESUME.md' })) {
  if (Test-Path $cand.p) {
    $first = Get-Content $cand.p -TotalCount 1
    if ($first -match '^\s*#?\s*RESUME') { $resume = $cand.p; $label = $cand.l; break }
  }
}
if (-not $resume) { exit 0 }
if ($first -match 'CLOSED') { exit 0 }
$ageDays = [int]((Get-Date) - (Get-Item $resume).LastWriteTime).TotalDays
$stale = if ($ageDays -ge 7) { " NOTE: it is $ageDays days old - treat it as history, verify state fresh before acting on it." } else { '' }
Write-Output "[handoff] $label is present in this project - read it FIRST to continue where you left off (cheap continuity: load the file, do not re-carry the old chat).$stale"
exit 0
