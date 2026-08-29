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

& $godot @godotArgs
exit $LASTEXITCODE
