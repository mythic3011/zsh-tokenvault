# TokenVault Enhancements Implementation Plan
> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Break the single `tokenvault.plugin.zsh` into self-contained modules, add quicker key-management hit commands (`tv-add-key`, `tv-key-rotate`, `tv-key-status`), add locale-aware strings and an updater, keep the UX exit affordances consistent, and document the open/close lifecycle/design pattern so each module knows when to initialize and expose features.

**Architecture:** Core globals and crypto helpers remain in a shared module (`core.zsh`), while the CLI commands live in their own scripts so oh-my-zsh can source just what it needs. We will document an “open/close” pattern: each module exposes `tv_module_open()` to initialize (set paths, register hooks) and `tv_module_close()` to tear down any state; the loader only calls `open` (with option to register cleanup hooks) and exposes a single `tokenvault` namespace in the shell. New helper commands reuse `_tv_prompt_exit` and `_tv_short_key` from the core module so we avoid duplication.

**Tech Stack:** zsh scripting, jq for JSON, openssl for encryption, oh-my-zsh plugin sourcing conventions.

---

### Task 1: Module extraction + shared helpers
**Files:**
- Modify: `/Users/mythic3014/.oh-my-zsh/custom/plugins/tokenvault/tokenvault.plugin.zsh`
- Create: `/Users/mythic3014/.oh-my-zsh/custom/plugins/tokenvault/lib/core.zsh`
- Update: `/Users/mythic3014/.oh-my-zsh/custom/plugins/tokenvault/lib/ui.zsh`

**Step 1:** Extract global paths, `_tv_init`, color constants, `_tv_print`, `_tv_banner`, `_tv_short_key`, `_tv_prompt_exit`, `_tv_fmt_num`, `_tv_coerce_int`, `_tv_mktemp`, `_tv_write_json`, `_tv_crypto`, `_tv_verify_sha256`, and i18n tables into `lib/core.zsh`.
**Step 2:** Rework `tokenvault.plugin.zsh` to source `lib/core.zsh` and move helper-only sections (e.g., `_tv_ask`, `_tv_menu`, `_tv_pick_model`, `_tv_read_codex_config`) into `lib/ui.zsh`; ensure any function references still resolve by sourcing order.
**Step 3:** Keep `tokenvault.plugin.zsh` lightweight, only handling command registration (`tv-add`, `tv-run`, etc.) and sourcing the two modules; update `zsh -n tokenvault/tokenvault.plugin.zsh` to verify.

### Task 2: Quick key commands + documentation
**Files:**
- Modify: `/Users/mythic3014/.oh-my-zsh/custom/plugins/tokenvault/tokenvault.plugin.zsh`
- Update: `/Users/mythic3014/.oh-my-zsh/custom/plugins/tokenvault/tokenvault.plugin.zsh` (help text)
- Create: `/Users/mythic3014/.oh-my-zsh/custom/plugins/tokenvault/commands/key-helpers.zsh` (new commands)

**Step 1:** Implement `tv-key-rotate`, `tv-key-status`, and `tv-update` (CLI + interactive variants) by reusing `_tv_prompt_exit` and `_tv_verify_sha256`; ensure they respect the translations via `_tv_tr`.
**Step 2:** Update `tv-help` to list the new commands and add aliases if helpful (e.g., `alias tv-addkey=tv-add-key`).
**Step 3:** Add automated verification (zsh -n on each new script and `tokenvault.plugin.zsh`, plus a quick smoke test via `XDG_CONFIG_HOME=/tmp XDG_CACHE_HOME=/tmp TV_DIR=/tmp/tokenvault zsh -c 'source tokenvault/tokenvault.plugin.zsh; _TV_MASTER_KEY=1; tv-add-key -ID existing -Key foo'`).

### Task 3: Provider catalog + contribution workflow
**Goal:** Turn the built-in provider list into a data-driven catalog so new provider entries can be added via GitHub PRs without touching imperative logic.
**Files:**
* Create `custom/plugins/tokenvault/providers/catalog.json`
* Create `custom/plugins/tokenvault/lib/providers.zsh`
* Update `custom/plugins/tokenvault/tokenvault.plugin.zsh` and the README/docs to load the catalog, integrate it into interactive prompts, and explain how to contribute.

**Step 1:** Define the JSON schema (`id`, `display_name`, `provider_type`, `default_base_url`, `env_map`, `model_endpoint`, `notes`). Include built-in examples (anthropic, openai, gemini, openrouter, bedrock, azure-openai) and write `_tv_load_provider_catalog` plus `_tv_provider_info` helpers.
**Step 2:** Update the plugin so provider selection menus, `_tv_fetch_models`, and env-var defaults pull from provider metadata instead of hard-coded cases. Add `tv-provider-list` (with translations) to preview catalog entries and validate that metadata is sane before use.
**Step 3:** Document how to contribute new providers: add contributor-facing instructions (e.g., `docs/providers.md`) detailing the schema, verification steps (run `zsh -n`, `tv-provider-list`), and the expectation that new entries come through PRs.

**Verification:** Run `zsh -n` on the touched modules, execute `tv-provider-list` with `_TV_MASTER_KEY` mocked to ensure the catalog loads, and confirm `tv-add` still compiles against the dynamic provider list.

---

Plan saved to `/Users/mythic3014/.oh-my-zsh/custom/plugins/docs/plans/2026-03-09-tokenvault-extensions-plan.md`. Execution options:

1. **Subagent-Driven (this session)** – continue here, run each Task step-by-step with review checkpoints (use superpowers:subagent-driven-development). 2. **Parallel Session** – start a fresh session with superpowers:executing-plans for batch work. Which approach would you like?
