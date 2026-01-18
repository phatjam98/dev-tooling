#!/usr/bin/env bash
#
# sync-ecfx.sh - Sync development directories between Mac-Studio and MacBookPro
#
# Usage: ./sync-ecfx.sh <command> [options]
#
# Commands:
#   push    - Push from current machine to remote
#   pull    - Pull from remote to current machine
#   status  - Dry-run preview of changes
#
# Options:
#   --target=ecfx|dotfiles|all  - What to sync (default: ecfx)
#   --force                     - Skip git dirty warnings
#   --yes                       - Skip confirmation prompt
#   -v, --verbose              - Verbose output
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${SCRIPT_DIR}/.sync.lock"

# Machine hostnames
MAC_STUDIO_HOSTNAME="Mac-Studio"
MACBOOK_PRO_HOSTNAME="MacBookPro"

# SSH host aliases (must match ~/.ssh/config)
MAC_STUDIO_SSH="mac-studio"
MACBOOK_PRO_SSH="macbook-pro"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# =============================================================================
# Sync Target Definitions
# =============================================================================

# ecfx target
ECFX_LOCAL_PATH="$HOME/ecfx/"
ECFX_EXCLUDE_FILE="${SCRIPT_DIR}/excludes/ecfx.exclude"

# dotfiles target
DOTFILES_EXCLUDE_FILE="${SCRIPT_DIR}/excludes/dotfiles.exclude"
DOTFILES_PATHS=(
    "$HOME/.claude/"
    "$HOME/.claude-components/"
    "$HOME/.kube/"
    "$HOME/.aws/"
    "$HOME/.zshrc"
)

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"
}

# Print usage information
usage() {
    cat << EOF
${BOLD}sync-ecfx.sh${NC} - Sync development directories between machines

${BOLD}USAGE:${NC}
    ./sync-ecfx.sh <command> [options]

${BOLD}COMMANDS:${NC}
    push      Push from current machine to remote
    pull      Pull from remote to current machine
    status    Dry-run preview of changes (no modifications)

${BOLD}OPTIONS:${NC}
    --target=<target>   What to sync: ecfx, dotfiles, or all (default: ecfx)
    --force             Skip git dirty warnings
    --yes               Skip confirmation prompt
    -v, --verbose       Verbose rsync output

${BOLD}TARGETS:${NC}
    ecfx       ~/ecfx/ directory (GitLab projects)
    dotfiles   ~/.claude/, ~/.claude-components/, ~/.kube/, ~/.aws/, ~/.zshrc
    all        Both ecfx and dotfiles

${BOLD}EXAMPLES:${NC}
    ./sync-ecfx.sh status                    # Preview ecfx changes
    ./sync-ecfx.sh push --target=ecfx        # Push ecfx to remote
    ./sync-ecfx.sh pull --target=dotfiles    # Pull dotfiles from remote
    ./sync-ecfx.sh push --target=all --yes   # Push everything, skip confirmation

EOF
    exit 1
}

# Detect current machine
detect_machine() {
    local hostname
    hostname=$(hostname -s)

    case "$hostname" in
        "$MAC_STUDIO_HOSTNAME")
            CURRENT_MACHINE="Mac-Studio"
            REMOTE_SSH="$MACBOOK_PRO_SSH"
            REMOTE_NAME="MacBookPro"
            ;;
        "$MACBOOK_PRO_HOSTNAME")
            CURRENT_MACHINE="MacBookPro"
            REMOTE_SSH="$MAC_STUDIO_SSH"
            REMOTE_NAME="Mac-Studio"
            ;;
        *)
            log_error "Unknown machine: $hostname"
            log_error "Expected: $MAC_STUDIO_HOSTNAME or $MACBOOK_PRO_HOSTNAME"
            exit 1
            ;;
    esac

    log_info "Current machine: ${BOLD}$CURRENT_MACHINE${NC}"
    log_info "Remote machine: ${BOLD}$REMOTE_NAME${NC} (via ssh $REMOTE_SSH)"
}

# Check SSH connectivity
check_ssh() {
    log_info "Checking SSH connectivity to $REMOTE_SSH..."

    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_SSH" "echo 'SSH OK'" &>/dev/null; then
        log_error "Cannot connect to $REMOTE_SSH"
        log_error "Please ensure:"
        log_error "  1. The remote machine is on and awake"
        log_error "  2. SSH is configured in ~/.ssh/config"
        log_error "  3. SSH keys are set up for passwordless login"
        exit 1
    fi

    log_success "SSH connection verified"
}

# Check for lock file (prevent concurrent syncs)
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another sync is in progress (PID: $lock_pid)"
            exit 1
        else
            log_warn "Stale lock file found, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
}

# Create lock file
create_lock() {
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# Check for uncommitted git changes in a directory
check_git_dirty() {
    local dir="$1"
    local force="$2"

    if [[ ! -d "$dir/.git" ]]; then
        return 0
    fi

    local dirty_count
    dirty_count=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$dirty_count" -gt 0 ]]; then
        log_warn "Directory has uncommitted changes: $dir"
        if [[ "$force" != "true" ]]; then
            log_warn "Use --force to sync anyway, or commit changes first"
            return 1
        fi
        log_warn "Proceeding anyway (--force specified)"
    fi

    return 0
}

# Check all git repos in ecfx directory
check_ecfx_git_status() {
    local force="$1"
    local dirty_repos=()

    log_info "Checking for uncommitted git changes in ~/ecfx/..."

    while IFS= read -r -d '' gitdir; do
        local repo_dir
        repo_dir=$(dirname "$gitdir")
        local dirty_count
        dirty_count=$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$dirty_count" -gt 0 ]]; then
            dirty_repos+=("$repo_dir")
        fi
    done < <(find "$HOME/ecfx" -maxdepth 3 -name ".git" -type d -print0 2>/dev/null)

    if [[ ${#dirty_repos[@]} -gt 0 ]]; then
        log_warn "Found ${#dirty_repos[@]} repo(s) with uncommitted changes:"
        for repo in "${dirty_repos[@]}"; do
            echo "  - $repo"
        done

        if [[ "$force" != "true" ]]; then
            log_warn "Use --force to sync anyway, or commit changes first"
            return 1
        fi
        log_warn "Proceeding anyway (--force specified)"
    else
        log_success "All git repos are clean"
    fi

    return 0
}

# Build rsync command for a single path
build_rsync_cmd() {
    local source="$1"
    local dest="$2"
    local exclude_file="$3"
    local dry_run="$4"
    local verbose="$5"

    local cmd="rsync -auzvP --delete"

    if [[ -f "$exclude_file" ]]; then
        cmd+=" --exclude-from='$exclude_file'"
    fi

    if [[ "$dry_run" == "true" ]]; then
        cmd+=" --dry-run"
    fi

    if [[ "$verbose" == "true" ]]; then
        cmd+=" --verbose"
    fi

    cmd+=" '$source' '$dest'"

    echo "$cmd"
}

# Execute sync for ecfx target
sync_ecfx() {
    local command="$1"
    local dry_run="$2"
    local verbose="$3"

    local local_path="$ECFX_LOCAL_PATH"
    local exclude_file="$ECFX_EXCLUDE_FILE"

    if [[ ! -d "$local_path" ]]; then
        log_error "Local path does not exist: $local_path"
        return 1
    fi

    local source dest
    if [[ "$command" == "push" ]]; then
        source="$local_path"
        dest="${REMOTE_SSH}:${local_path}"
    else
        source="${REMOTE_SSH}:${local_path}"
        dest="$local_path"
    fi

    log_header "Syncing ecfx ($command)"
    echo "Source: $source"
    echo "Dest:   $dest"
    echo "Exclude: $exclude_file"
    echo ""

    local cmd
    cmd=$(build_rsync_cmd "$source" "$dest" "$exclude_file" "$dry_run" "$verbose")

    if [[ "$verbose" == "true" ]]; then
        log_info "Command: $cmd"
    fi

    eval "$cmd"
}

# Execute sync for dotfiles target
sync_dotfiles() {
    local command="$1"
    local dry_run="$2"
    local verbose="$3"

    local exclude_file="$DOTFILES_EXCLUDE_FILE"

    log_header "Syncing dotfiles ($command)"

    for local_path in "${DOTFILES_PATHS[@]}"; do
        if [[ ! -e "$local_path" ]]; then
            log_warn "Skipping (not found): $local_path"
            continue
        fi

        local source dest
        if [[ "$command" == "push" ]]; then
            source="$local_path"
            dest="${REMOTE_SSH}:${local_path}"
        else
            source="${REMOTE_SSH}:${local_path}"
            dest="$local_path"
        fi

        echo ""
        log_info "Syncing: $local_path"
        echo "Source: $source"
        echo "Dest:   $dest"

        local cmd
        cmd=$(build_rsync_cmd "$source" "$dest" "$exclude_file" "$dry_run" "$verbose")

        if [[ "$verbose" == "true" ]]; then
            log_info "Command: $cmd"
        fi

        eval "$cmd"
    done
}

# Show summary before sync
show_summary() {
    local command="$1"
    local target="$2"

    echo ""
    echo -e "${BOLD}${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}│           Sync Summary                          │${NC}"
    echo -e "${BOLD}${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  Command:    ${BOLD}$command${NC}"
    echo -e "  Target:     ${BOLD}$target${NC}"
    echo -e "  Direction:  ${BOLD}$CURRENT_MACHINE${NC} → ${BOLD}$REMOTE_NAME${NC}"
    echo ""

    case "$target" in
        ecfx)
            echo "  Paths:"
            echo "    - ~/ecfx/"
            ;;
        dotfiles)
            echo "  Paths:"
            for path in "${DOTFILES_PATHS[@]}"; do
                echo "    - $path"
            done
            ;;
        all)
            echo "  Paths:"
            echo "    - ~/ecfx/"
            for path in "${DOTFILES_PATHS[@]}"; do
                echo "    - $path"
            done
            ;;
    esac
    echo ""
}

# Confirm with user
confirm() {
    local prompt="$1"
    local skip_confirm="$2"

    if [[ "$skip_confirm" == "true" ]]; then
        return 0
    fi

    echo -e -n "${YELLOW}$prompt [y/N]: ${NC}"
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    # Default values
    local command=""
    local target="ecfx"
    local force="false"
    local skip_confirm="false"
    local verbose="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            push|pull|status)
                command="$1"
                ;;
            --target=*)
                target="${1#*=}"
                ;;
            --force)
                force="true"
                ;;
            --yes)
                skip_confirm="true"
                ;;
            -v|--verbose)
                verbose="true"
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done

    # Validate command
    if [[ -z "$command" ]]; then
        log_error "No command specified"
        usage
    fi

    # Validate target
    case "$target" in
        ecfx|dotfiles|all)
            ;;
        *)
            log_error "Invalid target: $target"
            log_error "Valid targets: ecfx, dotfiles, all"
            exit 1
            ;;
    esac

    # Check for lock
    check_lock
    create_lock

    # Detect machine and set remote
    detect_machine

    # Check SSH connectivity
    check_ssh

    # Check git status for ecfx
    if [[ "$target" == "ecfx" || "$target" == "all" ]]; then
        if ! check_ecfx_git_status "$force"; then
            exit 1
        fi
    fi

    # Determine if this is a dry run
    local dry_run="false"
    if [[ "$command" == "status" ]]; then
        dry_run="true"
        log_info "DRY RUN MODE - No changes will be made"
    fi

    # For status command, use push direction for display
    local sync_command="$command"
    if [[ "$command" == "status" ]]; then
        sync_command="push"
    fi

    # Show summary
    show_summary "$sync_command" "$target"

    # Confirm (unless dry run or --yes)
    if [[ "$dry_run" != "true" ]]; then
        if ! confirm "Proceed with sync?" "$skip_confirm"; then
            log_info "Sync cancelled"
            exit 0
        fi
    fi

    # Execute sync
    local sync_failed="false"

    case "$target" in
        ecfx)
            if ! sync_ecfx "$sync_command" "$dry_run" "$verbose"; then
                sync_failed="true"
            fi
            ;;
        dotfiles)
            if ! sync_dotfiles "$sync_command" "$dry_run" "$verbose"; then
                sync_failed="true"
            fi
            ;;
        all)
            if ! sync_ecfx "$sync_command" "$dry_run" "$verbose"; then
                sync_failed="true"
            fi
            if ! sync_dotfiles "$sync_command" "$dry_run" "$verbose"; then
                sync_failed="true"
            fi
            ;;
    esac

    # Final status
    echo ""
    if [[ "$dry_run" == "true" ]]; then
        log_success "Dry run complete. No changes were made."
    elif [[ "$sync_failed" == "true" ]]; then
        log_error "Sync completed with errors"
        exit 1
    else
        log_success "Sync completed successfully!"
    fi
}

main "$@"
