# TokenVault Roadmap

This document outlines the future direction and planned improvements for TokenVault.

## Vision

TokenVault aims to be the most user-friendly and secure way to manage API keys and credentials in the terminal, with:

- Zero friction for daily use (tab completion, smart defaults)
- Enterprise-grade security (encryption, audit logging)
- Multi-provider support (Anthropic, OpenAI, Gemini, custom)
- Developer-friendly architecture (modular, extensible)

## Current Status (v7.0+)

### ✅ Completed

- Core vault functionality with AES-256-CBC encryption
- Multi-provider support (Anthropic, OpenAI, Gemini, custom)
- Profile-scoped defaults and model selection
- Quota tracking and status dashboard
- Codex configuration sync
- Multi-language support (English, Chinese variants)
- Full zsh tab completion
- Comprehensive documentation

### 🔄 In Progress

- Bug fixes and stability improvements
- Documentation enhancements
- Test coverage expansion
- muiltiple endpoint support for one provider

## Planned Features

### Phase 1: Stability & Polish (Q2 2026)

**Goal:** Make TokenVault production-ready with robust error handling and comprehensive testing.

- [ ] **File Locking** - Implement proper file locking for concurrent access
  - Prevent race conditions when multiple processes modify profiles
  - Use flock or similar mechanism
  - Add lock timeout handling

- [ ] **Atomic Operations** - Improve worker lock mechanism
  - Replace mkdir-based locking with atomic operations
  - Reduce race condition window
  - Add cleanup for stale locks

- [ ] **Enhanced Error Handling**
  - Better error messages for common issues
  - Graceful degradation when APIs are unavailable
  - Retry logic for transient failures

- [ ] **Comprehensive Testing**
  - Add negative path tests (invalid input, missing files, etc.)
  - Add concurrency tests
  - Add performance benchmarks
  - Increase test coverage to 90%+

- [ ] **GitHub Actions CI/CD**
  - Automated testing on push
  - Automated testing on multiple zsh versions
  - Automated testing on macOS and Linux
  - Automated release process

### Phase 2: Enterprise Features (Q3 2026)

**Goal:** Add features needed for enterprise/team environments.

- [ ] **Audit Logging**
  - Log all vault access and modifications
  - Include timestamp, user, action, and result
  - Support log rotation and archival
  - Optional remote logging

- [ ] **Key Rotation**
  - Automated key rotation scheduling
  - Rotation history and rollback
  - Notification before rotation
  - Batch rotation for multiple keys

- [ ] **Access Control**
  - Per-profile access permissions
  - Role-based access control (RBAC)
  - Audit trail for permission changes
  - Integration with system users/groups

- [ ] **Profile Encryption**
  - Encrypt profile metadata (not just keys)
  - Separate encryption keys for different profiles
  - Support for hardware security keys

- [ ] **Backup & Recovery**
  - Automated backup scheduling
  - Encrypted backup storage
  - Point-in-time recovery
  - Backup verification

### Phase 3: Developer Experience (Q4 2026)

**Goal:** Make TokenVault even easier to use and extend.

- [ ] **Web UI**
  - Browser-based vault management
  - Real-time quota monitoring
  - Profile management interface
  - Audit log viewer

- [ ] **API Server**
  - REST API for vault access
  - Authentication and authorization
  - Rate limiting
  - Webhook support for events

- [ ] **CLI Improvements**
  - Better progress indicators
  - Interactive wizards for complex operations
  - Batch operations
  - Configuration file support

- [ ] **Integration Plugins**
  - VS Code extension
  - IDE integrations (JetBrains, etc.)
  - Git hooks for credential injection
  - Docker integration

- [ ] **SDK/Library**
  - Python library for vault access
  - Node.js library
  - Go library
  - Rust library

### Phase 4: Advanced Features (2027+)

**Goal:** Add advanced capabilities for power users and enterprises.

- [ ] **Multi-Machine Sync**
  - Sync vault across multiple machines
  - Conflict resolution
  - Selective sync
  - Offline support

- [ ] **Team Collaboration**
  - Shared vaults
  - Team management
  - Permission delegation
  - Approval workflows

- [ ] **Hardware Security Keys**
  - Support for YubiKey, Titan, etc.
  - Master password stored on hardware key
  - Hardware-backed encryption

- [ ] **Advanced Quota Management**
  - Predictive quota exhaustion
  - Automatic key rotation on exhaustion
  - Cost tracking and optimization
  - Usage analytics

- [ ] **Performance Optimization**
  - Caching layer for frequently accessed keys
  - Lazy loading of profiles
  - Background sync
  - Memory optimization

## Known Issues & Limitations

### Current Limitations

1. **Race Conditions** - Multiple processes can write to profiles simultaneously
   - Workaround: Avoid running multiple `tv-*` commands in parallel
   - Fix: Implement file locking (Phase 1)

2. **Worker Lock** - Uses mkdir for locking (not atomic)
   - Workaround: None
   - Fix: Implement atomic lock mechanism (Phase 1)

3. **Number Precision** - Zsh arithmetic has precision limits
   - Workaround: None
   - Fix: Use alternative number formatting (Phase 1)

4. **Profile Metadata** - Only keys are encrypted, not profile metadata
   - Workaround: None
   - Fix: Implement profile encryption (Phase 2)

5. **No Audit Logging** - No record of vault access
   - Workaround: None
   - Fix: Implement audit logging (Phase 2)

## Breaking Changes

### Planned Breaking Changes

None planned for v7.x. Major version bumps (v8.0+) may introduce breaking changes with migration guides.

### Migration Path

When breaking changes are introduced:

1. Deprecation period (at least 2 releases)
2. Clear migration guide
3. Automated migration tool if possible
4. Support for old format during transition

## Community Contributions

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- How to contribute
- Development setup
- Code style guidelines
- Pull request process

### Areas Needing Help

- [ ] Documentation improvements
- [ ] Bug fixes
- [ ] Test coverage
- [ ] Performance optimization
- [ ] Platform-specific fixes (Windows, BSD, etc.)
- [ ] Language translations
- [ ] Integration plugins

## Release Schedule

### Versioning

TokenVault follows [Semantic Versioning](https://semver.org/):

- **MAJOR** - Breaking changes
- **MINOR** - New features (backward compatible)
- **PATCH** - Bug fixes

### Release Cadence

- **Patch releases** - As needed (bug fixes)
- **Minor releases** - Monthly (new features)
- **Major releases** - Annually (breaking changes)

### Current Version

- **Latest**: v7.0+
- **Next Minor**: v7.1 (Q2 2026)
- **Next Major**: v8.0 (2027)

## Feedback & Suggestions

We'd love to hear your ideas! Please:

1. **Check existing issues** - Your idea might already be discussed
2. **Open a new issue** - Describe your feature request or suggestion
3. **Discuss in comments** - Share your thoughts on existing issues
4. **Contribute** - Implement features yourself (see [CONTRIBUTING.md](CONTRIBUTING.md))

## Success Metrics

We measure success by:

- **User Adoption** - Number of users and installations
- **Community Engagement** - Issues, PRs, discussions
- **Code Quality** - Test coverage, security audits
- **Performance** - Command execution time, memory usage
- **Reliability** - Uptime, bug reports, user satisfaction

## Long-Term Vision (2027+)

TokenVault aims to become:

1. **The Standard** - Default credential manager for terminal users
2. **Enterprise-Ready** - Used in production by major companies
3. **Ecosystem** - Integrations with popular tools and platforms
4. **Community-Driven** - Maintained by active community
5. **Secure-First** - Industry-leading security practices

## Questions?

- Check [FAQ.md](FAQ.md) for common questions
- Check [DEVELOPMENT.md](DEVELOPMENT.md) for architecture
- Open an issue on GitHub
- Discuss in existing issues

## Contributing to the Roadmap

Have ideas for the roadmap? We'd love to hear them!

1. Open an issue with your suggestion
2. Describe the use case and benefits
3. Discuss with the community
4. Help implement if interested

---

**Last Updated:** March 2026
**Next Review:** June 2026
