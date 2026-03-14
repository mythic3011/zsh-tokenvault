# TokenVault Installation & Setup Guide

## Prerequisites

TokenVault requires:
- `zsh` (shell)
- `jq` (JSON processor)
- `openssl` (encryption)
- `python3` (TOML parsing)

Verify installation:
```bash
command -v zsh jq openssl python3
```

## Installation

### oh-my-zsh

Clone into your custom plugins directory:

```bash
git clone https://github.com/mythic3011/zsh-tokenvault \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/tokenvault
```

Add to `~/.zshrc`:
```zsh
plugins=(
    # ... other plugins ...
    tokenvault
)
```

Reload your shell:
```bash
exec zsh
```

### Other Plugin Managers

The plugin entrypoint is `tokenvault.plugin.zsh`. Configure your plugin manager to source this file from the repository root.

**Example (zplug):**
```zsh
zplug "mythic3011/zsh-tokenvault", from:github, as:plugin
```

## Quick Start

### 1. Unlock the Vault

```bash
tv-unlock
```

Enter your master password (used to encrypt stored API keys).

### 2. Add Your First Profile

Interactive mode:
```bash
tv-add
```

Or CLI mode:
```bash
tv-add -ID myprofile -Prov anthropic -Auth key -Key sk-ant-... -Model claude-sonnet
```

**Supported providers:** `anthropic`, `openai`, `gemini`, `custom`

### 3. Run Commands

With a named profile:
```bash
tv-run myprofile python script.py
```

Auto-select best key per provider:
```bash
tv-run auto python script.py
```

### 4. View Your Setup

```bash
tv-list          # List all profiles
tv-dash          # Dashboard with quota status
tv-help          # Show all commands
```

## Tab Completion

TokenVault includes full zsh tab completion. No additional setup needed!

### Examples

**Complete command names:**
```bash
tv-<TAB>
# Shows: tv-unlock, tv-lock, tv-add, tv-remove, tv-list, tv-dash, tv-run, ...
```

**Complete flags:**
```bash
tv-add -<TAB>
# Shows: -ID, -Prov, -Auth, -Base, -QuotaAPI, -Reset, -Key, -Model
```

**Complete provider options:**
```bash
tv-add -Prov <TAB>
# Shows: anthropic, openai, gemini, custom
```

**Complete profile names:**
```bash
tv-run <TAB>
# Shows: auto, profile1, profile2, ...
```

**Complete auth modes:**
```bash
tv-add -Auth <TAB>
# Shows: key, cli
```

**Complete reset types:**
```bash
tv-add -Reset <TAB>
# Shows: daily, payg
```

**Complete model tiers (Anthropic):**
```bash
tv-model-set -Tier <TAB>
# Shows: haiku, sonnet, opus, subagent, default
```

## Common Workflows

### Anthropic (Claude)

```bash
# Add profile
tv-add -ID claude -Prov anthropic -Auth key -Key sk-ant-... -Model claude-sonnet

# Run with Claude
tv-run claude python my_script.py

# Set default model tier
tv-model-set -Prov anthropic -Tier sonnet -Model claude-3-5-sonnet-20241022
```

### OpenAI

```bash
# Add profile
tv-add -ID openai -Prov openai -Auth key -Key sk-... -Model gpt-4

# Run with OpenAI
tv-run openai python my_script.py

# List available models
tv-model-list -Prov openai
```

### Multiple Providers

```bash
# Add multiple profiles
tv-add -ID claude -Prov anthropic -Auth key -Key sk-ant-...
tv-add -ID gpt -Prov openai -Auth key -Key sk-...

# Auto-select best key per provider
tv-run auto python multi_provider_script.py
```

### Proxy/Custom Base URL

```bash
tv-add -ID custom \
  -Prov custom \
  -Auth key \
  -Base https://api.example.com/v1 \
  -Key your-api-key \
  -Model your-model
```

## Vault Management

### Lock/Unlock

```bash
tv-unlock    # Unlock vault (enter master password)
tv-lock      # Lock vault (clear master key from memory)
```

### Unsafe Mode (Development Only)

Save master password to disk (NOT recommended for production):
```bash
tv-unsafe    # Toggle unsafe mode
```

### View Profiles

```bash
tv-list      # Simple list
tv-dash      # Dashboard with quota status
```

### Remove Profile

```bash
tv-remove myprofile
```

## Quota Management

### Check Quota Status

```bash
tv-dash      # Shows remaining quota per provider
```

### Report Exhausted Key

When a key hits rate limits:
```bash
tv-report myprofile
```

This marks the profile as exhausted and auto-selects the next best key.

### Codex Sync

Mirror Codex configuration into TokenVault:
```bash
tv-codex-sync -Config ~/.codex/config.toml
```

## Troubleshooting

### "command not found: tv-*"

**Problem:** Plugin not loaded.

**Solution:**
1. Verify plugin is in `~/.oh-my-zsh/custom/plugins/tokenvault`
2. Check `~/.zshrc` includes `tokenvault` in `plugins=()`
3. Run `exec zsh` to reload shell

### "Run tv-unlock first"

**Problem:** Vault is locked.

**Solution:**
```bash
tv-unlock
```

### Tab completion not working

**Problem:** Completion not registered.

**Solution:**
1. Verify zsh is interactive: `[[ -o interactive ]] && echo yes`
2. Check compdef is available: `typeset -f compdef`
3. Reload shell: `exec zsh`

### "Missing dependency: jq"

**Problem:** jq not installed.

**Solution:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Fedora
sudo dnf install jq
```

### "Invalid ID"

**Problem:** Profile ID contains invalid characters.

**Solution:** Use only letters, numbers, `_`, or `-`:
```bash
# ✗ Invalid
tv-add -ID my-profile@1

# ✓ Valid
tv-add -ID my-profile-1
```

## Testing

Run the full test suite:
```bash
./build.sh local
```

Run in Docker:
```bash
./build.sh docker
```

Tests verify:
- Syntax correctness
- Plugin loading
- Profile encryption/decryption
- Command execution
- Model management
- Codex sync
- Quota tracking

## Environment Variables

TokenVault respects these environment variables:

| Variable | Purpose |
|----------|---------|
| `TV_DIR` | Config directory (default: `~/.config/tokenvault`) |
| `TV_CACHE_DIR` | Cache directory (default: `~/.cache/tokenvault`) |
| `TV_LANG` | Language for UI (en, zh_cn, zh_hk, zh_tw) |
| `CODEX_CONFIG` | Path to Codex config for sync |
| `CODEX_HOME` | Codex home directory |

## File Structure

```
~/.config/tokenvault/
├── profiles.json      # Profile metadata (unencrypted)
├── models.json        # Model defaults per provider
├── usage.jsonl        # Usage log (one JSON per line)
├── vault.enc          # Encrypted API keys
└── .unsafe_pass       # Master password (only if unsafe mode enabled)

~/.cache/tokenvault/
├── .prompt_rendered   # Cached prompt output
└── .worker.lock       # Worker process lock
```

## Security Notes

- Master password is never written to disk (unless unsafe mode enabled)
- API keys are encrypted with AES-256-CBC + PBKDF2
- Each key is stored separately in the vault
- Profiles are stored in plaintext JSON (only keys are encrypted)
- Lock the vault when stepping away: `tv-lock`

## Support

For issues, questions, or feature requests:
- Check the [README](README.md)
- Review [troubleshooting](#troubleshooting) section
- Open an issue on GitHub
