# Codex Runtime Current TODO

> Date: 2026-04-09
> Scope: Current remaining work after commits `2448d72`, `5238339`, and `a9a7b15`

## Done

- Fixed zsh completion paths that were triggering expensive filesystem scans.
- Added Codex runtime roots, manifest, policy, and preflight primitives.
- Added Codex global filesystem conflict detection for `auth.json` and `config.toml`.
- Added macOS keychain probe-based auth evidence.
- Fixed `_tv_jq` dispatch enough for current runtime/preflight/smoke paths.
- Made env contamination fail closed with `E_ENV_CONFLICT`.
- Added smoke coverage for:
  - isolated OAuth launch
  - isolated API launch
  - global OAuth artifact conflict
  - global API artifact conflict
  - env contamination conflict

## Current TODO

### High

1. Make `E_GLOBAL_SHADOW_CONFLICT` details include both `proof` and `global_state` again, but through a dedicated JSON builder instead of shell string concatenation.
2. Replace the placeholder `reachable_global_paths: []` proof behavior with a real Codex reachability model that covers non-home config surfaces.

### Medium

1. Add negative coverage for externally-set `CODEX_HOME` that points to conflicting state.
2. Add negative coverage for project `.codex/config.toml` reachability.
3. Tighten `_tv_jq` long-term by splitting pass-through jq from explicit `json | jq filter` usage.

### Documentation

1. Document that keychain detection is evidence-enrichment only, not a complete global auth guarantee.
2. Document that current non-filesystem auth conflict detection is platform-dependent.

## Open Risks

- Keychain detection is still partial and probe-based.
- Resolution proof still does not model every reachable Codex config layer.
- Shadow-conflict reject details currently prioritize stability over completeness.

## Recommended Next Commit Order

1. `fix(runtime): emit deterministic shadow conflict payloads`
2. `fix(codex): prove reachable config surfaces`
3. `test(runtime): cover codex negative isolation cases`
4. `docs(codex): clarify external auth detection limits`
