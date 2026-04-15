# TokenVault Preflight Error Model And Adapter Capability Schema v0.1

> Status: Draft
> Scope: Deterministic preflight semantics and required adapter capability surface.

## Goal

Make launch rejection deterministic, testable, and machine-readable.

Without this document, adapters would interpret policy informally and the common contract would fragment.

## Preflight Order

Every launch must execute checks in this order:

1. resolve roots
2. load manifest
3. load policy
4. inspect observed profile artifacts
5. inspect runtime env
6. build effective resolution proof
7. inspect relevant global state against the resolved launch graph
8. evaluate mode invariants
9. evaluate shadow policy and conflict policy
10. return first failure or success

This order is normative.

Rationale:

- `forbid-conflict` and `shadow-ignore` are defined against the fully resolved launch graph.
- `E_GLOBAL_SHADOW_CONFLICT` therefore cannot be evaluated deterministically until the effective resolution proof exists.

## First-Failure Semantics

Preflight must stop on the first deterministic failure in the ordered sequence above.

Rules:

- only one primary rejection code is returned
- additional evidence may be attached
- launch does not continue after a failure

This is required so tests and audit logs remain stable.

## Rejection Codes

Minimum required rejection codes:

- `E_ROOT_RESOLUTION_FAILED`
- `E_MANIFEST_MISSING`
- `E_POLICY_MISSING`
- `E_PROFILE_STATE_MISMATCH`
- `E_ENV_CONFLICT`
- `E_GLOBAL_SHADOW_CONFLICT`
- `E_MANIFEST_DRIFT`
- `E_RESOLUTION_PROOF_FAILED`
- `E_MODE_INVARIANT_VIOLATION`
- `E_MIGRATION_LOCKED`

### Meanings

`E_PROFILE_STATE_MISMATCH`

- observed profile-local artifacts conflict with intended mode

`E_ENV_CONFLICT`

- runtime env still exposes forbidden state after scrub/allowlist application

`E_GLOBAL_SHADOW_CONFLICT`

- relevant global state violates current `global_shadow_policy`

`E_MANIFEST_DRIFT`

- manifest declaration does not match observed filesystem artifact class

`E_RESOLUTION_PROOF_FAILED`

- adapter could not prove the launched runtime resolves only approved roots

## Audit Record Contract

Every rejection must emit a structured audit event containing at minimum:

```json
{
  "event": "reject",
  "code": "E_ENV_CONFLICT",
  "agent": "codex",
  "profile": "work-oauth",
  "stage": "inspect runtime env",
  "details": {}
}
```

## Resolution Proof Requirement

Every adapter must provide `effective_resolution_proof()`.

Minimum proof payload:

```json
{
  "resolved_home_path": "...",
  "resolved_config_paths": ["..."],
  "resolved_auth_paths": ["..."],
  "reachable_global_paths": [],
  "proof_complete": true
}
```

If proof is missing, incomplete, or shows reachable forbidden global paths, preflight must fail with `E_RESOLUTION_PROOF_FAILED`.

Resolution proof is a core preflight primitive, not an optional advanced adapter feature.

## Adapter Capability Schema

Each adapter must declare capability metadata sufficient for the common layer to enforce policy.

Suggested shape:

```json
{
  "agent": "codex",
  "supports_oauth_mode": true,
  "supports_api_mode": true,
  "supports_shadow_ignore": true,
  "supports_profile_scoped_home": true,
  "supports_migration_lock": true
}
```

### Required capability functions

Every adapter must implement:

1. `resolve_roots(profile)`
2. `detect_profile_state(profile)`
3. `detect_global_state()`
4. `detect_env_conflicts(profile)`
5. `effective_resolution_proof(profile)`
6. `write_api_config(profile)`
7. `prepare_oauth_runtime(profile)`
8. `check_mode_invariants(profile)`

## Mode Invariant Evaluation

After root/env/global inspection, the adapter must emit an observed state summary:

```json
{
  "declared_mode": "oauth",
  "observed_profile_artifacts": ["oauth-session"],
  "observed_env_artifacts": [],
  "observed_global_artifacts": ["api-config"],
  "resolution_proof_ok": false
}
```

The common layer evaluates policy against this summary and returns a deterministic rejection code.

`forbid-conflict` must be evaluated against the fully resolved launch graph, not against declared mode alone.

## Migration Interaction

If migration is active:

- preflight may allow otherwise-invalid intermediate states only while a migration exclusive lock is held
- launch must still fail if migration lock is absent

This prevents adapters from normalizing invalid state opportunistically during launch.

## Why This Spec Exists

The common runtime contract is only enforceable if:

- check order is fixed
- failures are coded
- proof requirements are explicit
- adapter capabilities are declared up front

Without that, "ignore global state" and "mixed-state detection" remain policy slogans instead of implementable rules.
