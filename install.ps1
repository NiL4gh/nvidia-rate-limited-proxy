<#
.SYNOPSIS
    Installs the NVIDIA rate-limited proxy as a scheduled task that starts on login.

.DESCRIPTION
    Creates a Windows scheduled task that:
    - Starts the proxy when you log in
    - Runs hidden (no console window)
    - Restarts if it crashes (restart every minute on failure)
    - Logs to %APPDATA%\opencode\nvidia-proxy\logs\proxy.log

    To uninstall: Unregister-ScheduledTask -TaskName "NvidiaProxy" -Confirm:$false
#>

$taskName = "NvidiaProxy"
$scriptDir = Split-Path -Parent $PSCommandPath
$nodePath = (Get-Command node).Source
$serverPath = Join-Path $scriptDir "server.js"
$logDir = Join-Path $scriptDir "logs"

# Ensure log directory exists
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

# Build the action
$action = New-ScheduledTaskAction `
    -Execute $nodePath `
    -Argument "`"$serverPath`"" `
    -WorkingDirectory $scriptDir

# Trigger at logon
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Settings: restart on failure every minute, max 3 restarts, kill after 2 days
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 2) `
    -StartWhenAvailable

# Run as current user with highest privileges
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType S4U `
    -RunLevel Limited

# Register (or update) the task
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host "✓ Scheduled task '$taskName' registered." -ForegroundColor Green
Write-Host "  It will start automatically on next login." -ForegroundColor Gray
Write-Host "  To start it now, run:" -ForegroundColor Gray
Write-Host "    Start-ScheduledTask -TaskName `"$taskName`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To check status:" -ForegroundColor Gray
Write-Host "    Get-ScheduledTask -TaskName `"$taskName`" | fl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To uninstall:" -ForegroundColor Gray
Write-Host "    Unregister-ScheduledTask -TaskName `"$taskName`" -Confirm:`$false" -ForegroundColor Cyan
