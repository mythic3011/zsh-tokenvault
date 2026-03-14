# TokenVault

Zsh plugin for managing provider API keys, profile-scoped defaults, model selection, and command execution through an encrypted local vault.

## Features

- **Encrypted Vault**: AES-256-CBC encryption for API keys with PBKDF2
- **Tab Completion**: Full zsh completion for all commands and flags (no need to memorize syntax)
- **Multi-Provider**: Support for Anthropic, OpenAI, Gemini, and custom providers
- **Profile Management**: Profile-scoped defaults and model selection
- **Quota Tracking**: Real-time quota status and exhaustion detection
- **Async Operations**: Background worker for quota checks and prompt rendering
- **Modular Design**: Separate modules for config, auth, UI, models, and commands
- **Multi-Language**: English, Simplified Chinese, Traditional Chinese support

## Quick Start

```bash
# 1. Unlock vault
tv-unlock

# 2. Add a profile
tv-add -ID myprofile -Prov anthropic -Auth key -Key sk-ant-... -Model claude-sonnet

# 3. Run commands
tv-run myprofile python script.py

# 4. View status
tv-dash
```

**Tab completion works everywhere:**
```bash
tv-<TAB>              # Show all commands
tv-add -<TAB>         # Show all flags
tv-add -Prov <TAB>    # Show providers
tv-run <TAB>          # Show profiles
```

## Documentation

- **[INSTALL.md](INSTALL.md)** - Complete installation and setup guide with examples
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and recent improvements
- **[README.md](README.md)** - This file

## Requirements

- `zsh` (shell)
- `jq` (JSON processor)
- `openssl` (encryption)
- `python3` (TOML parsing)

## Install

### oh-my-zsh

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

Reload shell:
```bash
exec zsh
```

### Other Plugin Managers

The plugin entrypoint is `tokenvault.plugin.zsh`. Configure your plugin manager to source this file from the repository root.

See [INSTALL.md](INSTALL.md) for detailed instructions.

## Usage

### Basic Commands

```bash
tv-unlock              # Unlock vault (enter master password)
tv-lock                # Lock vault
tv-add                 # Add profile (interactive)
tv-remove <id>         # Remove profile
tv-list                # List all profiles
tv-dash                # Dashboard with quota status
tv-run <id> <cmd>      # Run command with profile
tv-run auto <cmd>      # Auto-select best key per provider
tv-help                # Show all commands
```

### Model Management

```bash
tv-model-set           # Set default model (interactive)
tv-model-list          # List available models
tv-codex-sync          # Sync Codex config into profiles
```

### Advanced

```bash
tv-report <id>         # Mark profile as exhausted
tv-unsafe              # Toggle unsafe mode (save password to disk)
```

See [INSTALL.md](INSTALL.md) for comprehensive examples and workflows.

## Development

### Run Tests

Local:
```bash
./build.sh local
```

Docker:
```bash
./build.sh docker
```

Tests verify:
- Syntax correctness
- Plugin loading
- Completion function registration
- Profile encryption/decryption
- Command execution
- Model management
- Codex sync
- Quota tracking

### Repository Layout

```
tokenvault.plugin.zsh   # Plugin entrypoint / loader
lib/                    # Shared modules
  ├── config.zsh        # Configuration and paths
  ├── core.zsh          # Core utilities and crypto
  ├── auth.zsh          # Authentication (unlock/lock)
  ├── ui.zsh            # User interaction helpers
  ├── models.zsh        # Model fetching
  ├── prompt.zsh        # Prompt rendering and worker
  ├── i18n.zsh          # Internationalization
  └── completion.zsh    # Tab completion
commands/               # Command implementations
  ├── profile-commands.zsh   # Profile management
  ├── model-commands.zsh     # Model management
  └── runtime-commands.zsh   # Command execution
build.sh                # Build and test script
test.sh                 # Functional test suite
INSTALL.md              # Installation guide
CHANGELOG.md            # Version history
```

## Recent Improvements

### Bug Fixes
- Fixed non-portable `echo -e` usage
- Removed external `bc` dependency
- Fixed eval injection vulnerabilities
- Fixed subshell array scope issues
- Improved build error handling

### New Features
- Full zsh tab completion for all commands and flags
- Comprehensive installation guide with examples
- Enhanced test coverage

See [CHANGELOG.md](CHANGELOG.md) for full details.

## Security

- Master password never written to disk (unless unsafe mode enabled)
- API keys encrypted with AES-256-CBC + PBKDF2
- Each key stored separately in vault
- Lock vault when stepping away: `tv-lock`

See [INSTALL.md](INSTALL.md#security-notes) for security notes.

## Troubleshooting

See [INSTALL.md](INSTALL.md#troubleshooting) for common issues and solutions.

## License

See LICENSE file for details.

