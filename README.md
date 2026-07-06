# nvidia-rate-limited-proxy

A lightweight Node.js proxy that sits between your local tools and the NVIDIA API, enforcing a configurable rate limit (default: 40 requests per minute) to avoid 429 errors.

## Why?

NVIDIA's API rate limits can be aggressive when using parallel sub-agents or batch operations. This proxy queues requests through [Bottleneck](https://github.com/SGrondin/bottleneck) so you never hit 429s.

## Features

- **Token-bucket rate limiting** — 40 RPM by default, configurable via env vars
- **Streaming (SSE) support** — correctly pipes `text/event-stream` responses
- **Non-streaming support** — buffers and forwards regular JSON responses
- **Health check** — `GET /health` returns status and queue depth
- **Auto-recovery** — exits silently if port is already in use (handles duplicate startup)
- **Windows scheduled task** — auto-starts on login via `install.ps1`

## Quick Start

```powershell
npm install
node server.js
```

The proxy listens on `http://127.0.0.1:1340` and forwards to `https://integrate.api.nvidia.com`.

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
# Returns: { "ok": true, "rps": 40, "queued": 0 }
```

## License

MIT
