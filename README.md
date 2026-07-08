# nvidia-rate-limited-proxy

A lightweight Node.js proxy that sits between your local tools and the NVIDIA API, enforcing a configurable rate limit (default: 40 requests per minute) to avoid 429 errors.

## Why?

NVIDIA's API rate limits can be aggressive when using parallel sub-agents or batch operations. This proxy queues requests through [Bottleneck](https://github.com/SGrondin/bottleneck) so you never hit 429s.

## Features

- **Token-bucket rate limiting** — 40 RPM by default, configurable via env vars
- **Streaming (SSE) support** — correctly pipes `text/event-stream` responses
- **Non-streaming support** — buffers and forwards regular JSON responses
- **Real-time status dashboard** — live-updating HTML page at `http://localhost:1340/status`
- **CLI status tool** — `proxy-status.ps1` with `-Watch` and `-Log` flags
- **ECONNRESET retry** — automatically retries stale pooled connections once
- **Connection pooling** — custom `https.Agent` with keep-alive for lower latency
- **Per-path metrics** — tracks request count, errors, and avg response time per endpoint
- **Live RPM tracking** — rolling 60-second window of completed requests
- **Auto-open browser** — opens the dashboard on proxy startup
- **Health check** — `GET /health` returns full status JSON
- **Log tail** — `GET /tail-log` returns last 50 log lines
- **Auto-recovery** — exits silently if port is already in use (handles duplicate startup)
- **Windows scheduled task** — auto-starts on login via `install.ps1`

## Quick Start

```powershell
npm install
node server.js
```

The proxy starts and automatically opens `http://localhost:1340/status` in your browser.

## Install as Windows Service

```powershell
.\install.ps1
```

This creates a scheduled task that starts the proxy on login. To uninstall:

```powershell
Unregister-ScheduledTask -TaskName "NvidiaProxy" -Confirm:$false
```

## Configuration (env vars)

| Variable | Default | Description |
|---|---|---|
| `PROXY_PORT` | `1340` | Local port to listen on |
| `RATE_LIMIT_RPM` | `40` | Max requests per minute |
| `UPSTREAM_TIMEOUT_MS` | `300000` | Upstream timeout (5 min) |

## Status Dashboard

Open `http://localhost:1340/status` in your browser:

- **Stats grid** — live-updating cards for Uptime, Live RPM, Running/Queued requests, Total/Completed/Failed, Avg Response Time
- **Per-path breakdown** — request count, errors, and average time per endpoint
- **Live log pane** — tail of the proxy log, auto-refreshing every 3 seconds, color-coded
- **Error display** — shows last error with timestamp and path when failures occur

All numbers update every 2 seconds. No manual refresh needed.

## CLI Status Tool

```powershell
.\proxy-status.ps1          # One-shot status
.\proxy-status.ps1 -Watch   # Live-refresh every 5 seconds
.\proxy-status.ps1 -Log     # Show last 20 log entries
```

## Usage with opencode

Set your NVIDIA provider's `baseURL` to `http://localhost:1340/v1` in `opencode.jsonc`:

```jsonc
"provider": {
  "nvidia": {
    "provider": "openai-compatible",
    "options": {
      "baseURL": "http://localhost:1340/v1",
      "apiKey": "nvapi-..."
    }
  }
}
```

## Health Check

```powershell
Invoke-RestMethod -Uri "http://localhost:1340/health"
# Returns: { "ok": true, "uptime_sec": 360, "live_rpm": 5, "max_rpm": 40, "queued": 0, "running": 0, "total_requests": 42, "failed_requests": 0 }
```

## License

MIT
