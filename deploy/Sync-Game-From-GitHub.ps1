# Double-click or right-click → Run with PowerShell.
# Updates THIS PC's game project folder from GitHub main.
# Does NOT touch the live VPS (that is automatic via GitHub Actions).

$ErrorActionPreference = "Stop"

# If you keep the project somewhere else, change this path:
$ProjectDir = Join-Path $env:USERPROFILE "OneDrive\Documents\GitHub\godot-tiny-mmo-demo"

if (-not (Test-Path (Join-Path $ProjectDir ".git"))) {
    Write-Host "Project folder not found or not a git repo:" -ForegroundColor Red
    Write-Host "  $ProjectDir"
    Write-Host "Edit the `$ProjectDir path at the top of this script."
    pause
    exit 1
}

Set-Location $ProjectDir
Write-Host "==> Project: $ProjectDir" -ForegroundColor Cyan

$dirty = git status --porcelain
if ($dirty) {
    Write-Host "You have local changes. Stashing them so pull can proceed..." -ForegroundColor Yellow
    git stash push -m ("auto-stash before sync " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
}

git checkout main
git pull origin main

Write-Host ""
Write-Host "PC project updated to:" -ForegroundColor Green
git log -1 --oneline
Write-Host ""
Write-Host "Close Godot and reopen the project if it was already open."
Write-Host "Live server updates happen automatically when main changes (GitHub Actions)."
pause
