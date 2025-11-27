#!/usr/bin/env bash

# Debug wrapper for MCP proxy
# This logs everything to help diagnose connection issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/mcp-proxy-debug.log"

# Log startup
echo "=================================" >> "$LOG_FILE"
echo "MCP Proxy Debug Started: $(date)" >> "$LOG_FILE"
echo "Script Dir: $SCRIPT_DIR" >> "$LOG_FILE"
echo "Args: $@" >> "$LOG_FILE"
echo "Node path: $(which node)" >> "$LOG_FILE"
echo "Node version: $(node --version 2>&1)" >> "$LOG_FILE"
echo "=================================" >> "$LOG_FILE"

# Check if proxy exists
if [[ ! -f "$SCRIPT_DIR/mcp-proxy.js" ]]; then
    echo "ERROR: mcp-proxy.js not found at $SCRIPT_DIR/mcp-proxy.js" >> "$LOG_FILE"
    exit 1
fi

echo "Proxy file found, starting..." >> "$LOG_FILE"

# Start the actual proxy, redirecting stderr to log
node "$SCRIPT_DIR/mcp-proxy.js" "$@" 2>> "$LOG_FILE"

EXIT_CODE=$?
echo "Proxy exited with code: $EXIT_CODE at $(date)" >> "$LOG_FILE"
exit $EXIT_CODE
