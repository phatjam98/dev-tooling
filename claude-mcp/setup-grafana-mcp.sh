#!/bin/bash
#
# Setup script for Grafana MCP with DuploCloud authentication
# This configures Claude Code to use the Grafana MCP server for ECFX environments
#
# Usage:
#   ./setup-grafana-mcp.sh [OPTIONS]
#
# See --help for all options
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_DUPLO_HOST="https://duplo.cloud.ecfxglobal.net"
DEFAULT_GRAFANA_URL="https://grafana-proxy-otel-nonprod.cloud.ecfxglobal.net"
DEFAULT_INSTALL_DIR="$HOME/tools/mcp-grafana"
MCP_GRAFANA_REPO="https://github.com/grafana/mcp-grafana.git"
MCP_NAME="grafana"

print_header() {
    echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}\n"
}

print_step() {
    echo -e "${GREEN}▶${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Parse command line arguments
GRAFANA_URL="$DEFAULT_GRAFANA_URL"
DUPLO_HOST="$DEFAULT_DUPLO_HOST"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
DISABLE_WRITE=false
SKIP_BUILD=false
FORCE=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Setup Grafana MCP for Claude Code with DuploCloud authentication.

This script will:
  1. Clone or update the mcp-grafana repository
  2. Build the mcp-grafana binary
  3. Create a DuploCloud authentication wrapper
  4. Configure Claude Code MCP server
  5. Verify the setup

Options:
    -g, --grafana-url URL    Grafana URL (default: $DEFAULT_GRAFANA_URL)
    -d, --duplo-host URL     DuploCloud host (default: $DEFAULT_DUPLO_HOST)
    -i, --install-dir DIR    Installation directory (default: $DEFAULT_INSTALL_DIR)
    -r, --read-only          Enable read-only mode (disable write operations)
    -s, --skip-build         Skip cloning/building (use existing binary)
    -f, --force              Overwrite existing configuration without prompting
    -h, --help               Show this help message

Examples:
    # Default setup (nonprod)
    $(basename "$0")

    # Production setup with read-only mode
    $(basename "$0") --grafana-url https://grafana-proxy-otel-prod.cloud.ecfxglobal.net --read-only

    # Custom install location
    $(basename "$0") --install-dir ~/my-tools/mcp-grafana

    # Quick reconfigure without rebuild
    $(basename "$0") --skip-build --force

Environment Variables:
    GRAFANA_URL     Override default Grafana URL
    DUPLO_HOST      Override default DuploCloud host

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--grafana-url)
            GRAFANA_URL="$2"
            shift 2
            ;;
        -d|--duplo-host)
            DUPLO_HOST="$2"
            shift 2
            ;;
        -i|--install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -r|--read-only)
            DISABLE_WRITE=true
            shift
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Allow environment variable overrides
GRAFANA_URL="${GRAFANA_URL:-$DEFAULT_GRAFANA_URL}"
DUPLO_HOST="${DUPLO_HOST:-$DEFAULT_DUPLO_HOST}"

print_header "Grafana MCP Setup for Claude Code"

echo "Configuration:"
echo "  Grafana URL:    $GRAFANA_URL"
echo "  DuploCloud:     $DUPLO_HOST"
echo "  Install Dir:    $INSTALL_DIR"
echo "  Read-only:      $DISABLE_WRITE"
echo ""

# ============================================================================
# Check Prerequisites
# ============================================================================
print_header "Checking Prerequisites"

MISSING_DEPS=false

if ! check_command "claude"; then
    print_error "Claude Code CLI is required"
    echo "       Install from: https://docs.anthropic.com/en/docs/claude-code"
    MISSING_DEPS=true
fi

if ! check_command "duplo-jit"; then
    print_error "duplo-jit is required"
    echo "       Install with: brew tap duplocloud/tap && brew install duplo-jit"
    MISSING_DEPS=true
fi

if ! check_command "git"; then
    print_error "git is required"
    MISSING_DEPS=true
fi

if ! check_command "go"; then
    if [ "$SKIP_BUILD" = false ]; then
        print_error "Go is required for building"
        echo "       Install with: brew install go"
        MISSING_DEPS=true
    else
        print_warning "Go not installed, but skipping build"
    fi
fi

if [ "$MISSING_DEPS" = true ]; then
    echo ""
    print_error "Missing dependencies. Please install them and try again."
    exit 1
fi

# ============================================================================
# Clone or Update Repository
# ============================================================================
print_header "Setting Up mcp-grafana Repository"

if [ "$SKIP_BUILD" = true ]; then
    if [ -f "$INSTALL_DIR/dist/mcp-grafana" ]; then
        print_success "Skipping clone/build, using existing binary at $INSTALL_DIR"
    else
        print_error "Binary not found at $INSTALL_DIR/dist/mcp-grafana"
        print_error "Cannot use --skip-build without an existing installation"
        exit 1
    fi
else
    if [ -d "$INSTALL_DIR/.git" ]; then
        print_step "Updating existing repository..."
        cd "$INSTALL_DIR"

        # Check for local changes
        if [ -n "$(git status --porcelain)" ]; then
            print_warning "Local changes detected, stashing..."
            git stash
        fi

        git fetch origin
        git checkout main 2>/dev/null || git checkout master
        git pull origin HEAD
        print_success "Repository updated"
    else
        print_step "Cloning mcp-grafana repository..."
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone "$MCP_GRAFANA_REPO" "$INSTALL_DIR"
        print_success "Repository cloned to $INSTALL_DIR"
    fi

    # ============================================================================
    # Build mcp-grafana
    # ============================================================================
    print_header "Building mcp-grafana"

    cd "$INSTALL_DIR"
    print_step "Running make build..."

    if make build > /tmp/mcp-grafana-build.log 2>&1; then
        print_success "Built dist/mcp-grafana"
    else
        print_error "Build failed. See /tmp/mcp-grafana-build.log for details"
        tail -20 /tmp/mcp-grafana-build.log
        exit 1
    fi
fi

# ============================================================================
# Create Wrapper Script
# ============================================================================
print_header "Creating DuploCloud Wrapper Script"

WRAPPER_PATH="$INSTALL_DIR/dist/mcp-grafana-duplo"

print_step "Creating $WRAPPER_PATH"

cat > "$WRAPPER_PATH" << 'WRAPPER_EOF'
#!/bin/bash
#
# Wrapper script for mcp-grafana that authenticates via DuploCloud
# Generated by setup-grafana-mcp.sh from https://gitlab.com/ecfx/claude-mcp-setup
#

set -e

DUPLO_HOST="${DUPLO_HOST:-https://duplo.cloud.ecfxglobal.net}"

# Get DuploCloud token using duplo-jit
# The --interactive flag will use cached credentials or prompt for login
TOKEN_JSON=$(duplo-jit duplo --host "$DUPLO_HOST" --interactive 2>/dev/null)

if [ -z "$TOKEN_JSON" ]; then
    echo "Failed to get DuploCloud token." >&2
    echo "Try running: duplo-jit duplo --host $DUPLO_HOST --interactive" >&2
    exit 1
fi

# Extract the token from JSON response
DUPLO_TOKEN=$(echo "$TOKEN_JSON" | grep -o '"DuploToken":"[^"]*"' | cut -d'"' -f4)

if [ -z "$DUPLO_TOKEN" ]; then
    echo "Failed to parse DuploCloud token from response" >&2
    exit 1
fi

# Export as Grafana service account token (mcp-grafana uses this env var)
export GRAFANA_SERVICE_ACCOUNT_TOKEN="$DUPLO_TOKEN"

# Run mcp-grafana with all passed arguments
exec "$(dirname "$0")/mcp-grafana" "$@"
WRAPPER_EOF

chmod +x "$WRAPPER_PATH"
print_success "Created wrapper script"

# ============================================================================
# Test DuploCloud Authentication
# ============================================================================
print_header "Testing DuploCloud Authentication"

print_step "Getting DuploCloud token..."
if TOKEN_JSON=$(duplo-jit duplo --host "$DUPLO_HOST" --interactive 2>/dev/null); then
    DUPLO_TOKEN=$(echo "$TOKEN_JSON" | grep -o '"DuploToken":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$DUPLO_TOKEN" ]; then
        print_success "Successfully obtained DuploCloud token"

        # Test Grafana connectivity
        print_step "Testing Grafana API connectivity..."
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $DUPLO_TOKEN" \
            "$GRAFANA_URL/api/health" 2>/dev/null || echo "000")

        if [ "$HTTP_STATUS" = "200" ]; then
            print_success "Successfully connected to Grafana API"
        elif [ "$HTTP_STATUS" = "000" ]; then
            print_warning "Could not connect to Grafana (network issue?)"
        else
            print_warning "Grafana API returned HTTP $HTTP_STATUS"
        fi
    else
        print_warning "Token obtained but couldn't parse. Continuing anyway..."
    fi
else
    print_warning "Could not get token automatically."
    echo "         You may need to authenticate manually after setup:"
    echo "         duplo-jit duplo --host $DUPLO_HOST --interactive"
fi

# ============================================================================
# Configure Claude Code MCP
# ============================================================================
print_header "Configuring Claude Code MCP"

# Check if MCP already exists
EXISTING_MCP=$(claude mcp list 2>/dev/null | grep "^$MCP_NAME:" || true)
if [ -n "$EXISTING_MCP" ]; then
    if [ "$FORCE" = true ]; then
        print_step "Removing existing '$MCP_NAME' MCP configuration..."
        claude mcp remove "$MCP_NAME" --scope user > /dev/null 2>&1 || true
    else
        echo ""
        print_warning "MCP server '$MCP_NAME' already exists:"
        echo "         $EXISTING_MCP"
        echo ""
        read -p "Do you want to replace it? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_step "Removing existing configuration..."
            claude mcp remove "$MCP_NAME" --scope user > /dev/null 2>&1 || true
        else
            echo ""
            print_error "Setup cancelled. Use --force to overwrite automatically."
            exit 1
        fi
    fi
fi

# Build args array
ARGS="[]"
if [ "$DISABLE_WRITE" = true ]; then
    ARGS='["--disable-write"]'
fi

# Create the MCP configuration
print_step "Adding MCP server configuration..."

MCP_CONFIG=$(cat << EOF
{
  "command": "$WRAPPER_PATH",
  "args": $ARGS,
  "env": {
    "GRAFANA_URL": "$GRAFANA_URL",
    "DUPLO_HOST": "$DUPLO_HOST"
  }
}
EOF
)

if claude mcp add-json "$MCP_NAME" "$MCP_CONFIG" --scope user > /dev/null 2>&1; then
    print_success "Added MCP server '$MCP_NAME' to user configuration"
else
    print_error "Failed to add MCP configuration"
    exit 1
fi

# ============================================================================
# Verify Setup
# ============================================================================
print_header "Verifying Setup"

print_step "Checking MCP server status..."
echo ""

MCP_STATUS=$(claude mcp list 2>/dev/null | grep -E "^$MCP_NAME:" || true)
if [ -n "$MCP_STATUS" ]; then
    echo "  $MCP_STATUS"
    echo ""
    if echo "$MCP_STATUS" | grep -q "✓ Connected"; then
        print_success "MCP server is connected and ready"
    else
        print_warning "MCP server configured but may need authentication"
    fi
else
    print_warning "Could not verify MCP status"
fi

# ============================================================================
# Done!
# ============================================================================
print_header "Setup Complete!"

cat << EOF
${GREEN}The Grafana MCP is now configured for Claude Code.${NC}

${YELLOW}Next steps:${NC}
  1. Start a ${BLUE}new${NC} Claude Code session (existing sessions won't see the change)
  2. Try asking Claude:
     - "List my Grafana dashboards"
     - "Show me the datasources"
     - "Search for dashboards about kubernetes"
     - "Query Prometheus for up metric"

${YELLOW}Configuration:${NC}
  Grafana URL:    $GRAFANA_URL
  DuploCloud:     $DUPLO_HOST
  Read-only mode: $DISABLE_WRITE
  Install dir:    $INSTALL_DIR
  Wrapper script: $WRAPPER_PATH

${YELLOW}Useful commands:${NC}
  claude mcp list                         # Check MCP status
  claude mcp remove grafana --scope user  # Remove configuration

${YELLOW}To update:${NC}
  $(dirname "$0")/$(basename "$0") --force

${YELLOW}Troubleshooting:${NC}
  If you see authentication errors, re-authenticate with DuploCloud:
  duplo-jit duplo --host $DUPLO_HOST --interactive

See docs/grafana-mcp.md for detailed documentation.
EOF
