#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

run_local() {
  require_cmd zsh
  require_cmd jq
  require_cmd openssl
  require_cmd python3

  cd "$ROOT_DIR"

  echo "==> syntax"
  zsh -n tokenvault.plugin.zsh lib/*.zsh commands/*.zsh

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  OH_MY_ZSH_CUSTOM="$TMP_DIR/oh-my-zsh/custom"
  PLUGIN_DIR="$OH_MY_ZSH_CUSTOM/plugins/tokenvault"
  mkdir -p "$PLUGIN_DIR"

  cp -R commands "$PLUGIN_DIR/"
  cp -R lib "$PLUGIN_DIR/"
  cp tokenvault.plugin.zsh "$PLUGIN_DIR/"

  echo "==> load as oh-my-zsh plugin"
  XDG_CONFIG_HOME="$TMP_DIR/config" \
  XDG_CACHE_HOME="$TMP_DIR/cache" \
  TV_DIR="$TMP_DIR/config/tokenvault" \
  TV_CACHE_DIR="$TMP_DIR/cache/tokenvault" \
  ZSH_CUSTOM="$OH_MY_ZSH_CUSTOM" \
  zsh -c '
    source "$ZSH_CUSTOM/plugins/tokenvault/tokenvault.plugin.zsh"
    typeset -f tv-help tv-add tv-run tv-model-set tv-model-list tv_render >/dev/null
  '

  echo "==> smoke test"
  local smoke_stdout="$TMP_DIR/smoke.stdout"
  local smoke_stderr="$TMP_DIR/smoke.stderr"
  XDG_CONFIG_HOME="$TMP_DIR/config" \
  XDG_CACHE_HOME="$TMP_DIR/cache" \
  TV_DIR="$TMP_DIR/config/tokenvault" \
  TV_CACHE_DIR="$TMP_DIR/cache/tokenvault" \
  ZSH_CUSTOM="$OH_MY_ZSH_CUSTOM" \
  zsh -c '
    source "$ZSH_CUSTOM/plugins/tokenvault/tokenvault.plugin.zsh"
    _TV_MASTER_KEY=1
    tv-add -ID existing -Prov openai -Auth key -Key foo-test-key -Model gpt-test >/dev/null
    jq -e ".existing.provider == \"openai\" and .existing.default_model == \"gpt-test\"" "$TV_PROFILES" >/dev/null
    openssl enc -aes-256-cbc -d -a -pbkdf2 -pass pass:1 -in "$TV_VAULT" 2>/dev/null | jq -e ".existing == \"foo-test-key\"" >/dev/null
    for i in {1..30}; do
      [[ -s "$TV_PROMPT_CACHE" ]] && break
      sleep 0.1
    done
    [[ -s "$TV_PROMPT_CACHE" ]]
    grep -F "foo-t..-key" "$TV_PROMPT_CACHE" >/dev/null
  ' >"$smoke_stdout" 2>"$smoke_stderr"

  if [[ -s "$smoke_stderr" ]]; then
    local expected_warning="_tv_spawn_worker:3: nice(5) failed: operation not permitted"
    if [[ "$(wc -l < "$smoke_stderr" | tr -d ' ')" != "1" ]] || \
       ! grep -Fx "$expected_warning" "$smoke_stderr" >/dev/null; then
      cat "$smoke_stderr" >&2
      exit 1
    fi
  fi

  echo "==> functional test suite"
  ./test.sh

  echo "build ok"
}

run_docker() {
  require_cmd docker
  cd "$ROOT_DIR"
  echo "==> docker build"
  docker build -f Dockerfile.test -t tokenvault-test .
  echo "==> docker run"
  docker run --rm tokenvault-test
}

case "${1:-local}" in
  local|--local)
    run_local
    ;;
  docker|--docker)
    run_docker
    ;;
  *)
    echo "usage: $0 [local|docker]" >&2
    exit 1
    ;;
esac
