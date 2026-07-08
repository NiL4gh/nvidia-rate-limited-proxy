<#
.SYNOPSIS
  Check NVIDIA proxy status at a glance.
  Run this anytime to see if the proxy is alive, how busy it is, and any errors.
.EXAMPLE
  .\proxy-status.ps1
  .\proxy-status.ps1 -Watch   # Refresh every 5 seconds
  .\proxy-status.ps1 -Log     # Show last 20 log entries
#>

param(
  [switch]$Log,
  [switch]$Watch
)

$proxyUrl = "http://127.0.0.1:1340"
$logFile = "$PSScriptRoot\logs\proxy.log"

function Show-Status {
  Clear-Host
  Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
  Write-Host "║     NVIDIA Proxy Status Dashboard        ║" -ForegroundColor Cyan
  Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
  Write-Host ""

  # Check if proxy is running
  $proc = Get-CimInstance Win32_Process -Filter "Name='node.exe'" | 
    Where-Object { $_.CommandLine -like "*server.js*" -and $_.CommandLine -like "*nvidia-proxy*" }
  
  if (-not $proc) {
    Write-Host "◉ PROXY: DEAD" -ForegroundColor Red
    Write-Host "  The proxy is not running. Start it with:" -ForegroundColor DarkGray
    Write-Host "  Start-Process -WindowStyle Hidden -FilePath node -ArgumentList '$PSScriptRoot\server.js'" -ForegroundColor DarkGray
    return
  }

  Write-Host "◉ PROXY: ALIVE" -ForegroundColor Green
  Write-Host "  PID: $($proc.ProcessId)  |  Started: $($proc.CreationDate)" -ForegroundColor DarkGray
  Write-Host ""

  # Fetch health data
  try {
    $health = Invoke-RestMethod -Uri "$proxyUrl/health" -UseBasicParsing -TimeoutSec 3
  } catch {
    Write-Host "  HEALTH CHECK FAILED: $_" -ForegroundColor Red
    return
  }

  # Process node processes that are NOT the proxy (MCP servers, etc.)
  $allNode = Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.ProcessId -ne $proc.ProcessId }
  $nodeCount = ($allNode | Measure-Object).Count

  # Uptime
  $uptime = $health.uptime_sec
  $uptimeStr = if ($uptime -lt 60) { "$uptime`s" }
    elseif ($uptime -lt 3600) { "$([math]::Floor($uptime / 60))m $($uptime % 60)s" }
    else { "$([math]::Floor($uptime / 3600))h $([math]::Floor(($uptime % 3600) / 60))m" }

  # Status grid
  Write-Host " ┌──────────────────────┬──────────────────────┐" -ForegroundColor DarkGray
  Write-Host (" │ {0,-20} │ {1,-20} │" -f "Uptime: $uptimeStr", "Live RPM: $($health.live_rpm) / $($health.max_rpm)") -ForegroundColor White
  Write-Host (" │ {0,-20} │ {1,-20} │" -f "Total requests: $($health.total_requests)", "Failed: $($health.failed_requests)") -ForegroundColor White

  $queueColor = if ($health.queued -gt 0) { "Yellow" } else { "White" }
  Write-Host (" │ {0,-20} │ {1,-20} │" -f "Running now: $($health.running)", "Queued: $($health.queued)") -ForegroundColor $queueColor

  Write-Host " └──────────────────────┴──────────────────────┘" -ForegroundColor DarkGray
  Write-Host ""

  # Check for recent errors in log
  if ($Log -and (Test-Path $logFile)) {
    Write-Host "─── Recent Log ─────────────────────────────" -ForegroundColor Cyan
    Get-Content $logFile -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object {
      $color = if ($_ -match "ERROR") { "Red" } elseif ($_ -match "WARN") { "Yellow" } else { "DarkGray" }
      Write-Host $_ -ForegroundColor $color
    }
    Write-Host ""
  }

  # Show errors from health
  if ($health.failed_requests -gt 0) {
    Write-Host "─── Last Error (from proxy) ────────────────" -ForegroundColor Red
    # Check the actual log for the last ERROR
    $lastErr = Select-String -Path $logFile -Pattern "ERROR" -Tail 3 -SimpleMatch 2>$null
    if ($lastErr) {
      $lastErr | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
    }
    Write-Host ""
  }

  # Node process overview
  Write-Host "─── Node Processes ──────────────────────────" -ForegroundColor Cyan
  Write-Host ("  Proxy:     $($proc.ProcessId)  (nvidia-proxy\server.js)") -ForegroundColor Green
  Write-Host ("  Others:    {0} processes (MCP servers, etc.)" -f $nodeCount) -ForegroundColor DarkGray
  Write-Host ""

  # Quick tips
  Write-Host "─── Quick Actions ───────────────────────────" -ForegroundColor Cyan
  Write-Host "  Status page: $proxyUrl/status" -ForegroundColor DarkGray
  Write-Host "  Health JSON: $proxyUrl/health" -ForegroundColor DarkGray
  Write-Host "  Log file:    $logFile" -ForegroundColor DarkGray
  if ($health.queued -gt 0) {
    Write-Host "  ⚠ Requests are queued! Check if NVIDIA API is slow." -ForegroundColor Yellow
  }
  if ($health.failed_requests -gt 3) {
    Write-Host "  ⚠ High error rate. Open $proxyUrl/status in browser." -ForegroundColor Red
  }
}

if ($Watch) {
  while ($true) {
    Show-Status
    Write-Host "`n  Refreshing every 5s... (Ctrl+C to stop)" -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
  }
} else {
  Show-Status
}
