# Grafana MCP Setup Guide

> **Prefer the shared-container setup.** `../mcp-grafana-http-up` runs one
> long-lived `streamable-http` container per Grafana environment (nonprod on
> `:8000`, prod on `:8001`), and every Claude Code session shares it. That
> replaces one stdio container per session. See
> [the README](../README.md#grafana-mcp--shared-containers-recommended) for setup.
> The rest of this guide covers the legacy per-session stdio wrapper.

This guide helps ECFX team members set up the Grafana MCP (Model Context Protocol) server for use with Claude Code, enabling AI-assisted Grafana operations.

## Overview

The Grafana MCP provides Claude Code with tools to:
- Search and view dashboards
- Query Prometheus and Loki datasources
- Manage alerts and incidents
- Browse datasources and folders

Since our Grafana instances are behind DuploCloud authentication, the setup script creates a wrapper that obtains a DuploCloud token before connecting to Grafana.

## Prerequisites

### 1. Claude Code CLI
```bash
# Check if installed
claude --version

# If not installed, see: https://docs.anthropic.com/en/docs/claude-code
```

### 2. DuploCloud CLI Tools
```bash
# Check if installed
which duplo-jit

# If not installed:
brew tap duplocloud/tap
brew install duplo-jit
```

### 3. Go (for building)
```bash
# Check if installed
go version

# If not installed:
brew install go
```

### 4. DuploCloud Access
You must have access to the ECFX DuploCloud portal at `https://duplo.cloud.ecfxglobal.net`.

## Quick Setup

```bash
cd ~/ecfx/claude-mcp-setup
./setup-grafana-mcp.sh
```

The script will:
1. Clone or update the mcp-grafana repository
2. Build the mcp-grafana binary
3. Create the DuploCloud authentication wrapper
4. Configure Claude Code MCP server
5. Verify the setup

## Setup Options

```bash
# Default setup (nonprod Grafana)
./setup-grafana-mcp.sh

# Production Grafana with read-only mode (recommended for prod)
./setup-grafana-mcp.sh \
  --grafana-url https://grafana-proxy-otel-prod.cloud.ecfxglobal.net \
  --read-only

# Skip rebuild if you already have a working binary
./setup-grafana-mcp.sh --skip-build

# Force overwrite existing configuration
./setup-grafana-mcp.sh --force

# Custom installation directory
./setup-grafana-mcp.sh --install-dir ~/my-tools/mcp-grafana
```

### All Options

| Option | Description |
|--------|-------------|
| `-g, --grafana-url URL` | Grafana URL (default: nonprod) |
| `-d, --duplo-host URL` | DuploCloud host URL |
| `-i, --install-dir DIR` | Where to clone mcp-grafana |
| `-r, --read-only` | Disable write operations |
| `-s, --skip-build` | Use existing binary |
| `-f, --force` | Overwrite without prompting |
| `-h, --help` | Show help |

## Usage

After setup, start a **new** Claude Code session and try:
- "List my Grafana dashboards"
- "Show me the datasources in Grafana"
- "Search for dashboards about kubernetes"
- "Query Prometheus for the up metric"
- "Show me recent logs from Loki"

## Configuration

### Switching Grafana Instances

To switch between nonprod and prod:

```bash
# Remove current config
claude mcp remove grafana --scope user

# Re-run setup with different URL
./setup-grafana-mcp.sh --grafana-url https://grafana-proxy-otel-prod.cloud.ecfxglobal.net --read-only
```

### Disabling Specific Tools

Edit the MCP configuration to add disable flags:

```bash
claude mcp remove grafana --scope user
claude mcp add-json "grafana" '{
  "command": "~/tools/mcp-grafana/dist/mcp-grafana-duplo",
  "args": ["--disable-oncall", "--disable-incident"],
  "env": {
    "GRAFANA_URL": "https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net",
    "DUPLO_HOST": "https://duplo.cloud.ecfxglobal.net"
  }
}' --scope user
```

Available disable flags:
- `--disable-admin` - Admin operations
- `--disable-alerting` - Alert rules, contact points
- `--disable-dashboard` - Dashboard operations
- `--disable-datasource` - Datasource operations
- `--disable-incident` - Incident management
- `--disable-loki` - Loki/LogQL queries
- `--disable-oncall` - OnCall integration
- `--disable-prometheus` - Prometheus/PromQL queries
- `--disable-search` - Search functionality
- `--disable-write` - All write operations

## Troubleshooting

### "Failed to get DuploCloud token"

Your DuploCloud session may have expired. Re-authenticate:
```bash
duplo-jit duplo --host https://duplo.cloud.ecfxglobal.net --interactive
```

### "302 Redirect" errors

The Grafana proxy is redirecting to DuploCloud auth. Verify your token works:
```bash
# Get a fresh token
TOKEN=$(duplo-jit duplo --host https://duplo.cloud.ecfxglobal.net --interactive 2>/dev/null | grep -o '"DuploToken":"[^"]*"' | cut -d'"' -f4)

# Test it
curl -s -H "Authorization: Bearer $TOKEN" "https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net/api/health"
```

### "406 Not Acceptable" errors

This usually means the wrong token type is being used. Ensure the setup script created the DuploCloud wrapper correctly. Re-run:
```bash
./setup-grafana-mcp.sh --force
```

### MCP shows "✗ Failed to connect"

1. Check that the wrapper script exists:
   ```bash
   ls -la ~/tools/mcp-grafana/dist/mcp-grafana-duplo
   ```
2. Check that `duplo-jit` is in your PATH:
   ```bash
   which duplo-jit
   ```
3. Try running the wrapper manually:
   ```bash
   ~/tools/mcp-grafana/dist/mcp-grafana-duplo --help
   ```

### Changes not taking effect

Claude Code caches MCP connections. Start a **new** Claude Code session after configuration changes.

### Build failures

Ensure Go is installed and your network can reach GitHub:
```bash
go version
git ls-remote https://github.com/grafana/mcp-grafana.git
```

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐     ┌─────────┐
│ Claude Code │────▶│ mcp-grafana-duplo│────▶│ DuploCloud  │────▶│ Grafana │
└─────────────┘     │   (wrapper)      │     │   Proxy     │     │   API   │
                    └──────────────────┘     └─────────────┘     └─────────┘
                            │
                            ▼
                    ┌──────────────────┐
                    │    duplo-jit     │
                    │  (gets token)    │
                    └──────────────────┘
```

1. Claude Code starts the MCP server using the wrapper script
2. The wrapper calls `duplo-jit` to get a DuploCloud authentication token
3. The token is passed to `mcp-grafana` as the Grafana API key
4. Requests to Grafana go through DuploCloud's proxy with proper auth
5. Grafana API responds, and mcp-grafana returns results to Claude

## Updating

To update to the latest mcp-grafana:
```bash
./setup-grafana-mcp.sh --force
```

This will pull the latest code and rebuild.

## Uninstalling

```bash
# Remove Claude Code MCP configuration
claude mcp remove grafana --scope user

# Optionally remove the cloned repo
rm -rf ~/tools/mcp-grafana
```
