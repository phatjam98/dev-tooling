# Claude Code MCP Setup

Setup tooling for configuring Claude Code with MCP (Model Context Protocol) servers for ECFX development environments.

## Available MCP Setups

| MCP Server | Description | Setup Script |
|------------|-------------|--------------|
| **Grafana** | Dashboards, Prometheus, Loki, alerts | `./setup-grafana-mcp.sh` |

## Grafana MCP

Provides Claude Code with tools to interact with Grafana:
- Search and view dashboards
- Query Prometheus and Loki datasources
- Manage alerts and incidents
- Browse datasources and folders

### Quick Setup

```bash
cd ~/dev-tooling/claude-mcp
./setup-grafana-mcp.sh
```

The script will:
1. Clone the [mcp-grafana](https://github.com/grafana/mcp-grafana) repository to `~/tools/mcp-grafana`
2. Build the binary
3. Create a DuploCloud authentication wrapper
4. Configure Claude Code MCP server
5. Verify the setup

### Options

```bash
# Default setup (nonprod Grafana)
./setup-grafana-mcp.sh

# Production with read-only mode (recommended)
./setup-grafana-mcp.sh \
  --grafana-url https://grafana-proxy-otel-prod.cloud.ecfxglobal.net \
  --read-only

# Custom install location
./setup-grafana-mcp.sh --install-dir ~/my-tools/mcp-grafana

# Update/reconfigure without rebuilding
./setup-grafana-mcp.sh --skip-build --force

# Show all options
./setup-grafana-mcp.sh --help
```

### After Setup

Start a **new** Claude Code session and try:
- "List my Grafana dashboards"
- "Show me the datasources"
- "Search for dashboards about kubernetes"
- "Query Prometheus for up metric"

### Documentation

See [docs/grafana-mcp.md](docs/grafana-mcp.md) for:
- Detailed configuration options
- Troubleshooting guide
- How the DuploCloud authentication works

## Prerequisites

- **Claude Code CLI** - [Installation guide](https://docs.anthropic.com/en/docs/claude-code)
- **DuploCloud CLI** - `brew tap duplocloud/tap && brew install duplo-jit`
- **Go** - `brew install go` (for building)
- **DuploCloud Access** - Access to `https://duplo.cloud.ecfxglobal.net`

## How It Works

Our Grafana instances are behind DuploCloud authentication. The setup creates a wrapper script that:

1. Calls `duplo-jit` to get a DuploCloud token
2. Passes the token to mcp-grafana
3. Requests go through DuploCloud's proxy with proper auth

```
Claude Code → mcp-grafana-duplo → DuploCloud Proxy → Grafana API
                    ↓
               duplo-jit (token)
```

## Troubleshooting

### Authentication errors

Re-authenticate with DuploCloud:
```bash
duplo-jit duplo --host https://duplo.cloud.ecfxglobal.net --interactive
```

### MCP not connecting

Check status and re-run setup:
```bash
claude mcp list
./setup-grafana-mcp.sh --force
```

### Changes not taking effect

Start a **new** Claude Code session - existing sessions cache MCP connections.
