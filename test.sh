#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

require_cmd zsh
require_cmd jq
require_cmd openssl
require_cmd python3

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OH_MY_ZSH_CUSTOM="$TMP_DIR/oh-my-zsh/custom"
PLUGIN_DIR="$OH_MY_ZSH_CUSTOM/plugins/tokenvault"
mkdir -p "$PLUGIN_DIR"

cp -R commands "$PLUGIN_DIR/"
cp -R lib "$PLUGIN_DIR/"
cp tokenvault.plugin.zsh "$PLUGIN_DIR/"

export XDG_CONFIG_HOME="$TMP_DIR/config"
export XDG_CACHE_HOME="$TMP_DIR/cache"
export TV_DIR="$TMP_DIR/config/tokenvault"
export TV_CACHE_DIR="$TMP_DIR/cache/tokenvault"
export ZSH_CUSTOM="$OH_MY_ZSH_CUSTOM"

CONFIG_TOML="$TMP_DIR/codex.toml"
cat >"$CONFIG_TOML" <<'EOF'
model_provider = "openai-main"
model = "gpt-4.1-mini"

[model_providers.openai-main]
base_url = "https://example.test/v1"
requires_openai_auth = true
model = "gpt-4.1-mini"
EOF

echo "==> functional"
zsh -c '
  set -euo pipefail
  source "$ZSH_CUSTOM/plugins/tokenvault/tokenvault.plugin.zsh"
  _TV_MASTER_KEY=1

  wait_for_worker() {
    local i
    for i in {1..50}; do
      [[ ! -e "$TV_WORKER_LOCK" ]] && return 0
      sleep 0.1
    done
    return 1
  }

  tv-add -ID openai-main -Prov openai -Auth key -Key sk-openai -Model gpt-openai >/dev/null
  wait_for_worker
  tv-add -ID anthropic-main -Prov anthropic -Auth key -Key sk-anthropic -Model claude-sonnet >/dev/null
  wait_for_worker

  jq -e ".\"openai-main\".provider == \"openai\"" "$TV_PROFILES" >/dev/null
  jq -e ".\"anthropic-main\".provider == \"anthropic\"" "$TV_PROFILES" >/dev/null

  named_out=$(tv-run openai-main zsh -c "print -r -- \$OPENAI_API_KEY:\$OPENAI_DEFAULT_MODEL")
  [[ "$named_out" == "sk-openai:gpt-openai" ]]

  auto_out=$(tv-run auto zsh -c "print -r -- \$OPENAI_API_KEY:\$OPENAI_DEFAULT_MODEL:\$ANTHROPIC_API_KEY:\$ANTHROPIC_MODEL")
  [[ "$auto_out" == "sk-openai:gpt-openai:sk-anthropic:claude-sonnet" ]]

  list_out=$(tv-list)
  [[ "$list_out" == *"openai-main"* ]]
  [[ "$list_out" == *"anthropic-main"* ]]

  dash_out=$(tv-dash)
  [[ "$dash_out" == *"PROFILE"* ]]
  [[ "$dash_out" == *"openai-main"* ]]

  _tv_fetch_models() {
    print -r -- "gpt-4.1"
    print -r -- "gpt-4.1-mini"
  }

  tv-model-set -Prov openai -Tier default -Model gpt-4.1 >/dev/null
  jq -e ".openai.default == \"gpt-4.1\"" "$TV_MODELS" >/dev/null

  tv-model-set -Profile openai-main -Model gpt-4.1-mini >/dev/null
  jq -e ".\"openai-main\".default_model == \"gpt-4.1-mini\"" "$TV_PROFILES" >/dev/null

  model_list_out=$(tv-model-list -Prov openai)
  [[ "$model_list_out" == *"gpt-4.1-mini"* ]]

  tv-codex-sync -Config "'"$CONFIG_TOML"'" -Yes >/dev/null
  wait_for_worker
  jq -e ".\"codex-openai-main\".source == \"codex-sync\"" "$TV_PROFILES" >/dev/null

  printf "y\n" | tv-report openai-main >/dev/null
  wait_for_worker
  jq -e ".\"openai-main\".status == \"exhausted\"" "$TV_PROFILES" >/dev/null

  printf "y\n" | tv-remove anthropic-main >/dev/null
  wait_for_worker
  jq -e "has(\"anthropic-main\") | not" "$TV_PROFILES" >/dev/null

  help_out=$(tv-help)
  [[ "$help_out" == *"tv-codex-sync"* ]]

  wait_for_worker
'

echo "functional ok"
