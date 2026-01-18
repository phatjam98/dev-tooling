# Dev-Tooling

Development environment synchronization and remote access tools for Mac-Studio and MacBookPro.

## Overview

This repo provides:
- **Rsync sync script** - Mirror directories between machines for offline work
- **Tailscale setup** - Mesh VPN for secure remote access from anywhere

See [TAILSCALE.md](TAILSCALE.md) for network setup guide.

## Quick Start

```bash
# Preview what would sync (dry-run)
./sync-ecfx.sh status

# Push ecfx directory to remote machine
./sync-ecfx.sh push --target=ecfx

# Pull dotfiles from remote machine
./sync-ecfx.sh pull --target=dotfiles
```

## Commands

| Command | Description |
|---------|-------------|
| `push` | Push from current machine to remote |
| `pull` | Pull from remote to current machine |
| `status` | Dry-run preview of changes |

## Options

| Option | Description |
|--------|-------------|
| `--target=<target>` | What to sync: `ecfx`, `dotfiles`, or `all` (default: `ecfx`) |
| `--force` | Skip git dirty warnings |
| `--yes` | Skip confirmation prompt |
| `-v, --verbose` | Verbose rsync output |

## Sync Targets

| Target | Directories | Description |
|--------|-------------|-------------|
| `ecfx` | `~/ecfx/` | GitLab projects |
| `dotfiles` | `~/.claude/`, `~/.claude-components/`, `~/.kube/`, `~/.aws/`, `~/.zshrc` | Dev environment config |
| `all` | Both above | Full sync |

## Machine Configuration

| Machine | Hostname | SSH Alias |
|---------|----------|-----------|
| Mac Studio | `Mac-Studio` | `mac-studio` |
| MacBook Pro | `MacBookPro` | `macbook-pro` |

## SSH Setup

Add the following to `~/.ssh/config` on **both machines**:

### With Tailscale (Recommended)

Using Tailscale MagicDNS names works from anywhere:

```
Host mac-studio
    HostName mac-studio
    User traviscarter
    IdentityFile ~/.ssh/id_ed25519

Host macbook-pro
    HostName macbook-pro
    User traviscarter
    IdentityFile ~/.ssh/id_ed25519
```

### Local Network Only (Bonjour)

If you only need to connect on the same local network:

```
Host mac-studio
    HostName Mac-Studio.local
    User traviscarter
    IdentityFile ~/.ssh/id_ed25519

Host macbook-pro
    HostName MacBookPro.local
    User traviscarter
    IdentityFile ~/.ssh/id_ed25519
```

### Setting Up SSH Keys

If you haven't already, set up passwordless SSH:

```bash
# Generate key if needed
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy to other machine
ssh-copy-id mac-studio
# or
ssh-copy-id macbook-pro
```

### Test SSH Connection

```bash
ssh mac-studio "hostname"
ssh macbook-pro "hostname"
```

## Workflow Recommendations

### Starting Work on MacBook (away from home)

```bash
# Pull latest from Mac Studio before leaving
./sync-ecfx.sh pull --target=all
```

### Returning to Mac Studio

```bash
# Push changes made on MacBook
./sync-ecfx.sh push --target=all
```

### Before Major Syncs

1. Commit all git changes in `~/ecfx/` repos
2. Run `status` first to preview changes
3. Then run `push` or `pull`

## Exclude Patterns

### ecfx.exclude

Excludes common build artifacts and dependencies:
- `node_modules/` - Node.js dependencies
- `.terraform/`, `*.tfstate*` - Terraform state
- `target/`, `build/`, `.gradle/` - Java/Gradle build outputs
- `dist/` - Generic build outputs
- `.venv/`, `venv/`, `__pycache__/` - Python environments
- `.DS_Store` - macOS metadata

### dotfiles.exclude

Excludes cache and temporary files:
- `cache/`, `http-cache/` - Various caches
- `history.jsonl` - Command history
- `*.swp`, `*.swo` - Vim swap files

## Safety Features

- **Git dirty check**: Warns if repos have uncommitted changes
- **Confirmation prompt**: Asks before executing (use `--yes` to skip)
- **Dry-run mode**: `status` command previews without changes
- **Lock file**: Prevents concurrent sync operations
- **SSH validation**: Verifies connectivity before sync

## Troubleshooting

### SSH Connection Failed

1. Ensure remote machine is on and awake
2. Check `~/.ssh/config` has correct entries
3. Test with: `ssh mac-studio "echo ok"` or `ssh macbook-pro "echo ok"`
4. Ensure SSH keys are configured for passwordless login

### Unknown Machine Error

The script detects the current machine via `hostname -s`. Expected values:
- `Mac-Studio` for the Mac Studio
- `MacBookPro` for the MacBook Pro

### Lock File Issues

If you see "Another sync is in progress" but no sync is running:

```bash
rm ~/dev-tooling/.sync.lock
```

## File Structure

```
~/dev-tooling/
├── sync-ecfx.sh          # Main sync script
├── excludes/
│   ├── ecfx.exclude      # Exclude patterns for ~/ecfx/
│   └── dotfiles.exclude  # Exclude patterns for dotfiles
├── README.md
└── .gitignore
```
