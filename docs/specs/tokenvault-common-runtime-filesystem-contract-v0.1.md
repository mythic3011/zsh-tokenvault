# TokenVault Common Runtime Filesystem Contract v0.1

> Status: Draft
> Scope: TokenVault-owned runtime contract for all agent adapters.

## Goal

Define the common filesystem, policy, and rejection model that every TokenVault-managed agent runtime must obey.

This document is intentionally adapter-agnostic. It does not reserve agent-specific filenames such as `config.toml` or `auth.json`. Those belong in adapter mapping specs.

## Design Principles

1. Config is declarative intent.
2. State is persistent mutable runtime material.
3. Cache is disposable.
4. Logs are append-only audit/usage records.
5. Declared state is not authoritative over observed state.
6. Mixed auth state must fail closed.
7. Global state handling must be explicit and machine-checkable.
8. Adapter-specific artifacts must not leak into the common contract.
9. Conflict is judged against the fully resolved launch graph, not declared intent alone.

## TokenVault-Owned Roots

Each agent profile resolves these four roots:

- `config_root`
- `state_root`
- `cache_root`
- `log_root`

### Config root

Persistent declarative configuration only:

```text
~/.config/tokenvault/agents/<agent>/<profile>/
  manifest.json
  policy.json
  adapter_config/
  env.allowlist
  env.scrublist
```

Rules:

- `manifest.json`
  Stores TokenVault-owned identity and mode declaration.
- `policy.json`
  Stores TokenVault-owned isolation policy.
- `adapter_config/`
  Adapter-scoped persistent declarative config namespace.
- `env.allowlist`
  Explicit env vars allowed to pass into runtime.
- `env.scrublist`
  Explicit env vars that must be removed before launch.

Forbidden in config root:

- Session tokens
- OAuth runtime artifacts
- Lockfiles
- Temp files
- Usage logs
- Mutable last-used metadata

### State root

Persistent mutable runtime state:

```text
~/.local/state/tokenvault/agents/<agent>/<profile>/
  auth/
  session/
  locks/
  last-used.json
```

Rules:

- `auth/`
  Adapter-owned persistent auth/session artifacts.
- `session/`
  TokenVault or adapter runtime session metadata.
- `locks/`
  TokenVault-owned coordination locks.
- `last-used.json`
  Minimal mutable lifecycle metadata.

State root may be rotated, migrated, or purged without changing intended declarative configuration.

### Cache root

Disposable artifacts only:

```text
~/.cache/tokenvault/agents/<agent>/<profile>/
  runtime/
  temp/
  derived/
```

Rules:

- `runtime/`
  Ephemeral rendered runtime artifacts.
- `temp/`
  Temporary files created during launch, sync, or migration.
- `derived/`
  Recomputable data derived from config or state.

Deleting cache root must never destroy intended config or canonical auth state.

### Log root

Per-agent, per-profile append-only logs:

```text
~/.local/state/tokenvault/logs/<agent>/<profile>/
  usage.jsonl
  audit.jsonl
```

Rules:

- Logs are sharded by `<agent>/<profile>`.
- Each file is append-only from the TokenVault contract perspective.
- Global aggregate indexes are optional and non-authoritative.

## Manifest Contract

`manifest.json` is a TokenVault declaration, not a source of truth over observed state.

Suggested fields:

```json
{
  "schema_version": 1,
  "agent": "codex",
  "profile": "work-oauth",
  "auth_mode": "oauth",
  "created_at": "2026-04-08T00:00:00Z",
  "updated_at": "2026-04-08T00:00:00Z"
}
```

Rules:

- `auth_mode` is a claim.
- If declared mode and observed filesystem/env state diverge, launch must fail.
- The manifest must be sufficient to identify the adapter and profile, but not sufficient to suppress artifact checks.

## Policy Contract

`policy.json` defines how TokenVault must isolate and validate this profile.

Suggested fields:

```json
{
  "global_shadow_policy": "forbid-conflict",
  "mixed_state_policy": "hard-fail",
  "allow_global_fallback": false
}
```

### `global_shadow_policy`

Valid values:

- `forbid-exists`
  Any relevant global agent state existing is a hard failure.
- `forbid-conflict`
  Relevant global state may exist, but if it conflicts with the active profile’s intended mode or reachable resolution graph, launch fails.
- `shadow-ignore`
  Relevant global state may exist, but the adapter must prove the launched runtime cannot resolve it through the effective launch graph.

Notes:

- `forbid-exists` is stronger than `forbid-conflict`.
- `shadow-ignore` is only valid when the adapter can produce a resolution proof.
- `forbid-conflict` is defined against the fully resolved launch graph, not manifest intent alone.

## Auth Mode Invariants

### OAuth mode

Required:

- Scrub forbidden API env before launch.
- Use profile-scoped roots only.
- Allow auth/session artifacts under `state_root`.
- Forbid adapter persistent API credential config for the same profile.

Forbidden:

- API-mode persistent config in the same profile
- Silent fallback to conflicting global API state

### API mode

Required:

- Use profile-scoped roots only.
- Write adapter persistent config only under `config_root/adapter_config/`.
- Forbid OAuth/session artifacts for the same profile unless explicitly migrating.

Forbidden:

- Simultaneous OAuth session state in the same profile
- Silent fallback to global auth/session state

## Lock Scope

Locks are TokenVault-owned and must be scoped by intent:

1. `launch`
   Per-profile launch lock.
2. `config-writer`
   Per-agent profile config writer lock.
3. `migration`
   Exclusive profile migration lock.

Rules:

- `migration` excludes `launch` and `config-writer`.
- `launch` does not imply `migration`.
- Adapter code must not create out-of-contract lock semantics without declaring them in capability metadata.

## Profile Rename / Clone Policy

The common contract must treat profile identity as a multi-root namespace.

### Rename

Renaming a profile must update:

- `config_root`
- `state_root`
- `cache_root`
- `log_root`
- `manifest.json`

Partial rename is invalid.

### Clone

Cloning a profile must define whether the following are copied, cleared, or rejected:

- declarative config
- auth/session state
- cache artifacts
- logs

Default safe rule:

- copy declarative config
- clear state
- clear cache
- do not copy logs

## Mixed-State Rule

Declared state is never enough. Observed state is always checked.

The common layer must reject if:

1. OAuth mode profile contains forbidden API persistent config artifacts.
2. API mode profile contains forbidden OAuth/session artifacts.
3. Runtime env contains forbidden credentials under the active policy.
4. Relevant global state violates `global_shadow_policy`.
5. Manifest claims do not match observed artifact class.

This contract may extend beyond pure filesystem state. If an adapter can resolve credentials or session state from non-filesystem global surfaces, those surfaces are part of global state for conflict purposes.

## Logging Rules

Logs must not leak secrets.

Rules:

- Never log keys, tokens, passwords, or raw auth material.
- Do not log full commands by default.
- Prefer structured event classes:
  `launch`, `reject`, `sync`, `migrate`, `conflict_detected`

## Adapter Boundary

The common contract only owns:

- roots
- manifest
- policy
- lock scopes
- rejection model
- capability requirements

The common contract does not own:

- adapter-specific config file names
- adapter-specific auth/session file names
- adapter-specific home layout

Those belong in adapter mapping specs.

## Required Next Spec

This common contract is not sufficient by itself. It requires:

1. an adapter mapping spec
2. a deterministic preflight error model
3. an adapter capability schema
