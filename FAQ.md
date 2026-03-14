# Frequently Asked Questions (FAQ)

## Installation & Setup

### Q: How do I install TokenVault?

**A:** See [INSTALL.md](INSTALL.md) for detailed instructions. Quick version:

```bash
git clone https://github.com/mythic3011/zsh-tokenvault \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/tokenvault
```

Add to `~/.zshrc`:
```zsh
plugins=(tokenvault)
```

Then reload: `exec zsh`

### Q: What are the requirements?

**A:** TokenVault requires:
- `zsh` (shell)
- `jq` (JSON processor)
- `openssl` (encryption)
- `python3` (TOML parsing)

Verify: `command -v zsh jq openssl python3`

### Q: Can I use TokenVault with other plugin managers?

**A:** Yes! The plugin entrypoint is `tokenvault.plugin.zsh`. Configure your plugin manager to source this file from the repository root.

Examples:
- **zplug**: `zplug "mythic3011/zsh-tokenvault", from:github, as:plugin`
- **zinit**: `zinit light mythic3011/zsh-tokenvault`
- **antigen**: `antigen bundle mythic3011/zsh-tokenvault`

### Q: Does TokenVault work on macOS and Linux?

**A:** Yes! TokenVault works on both macOS and Linux. Some commands may differ slightly (e.g., `stat` flags), but the plugin handles this automatically.

## Usage & Commands

### Q: How do I add my first profile?

**A:** Run `tv-add` for interactive mode:

```bash
tv-unlock              # Unlock vault first
tv-add                 # Follow prompts
```

Or use CLI mode:
```bash
tv-add -ID myprofile -Prov anthropic -Auth key -Key sk-ant-... -Model claude-sonnet
```

### Q: What's the difference between `tv-run auto` and `tv-run <id>`?

**A:**
- `tv-run auto <cmd>` - Auto-selects the best key per provider based on remaining quota
- `tv-run <id> <cmd>` - Uses a specific named profile

Use `auto` when you have multiple keys and want the best one automatically selected.

### Q: How do I check my quota status?

**A:** Run `tv-dash` to see:
- All profiles with their status
- Remaining quota per provider
- Active providers

### Q: Can I use TokenVault with multiple providers?

**A:** Yes! Add profiles for each provider:

```bash
tv-add -ID claude -Prov anthropic -Auth key -Key sk-ant-...
tv-add -ID gpt -Prov openai -Auth key -Key sk-...
tv-run auto python script.py  # Uses both
```

### Q: How do I set a default model?

**A:** Use `tv-model-set`:

```bash
tv-model-set -Prov anthropic -Tier sonnet -Model claude-3-5-sonnet-20241022
```

Or for a specific profile:
```bash
tv-model-set -Profile myprofile -Model claude-sonnet
```

## Tab Completion

### Q: Why isn't tab completion working?

**A:** Try these steps:

1. Reload shell: `exec zsh`
2. Verify compdef is available: `zsh -c 'typeset -f compdef'`
3. Check completion function loaded: `zsh -c 'source tokenvault.plugin.zsh; typeset -f _tokenvault'`

### Q: How do I use tab completion?

**A:** Just press `<TAB>` after typing a command:

```bash
tv-<TAB>              # Show all commands
tv-add -<TAB>         # Show all flags
tv-add -Prov <TAB>    # Show providers
tv-run <TAB>          # Show profiles
```

### Q: Can I customize tab completion?

**A:** Yes! Edit `lib/completion.zsh` to add or modify completions. See [DEVELOPMENT.md](DEVELOPMENT.md) for details.

## Security & Encryption

### Q: How secure is TokenVault?

**A:** TokenVault uses:
- **AES-256-CBC** encryption for API keys
- **PBKDF2** key derivation
- **Random salt** for each encryption
- **Secure file permissions** (600 for files, 700 for directories)

Master password is never written to disk (unless unsafe mode enabled).

### Q: What is "unsafe mode"?

**A:** Unsafe mode saves your master password to disk (`~/.config/tokenvault/.unsafe_pass`). This is convenient but less secure. Only use in development environments.

Enable: `tv-unsafe`

### Q: Can someone access my keys if they have my computer?

**A:** If your vault is locked (`tv-lock`), they cannot access your keys without the master password.

If your vault is unlocked, they can access all keys. Always lock when stepping away: `tv-lock`

### Q: How do I rotate my API keys?

**A:**
1. Remove old profile: `tv-remove oldprofile`
2. Add new profile: `tv-add -ID newprofile -Prov ... -Key new-key-...`

Or update existing profile:
```bash
tv-add -ID myprofile -Prov anthropic -Auth key -Key new-key-...
```

### Q: Is my master password stored anywhere?

**A:** No, unless you enable unsafe mode. The master password is only kept in memory while the vault is unlocked.

## Troubleshooting

### Q: "command not found: tv-*"

**A:** The plugin didn't load. Try:

1. Verify plugin is installed: `ls ~/.oh-my-zsh/custom/plugins/tokenvault/`
2. Check `~/.zshrc` includes `tokenvault` in `plugins=()`
3. Reload shell: `exec zsh`

### Q: "Run tv-unlock first"

**A:** Your vault is locked. Unlock it:

```bash
tv-unlock
```

Enter your master password.

### Q: "Missing dependency: jq"

**A:** Install jq:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Fedora
sudo dnf install jq

# Alpine
apk add jq
```

### Q: "Invalid ID"

**A:** Profile IDs can only contain letters, numbers, `_`, or `-`.

```bash
# ✗ Invalid
tv-add -ID my-profile@1

# ✓ Valid
tv-add -ID my-profile-1
```

### Q: "Profile not found"

**A:** The profile doesn't exist. Check available profiles:

```bash
tv-list
```

### Q: "Could not fetch model list"

**A:** The API call failed. Check:

1. API key is correct
2. Network connection is working
3. API endpoint is accessible
4. Rate limits aren't exceeded

### Q: Tests fail with "nice(5) failed"

**A:** This is a harmless warning on systems without nice privilege. Tests still pass.

### Q: "Vault Locked" appears in prompt

**A:** Your vault is locked. Unlock it:

```bash
tv-unlock
```

## Performance & Optimization

### Q: Why is the first command slow?

**A:** The first command spawns a background worker to check quotas and render the prompt. Subsequent commands are faster.

### Q: Can I disable quota checking?

**A:** Yes, don't set a quota API URL when adding profiles:

```bash
tv-add -ID myprofile -Prov anthropic -Auth key -Key sk-ant-...
# Don't set -QuotaAPI
```

### Q: How often is the prompt updated?

**A:** The prompt cache is updated:
- Every 180 seconds (3 minutes)
- When the vault is locked/unlocked
- At midnight (daily reset)

## Advanced Usage

### Q: Can I use TokenVault with scripts?

**A:** Yes! Set `_TV_MASTER_KEY` before running commands:

```bash
export _TV_MASTER_KEY="your-master-password"
tv-run myprofile python script.py
```

Or use unsafe mode (not recommended for production).

### Q: Can I sync multiple machines?

**A:** Not directly. You can:

1. Copy `~/.config/tokenvault/` to another machine
2. Use the same master password
3. Profiles and keys will be available

**Warning:** This shares your encrypted vault. Keep it secure!

### Q: Can I backup my vault?

**A:** Yes! Backup these files:

```bash
~/.config/tokenvault/profiles.json
~/.config/tokenvault/models.json
~/.config/tokenvault/vault.enc
```

Keep backups secure (encrypted storage recommended).

### Q: Can I use TokenVault with CI/CD?

**A:** Yes! Set environment variables:

```bash
export TV_DIR="/tmp/tokenvault"
export _TV_MASTER_KEY="your-master-password"
tv-run myprofile python test.py
```

Or use unsafe mode in CI environment.

### Q: How do I integrate with Codex?

**A:** Use `tv-codex-sync`:

```bash
tv-unlock
tv-codex-sync -Config ~/.codex/config.toml
```

This mirrors Codex providers into TokenVault profiles.

## Development & Contributing

### Q: How do I contribute?

**A:** See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup
- Code style guidelines
- Testing requirements
- Pull request process

### Q: How do I report a bug?

**A:** Open an issue on GitHub with:
- Clear title
- Steps to reproduce
- Expected vs actual behavior
- Your environment (OS, zsh version, etc.)

### Q: How do I request a feature?

**A:** Open an issue on GitHub with:
- Clear title
- Use case and motivation
- Proposed implementation (if you have ideas)
- Examples of usage

### Q: Can I modify TokenVault for my needs?

**A:** Yes! TokenVault is open source. Fork it and customize as needed.

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and patterns.

## Miscellaneous

### Q: What's the difference between profiles and models?

**A:**
- **Profiles** - Named API key configurations (e.g., "claude", "gpt")
- **Models** - Default model IDs per provider or profile

### Q: Can I have multiple keys for the same provider?

**A:** Yes! Create multiple profiles:

```bash
tv-add -ID claude-1 -Prov anthropic -Auth key -Key sk-ant-key1-...
tv-add -ID claude-2 -Prov anthropic -Auth key -Key sk-ant-key2-...
tv-run auto python script.py  # Uses best one
```

### Q: What happens when a key is exhausted?

**A:** If quota checking is enabled:
1. Status changes to "exhausted"
2. `tv-run auto` skips it and uses next best key
3. Mark as exhausted manually: `tv-report myprofile`

### Q: Can I use TokenVault without a master password?

**A:** No, the master password is required to encrypt/decrypt keys.

### Q: How do I uninstall TokenVault?

**A:**
1. Remove from `~/.zshrc`: Remove `tokenvault` from `plugins=()`
2. Delete plugin directory: `rm -rf ~/.oh-my-zsh/custom/plugins/tokenvault`
3. Delete config: `rm -rf ~/.config/tokenvault`
4. Reload shell: `exec zsh`

### Q: Is TokenVault open source?

**A:** Yes! See the repository for license details.

### Q: How do I get help?

**A:**
- Check [INSTALL.md](INSTALL.md) for setup help
- Check [QUICKREF.md](QUICKREF.md) for command reference
- Check [DEVELOPMENT.md](DEVELOPMENT.md) for architecture
- Open an issue on GitHub
- Check existing issues for similar problems

## Still Have Questions?

- Check the [README](README.md)
- Check the [Installation Guide](INSTALL.md)
- Check the [Quick Reference](QUICKREF.md)
- Check the [Development Guide](DEVELOPMENT.md)
- Open an issue on GitHub
