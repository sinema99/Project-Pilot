# Runs the headless test suite for the Moebius rendering pipeline.
#   powershell -File tests/run.ps1            # all tests
#   powershell -File tests/run.ps1 outline    # only tests matching "outline"
#
# Set $env:GODOT to override the engine path.
param([string]$Filter = "")

$godot = $env:GODOT
if (-not $godot) {
    $godot = Join-Path $env:USERPROFILE "Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at '$godot'. Set `$env:GODOT to the console binary."
    exit 2
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$godotArgs = @("--headless", "--path", $projectRoot, "--script", "tests/run_tests.gd")
if ($Filter) { $godotArgs += @("--", $Filter) }

# run_tests.gd quit()s 0 on pass and 1 on fail, but Godot segfaults during headless
# shutdown (leaked Canvas RIDs) and overwrites the code with 0xC0000005 - so $LASTEXITCODE
# reported failure on a green suite. The printed summary line is the only trustworthy
# verdict. PowerShell 5.1 wraps a native command's stderr in ErrorRecords, hence ToString().
$output = @(& $godot @godotArgs 2>&1 | ForEach-Object { $_.ToString() })
$output | ForEach-Object { Write-Host $_ }

$summary = $output | Select-String -Pattern '^(PASS|FAIL)\s' | Select-Object -Last 1
if (-not $summary) {
    Write-Error "the suite printed no PASS/FAIL line - it did not finish"
    exit 1
}
if ($summary.Line -like "FAIL*") { exit 1 }
exit 0
