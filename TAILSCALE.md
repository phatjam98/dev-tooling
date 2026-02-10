# Tailscale Setup Guide

Tailscale creates a secure mesh VPN between Mac-Studio and MacBookPro, enabling connectivity from anywhere.

## Why Tailscale?

- **Works anywhere**: Connect to Mac-Studio from coffee shop, office, or home
- **No port forwarding**: Works through NAT and firewalls
- **MagicDNS**: Use simple hostnames (`mac-studio`, `macbook-pro`) instead of IP addresses
- **Automatic reconnection**: Handles network changes gracefully

## Installation

### Mac App Store (Recommended)

1. Open Mac App Store
2. Search for "Tailscale"
3. Install and open
4. Sign in (use same account on both machines)

### Homebrew (Alternative)

```bash
brew install --cask tailscale
```

Note: The CLI-only install (`brew install tailscale`) requires manual daemon management. The Mac App Store or cask version handles this automatically.

## Setup Steps

### Step 1: Install on Both Machines

Install Tailscale on Mac-Studio and MacBookPro using the same method.

### Step 2: Sign In

Sign in with the same identity provider (GitHub, Google, Apple, etc.) on **both machines**.

### Step 3: Verify Connection

```bash
# Check Tailscale status
tailscale status

# Should show both machines, e.g.:
# 100.x.x.x   mac-studio       traviscarter@  macOS   -
# 100.y.y.y   macbook-pro      traviscarter@  macOS   -
```

### Step 4: Test Connectivity

```bash
# From Mac-Studio
tailscale ping macbook-pro

# From MacBook Pro
tailscale ping mac-studio
```

## MagicDNS Hostnames

Tailscale automatically assigns DNS names based on your machine hostname:

| Machine | Tailscale Hostname |
|---------|-------------------|
| Mac Studio | `mac-studio` |
| MacBook Pro | `macbook-pro` |

These hostnames work from anywhere in your Tailscale network.

## SSH Configuration

Update `~/.ssh/config` to use Tailscale hostnames for reliable connectivity:

```
# mac-studio (via Tailscale)
Host mac-studio
    HostName mac-studio
    User traviscarter
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

# macbook-pro (via Tailscale)
Host macbook-pro
    HostName macbook-pro
    User traviscarter
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519
```

**Key change**: `HostName` now uses Tailscale MagicDNS name (e.g., `mac-studio`) instead of `.local` Bonjour name (e.g., `Mac-Studio.local`).

### Test SSH

```bash
ssh mac-studio "hostname"
ssh macbook-pro "hostname"
```

## Workflow Options

### Option A: Remote Development (Recommended for daily work)

Work directly on Mac-Studio files from MacBook using VS Code Remote-SSH or JetBrains Gateway.

**VS Code Remote-SSH:**
1. Install "Remote - SSH" extension
2. Press `Cmd+Shift+P` → "Remote-SSH: Connect to Host"
3. Select `mac-studio`
4. Open folders directly on Mac-Studio

**Benefits:**
- Single source of truth
- No sync conflicts
- Works over any network via Tailscale

### Option B: Rsync Sync (For offline work)

Use the sync script when you need a local copy (travel, unreliable network):

```bash
# Before going offline
./sync-ecfx.sh pull --target=all

# After returning online
./sync-ecfx.sh push --target=all
```

### Hybrid Approach (Best of both)

- **Daily work**: Remote development via VS Code Remote-SSH
- **Travel/offline**: Rsync pull before disconnecting
- **Dotfiles**: Always keep synced on both machines

## Troubleshooting

### Tailscale Not Connected

```bash
# Check status
tailscale status

# If "Logged out", authenticate:
# Open Tailscale from menu bar → Log in
```

### MagicDNS Not Resolving

```bash
# Check if MagicDNS is enabled
tailscale debug netmap | grep DNS

# Try the Tailscale IP directly
tailscale status  # Get IP (100.x.x.x)
ssh traviscarter@100.x.x.x
```

### SSH Connection Refused

1. Ensure "Remote Login" is enabled on target machine:
   - System Settings → Sharing → Remote Login → On

2. Check Tailscale is connected on both machines

3. Test with Tailscale IP:
   ```bash
   tailscale ip -4 mac-studio  # Get IP
   ssh traviscarter@<ip>
   ```

### Slow Connection

Tailscale uses direct connections when possible, but may relay through DERP servers if direct path fails.

```bash
# Check connection path
tailscale ping mac-studio

# Should show "pong from mac-studio via direct"
# If it shows "via DERP", there may be NAT issues
```

## Security Notes

- Tailscale uses WireGuard encryption
- Only devices signed into your Tailscale account can connect
- No ports exposed to public internet
- Access control can be configured in Tailscale admin console

## Useful Commands

```bash
# Show connected devices
tailscale status

# Ping another device
tailscale ping <hostname>

# Get Tailscale IP of a device
tailscale ip -4 <hostname>

# Show network information
tailscale netcheck

# Check debug info
tailscale debug
```

## Related Files

- `~/.ssh/config` - SSH configuration with Tailscale hostnames
- `~/dev-tooling/sync-ecfx.sh` - Rsync script for offline sync
