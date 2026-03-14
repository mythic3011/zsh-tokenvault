# TokenVault Quick Reference

## Vault Management

```bash
tv-unlock              # Unlock vault (enter master password)
tv-lock                # Lock vault (clear master key from memory)
tv-unsafe              # Toggle unsafe mode (save password to disk)
```

## Profile Management

```bash
tv-add                 # Add profile (interactive)
tv-add -ID id \
  -Prov anthropic|openai|gemini|custom \
  -Auth key|cli \
  -Base url \
  -QuotaAPI url \
  -Reset daily|payg \
  -Key api-key \
  -Model model-id     # Add profile (CLI)

tv-remove [id]         # Remove profile
tv-list                # List all profiles
tv-dash                # Dashboard with quota status
```

## Command Execution

```bash
tv-run <id> <cmd>      # Run command with named profile
tv-run auto <cmd>      # Auto-select best key per provider
tv-report [id]         # Mark profile as exhausted
```

## Model Management

```bash
tv-model-set           # Set default model (interactive)
tv-model-set \
  -Prov anthropic|openai|gemini|custom \
  -Tier haiku|sonnet|opus|subagent|default \
  -Model model-id      # Set provider-level default

tv-model-set \
  -Profile id \
  -Model model-id      # Set profile-level override

tv-model-list          # List available models (interactive)
tv-model-list -Prov anthropic|openai|gemini|custom
tv-model-list -Profile id
```

## Codex Integration

```bash
tv-codex-sync          # Sync Codex config (interactive)
tv-codex-sync \
  -Config path \
  -Force \
  -DryRun \
  -AllowWireApi \
  -Yes                 # Sync with options
```

## Help

```bash
tv-help                # Show all commands
```

## Tab Completion

```bash
tv-<TAB>               # Complete command names
tv-add -<TAB>          # Complete flags
tv-add -Prov <TAB>     # Complete provider options
tv-add -Auth <TAB>     # Complete auth modes
tv-add -Reset <TAB>    # Complete reset types
tv-model-set -Tier <TAB>  # Complete model tiers
tv-run <TAB>           # Complete profile names
```

## Common Workflows

### Add Anthropic Profile

```bash
tv-unlock
tv-add -ID claude \
  -Prov anthropic \
  -Auth key \
  -Key sk-ant-... \
  -Model claude-sonnet
tv-run claude python script.py
```

### Add OpenAI Profile

```bash
tv-unlock
tv-add -ID gpt \
  -Prov openai \
  -Auth key \
  -Key sk-... \
  -Model gpt-4
tv-run gpt python script.py
```

### Use Multiple Providers

```bash
tv-unlock
tv-add -ID claude -Prov anthropic -Auth key -Key sk-ant-...
tv-add -ID gpt -Prov openai -Auth key -Key sk-...
tv-run auto python multi_provider_script.py
```

### Check Quota Status

```bash
tv-dash
```

### Set Default Models

```bash
tv-unlock
tv-model-set -Prov anthropic -Tier sonnet -Model claude-3-5-sonnet-20241022
tv-model-set -Profile claude -Model claude-3-5-sonnet-20241022
```

### Sync Codex Config

```bash
tv-unlock
tv-codex-sync -Config ~/.codex/config.toml -Yes
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `TV_DIR` | Config directory (default: `~/.config/tokenvault`) |
| `TV_CACHE_DIR` | Cache directory (default: `~/.cache/tokenvault`) |
| `TV_LANG` | Language (en, zh_cn, zh_hk, zh_tw) |
| `CODEX_CONFIG` | Path to Codex config |
| `CODEX_HOME` | Codex home directory |

## File Locations

```
~/.config/tokenvault/
├── profiles.json       # Profile metadata
├── models.json         # Model defaults
├── usage.jsonl         # Usage log
├── vault.enc           # Encrypted keys
└── .unsafe_pass        # Master password (unsafe mode only)

~/.cache/tokenvault/
├── .prompt_rendered    # Cached prompt
└── .worker.lock        # Worker lock
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "command not found: tv-*" | Run `exec zsh` to reload shell |
| "Run tv-unlock first" | Run `tv-unlock` and enter master password |
| Tab completion not working | Run `exec zsh` to reload shell |
| "Missing dependency: jq" | Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux) |
| "Invalid ID" | Use only letters, numbers, `_`, or `-` |

## Keyboard Shortcuts

In interactive prompts:
- `Enter` - Accept default or selection
- `Ctrl+C` - Cancel operation
- `Ctrl+U` - Clear line
- `Ctrl+W` - Delete word

## Tips & Tricks

### Use `auto` for Multi-Provider Scripts

```bash
# Automatically injects all active keys
tv-run auto python script.py
```

### Check Key Status

```bash
# Shows remaining quota per provider
tv-dash
```

### Mark Key as Exhausted

```bash
# When you hit rate limits
tv-report myprofile
```

### Lock Vault When Away

```bash
# Clear master key from memory
tv-lock
```

### View All Profiles

```bash
# Simple list
tv-list

# Detailed dashboard
tv-dash
```

## Security Reminders

- ✓ Master password never written to disk (unless unsafe mode)
- ✓ API keys encrypted with AES-256-CBC + PBKDF2
- ✓ Lock vault when stepping away: `tv-lock`
- ✓ Don't use unsafe mode in production
- ✓ Keep master password secure

## More Information

- Full documentation: [INSTALL.md](INSTALL.md)
- Development guide: [DEVELOPMENT.md](DEVELOPMENT.md)
- Version history: [CHANGELOG.md](CHANGELOG.md)
- Main README: [README.md](README.md)
