# Test for hooks/sessionstart-reinject.ps1 (contract: README.md in this folder). ASCII-only.
$hook = Join-Path $HOME '.claude\hooks\sessionstart-reinject.ps1'
$T = Join-Path $env:TEMP ("ssr-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $T | Out-Null
$fail = 0
$savedPD = $env:CLAUDE_PROJECT_DIR
function Run($json) { $o = @($json | & powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$hook'" 2>&1 | % { "$_" }); @{ out = ($o -join "`n"); code = $LASTEXITCODE } }
function J($s) { $s.Replace('\', '\\') }
Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue

# --- KNOWN-BAD 1: no RESUME.md -> silent
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ([string]::IsNullOrWhiteSpace($r.out)) { 'KNOWN-BAD-RED no RESUME.md -> silent' } else { 'KNOWN-BAD-GREEN no RESUME.md -> emitted something'; $fail++ }

# plant a RESUME.md
"RESUME - test track`nState: x`nNext: y" | Out-File (Join-Path $T 'RESUME.md') -Encoding utf8

# --- KNOWN-BAD 2: source=compact -> silent (owned by postcompact-recovery); source=clear -> silent (user wanted a clean slate)
$r = Run ('{"cwd":"' + (J $T) + '","source":"compact"}')
if ([string]::IsNullOrWhiteSpace($r.out)) { 'KNOWN-BAD-RED source=compact -> silent' } else { 'KNOWN-BAD-GREEN source=compact -> re-injected'; $fail++ }
$r = Run ('{"cwd":"' + (J $T) + '","source":"clear"}')
if ([string]::IsNullOrWhiteSpace($r.out)) { 'KNOWN-BAD-RED source=clear -> silent' } else { 'KNOWN-BAD-GREEN source=clear -> re-injected'; $fail++ }

# --- PASS: startup + resume surface the handoff line
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ($r.out -match '\[handoff\] RESUME\.md is present') { 'PASS source=startup surfaces RESUME.md' } else { "FAIL startup: $($r.out)"; $fail++ }
$r = Run ('{"cwd":"' + (J $T) + '","source":"resume"}')
if ($r.out -match '\[handoff\]') { 'PASS source=resume surfaces RESUME.md' } else { "FAIL resume: $($r.out)"; $fail++ }
if ($r.out -notmatch 'days old') { 'PASS fresh file carries no staleness note' } else { 'FAIL fresh file flagged stale'; $fail++ }

# --- PASS: staleness note when the file is old
(Get-Item (Join-Path $T 'RESUME.md')).LastWriteTime = (Get-Date).AddDays(-10)
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ($r.out -match '10 days old') { 'PASS 10-day-old RESUME.md carries a staleness note' } else { "FAIL staleness note: $($r.out)"; $fail++ }

# --- KNOWN-BAD 3: first line marks the thread CLOSED -> silent
"RESUME - CLOSED, nothing pending`nState: done" | Out-File (Join-Path $T 'RESUME.md') -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ([string]::IsNullOrWhiteSpace($r.out)) { 'KNOWN-BAD-RED CLOSED thread -> silent' } else { 'KNOWN-BAD-GREEN CLOSED thread -> still surfaced'; $fail++ }

# --- PASS: CLAUDE_PROJECT_DIR wins over cwd (session started in a subdirectory)
"RESUME - live track" | Out-File (Join-Path $T 'RESUME.md') -Encoding utf8
$sub = Join-Path $T 'sub'; New-Item -ItemType Directory -Force -Path $sub | Out-Null
$env:CLAUDE_PROJECT_DIR = $T
$r = Run ('{"cwd":"' + (J $sub) + '","source":"startup"}')
if ($r.out -match '\[handoff\]') { 'PASS CLAUDE_PROJECT_DIR resolves the project root from a subdirectory' } else { "FAIL project-root resolution: $($r.out)"; $fail++ }
Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
if ($null -ne $savedPD) { $env:CLAUDE_PROJECT_DIR = $savedPD }

# --- KNOWN-BAD 4: a FOREIGN RESUME.md (a CV: first line not RESUME) must NOT be surfaced; the skill's .claude/RESUME.md fallback must be
"Jane Doe`nSenior Engineer, 12 years" | Out-File (Join-Path $T 'RESUME.md') -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ([string]::IsNullOrWhiteSpace($r.out)) { 'KNOWN-BAD-RED foreign RESUME.md (CV) -> silent' } else { "KNOWN-BAD-GREEN foreign RESUME.md surfaced as a handoff: $($r.out)"; $fail++ }
New-Item -ItemType Directory -Force -Path (Join-Path $T '.claude') | Out-Null
"RESUME - fallback track" | Out-File (Join-Path $T '.claude\RESUME.md') -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","source":"startup"}')
if ($r.out -match '\[handoff\] \.claude/RESUME\.md is present') { 'PASS with a foreign RESUME.md at root, the .claude/RESUME.md fallback is surfaced instead' } else { "FAIL fallback: $($r.out)"; $fail++ }

Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
if ($fail -gt 0) { exit 1 } else { exit 0 }
