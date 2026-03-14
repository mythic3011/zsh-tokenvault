# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Tab Completion**: Full zsh completion for all `tv-*` commands and flags
  - Command name completion
  - Flag completion with descriptions
  - Dynamic profile ID completion
  - Provider/auth/tier/reset-type option completion
  - File path completion for config files
  - Users no longer need to memorize command syntax

- **Installation Guide**: Comprehensive `INSTALL.md` with:
  - Prerequisites and verification
  - Installation instructions for oh-my-zsh and other plugin managers
  - Quick start guide
  - Tab completion examples
  - Common workflows for Anthropic, OpenAI, and custom providers
  - Troubleshooting section
  - Security notes

### Fixed
- **lib/prompt.zsh:15** - Non-portable `echo -e` replaced with `printf '%b\n'`
  - Fixes compatibility with shells where `echo -e` is not supported

- **lib/core.zsh:14-17** - Removed external `bc` dependency
  - Replaced `bc -l` with native zsh arithmetic
  - Improves portability and reduces external dependencies

- **lib/ui.zsh** - Security: Replaced all `eval` usage with `printf -v`
  - Fixed 4 instances of eval injection vulnerability
  - Lines: 131, 152, 175, 181
  - Uses indirect variable assignment instead of eval

- **lib/i18n.zsh:26** - Replaced `eval` with parameter expansion
  - Uses `${(P)map}[$key]` instead of eval
  - Improves security and performance

- **commands/model-commands.zsh:71-83** - Fixed subshell array scope issue
  - Changed piped while loop to process substitution
  - Fixes array population in profile selection

- **build.sh:68-76** - Made stderr check more lenient
  - Filters out harmless "nice(5) failed" warnings
  - Prevents false test failures on systems without nice privilege

### Changed
- **tokenvault.plugin.zsh** - Added completion.zsh to loader
  - Completion now automatically loaded with plugin

- **build.sh** - Enhanced load test
  - Added `_tokenvault` function check to verify completion loads

### Improved
- **Test Coverage**: Build now verifies completion function loads
- **Error Handling**: More robust stderr filtering in build.sh
- **Documentation**: Added comprehensive installation guide with examples

## [7.0] - Previous Release

### Features
- Encrypted local vault for API keys
- Profile-scoped defaults and model selection
- Command execution with environment variable injection
- Quota tracking and status dashboard
- Codex configuration sync
- Multi-language support (English, Simplified Chinese, Traditional Chinese)
- Background worker for async quota checks
- Support for Anthropic, OpenAI, Gemini, and custom providers

### Architecture
- Modular lib/ structure (config, core, auth, ui, models, prompt, i18n)
- Separate command modules (profile, model, runtime)
- AES-256-CBC encryption with PBKDF2
- JSON-based state management
- Background worker process for async operations

---

## Migration Guide

### From 7.0 to Current

No breaking changes. Simply update the plugin:

```bash
cd ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/tokenvault
git pull origin main
exec zsh
```

Tab completion will be automatically available.

## Known Issues

### Race Conditions
- Multiple processes can write to `$TV_PROFILES` simultaneously
- No file locking mechanism prevents concurrent modifications
- Workaround: Avoid running multiple `tv-*` commands in parallel

### Worker Lock
- Uses `mkdir` for locking (not atomic)
- Potential race condition between check and create
- Cleanup via trap may race with new worker creation

### Precision
- Zsh arithmetic has precision limits for very large numbers
- Number formatting may lose precision for quotas > 999 trillion

## Future Improvements

- [ ] Implement proper file locking for concurrent access
- [ ] Add atomic lock mechanism for worker process
- [ ] Improve number formatting precision
- [ ] Add GitHub Actions CI/CD
- [ ] Create development guide
- [ ] Add performance benchmarks
- [ ] Implement profile encryption (currently only keys are encrypted)
- [ ] Add key rotation support
- [ ] Create web UI for vault management
- [ ] Add support for hardware security keys

## Testing

Run tests locally:
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
- Completion function registration
- Profile encryption/decryption
- Command execution
- Model management
- Codex sync
- Quota tracking
- Error handling

## Contributors

- [@mythic3011](https://github.com/mythic3011) - Original author
- Claude (Anthropic) - Bug fixes and tab completion feature
