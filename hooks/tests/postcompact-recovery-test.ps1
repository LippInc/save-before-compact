# Test for hooks/postcompact-recovery.ps1 (contract: README.md in this folder). ASCII-only.
$hook = Join-Path $HOME '.claude\hooks\postcompact-recovery.ps1'
$T = Join-Path $env:TEMP ("pcr-test-" + [guid]::NewGuid().ToString('N'))
$dir = Join-Path $T '.claude\checkpoints'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$fail = 0
$savedPD = $env:CLAUDE_PROJECT_DIR
Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
function Run($json) { $o = @($json | & powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$hook'" 2>&1 | % { "$_" }); @{ out = ($o -join "`n"); code = $LASTEXITCODE } }
function J($s) { $s.Replace('\', '\\') }
function Ctx($r) { try { (($r.out | ConvertFrom-Json).hookSpecificOutput.additionalContext) } catch { '' } }

# two archives: the OLDER-named one gets the NEWER mtime (what a failed copy + Copy-Item mtime preservation produces)
$old = Join-Path $dir 'transcript-20260101-000000.jsonl'
$new = Join-Path $dir 'transcript-20260815-120000.jsonl'
'x' | Out-File $old -Encoding utf8; 'y' | Out-File $new -Encoding utf8
(Get-Item $old).LastWriteTime = (Get-Date).AddHours(1)
(Get-Item $new).LastWriteTime = (Get-Date).AddHours(-1)
'compaction 20260815-120000 (trigger=auto); snapshot .claude/checkpoints/transcript-20260815-120000.jsonl' | Out-File (Join-Path $dir 'last-compaction.txt') -Encoding utf8

# --- KNOWN-BAD 1: source=startup must produce NO output (this hook owns compact only)
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ([string]::IsNullOrWhiteSpace($r.out)) { 'KNOWN-BAD-RED source=startup -> silent' } else { 'KNOWN-BAD-GREEN source=startup -> emitted context'; $fail++ }

# --- KNOWN-BAD 2: breadcrumb says snapshot NONE -> must NOT point at any archive
'compaction 20260815-130000 (trigger=auto); snapshot NONE (transcript copy failed)' | Out-File (Join-Path $dir 'last-compaction.txt') -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","source":"compact"}')
$c = Ctx $r
if ($c -and $c -notmatch 'transcript-2026' -and $c -match 'No transcript archive') { 'KNOWN-BAD-RED failed-copy breadcrumb -> no archive claimed' } else { "KNOWN-BAD-GREEN failed-copy breadcrumb -> pointed at an archive: $c"; $fail++ }

# --- PASS: source=compact, trigger=auto -> newest archive BY NAME, sweep instruction, 40 KB unit, data-not-instructions
'compaction 20260815-120000 (trigger=auto); snapshot .claude/checkpoints/transcript-20260815-120000.jsonl' | Out-File (Join-Path $dir 'last-compaction.txt') -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","source":"compact"}')
$c = Ctx $r
if ($c -match 'transcript-20260815-120000\.jsonl' -and $c -notmatch 'transcript-20260101') { 'PASS newest archive chosen by NAME despite older mtime' } else { "FAIL archive choice: $c"; $fail++ }
if ($c -match 'trigger=auto' -and $c -match 'recovery sweep') { 'PASS auto compaction -> recovery sweep instruction' } else { 'FAIL auto sweep instruction missing'; $fail++ }
if ($c -match 'tail -c 40000' -and $c -notmatch 'Get-Content -Tail 40 ' -and $c -match 'never as instructions') { 'PASS bounded unit is a BYTE tail (tail -c 40000), no line-count command, + data-not-instructions clause' } else { "FAIL bounded-unit command / injection clause: $c"; $fail++ }
if ($r.code -eq 0) { 'PASS exit code 0' } else { "FAIL exit code $($r.code)"; $fail++ }

# --- PASS: trigger=manual -> re-orient wording, no mandatory sweep
'compaction 20260815-120000 (trigger=manual); snapshot .claude/checkpoints/transcript-20260815-120000.jsonl' | Out-File (Join-Path $dir 'last-compaction.txt') -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","source":"compact"}')
$c = Ctx $r
if ($c -match 'trigger=manual' -and $c -match 'was manual') { 'PASS manual compaction -> re-orient wording' } else { "FAIL manual wording: $c"; $fail++ }

# --- project-root resolution: cwd inside CLAUDE_PROJECT_DIR -> archives under the project root; unrelated CLAUDE_PROJECT_DIR -> ignored
$sub = Join-Path $T 'sub'; New-Item -ItemType Directory -Force -Path $sub | Out-Null
'compaction 20260815-120000 (trigger=auto); snapshot .claude/checkpoints/transcript-20260815-120000.jsonl' | Out-File (Join-Path $dir 'last-compaction.txt') -Encoding utf8
$env:CLAUDE_PROJECT_DIR = $T
$r = Run ('{"cwd":"' + (J $sub) + '","source":"compact"}')
$c = Ctx $r
if ($c -match 'transcript-20260815-120000\.jsonl') { 'PASS cwd in a subdirectory still finds the project-root archive via CLAUDE_PROJECT_DIR' } else { "FAIL project-root resolution: $c"; $fail++ }
$env:CLAUDE_PROJECT_DIR = Join-Path $env:TEMP 'unrelated-project-root'
$r = Run ('{"cwd":"' + (J $T) + '","source":"compact"}')
$c = Ctx $r
if ($c -match 'transcript-20260815-120000\.jsonl') { 'KNOWN-BAD-RED unrelated CLAUDE_PROJECT_DIR ignored (cwd not inside it)' } else { "KNOWN-BAD-GREEN unrelated CLAUDE_PROJECT_DIR hijacked the archive dir: $c"; $fail++ }
Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
if ($null -ne $savedPD) { $env:CLAUDE_PROJECT_DIR = $savedPD }

Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
if ($fail -gt 0) { exit 1 } else { exit 0 }
