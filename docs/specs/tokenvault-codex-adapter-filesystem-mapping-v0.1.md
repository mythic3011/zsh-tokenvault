# TokenVault Codex Adapter Filesystem Mapping v0.1

> Status: Draft
> Scope: Codex-specific mapping on top of the TokenVault common runtime contract.

## Goal

Map the TokenVault common runtime contract onto Codex-specific artifacts and launch behavior without leaking Codex semantics back into the common layer.

## TokenVault Roots

For Codex profile `<profile>`:

```text
config_root = ~/.config/tokenvault/agents/codex/<profile>/
state_root  = ~/.local/state/tokenvault/agents/codex/<profile>/
cache_root  = ~/.cache/tokenvault/agents/codex/<profile>/
log_root    = ~/.local/state/tokenvault/logs/codex/<profile>/
```

## Codex Adapter-Owned Files

### Config namespace

```text
<config_root>/adapter_config/
  config.toml
```

Meaning:

- `config.toml` is Codex-specific persistent declarative config.
- It exists only for API mode profiles.

### State namespace

```text
<state_root>/auth/
  auth.json

<state_root>/session/
  session.json
```

Meaning:

- `auth.json` is a Codex-specific persistent auth/session artifact.
- `session.json` is TokenVault/Codex mutable session metadata.

## Profile-Scoped Codex Home

Codex launch must use a profile-scoped `CODEX_HOME`.

The adapter may materialize or project a Codex home view, but it must resolve only to TokenVault-owned profile roots.

Required proof fields:

- resolved `CODEX_HOME`
- resolved config path
- resolved auth/session path
- whether any global Codex path is reachable

## OAuth Mode Mapping

Required:

- scrub provider API env
- set profile-scoped `CODEX_HOME`
- allow `auth.json` under `state_root/auth/`
- allow session metadata under `state_root/session/`
- forbid `adapter_config/config.toml` carrying API credentials

Reject if:

- profile-local API config exists
- global Codex API config conflicts under the current shadow policy
- env still exposes forbidden provider credentials after scrub phase

## API Mode Mapping

Required:

- set profile-scoped `CODEX_HOME`
- write `adapter_config/config.toml`
- forbid `state_root/auth/auth.json` for the same profile

Reject if:

- OAuth session/auth artifacts already exist and no explicit migration is active
- profile or global state would cause Codex to resolve OAuth/session material instead of the intended API config

## Relevant Global Codex State

Codex global state surfaces include at minimum:

- effective `CODEX_HOME`, with `~/.codex` as the default conventional root
- `~/.codex/config.toml`
- `~/.codex/auth.json`
- `~/.codex/history.jsonl`
- `~/.codex/logs/`
- `~/.codex/caches/`
- OS keychain/keyring-backed credentials used by Codex as a non-filesystem auth surface

The Codex adapter must classify each relevant global artifact by mode:

- API config artifact
- OAuth/session artifact
- unknown artifact class

Unknown artifact class under isolated launch must default to reject unless policy explicitly allows otherwise.

Codex conflict detection is therefore not purely filesystem-scoped. The adapter must consider both filesystem-backed state and external credential stores if they can affect the effective launch graph.

## Conflict Semantics

Codex adapter conflict detection must distinguish:

1. profile-local conflict
2. env conflict
3. global shadow conflict
4. manifest drift

The adapter must return structured evidence, not only booleans.

That evidence must include:

- profile-local artifact evidence
- env evidence
- global filesystem evidence
- global non-filesystem auth evidence, if available
- effective resolution proof snapshot

## Non-Goals

- define common rejection codes
- define common capability schema
- define clone/rename lifecycle behavior beyond Codex artifact mapping

Those belong outside this document.
