# Contributing to TokenVault

Thank you for your interest in contributing to TokenVault! This guide will help you get started.

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions.

## Getting Started

### Prerequisites

- `zsh` shell
- `git`
- `jq`, `openssl`, `python3` (for testing)
- Basic understanding of zsh scripting

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/mythic3011/zsh-tokenvault
cd zsh-tokenvault

# Verify dependencies
command -v zsh jq openssl python3

# Run tests to verify setup
./build.sh local
```

## Types of Contributions

### Bug Reports

Found a bug? Please report it!

1. Check [existing issues](https://github.com/mythic3011/zsh-tokenvault/issues) first
2. Create a new issue with:
   - Clear title describing the bug
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, zsh version, etc.)
   - Error messages or logs

### Feature Requests

Have an idea? We'd love to hear it!

1. Check [existing issues](https://github.com/mythic3011/zsh-tokenvault/issues) first
2. Create a new issue with:
   - Clear title describing the feature
   - Use case and motivation
   - Proposed implementation (if you have ideas)
   - Examples of how it would be used

### Documentation

Help improve our docs!

- Fix typos or unclear explanations
- Add examples or clarifications
- Improve organization or structure
- Translate documentation

### Code Contributions

Want to fix a bug or add a feature? Great!

## Development Workflow

### 1. Fork and Clone

```bash
# Fork on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/zsh-tokenvault
cd zsh-tokenvault

# Add upstream remote
git remote add upstream https://github.com/mythic3011/zsh-tokenvault
```

### 2. Create a Feature Branch

```bash
# Update main
git fetch upstream
git checkout main
git merge upstream/main

# Create feature branch
git checkout -b feature/my-feature
```

Branch naming:
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation
- `refactor/description` - Code refactoring
- `test/description` - Test improvements

### 3. Make Changes

Follow the [Development Guide](DEVELOPMENT.md) for:
- Code style and conventions
- Module structure
- Testing patterns
- Security considerations

### 4. Test Your Changes

```bash
# Run all tests
./build.sh local

# Run in Docker
./build.sh docker

# Test specific functionality
zsh -c 'source tokenvault.plugin.zsh; tv-mycommand'
```

### 5. Commit Changes

```bash
# Stage changes
git add .

# Commit with clear message
git commit -m "feat: add my feature

- Detailed explanation of changes
- Why this change was needed
- Any breaking changes or notes"
```

Commit message format:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `refactor:` - Code refactoring
- `test:` - Test improvements
- `chore:` - Build, dependencies, etc.

### 6. Push and Create Pull Request

```bash
# Push to your fork
git push origin feature/my-feature

# Create PR on GitHub
# - Clear title and description
# - Reference related issues
# - Explain what changed and why
```

## Pull Request Guidelines

### Before Submitting

- [ ] Tests pass: `./build.sh local`
- [ ] Code follows style guide (see [Development Guide](DEVELOPMENT.md))
- [ ] Documentation is updated
- [ ] Commit messages are clear
- [ ] No unrelated changes included

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Refactoring

## Related Issues
Fixes #123

## Testing
How to test these changes:
1. Step 1
2. Step 2

## Checklist
- [ ] Tests pass
- [ ] Documentation updated
- [ ] No breaking changes
```

### Review Process

1. Maintainers will review your PR
2. Address any feedback or questions
3. Make requested changes
4. PR will be merged once approved

## Code Review Checklist

When reviewing code, check:

- [ ] Code follows style guide
- [ ] Tests are included and pass
- [ ] Documentation is updated
- [ ] No security issues
- [ ] No performance regressions
- [ ] Commit messages are clear
- [ ] No unrelated changes

## Testing Guidelines

### Write Tests For

- New features
- Bug fixes
- Edge cases
- Error conditions

### Test Format

Add tests to `test.sh`:

```zsh
# Test your feature
tv-mycommand -flag value >/dev/null
[[ $? -eq 0 ]] || exit 1

# Verify state
jq -e '.expected == "value"' "$TV_PROFILES" >/dev/null
```

### Run Tests

```bash
# All tests
./build.sh local

# Specific test
zsh -c 'source tokenvault.plugin.zsh; tv-mycommand'

# With debug output
zsh -x tokenvault.plugin.zsh
```

## Documentation Guidelines

### Update These Files

- `README.md` - Overview and quick start
- `INSTALL.md` - Installation and setup
- `DEVELOPMENT.md` - Developer guide
- `QUICKREF.md` - Command reference
- `CHANGELOG.md` - Version history

### Documentation Style

- Use clear, concise language
- Include examples
- Link to related sections
- Keep it up-to-date with code changes

## Commit Message Guidelines

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Examples

```
feat(completion): add tab completion for tv-add flags

- Add _tokenvault completion function
- Register compdef for all tv-* commands
- Support dynamic profile ID completion

Fixes #42
```

```
fix(core): remove bc dependency for number formatting

Replace bc -l with native zsh arithmetic to improve
portability and reduce external dependencies.

Fixes #38
```

## Code Style

See [Development Guide - Code Style](DEVELOPMENT.md#code-style) for:
- Naming conventions
- Zsh features to use
- Error handling patterns
- Comment style

## Performance Considerations

See [Development Guide - Performance](DEVELOPMENT.md#performance-considerations) for:
- Avoiding subshells
- Minimizing external calls
- Caching results

## Security Considerations

See [Development Guide - Security](DEVELOPMENT.md#security-considerations) for:
- Input validation
- Avoiding eval
- File permissions
- Sensitive data handling

## Common Issues

### Tests Fail Locally

```bash
# Verify dependencies
command -v zsh jq openssl python3

# Check zsh version
zsh --version

# Run with debug output
zsh -x build.sh local
```

### Completion Not Working

```bash
# Verify compdef is available
zsh -c 'typeset -f compdef'

# Reload shell
exec zsh

# Check completion function
zsh -c 'source tokenvault.plugin.zsh; typeset -f _tokenvault'
```

### Permission Denied

```bash
# Make scripts executable
chmod +x build.sh test.sh

# Check file permissions
ls -la build.sh test.sh
```

## Getting Help

- Check [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and patterns
- Review existing code for examples
- Open an issue with questions
- Ask in pull request comments

## Recognition

Contributors will be recognized in:
- `CHANGELOG.md` - For significant contributions
- GitHub contributors page
- Project README (for major features)

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Questions?

- Open an issue on GitHub
- Check existing documentation
- Review similar code in the project

Thank you for contributing to TokenVault! 🎉
