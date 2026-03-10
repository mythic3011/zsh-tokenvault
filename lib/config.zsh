# Guard against double sourcing
[[ -n "${TV_CONFIG_LOADED:-}" ]] && return 0
typeset -g TV_CONFIG_LOADED=1

# --- PATHS ---
typeset -g TV_DIR="${TV_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tokenvault}"
typeset -g TV_CACHE_DIR="${TV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/tokenvault}"
typeset -g TV_VAULT="${TV_VAULT:-$TV_DIR/vault.enc}"
typeset -g TV_PROFILES="${TV_PROFILES:-$TV_DIR/profiles.json}"
typeset -g TV_MODELS="${TV_MODELS:-$TV_DIR/models.json}"
typeset -g TV_USAGE_LOG="${TV_USAGE_LOG:-$TV_DIR/usage.jsonl}"
typeset -g TV_PROMPT_CACHE="${TV_PROMPT_CACHE:-$TV_CACHE_DIR/.prompt_rendered}"
typeset -g TV_WORKER_LOCK="${TV_WORKER_LOCK:-$TV_CACHE_DIR/.worker.lock}"
typeset -g TV_UNSAFE_FILE="${TV_UNSAFE_FILE:-$TV_DIR/.unsafe_pass}"

# --- VERSION / DEFAULTS ---
typeset -g TV_QUOTA_API_URL="${TV_QUOTA_API_URL:-https://example.com/api/route/to/quota/check}"
typeset -g TV_VERSION="${TV_VERSION:-7.0}"
typeset -g TV_UPDATE_METADATA_URL="${TV_UPDATE_METADATA_URL:-https://example.com/tokenvault/latest.json}"

# --- RUNTIME STATE ---
typeset -g _TV_MASTER_KEY="${_TV_MASTER_KEY:-}"
typeset -g _TV_IS_UNSAFE="${_TV_IS_UNSAFE:-0}"
typeset -g _TV_LAST_RENDER_TIME="${_TV_LAST_RENDER_TIME:-0}"

# --- COLORS ---
typeset -g _TV_RST="${_TV_RST:-%f%k%b}"
typeset -g _TV_RED="${_TV_RED:-%F{196}}"
typeset -g _TV_GRN="${_TV_GRN:-%F{46}}"
typeset -g _TV_YEL="${_TV_YEL:-%F{226}}"
typeset -g _TV_GRY="${_TV_GRY:-%F{240}}"
typeset -g _TV_CYA="${_TV_CYA:-%F{51}}"
typeset -g _TV_BLU="${_TV_BLU:-%F{39}}"
typeset -g _TV_WHT="${_TV_WHT:-%F{255}}"
typeset -g _TV_MGT="${_TV_MGT:-%F{201}}"

# --- ENV UNSET LISTS ---
typeset -ga _TV_UNSET_anthropic=(
    ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    ANTHROPIC_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
    ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL
    CLAUDE_CODE_SUBAGENT_MODEL
)
typeset -ga _TV_UNSET_openai=(
    OPENAI_API_KEY OPENAI_BASE_URL OPENAI_API_BASE OPENAI_DEFAULT_MODEL
)
typeset -ga _TV_UNSET_gemini=(
    GEMINI_API_KEY GEMINI_DEFAULT_MODEL GOOGLE_API_KEY
)
