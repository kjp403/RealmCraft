# Double-click this to restart Arkenelle local servers (Windows).
# Requires: Godot on PATH, or edit Restart-LocalServers.ps1 ($GodotExe).
@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restart-LocalServers.ps1"
pause
