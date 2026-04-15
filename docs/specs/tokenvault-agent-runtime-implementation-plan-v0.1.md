# TokenVault Agent Runtime Implementation Plan v0.1

> Status: Draft
> Scope: Implementation baseline derived from the common runtime contract, Codex adapter mapping, and preflight/error model.

## Goal

Refactor TokenVault from env-injection-first profile launching into a policy-driven agent runtime manager with:

- split XDG roots
- deterministic preflight rejection
- profile-scoped runtime isolation
- Codex-first adapter enforcement

This plan is intentionally implementation-oriented and mapped to the current repo.

## Current Code Reality

Today the main execution path is centered on:

- [commands/runtime-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/runtime-commands.zsh)
- [commands/profile-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/profile-commands.zsh)
- [lib/config.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/config.zsh)
- [lib/security.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/security.zsh)
- [lib/agent-provider.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/agent-provider.zsh)
- [lib/agents/codex.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/agents/codex.zsh)

Current limitations:

- `auth_mode=cli` is not a real isolated OAuth mode.
- env scrubbing is incomplete and not fail-closed.
- `CODEX_HOME` isolation does not exist.
- runtime policy is not represented as machine-checkable roots + manifest + policy + rejection codes.
- usage logging is still too command-oriented.

## Implementation Strategy

Do this in layers:

1. introduce TokenVault-owned runtime root resolution
2. introduce manifest/policy materialization
3. introduce deterministic preflight
4. integrate Codex adapter proof + conflict detection
5. switch launch path to runtime-policy-driven execution

Do not start by rewriting every adapter. Codex is the only concrete target in v0.1.

## Phase 1: Add Runtime Root Model

### Files to modify

- [lib/config.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/config.zsh)
- [lib/io.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/io.zsh)
- [lib/core.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/core.zsh)

### Files to add

- `lib/runtime-roots.zsh`

### Work

Add a root resolver for:

- `config_root`
- `state_root`
- `cache_root`
- `log_root`

for `<agent>/<profile>`.

Responsibilities:

- build XDG-split paths
- create missing directories with safe permissions
- expose a single function like:
  `_tv_runtime_roots <agent> <profile>`
- return structured JSON, not ad hoc strings

Example shape:

```json
{
  "agent": "codex",
  "profile": "work-oauth",
  "config_root": "/.../.config/tokenvault/agents/codex/work-oauth",
  "state_root": "/.../.local/state/tokenvault/agents/codex/work-oauth",
  "cache_root": "/.../.cache/tokenvault/agents/codex/work-oauth",
  "log_root": "/.../.local/state/tokenvault/logs/codex/work-oauth"
}
```

## Phase 2: Add Manifest And Policy Materialization

### Files to add

- `lib/runtime-manifest.zsh`
- `lib/runtime-policy.zsh`

### Files to modify

- [commands/profile-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/profile-commands.zsh)
- [commands/model-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/model-commands.zsh)

### Work

When a profile is created or upgraded, TokenVault must be able to materialize:

- `manifest.json`
- `policy.json`
- `env.allowlist`
- `env.scrublist`

This should not yet rewrite the whole legacy profile flow. First add explicit helper functions:

- `_tv_runtime_manifest_read`
- `_tv_runtime_manifest_write`
- `_tv_runtime_policy_read`
- `_tv_runtime_policy_write`

The profile schema in `TV_PROFILES` can remain temporarily, but it becomes legacy input, not the final runtime policy source.

## Phase 3: Add Preflight Engine

### Files to add

- `lib/runtime-preflight.zsh`

### Files to modify

- [lib/security.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/security.zsh)
- [lib/agent-provider.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/agent-provider.zsh)

### Work

Implement the ordered preflight pipeline from the spec:

1. resolve roots
2. load manifest
3. load policy
4. inspect observed profile artifacts
5. inspect runtime env
6. build effective resolution proof
7. inspect global state against resolved graph
8. evaluate mode invariants
9. evaluate shadow/conflict policy

Preflight output must be JSON:

```json
{
  "ok": false,
  "code": "E_ENV_CONFLICT",
  "stage": "inspect runtime env",
  "details": {}
}
```

No natural-language-only errors at this layer.

## Phase 4: Expand Agent Provider Interface

### Files to modify

- [lib/agent-provider.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/agent-provider.zsh)

### Work

The provider interface currently covers config/model/version operations only.

Add required adapter hooks:

- `tv_agent_<id>_resolve_roots`
- `tv_agent_<id>_detect_profile_state`
- `tv_agent_<id>_detect_global_state`
- `tv_agent_<id>_detect_env_conflicts`
- `tv_agent_<id>_effective_resolution_proof`
- `tv_agent_<id>_write_api_config`
- `tv_agent_<id>_prepare_oauth_runtime`
- `tv_agent_<id>_check_mode_invariants`

Keep fallback behavior minimal. Do not silently invent runtime policy for adapters that do not implement these hooks.

If an adapter lacks runtime hooks, runtime launch should reject cleanly instead of “best effort”.

## Phase 5: Codex Adapter Mapping

### Files to modify

- [lib/agents/codex.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/agents/codex.zsh)
- [commands/model-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/model-commands.zsh)

### Work

Codex adapter must become the first real runtime-policy implementation.

Implement:

- profile-scoped Codex root projection
- Codex-specific config namespace mapping:
  `adapter_config/config.toml`
- Codex-specific auth/session namespace mapping:
  `state_root/auth/auth.json`
  `state_root/session/...`
- global surface detection:
  - effective `CODEX_HOME`
  - `~/.codex/config.toml`
  - `~/.codex/auth.json`
  - `~/.codex/history.jsonl`
  - `~/.codex/logs/`
  - `~/.codex/caches/`
  - keychain/keyring-backed credentials if detectable

The Codex adapter must return structured evidence, not only booleans.

## Phase 6: Replace `tv-run` Launch Semantics

### Files to modify

- [commands/runtime-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/runtime-commands.zsh)

### Work

Current `tv-run` does env injection directly.

Refactor it so launch becomes:

1. resolve target profile and adapter
2. run preflight
3. if rejection, emit coded failure and audit record
4. if success, construct runtime env from policy
5. set adapter-scoped home
6. execute command

For Codex:

- OAuth mode:
  scrub provider API env
  set profile-scoped `CODEX_HOME`
  do not write API config
- API mode:
  set profile-scoped `CODEX_HOME`
  materialize Codex config under profile config namespace
  forbid OAuth session artifacts for same profile

## Phase 7: Logging And Audit Redesign

### Files to modify

- [lib/config.zsh](/Users/mythic3014/Documents/project/tokenvault/lib/config.zsh)
- [commands/runtime-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/runtime-commands.zsh)

### Work

Replace the current single global usage log model with sharded profile logs:

- `~/.local/state/tokenvault/logs/<agent>/<profile>/usage.jsonl`
- `~/.local/state/tokenvault/logs/<agent>/<profile>/audit.jsonl`

Rules:

- do not log full raw command by default
- log event classes and minimal metadata
- record rejection code on failed preflight

## Phase 8: Legacy Profile Migration

### Files to add

- `lib/runtime-migration.zsh`

### Files to modify

- [commands/profile-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/profile-commands.zsh)
- [commands/update-commands.zsh](/Users/mythic3014/Documents/project/tokenvault/commands/update-commands.zsh)

### Work

Add explicit migration from legacy `TV_PROFILES` entries into runtime-managed profiles.

Rules:

- infer candidate mode from legacy state
- write manifest/policy
- refuse ambiguous mixed-state migration
- require explicit user action for ambiguous profiles
- migration must hold exclusive migration lock

Do not auto-normalize invalid profiles during normal launch.

## Phase 9: Tests

### Files to add

- `tests/runtime/test_runtime_roots.py` or shell equivalent
- `tests/runtime/test_preflight_rejections.py`
- `tests/runtime/test_codex_adapter_mapping.py`
- `tests/runtime/test_tv_run_runtime_policy.py`

### Minimum scenarios

1. OAuth profile with API config artifact -> reject
2. API profile with OAuth artifact -> reject
3. env contamination survives scrub -> reject with `E_ENV_CONFLICT`
4. global Codex config reachable under `forbid-conflict` -> reject
5. missing or incomplete resolution proof -> reject with `E_RESOLUTION_PROOF_FAILED`
6. isolated API launch writes profile-scoped config and sets profile-scoped `CODEX_HOME`

## Phase 10: Docs

### Files to modify

- [README.md](/Users/mythic3014/Documents/project/tokenvault/README.md)
- [INSTALL.md](/Users/mythic3014/Documents/project/tokenvault/INSTALL.md)
- [FAQ.md](/Users/mythic3014/Documents/project/tokenvault/FAQ.md)

### Work

Document the new product definition clearly:

- OAuth mode is isolated runtime mode, not “just don’t inject env”
- API mode is profile-scoped persistent config, not global `~/.codex` mutation
- mixed state rejects
- unsafe mode remains a downgrade
- conflict detection scope and limitations must be explicit, especially for keychain/keyring visibility

## Recommended Commit Boundaries

1. `feat(runtime): add runtime root and manifest/policy primitives`
2. `feat(runtime): add preflight engine and rejection codes`
3. `feat(codex): add codex runtime mapping and conflict detection`
4. `refactor(runtime): route tv-run through runtime preflight`
5. `feat(runtime): add migration and sharded audit logs`
6. `docs(runtime): document isolated oauth/api runtime model`

## Non-Goals For This Implementation Plan

- full Claude Code runtime mapping
- full aider runtime mapping
- vault cryptography redesign
- unsafe mode redesign
- full OS keychain introspection across every platform

Those can follow after Codex v1 is correct.
