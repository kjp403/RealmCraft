# Restarts the three local Arkenelle servers in separate windows.
# Run from the repo root (or double-click Restart-LocalServers.bat).

param(
    # Full path to Godot if `godot` is not on PATH, e.g.:
    #   -GodotExe "C:\Godot\Godot_v4.7.1-stable_win64.exe"
    [string]$GodotExe = "godot"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

function Resolve-Godot {
    param([string]$Candidate)
    if (Test-Path $Candidate) { return (Resolve-Path $Candidate).Path }
    $cmd = Get-Command $Candidate -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$godot = Resolve-Godot $GodotExe
if (-not $godot) {
    Write-Host ""
    Write-Host "Could not find Godot." -ForegroundColor Red
    Write-Host "Install Godot 4.7, add it to PATH as 'godot', or run:"
    Write-Host '  .\Restart-LocalServers.ps1 -GodotExe "C:\path\to\Godot_v4.7.1-stable_win64.exe"'
    Write-Host ""
    Write-Host "See docs\LOCAL_SERVERS_WINDOWS.md"
    exit 1
}

if (-not (Test-Path (Join-Path $RepoRoot "project.godot"))) {
    Write-Host "project.godot not found. Run this from the RealmCraft folder." -ForegroundColor Red
    exit 1
}

$classCache = Join-Path $RepoRoot ".godot\global_script_class_cache.cfg"
if (-not (Test-Path $classCache)) {
    Write-Host ""
    Write-Host "Godot has not finished importing this project yet." -ForegroundColor Red
    Write-Host "Local servers will spam fake 'GameMode not declared' errors without this step."
    Write-Host ""
    Write-Host "Do this ONCE:"
    Write-Host "  1) Open Godot 4.7"
    Write-Host "  2) Open C:\Users\$env:USERNAME\Documents\RealmCraft\project.godot"
    Write-Host "  3) Wait until the bottom status bar is idle (no 'Scanning' / 'Importing')"
    Write-Host "  4) In Godot menu: Project -> Reload Current Project"
    Write-Host "  5) Wait again until idle"
    Write-Host "  6) Confirm this file exists:"
    Write-Host "       $classCache"
    Write-Host "  7) Then run this restart script again"
    Write-Host ""
    Write-Host "Or just play live: https://play.arkenelle.com  (no local servers needed)"
    exit 1
}

Write-Host "Repo:   $RepoRoot"
Write-Host "Godot:  $godot"
Write-Host "Cache:  OK ($classCache)"
Write-Host "Stopping old local Godot servers (if any)..."

# Stop previous headless server windows started for this project (best-effort).
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match 'Godot|godot' -and
        $_.CommandLine -and
        $_.CommandLine -match '--headless' -and
        $_.CommandLine -match 'master-server|gateway-server|world-server'
    } |
    ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }

Start-Sleep -Seconds 1

function Start-ServerWindow {
    param([string]$Title, [string]$Mode, [string]$WaitPort = "")
    $waitBit = ""
    if ($WaitPort) {
        $waitBit = @"
Write-Host '[$Mode] waiting for 127.0.0.1:$WaitPort ...'
while (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port $WaitPort -WarningAction SilentlyContinue).TcpTestSucceeded) { Start-Sleep -Seconds 1 }
Write-Host '[$Mode] dependency port $WaitPort is up.'
"@
    }
    $script = @"
`$Host.UI.RawUI.WindowTitle = '$Title'
Set-Location -LiteralPath '$RepoRoot'
$waitBit
while (`$true) {
  Write-Host '[$Mode] starting...'
  & '$godot' --headless --path . --mode=$Mode
  Write-Host '[$Mode] exited; restarting in 2s...' 
  Start-Sleep -Seconds 2
}
"@
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $script
    )
}

Write-Host "Starting master, gateway, world..."
Start-ServerWindow -Title "Arkenelle master-server" -Mode "master-server"
Start-ServerWindow -Title "Arkenelle gateway-server" -Mode "gateway-server" -WaitPort "8064"
Start-ServerWindow -Title "Arkenelle world-server" -Mode "world-server" -WaitPort "8062"

Write-Host ""
Write-Host "Three server windows should be open." -ForegroundColor Green
Write-Host "Then start the client:"
Write-Host "  godot --path . --mode=client"
Write-Host ""
Write-Host "Playing only on https://play.arkenelle.com? You can ignore this script."
