#!/usr/bin/env node

/**
 * MCP Proxy for Zed Editor - Stdio Protocol
 *
 * This proxy bridges Zed's stdio-based MCP client with HTTP-based MCP servers.
 * It maintains a persistent connection and handles JSON-RPC messages over stdio.
 *
 * Usage:
 *   node mcp-proxy.js <MCP_SERVER_URL>
 *
 * Example:
 *   node mcp-proxy.js http://91.99.186.83:7284/mcp
 */

const http = require("http");
const https = require("https");
const url = require("url");
const readline = require("readline");

// Get MCP server URL from command line argument
const MCP_SERVER_URL = process.argv[2];

if (!MCP_SERVER_URL) {
  console.error("Error: MCP server URL is required");
  console.error("Usage: node mcp-proxy.js <MCP_SERVER_URL>");
  process.exit(1);
}

// Parse the MCP server URL
const serverUrl = url.parse(MCP_SERVER_URL);
const isHttps = serverUrl.protocol === "https:";
const httpModule = isHttps ? https : http;

// Log to stderr (stdout is reserved for MCP responses)
function log(message) {
  console.error(`[MCP Proxy] ${new Date().toISOString()} - ${message}`);
}

log(`Starting MCP proxy for: ${MCP_SERVER_URL}`);

// Keep track of pending requests
const pendingRequests = new Map();
let isShuttingDown = false;

// Create readline interface for line-by-line input
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
});

// Handle each line of input as a JSON-RPC message
rl.on("line", (line) => {
  if (isShuttingDown) return;

  line = line.trim();
  if (!line) return;

  try {
    const message = JSON.parse(line);
    forwardToMCPServer(message);
  } catch (e) {
    log(`Failed to parse message: ${e.message}`);
    log(`Message content: ${line.substring(0, 100)}...`);
  }
});

// Handle stdin close
rl.on("close", () => {
  log("Stdin closed");
  // Wait a bit for pending requests to complete
  setTimeout(() => {
    if (pendingRequests.size === 0) {
      log("No pending requests, exiting");
      process.exit(0);
    } else {
      log(`Waiting for ${pendingRequests.size} pending requests...`);
      // Give them more time
      setTimeout(() => {
        log("Forcing exit");
        process.exit(0);
      }, 5000);
    }
  }, 1000);
});

// Handle errors
rl.on("error", (err) => {
  log(`Readline error: ${err.message}`);
});

process.stdin.on("error", (err) => {
  log(`Stdin error: ${err.message}`);
  if (!isShuttingDown) {
    process.exit(1);
  }
});

/**
 * Forward a message to the remote MCP server
 */
function forwardToMCPServer(message) {
  const requestId = message.id;
  const method = message.method || "unknown";

  log(`Forwarding request: ${method} (id: ${requestId})`);

  const postData = JSON.stringify(message);

  const options = {
    hostname: serverUrl.hostname,
    port: serverUrl.port || (isHttps ? 443 : 80),
    path: serverUrl.path || "/mcp",
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "Content-Length": Buffer.byteLength(postData),
      "User-Agent": "Zed-MCP-Proxy/1.0",
    },
  };

  // Track this request
  const startTime = Date.now();
  pendingRequests.set(requestId, { method, startTime });

  const req = httpModule.request(options, (res) => {
    let responseData = "";

    res.on("data", (chunk) => {
      responseData += chunk;
    });

    res.on("end", () => {
      const elapsed = Date.now() - startTime;
      pendingRequests.delete(requestId);

      try {
        const response = JSON.parse(responseData);
        log(
          `Response received: ${res.statusCode} (id: ${requestId}, ${elapsed}ms)`,
        );

        // Send response back to Zed via stdout
        // Important: Must be followed by newline and flushed
        process.stdout.write(JSON.stringify(response) + "\n");
      } catch (e) {
        log(`Failed to parse response: ${e.message}`);
        sendErrorResponse(
          requestId,
          -32603,
          `Invalid JSON response from server: ${e.message}`,
        );
      }
    });
  });

  req.on("error", (e) => {
    log(`Request error: ${e.message}`);
    pendingRequests.delete(requestId);
    sendErrorResponse(
      requestId,
      -32603,
      `MCP server connection failed: ${e.message}`,
    );
  });

  req.on("timeout", () => {
    log(`Request timeout for ${method} (id: ${requestId})`);
    req.destroy();
    pendingRequests.delete(requestId);
    sendErrorResponse(requestId, -32603, "MCP server request timeout");
  });

  // Set timeout per request (60 seconds for initialize, 30 for others)
  const timeout = method === "initialize" ? 60000 : 30000;
  req.setTimeout(timeout);

  req.write(postData);
  req.end();
}

/**
 * Send an error response to Zed
 */
function sendErrorResponse(id, code, message) {
  const errorResponse = {
    jsonrpc: "2.0",
    id: id,
    error: {
      code: code,
      message: message,
    },
  };
  process.stdout.write(JSON.stringify(errorResponse) + "\n");
}

// Handle process termination gracefully
process.on("SIGTERM", () => {
  log("Received SIGTERM, shutting down gracefully");
  isShuttingDown = true;
  rl.close();
  setTimeout(() => process.exit(0), 1000);
});

process.on("SIGINT", () => {
  log("Received SIGINT, shutting down gracefully");
  isShuttingDown = true;
  rl.close();
  setTimeout(() => process.exit(0), 1000);
});

process.on("uncaughtException", (err) => {
  log(`Uncaught exception: ${err.message}`);
  log(err.stack);
  if (!isShuttingDown) {
    process.exit(1);
  }
});

process.on("unhandledRejection", (reason, promise) => {
  log(`Unhandled rejection at ${promise}: ${reason}`);
  if (!isShuttingDown) {
    process.exit(1);
  }
});

// Periodic health check
setInterval(() => {
  if (pendingRequests.size > 0) {
    log(`Health check: ${pendingRequests.size} pending requests`);
  }
}, 30000);

log("MCP proxy initialized and ready");
