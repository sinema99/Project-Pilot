# Pulls a re-exported pilot9.glb from Blender into the project and rebuilds his scene.
#
#   powershell -File tools/sync_pilot9.ps1              # copy, import, swap rig, test
#   powershell -File tools/sync_pilot9.ps1 -Play        # ...then launch scenes/trial.tscn
#   powershell -File tools/sync_pilot9.ps1 -Fresh       # rebuild pilot9.tscn from RC stock
#   powershell -File tools/sync_pilot9.ps1 -Source path\to\other.glb
#   powershell -File tools/sync_pilot9.ps1 -Raw         # don't filter Godot's exit noise
#
# The step people forget is the rebuild: scenes/pilot9.tscn holds an INLINED copy of the
# mesh and skin, so a reimport on its own leaves the old rig in the scene and the export
# looks like it failed. This script always does both.
#
# Set $env:GODOT to override the engine path. See docs/reimport.md.

param(
    [string]$Source = (Join-Path $env:USERPROFILE "Documents\pilot9.glb"),
    [switch]$Fresh,
    [switch]$Play,
    [switch]$SkipTests,
    [switch]$Raw
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "assets\pilot9.glb"
$importFile = "$dest.import"

$godot = $env:GODOT
if (-not $godot) {
    $godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at '$godot'. Set `$env:GODOT to the console binary."
    exit 2
}
if (-not (Test-Path $Source)) {
    Write-Error "No export at '$Source'. Export from Blender first, or pass -Source."
    exit 2
}
# The .import file carries the uid AND the BoneMap. Losing it drops the retarget with no
# error: the skeleton stays Skeleton3D, bones stay mixamorig_*, every RC clip plays on
# nothing. Only ever delete .godot/imported/ - never this.
if (-not (Test-Path $importFile)) {
    Write-Error "assets/pilot9.glb.import is missing - the BoneMap went with it. Restore it from git before importing (see docs/reimport.md)."
    exit 2
}

# Godot's headless shutdown leaks RIDs and says so at length, and --import narrates its
# progress bar. None of it survives a successful run as information, and 60 lines of
# ERROR after a clean build reads like a failure. Hidden unless -Raw.
$noise = @(
    '^\[\s*\d+%\s*\]',
    '^\[ DONE \]',
    '^ERROR: \d+ RID allocations of type',
    '^ERROR: \d+ resources still in use at exit',
    '^ERROR: Pages in use exist at exit in PagedAllocator',
    '^WARNING: Leaked instance dependency',
    '^WARNING: ObjectDB instances leaked at exit',
    '^WARNING: \d+ RIDs of type .+ were leaked',
    '^\s+at: (~Dependency|cleanup|clear|_free_rids|~PagedAllocator)'
) -join '|'

$script:hidden = 0

function Invoke-GodotCaptured {
    param([string[]]$GodotArgs)
    # PowerShell 5.1 wraps a native command's stderr in ErrorRecords, which would be
    # terminating under $ErrorActionPreference = "Stop". Relax it just for the capture.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        return @(& $godot @GodotArgs 2>&1 | ForEach-Object { $_.ToString() })
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Show-GodotOutput {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        $clean = $line -replace "$([char]27)\[[0-9;]*m", ""
        if (-not $Raw) {
            if ($clean -match $noise) { $script:hidden++; continue }
            # a line that was only colour codes
            if ($line -and -not $clean.Trim()) { $script:hidden++; continue }
        }
        Write-Host $clean
    }
}

function Invoke-Godot {
    param([string]$Label, [string[]]$GodotArgs)
    Write-Host ""
    Write-Host "== $Label" -ForegroundColor Cyan
    $out = Invoke-GodotCaptured $GodotArgs
    $code = $LASTEXITCODE
    Show-GodotOutput $out
    if ($code -ne 0) {
        Write-Error "$Label failed (exit $code)"
        exit $code
    }
}

Write-Host "== copy  $Source -> assets/pilot9.glb" -ForegroundColor Cyan
Copy-Item -Path $Source -Destination $dest -Force
Write-Host ("   {0:N0} bytes, exported {1}" -f (Get-Item $dest).Length, (Get-Item $Source).LastWriteTime)

# Godot keys the imported scene by a content hash, so a stale cache is silently reused.
Write-Host ""
Write-Host "== clear import cache" -ForegroundColor Cyan
Get-ChildItem -Path (Join-Path $root ".godot\imported") -Filter "pilot9.glb-*" -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "   rm $($_.Name)"; Remove-Item $_.FullName -Force }
Get-ChildItem -Path (Join-Path $root ".godot\editor") -Filter "pilot9.glb-folding-*" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force }

Invoke-Godot "import" @("--headless", "--path", $root, "--import")

$buildArgs = @("--headless", "--path", $root, "--script", "scripts/pilot9_build_scene.gd")
if ($Fresh) { $buildArgs += @("--", "--fresh") }
Invoke-Godot $(if ($Fresh) { "rebuild pilot9.tscn (fresh)" } else { "swap rig into pilot9.tscn" }) $buildArgs

# Informational only. pilot9 is smooth-weighted by design (Setsuna's single-bone rule is
# hers, settled 2026-09-06); this is here to catch a weighting change you did not intend.
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    Write-Host ""
    Write-Host "== skin weights" -ForegroundColor Cyan
    & $python.Source (Join-Path $root "tools\check_weights.py") $dest --brief
} else {
    Write-Host ""
    Write-Host "(python not on PATH - skipping the weight report)" -ForegroundColor DarkGray
}

if (-not $SkipTests) {
    Write-Host ""
    Write-Host "== tests" -ForegroundColor Cyan
    # run_tests.gd quit()s 0 on pass and 1 on fail, but Godot segfaults during headless
    # shutdown (leaked Canvas RIDs) and overwrites the code with 0xC0000005. The printed
    # summary line is the only trustworthy verdict.
    $out = Invoke-GodotCaptured @("--headless", "--path", $root, "--script", "tests/run_tests.gd")
    $summary = $out | Select-String -Pattern '^(PASS|FAIL)\s' | Select-Object -Last 1
    if (-not $summary) {
        Show-GodotOutput $out
        Write-Error "the suite printed no PASS/FAIL line - it did not finish"
        exit 1
    }
    if ($summary.Line -like "FAIL*") {
        Show-GodotOutput $out
        Write-Error "tests failed"
        exit 1
    }
    Write-Host "   $($summary.Line)" -ForegroundColor Green
}

if ($script:hidden -gt 0) {
    Write-Host ""
    Write-Host "($script:hidden lines of Godot progress and shutdown-leak noise hidden; -Raw shows them)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "pilot9 is in sync." -ForegroundColor Green

if ($Play) {
    Write-Host ""
    Write-Host "== play scenes/trial.tscn" -ForegroundColor Cyan
    & $godot "--path" $root "scenes/trial.tscn"
    exit $LASTEXITCODE
}
