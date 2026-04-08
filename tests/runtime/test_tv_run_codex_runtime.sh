#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
tmp_root="$(mktemp -d /tmp/tokenvault-runtime-smoke.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

export TV_DIR="$tmp_root/config"
export TV_STATE_DIR="$tmp_root/state"
export TV_CACHE_DIR="$tmp_root/cache"
export TV_VAULT="$TV_DIR/vault.enc"
export TV_PROFILES="$TV_DIR/profiles.json"
export TV_MODELS="$TV_DIR/models.json"
export TV_USAGE_LOG="$TV_DIR/usage.jsonl"
export PATH="$tmp_root/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export HOME="$tmp_root/home"

mkdir -p "$tmp_root/bin" "$TV_DIR" "$HOME/.codex"

cat > "$tmp_root/bin/codex" <<'EOF'
#!/bin/zsh
set -eu
print -r -- "CODEX_HOME=${CODEX_HOME:-}" > "${TV_SMOKE_OUT:?}"
print -r -- "OPENAI_API_KEY=${OPENAI_API_KEY:-}" >> "${TV_SMOKE_OUT:?}"
print -r -- "OPENAI_BASE_URL=${OPENAI_BASE_URL:-}" >> "${TV_SMOKE_OUT:?}"
print -r -- "OPENAI_DEFAULT_MODEL=${OPENAI_DEFAULT_MODEL:-}" >> "${TV_SMOKE_OUT:?}"
EOF
chmod 755 "$tmp_root/bin/codex"

cat > "$TV_PROFILES" <<'EOF'
{
  "oauth-demo": {
    "provider": "openai",
    "auth_mode": "cli",
    "reset_type": "official",
    "base_url": "",
    "default_model": "",
    "env_map": {
      "key": "OPENAI_API_KEY",
      "token": "",
      "base": "OPENAI_BASE_URL",
      "model": "OPENAI_DEFAULT_MODEL"
    }
  },
  "api-demo": {
    "provider": "openai",
    "auth_mode": "key",
    "reset_type": "daily",
    "base_url": "https://api.example.test/v1",
    "default_model": "gpt-test",
    "env_map": {
      "key": "OPENAI_API_KEY",
      "token": "",
      "base": "OPENAI_BASE_URL",
      "model": "OPENAI_DEFAULT_MODEL"
    }
  }
}
EOF

printf '{}\n' > "$TV_MODELS"
printf '{}\n' > "$TV_USAGE_LOG"

source "$repo_root/tokenvault.plugin.zsh"

typeset -g _TV_MASTER_KEY="smoke-test-master-key"
_tv_crypto enc '{"api-demo":"sk-test-1234567890"}'

export TV_SMOKE_OUT="$tmp_root/oauth.out"
tv-run oauth-demo codex

oauth_home_expected="$TV_STATE_DIR/agents/codex/oauth-demo/home"
grep -q "^CODEX_HOME=${oauth_home_expected}\$" "$TV_SMOKE_OUT"
grep -q '^OPENAI_API_KEY=$' "$TV_SMOKE_OUT"

export TV_SMOKE_OUT="$tmp_root/api.out"
tv-run api-demo codex

api_home_expected="$TV_STATE_DIR/agents/codex/api-demo/home"
grep -q "^CODEX_HOME=${api_home_expected}\$" "$TV_SMOKE_OUT"
grep -q '^OPENAI_API_KEY=sk-test-1234567890$' "$TV_SMOKE_OUT"
grep -q '^OPENAI_BASE_URL=$' "$TV_SMOKE_OUT"
grep -q '^OPENAI_DEFAULT_MODEL=$' "$TV_SMOKE_OUT"

api_config="$api_home_expected/config.toml"
[[ -f "$api_config" ]]
grep -q 'model_provider = "tokenvault"' "$api_config"
grep -q 'base_url = "https://api.example.test/v1"' "$api_config"
grep -q 'model = "gpt-test"' "$api_config"

oauth_usage="$TV_STATE_DIR/logs/codex/oauth-demo/usage.jsonl"
api_usage="$TV_STATE_DIR/logs/codex/api-demo/usage.jsonl"
[[ -f "$oauth_usage" ]]
[[ -f "$api_usage" ]]

echo "smoke-ok"
