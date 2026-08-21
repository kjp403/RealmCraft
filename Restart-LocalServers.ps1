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
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }

    # Must be a real .exe file — never a folder (people often pass the repo path by mistake).
    if (Test-Path -LiteralPath $Candidate) {
        $item = Get-Item -LiteralPath $Candidate
        if ($item.PSIsContainer) { return $null }
        if ($item.Extension -ieq ".exe") { return $item.FullName }
        return $null
    }

    $cmd = Get-Command $Candidate -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source) -and -not (Get-Item -LiteralPath $cmd.Source).PSIsContainer) {
        return $cmd.Source
    }
    return $null
}

$godot = Resolve-Godot $GodotExe
if (-not $godot) {
    Write-Host ""
    Write-Host "Could not find Godot." -ForegroundColor Red
    Write-Host "You must point at the Godot ENGINE .exe (not the RealmCraft folder)."
    Write-Host ""
    Write-Host "1) Download Godot 4.7 from https://godotengine.org/download/windows/"
    Write-Host "2) Unzip it (example): C:\Godot\Godot_v4.7.1-stable_win64.exe"
    Write-Host "3) Then run:"
    Write-Host '   cd $HOME\Documents\RealmCraft'
    Write-Host '   .\Restart-LocalServers.ps1 -GodotExe "C:\Godot\Godot_v4.7.1-stable_win64.exe"'
    Write-Host ""
    Write-Host "See LOCAL_SERVERS_WINDOWS.md"
    exit 1
}

if (-not (Test-Path (Join-Path $RepoRoot "project.godot"))) {
    Write-Host "project.godot not found. Run this from the RealmCraft folder." -ForegroundColor Red
    exit 1
}

Write-Host "Repo:   $RepoRoot"
Write-Host "Godot:  $godot"
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
