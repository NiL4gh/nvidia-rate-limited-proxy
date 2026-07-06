/**
 * Rate-limited proxy for NVIDIA API.
 *
 * Queues outgoing requests to stay within 40 requests per 60 seconds.
 * Handles streaming (SSE) responses correctly.
 *
 * opencode.jsonc should set the NVIDIA provider's baseURL to:
 *   http://localhost:1340/v1
 */

const express = require("express");
const https = require("https");
const http = require("http");
const Bottleneck = require("bottleneck");
const { dirname } = require("path");
const { writeFile, mkdir } = require("fs/promises");
const { existsSync } = require("fs");

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const PORT = parseInt(process.env.PROXY_PORT, 10) || 1340;
const UPSTREAM_HOST = "integrate.api.nvidia.com";
const UPSTREAM_PORT = 443;
const RPM = parseInt(process.env.RATE_LIMIT_RPM, 10) || 40;
const UPSTREAM_TIMEOUT_MS = parseInt(process.env.UPSTREAM_TIMEOUT_MS, 10) || 300_000; // 5 min
const LOG_DIR = `${__dirname}/logs`;

// ---------------------------------------------------------------------------
// Simple file logger (no external dep)
// ---------------------------------------------------------------------------
async function log(level, msg, extra) {
  const ts = new Date().toISOString();
  const line = `[${ts}] ${level}: ${msg}${extra ? " " + JSON.stringify(extra) : ""}\n`;
  try {
    if (!existsSync(LOG_DIR)) await mkdir(LOG_DIR, { recursive: true });
    await writeFile(`${LOG_DIR}/proxy.log`, line, { flag: "a" });
  } catch {
    // Best-effort logging
  }
  // Also print to stderr so it shows in the terminal / Windows Event viewer
  process.stderr.write(line);
}

// ---------------------------------------------------------------------------
// Rate limiter — token-bucket reservoir, 40 requests per 60 seconds
// ---------------------------------------------------------------------------
const limiter = new Bottleneck({
  reservoir: RPM,
  reservoirRefreshAmount: RPM,
  reservoirRefreshInterval: 60 * 1000,
  maxConcurrent: 5,           // allow parallel streams; the reservoir enforces RPM
  minTime: 50,                // 50ms min gap between scheduling (20 req/s ceiling)
});

limiter.on("error", (err) => log("ERROR", "limiter error", { error: err.message }));

// ---------------------------------------------------------------------------
// Express app
// ---------------------------------------------------------------------------
const app = express();

// Capture raw body for all content types (we need to replay it upstream)
app.use(
  express.raw({
    type: "*/*",
    limit: "20mb",
  })
);

// Health check
app.get("/health", (_req, res) => {
  res.json({ ok: true, rps: RPM, queued: limiter.counts().QUEUED || 0 });
});

// Proxy all other paths
app.all("/*", async (req, res) => {
  const startMs = Date.now();
  const path = req.originalUrl;

  log("INFO", `→ ${req.method} ${path}`);

  try {
    // Schedule the upstream call through the rate limiter
    await limiter.schedule(() => forwardToNvidia(req, res, path));
    const elapsed = Date.now() - startMs;
    log("INFO", `✓ ${req.method} ${path} (${elapsed}ms)`);
  } catch (err) {
    const elapsed = Date.now() - startMs;
    log("ERROR", `✗ ${req.method} ${path} (${elapsed}ms)`, { error: err.message });

    // If headers already sent (e.g. streaming mid-response failure), we can't send a response
    if (res.headersSent) {
      log("WARN", "headers already sent, destroying connection");
      res.destroy();
      return;
    }

    res.status(502).json({
      error: {
        message: `Proxy error: ${err.message}`,
        type: "proxy_error",
        proxy: true,
      },
    });
  }
});

// ---------------------------------------------------------------------------
// Forward a single request to NVIDIA upstream
// ---------------------------------------------------------------------------
function forwardToNvidia(expressReq, expressRes, path) {
  return new Promise((resolve, reject) => {
    const body = expressReq.body;
    const isStreaming = isStreamRequest(expressReq);

    // Build upstream URL
    const upstreamPath = path;

    // Forward headers, stripping connection-level ones
    const upstreamHeaders = { ...expressReq.headers };
    delete upstreamHeaders.host;
    delete upstreamHeaders["transfer-encoding"];
    delete upstreamHeaders["content-length"];
    // normalize content-length
    if (body && body.length > 0) {
      upstreamHeaders["content-length"] = Buffer.byteLength(body);
    }
    // Force close upstream connection after each request (avoids lingering sockets)
    upstreamHeaders.connection = "close";

    const options = {
      hostname: UPSTREAM_HOST,
      port: UPSTREAM_PORT,
      path: upstreamPath,
      method: expressReq.method,
      headers: upstreamHeaders,
      timeout: UPSTREAM_TIMEOUT_MS,
      rejectUnauthorized: true,
    };

    const proxyReq = https.request(options, (proxyRes) => {
      // Copy upstream status and headers to the downstream response
      expressRes.status(proxyRes.statusCode);
      for (let i = 0; i < proxyRes.rawHeaders.length; i += 2) {
        const key = proxyRes.rawHeaders[i];
        const val = proxyRes.rawHeaders[i + 1];
        // Skip transfer-encoding; Express handles chunked responses
        if (key.toLowerCase() === "transfer-encoding") continue;
        expressRes.setHeader(key, val);
      }

      // For streaming responses, pipe immediately
      if (isStreaming) {
        proxyRes.pipe(expressRes);
        proxyRes.on("end", resolve);
        proxyRes.on("error", (err) => {
          log("ERROR", "upstream stream error", { error: err.message });
          reject(err);
        });
      } else {
        // For non-streaming, buffer and send
        const chunks = [];
        proxyRes.on("data", (chunk) => chunks.push(chunk));
        proxyRes.on("end", () => {
          const buf = Buffer.concat(chunks);
          expressRes.send(buf);
          resolve();
        });
        proxyRes.on("error", reject);
      }
    });

    proxyReq.on("timeout", () => {
      proxyReq.destroy();
      reject(new Error(`Upstream request timed out after ${UPSTREAM_TIMEOUT_MS / 1000}s`));
    });

    proxyReq.on("error", (err) => {
      // If the upstream is unreachable or connection refused
      reject(new Error(`Upstream connection failed: ${err.message}`));
    });

    // Send the request body
    if (body && body.length > 0) {
      proxyReq.write(body);
    }
    proxyReq.end();
  });
}

// ---------------------------------------------------------------------------
// Detect streaming requests (SSE)
// ---------------------------------------------------------------------------
function isStreamRequest(req) {
  const accept = (req.headers.accept || "").toLowerCase();
  const contentType = (req.headers["content-type"] || "").toLowerCase();
  const body = req.body ? req.body.toString("utf8") : "";

  // Use both headers and body to detect streaming
  if (accept.includes("text/event-stream")) return true;
  try {
    const parsed = JSON.parse(body);
    return parsed.stream === true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Startup — gracefully handle port already in use
// ---------------------------------------------------------------------------
const server = app.listen(PORT, "127.0.0.1");
server.on("listening", () => {
  const msg = `NVIDIA rate-limited proxy running on http://127.0.0.1:${PORT}/v1 → https://${UPSTREAM_HOST} (${RPM} RPM)`;
  process.stdout.write(msg + "\n");
  log("INFO", msg);
});
server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    // Another proxy instance is already running — nothing to do
    process.exit(0);
  }
  log("ERROR", "failed to start", { error: err.message });
  process.exit(1);
});
