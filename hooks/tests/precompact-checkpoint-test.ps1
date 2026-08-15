# Test for hooks/precompact-checkpoint.ps1 (contract: README.md in this folder). ASCII-only.
$hook = Join-Path $HOME '.claude\hooks\precompact-checkpoint.ps1'
$T = Join-Path $env:TEMP ("pcc-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $T | Out-Null
$fail = 0
$savedPD = $env:CLAUDE_PROJECT_DIR
Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
function Run($json) { $o = @($json | & powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$hook'" 2>&1 | % { "$_" }); @{ out = $o; code = $LASTEXITCODE } }
function J($s) { $s.Replace('\', '\\') }
$dir = Join-Path $T '.claude\checkpoints'

# --- KNOWN-BAD 1: transcript_path points at a file that does not exist -> no snapshot may be claimed
$r = Run ('{"cwd":"' + (J $T) + '","transcript_path":"' + (J (Join-Path $T 'nope.jsonl')) + '","trigger":"auto"}')
$bc = if (Test-Path (Join-Path $dir 'last-compaction.txt')) { Get-Content (Join-Path $dir 'last-compaction.txt') -TotalCount 1 } else { '' }
$snaps = @(Get-ChildItem $dir -Filter 'transcript-*.jsonl' -ErrorAction SilentlyContinue)
if ($bc -match 'snapshot NONE' -and $snaps.Count -eq 0) { 'KNOWN-BAD-RED missing transcript -> breadcrumb says snapshot NONE, no archive claimed' } else { 'KNOWN-BAD-GREEN missing transcript -> breadcrumb claimed a snapshot or a file appeared'; $fail++ }

# --- PASS: valid transcript -> archive + breadcrumb + '*' .gitignore
$tp = Join-Path $T 'transcript.jsonl'
'{"type":"user","message":"hello"}' | Out-File $tp -Encoding utf8
$r = Run ('{"cwd":"' + (J $T) + '","transcript_path":"' + (J $tp) + '","trigger":"manual"}')
$snaps = @(Get-ChildItem $dir -Filter 'transcript-*.jsonl')
$bc = Get-Content (Join-Path $dir 'last-compaction.txt') -TotalCount 1
if ($snaps.Count -eq 1 -and $bc -match 'trigger=manual' -and $bc -match ('snapshot .claude/checkpoints/' + $snaps[0].Name)) { 'PASS valid transcript archived and breadcrumb names it' } else { "FAIL valid transcript: snaps=$($snaps.Count) bc=$bc"; $fail++ }
$gi = Join-Path $dir '.gitignore'
if ((Test-Path $gi) -and ((Get-Content $gi -Raw).Trim() -eq '*')) { 'PASS checkpoint dir carries a * .gitignore' } else { 'FAIL .gitignore missing or wrong'; $fail++ }
if ($r.code -eq 0) { 'PASS exit code 0' } else { "FAIL exit code $($r.code)"; $fail++ }

# --- KNOWN-BAD 2: prune must go by NAME, not mtime. Plant 6 old-named archives, give the OLDEST-named one the NEWEST mtime.
1..6 | % { $p = Join-Path $dir ("transcript-20200101-00000$_.jsonl"); 'x' | Out-File $p -Encoding utf8 }
(Get-Item (Join-Path $dir 'transcript-20200101-000001.jsonl')).LastWriteTime = (Get-Date).AddHours(1)
$before = @(Get-ChildItem $dir -Filter 'transcript-*.jsonl' | % { $_.Name })
Start-Sleep -Milliseconds 1100   # the stamp is seconds-resolution; make sure this run gets its own file name
$r = Run ('{"cwd":"' + (J $T) + '","transcript_path":"' + (J $tp) + '","trigger":"auto"}')
$names = @(Get-ChildItem $dir -Filter 'transcript-*.jsonl' | Sort-Object Name | % { $_.Name })
$gone1 = -not (Test-Path (Join-Path $dir 'transcript-20200101-000001.jsonl'))
if ($gone1) { 'KNOWN-BAD-RED old-named archive with the newest mtime was pruned (name is the sort key)' } else { 'KNOWN-BAD-GREEN old-named archive with newest mtime survived the prune (mtime sort key?)'; $fail++ }
if ($names.Count -eq 5) { 'PASS prune keeps exactly 5 archives' } else { "FAIL prune kept $($names.Count): $($names -join ',')"; $fail++ }
# expected survivors = newest 5 BY NAME of (what existed before + whatever this run created); computed, not hard-coded
$created = @(Get-ChildItem $dir -Filter 'transcript-*.jsonl' | % { $_.Name } | ? { $before -notcontains $_ })
$universe = @($before + $created | Sort-Object -Unique)
$expected = @($universe | Sort-Object -Descending | Select-Object -First 5 | Sort-Object)
if (($names -join ',') -eq ($expected -join ',')) { 'PASS the surviving set is the newest 5 by name' } else { "FAIL survivors=$($names -join ',') expected=$($expected -join ',')"; $fail++ }

# --- PASS: CLAUDE_CHECKPOINT_KEEP env override
$env:CLAUDE_CHECKPOINT_KEEP = '2'
$r = Run ('{"cwd":"' + (J $T) + '","transcript_path":"' + (J $tp) + '","trigger":"auto"}')
Remove-Item Env:\CLAUDE_CHECKPOINT_KEEP -ErrorAction SilentlyContinue
$n = @(Get-ChildItem $dir -Filter 'transcript-*.jsonl').Count
if ($n -eq 2) { 'PASS CLAUDE_CHECKPOINT_KEEP=2 honored' } else { "FAIL keep override: $n archives remain"; $fail++ }

# --- project-root resolution: cwd inside CLAUDE_PROJECT_DIR -> archive at the project root, not in the subdirectory
$T2 = Join-Path $env:TEMP ("pcc-root-" + [guid]::NewGuid().ToString('N')); $sub2 = Join-Path $T2 'src\deep'; New-Item -ItemType Directory -Force -Path $sub2 | Out-Null
$env:CLAUDE_PROJECT_DIR = $T2
$r = Run ('{"cwd":"' + (J $sub2) + '","transcript_path":"' + (J $tp) + '","trigger":"auto"}')
$atRoot = @(Get-ChildItem (Join-Path $T2 '.claude\checkpoints') -Filter 'transcript-*.jsonl' -ErrorAction SilentlyContinue).Count
$atSub = Test-Path (Join-Path $sub2 '.claude\checkpoints')
if ($atRoot -eq 1 -and -not $atSub) { 'PASS subdirectory session archives at the project root (CLAUDE_PROJECT_DIR)' } else { "FAIL project-root archive: atRoot=$atRoot atSub=$atSub"; $fail++ }
$env:CLAUDE_PROJECT_DIR = Join-Path $env:TEMP 'unrelated-project-root-pcc'
$T3 = Join-Path $env:TEMP ("pcc-unrel-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $T3 | Out-Null
$r = Run ('{"cwd":"' + (J $T3) + '","transcript_path":"' + (J $tp) + '","trigger":"auto"}')
$inCwd = @(Get-ChildItem (Join-Path $T3 '.claude\checkpoints') -Filter 'transcript-*.jsonl' -ErrorAction SilentlyContinue).Count
$inUnrel = Test-Path (Join-Path $env:CLAUDE_PROJECT_DIR '.claude\checkpoints')
if ($inCwd -eq 1 -and -not $inUnrel) { 'KNOWN-BAD-RED unrelated CLAUDE_PROJECT_DIR ignored, archive stayed in cwd' } else { "KNOWN-BAD-GREEN unrelated CLAUDE_PROJECT_DIR hijacked the archive: inCwd=$inCwd inUnrel=$inUnrel"; $fail++ }
Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
if ($null -ne $savedPD) { $env:CLAUDE_PROJECT_DIR = $savedPD }
Remove-Item -Recurse -Force $T2, $T3 -ErrorAction SilentlyContinue

Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
if ($fail -gt 0) { exit 1 } else { exit 0 }
