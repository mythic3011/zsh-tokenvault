# Codex Runtime Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task.

**Goal:** Close the remaining fail-open gaps in TokenVault's Codex runtime path and make rejection evidence more deterministic.

**Architecture:** Keep the current XDG-split runtime model and Codex-first adapter approach. Tighten enforcement at the preflight boundary instead of adding more launch-time magic, and prefer deterministic evidence over heuristic recovery.

**Tech Stack:** zsh, jq, TokenVault runtime primitives, Codex adapter hooks, shell smoke tests.

---

### Task 1: Make Shadow-Conflict Payloads Deterministic

**Files:**
- Modify: `lib/runtime-preflight.zsh`
- Test: `tests/runtime/test_tv_run_codex_runtime.sh`

**Step 1: Add a dedicated helper for conflict details**

Create a helper such as `_tv_runtime_preflight_shadow_details_json` that accepts compact `proof` and `global_state` JSON strings and emits one deterministic JSON object.

**Step 2: Stop building combined JSON with shell string concatenation**

Replace the inline payload construction inside `E_GLOBAL_SHADOW_CONFLICT` with the new helper so the reject path does not depend on shell quoting tricks.

**Step 3: Preserve current fallback safety**

Keep the existing `try fromjson catch {raw:...}` behavior in reject emission so malformed detail payloads still produce a rejection record instead of an empty result.

**Step 4: Extend smoke coverage**

Add an assertion that `E_GLOBAL_SHADOW_CONFLICT` details include both `proof` and `global_state` once the helper is in place.

**Step 5: Verify**

Run:

```bash
zsh -n tokenvault.plugin.zsh lib/*.zsh lib/agents/*.zsh commands/*.zsh tests/runtime/test_tv_run_codex_runtime.sh
zsh tests/runtime/test_tv_run_codex_runtime.sh
```

**Step 6: Commit**

```bash
git add lib/runtime-preflight.zsh tests/runtime/test_tv_run_codex_runtime.sh
git commit -m "fix(runtime): emit deterministic shadow conflict payloads"
```

### Task 2: Upgrade Resolution Proof Beyond Placeholder Scope

**Files:**
- Modify: `lib/agents/codex.zsh`
- Modify: `docs/specs/tokenvault-codex-adapter-filesystem-mapping-v0.1.md`
- Modify: `docs/specs/tokenvault-preflight-error-model-and-adapter-capability-schema-v0.1.md`
- Test: `tests/runtime/test_tv_run_codex_runtime.sh`

**Step 1: Enumerate reachable Codex config surfaces**

Use the adapter's existing knowledge of Codex config layers to decide which paths are reachable for the current launch graph, not just the profile-scoped home.

**Step 2: Emit real proof fields**

Update `tv_agent_codex_effective_resolution_proof` so `reachable_global_paths` reflects any user, project, system, or overridden home paths that remain reachable.

**Step 3: Fail if isolation cannot be proven**

Keep `proof_complete` false when the adapter cannot prove path isolation. Do not silently return an optimistic empty graph.

**Step 4: Add negative coverage**

Add at least one test case for a reachable non-home Codex path, for example a project `.codex/config.toml` under the working directory.

**Step 5: Verify**

Run the same parse and smoke commands, plus any focused shell test you add for project-level reachability.

**Step 6: Commit**

```bash
git add lib/agents/codex.zsh docs/specs/tokenvault-codex-adapter-filesystem-mapping-v0.1.md docs/specs/tokenvault-preflight-error-model-and-adapter-capability-schema-v0.1.md tests/runtime/test_tv_run_codex_runtime.sh
git commit -m "fix(codex): prove reachable config surfaces"
```

### Task 3: Make Keychain Detection Limits Explicit

**Files:**
- Modify: `lib/agents/codex.zsh`
- Modify: `README.md`
- Modify: `FAQ.md`

**Step 1: Keep probe-based detection as evidence only**

Do not present the current macOS keychain probe as a full guarantee. Treat it as detectable-surface evidence.

**Step 2: Add explicit limitation wording**

Document that non-filesystem auth conflict detection is partial and platform-dependent.

**Step 3: Tighten naming**

Rename any ambiguous fields or comments that overstate confidence, especially around global auth proof completeness.

**Step 4: Verify**

Manually inspect the emitted global-state details and confirm docs match implementation limits.

**Step 5: Commit**

```bash
git add lib/agents/codex.zsh README.md FAQ.md
git commit -m "docs(codex): clarify external auth detection limits"
```

### Task 4: Expand Negative Runtime Coverage

**Files:**
- Modify: `tests/runtime/test_tv_run_codex_runtime.sh`

**Step 1: Add env contamination cases**

Keep the new `E_ENV_CONFLICT` case and extend it if needed for other scrubbed OpenAI variables.

**Step 2: Add `CODEX_HOME` override coverage**

Test that a conflicting externally-set `CODEX_HOME` with conflicting artifacts is rejected.

**Step 3: Add project config reachability coverage**

Test that a reachable project `.codex/config.toml` is reflected in proof or conflict evidence once Task 2 is complete.

**Step 4: Verify**

Run:

```bash
zsh tests/runtime/test_tv_run_codex_runtime.sh
```

**Step 5: Commit**

```bash
git add tests/runtime/test_tv_run_codex_runtime.sh
git commit -m "test(runtime): cover codex negative isolation cases"
```

### Task 5: Final Focused Review

**Files:**
- Review only: `lib/agents/codex.zsh`
- Review only: `lib/runtime-preflight.zsh`
- Review only: `commands/runtime-commands.zsh`
- Review only: `tests/runtime/test_tv_run_codex_runtime.sh`

**Step 1: Re-check fail-open behavior**

Verify that env, profile-local artifacts, global state, and proof incompleteness all reject before launch.

**Step 2: Re-check launch boundary**

Confirm `tv-run` is only executing `codex` after preflight success and is not silently compensating for invalid state.

**Step 3: Re-check residual risks**

List only real remaining gaps, especially around external credential stores and non-home config reachability.

**Step 4: Save review notes**

Save the review result into a short markdown note if needed, or include it in the PR summary.
