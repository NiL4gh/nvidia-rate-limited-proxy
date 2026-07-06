# Start the NVIDIA rate-limited proxy
$workDir = Split-Path -Parent $PSCommandPath
$logFile = "$env:TEMP\nvidia-proxy.log"

# Check if already running
try {
    $health = Invoke-RestMethod -Uri "http://localhost:1340/health" -ErrorAction Stop
    Write-Host "Proxy already running at http://localhost:1340/v1 (RPM: $($health.rps))" -ForegroundColor Green
    exit 0
} catch {
    # Not running, start it
}

$serverPath = Join-Path $workDir "server.js"
Start-Process -FilePath "node" -ArgumentList "`"$serverPath`"" -WorkingDirectory $workDir -WindowStyle Hidden

Start-Sleep -Seconds 2

try {
    $health = Invoke-RestMethod -Uri "http://localhost:1340/health" -ErrorAction Stop
    Write-Host "[OK] Proxy started at http://localhost:1340/v1 (RPM: $($health.rps))" -ForegroundColor Green
} catch {
    Write-Host "[FAILED] Check $logFile" -ForegroundColor Red
}

# Keep window open so user can press Enter to close
Write-Host ""
Write-Host "Press Enter to close this window (proxy keeps running in background)." -ForegroundColor Gray
Read-Host
