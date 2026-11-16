# Runs Godot WINDOWED (real renderer: probe screenshots, the hub2 dressing bake) without a window ever
# showing or taking focus: the game window is parented (--wid) to a host form that is never shown.
#   powershell -ExecutionPolicy Bypass -File tools/godot_bg.ps1 <godot args>
# Use ++ (not --) before the script's user args: PowerShell eats a bare --. Godot treats ++ the same.
#   powershell -ExecutionPolicy Bypass -File tools/godot_bg.ps1 --script tests/_probe_hub2_wear_shot.gd ++ out 0 1 2 3 4 5
# Env: GODOT_BG_RES (default 1920x1080), GODOT_BG_TIMEOUT seconds (default 900).
# stdout/stderr of Godot are echoed after it exits; the exit code is Godot's.
$GodotArgs = $args
$Resolution = if ($env:GODOT_BG_RES) { $env:GODOT_BG_RES } else { "1920x1080" }
$TimeoutSec = if ($env:GODOT_BG_TIMEOUT) { [int]$env:GODOT_BG_TIMEOUT } else { 900 }
Add-Type -AssemblyName System.Windows.Forms
$exe = "C:\Users\panac\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
$project = Split-Path -Parent $PSScriptRoot
$wh = $Resolution.Split("x")
$host_form = New-Object System.Windows.Forms.Form
$host_form.ShowInTaskbar = $false
$host_form.Size = New-Object System.Drawing.Size([int]$wh[0], [int]$wh[1])
$hwnd = $host_form.Handle.ToInt64()
$log = [System.IO.Path]::GetTempFileName()
$err = [System.IO.Path]::GetTempFileName()
$quoted = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " "
$argline = "--path `"$project`" --wid $hwnd --resolution $Resolution $quoted"
$p = Start-Process -FilePath $exe -ArgumentList $argline -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
$ticks = 0
while (-not $p.HasExited -and $ticks -lt $TimeoutSec * 10) {
	[System.Windows.Forms.Application]::DoEvents()
	Start-Sleep -Milliseconds 100
	$ticks++
}
if (-not $p.HasExited) {
	Write-Output "godot_bg: timed out after $TimeoutSec s, killing"
	$p.Kill()
}
$host_form.Dispose()
Get-Content $log
Get-Content $err
Remove-Item $log, $err -ErrorAction SilentlyContinue
exit $p.ExitCode
