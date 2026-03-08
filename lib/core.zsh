# Guard against double sourcing
[[ -n "${TV_CORE_LOADED:-}" ]] && return 0
typeset -g TV_CORE_LOADED=1

# --- PATHS ---
TV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tokenvault"
TV_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tokenvault"
TV_VAULT="$TV_DIR/vault.enc"
TV_PROFILES="$TV_DIR/profiles.json"
TV_MODELS="$TV_DIR/models.json"
TV_USAGE_LOG="$TV_DIR/usage.jsonl"
TV_PROMPT_CACHE="$TV_CACHE_DIR/.prompt_rendered"
TV_WORKER_LOCK="$TV_CACHE_DIR/.worker.lock"
TV_UNSAFE_FILE="$TV_DIR/.unsafe_pass"
TV_QUOTA_API_URL="${TV_QUOTA_API_URL:-"https://example.com/api/route/to/quota/check"}"
# --- VERSION / UPDATE ---
typeset -g TV_VERSION="${TV_VERSION:-7.0}"
typeset -g TV_UPDATE_METADATA_URL="${TV_UPDATE_METADATA_URL:-https://example.com/tokenvault/latest.json}"
typeset -g _TV_MASTER_KEY=""
typeset -g _TV_IS_UNSAFE=0
typeset -g _TV_LAST_RENDER_TIME=0

# --- COLORS ---
_TV_RST="%f%k%b"
_TV_RED="%F{196}"; _TV_GRN="%F{46}";  _TV_YEL="%F{226}"
_TV_GRY="%F{240}"; _TV_CYA="%F{51}";  _TV_BLU="%F{39}"
_TV_WHT="%F{255}"; _TV_MGT="%F{201}"

# --- ENV UNSET LISTS ---
_TV_UNSET_anthropic=(
    ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    ANTHROPIC_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
    ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL
    CLAUDE_CODE_SUBAGENT_MODEL
)
_TV_UNSET_openai=(
    OPENAI_API_KEY OPENAI_BASE_URL OPENAI_API_BASE OPENAI_DEFAULT_MODEL
)
_TV_UNSET_gemini=(
    GEMINI_API_KEY GEMINI_DEFAULT_MODEL GOOGLE_API_KEY
)

# --- INTERNATIONALIZATION ---
typeset -g TV_LANG="${TV_LANG:-${LANG%%.*:-en}}"

_tv_i18n_locale() {
    local lang="${TV_LANG:-${LANG%%.*:-en}}"
    lang=${lang//_/\-}
    lang=${lang:l}
    case "$lang" in
        zh-hk|zh-hant-hk|zh-hant) echo "zh_hk" ;;
        zh-tw) echo "zh_tw" ;;
        zh-cn|zh-hans) echo "zh_cn" ;;
        *) echo "en" ;;
    esac
}

_tv_tr() {
    local key="$1" default="${2:-$1}"
    local locale="$(_tv_i18n_locale)"
    local map="_TV_I18N_${locale}"
    local text
    text=$(eval "printf '%s' \"\${${map}[${key}]:-}\"" 2>/dev/null)
    if [[ -n "$text" ]]; then
        printf '%s' "$text"
    else
        printf '%s' "$default"
    fi
}

typeset -A _TV_I18N_en=(
    profile_id_prompt "Profile ID"
    provider_title "Provider"
    auth_mode_title "Auth mode"
    base_url_prompt "Proxy / Base URL (blank = official endpoint)"
    quota_api_prompt "Quota check API URL"
    reset_type_title "Reset type"
    env_vars_header "Env var names (Enter = keep default)"
    key_env_prompt "Key env"
    base_env_prompt "Base env"
    model_env_prompt "Model env"
    api_key_prompt "API Key"
    model_fetching "Fetching model list..."
    models_available "Available models:"
    skip_option "Skip"
    default_model_prompt "Default model"
    add_profile_title "Add Profile"
    add_key_title "Add Key"
    help_vault "Vault"
    help_profiles "Profiles"
    help_add "Interactive add"
    help_add_cli "CLI add"
    help_rotate_key "Add/rotate key for existing profile"
    help_remove "Remove profile"
    help_list "List all profiles"
    help_run "Run command"
    help_help "Help"
    update_title "Update TokenVault"
    update_prompt "Update to version %s?"
    update_success "Updated to version %s"
    update_already_latest "Already at version %s"
    update_error "Update failed: %s"
    update_cancelled "Update cancelled"
)
typeset -A _TV_I18N_zh_hk=(
    profile_id_prompt "設定檔 ID"
    provider_title "提供者"
    auth_mode_title "驗證方式"
    base_url_prompt "代理 / 基本網址（空白使用官方）"
    quota_api_prompt "配額查詢 API URL"
    reset_type_title "重設類型"
    env_vars_header "環境變數名稱（Enter 保留預設）"
    key_env_prompt "Key 環境"
    base_env_prompt "Base 環境"
    model_env_prompt "Model 環境"
    api_key_prompt "API 金鑰"
    model_fetching "正在擷取模型清單..."
    models_available "可用模型："
    skip_option "跳過"
    default_model_prompt "預設模型"
    add_profile_title "新增設定檔"
    add_key_title "新增金鑰"
    help_vault "金庫"
    help_profiles "設定檔"
    help_add "互動式新增"
    help_add_cli "CLI 新增"
    help_rotate_key "新增/更新現有設定檔金鑰"
    help_remove "刪除設定檔"
    help_list "列出所有設定檔"
    help_run "執行指令"
    help_help "說明"
    update_title "更新 TokenVault"
    update_prompt "要更新到版本 %s 嗎？"
    update_success "已更新至版本 %s"
    update_already_latest "已經是版本 %s"
    update_error "更新失敗：%s"
    update_cancelled "已取消更新"
)
typeset -A _TV_I18N_zh_cn=(
    profile_id_prompt "配置 ID"
    provider_title "提供者"
    auth_mode_title "认证方式"
    base_url_prompt "代理 / 基础 URL（留空使用官方）"
    quota_api_prompt "配额查询 API URL"
    reset_type_title "重置类型"
    env_vars_header "环境变量名（Enter 保留默认）"
    key_env_prompt "Key 环境"
    base_env_prompt "Base 环境"
    model_env_prompt "Model 环境"
    api_key_prompt "API 密钥"
    model_fetching "正在获取模型列表..."
    models_available "可用模型："
    skip_option "跳过"
    default_model_prompt "默认模型"
    add_profile_title "新增配置"
    add_key_title "新增密钥"
    help_vault "金库"
    help_profiles "配置"
    help_add "交互式添加"
    help_add_cli "CLI 添加"
    help_rotate_key "为现有配置添加/更新密钥"
    help_remove "移除配置"
    help_list "列出所有配置"
    help_run "执行命令"
    help_help "帮助"
    update_title "更新 TokenVault"
    update_prompt "要更新到版本 %s 吗？"
    update_success "已更新到版本 %s"
    update_already_latest "已经是版本 %s"
    update_error "更新失败：%s"
    update_cancelled "已取消更新"
)
typeset -A _TV_I18N_zh_tw=(
    profile_id_prompt "設定檔 ID"
    provider_title "提供者"
    auth_mode_title "驗證方式"
    base_url_prompt "代理 / 基本網址（留白使用官方）"
    quota_api_prompt "額度查詢 API URL"
    reset_type_title "重設類型"
    env_vars_header "環境變數名稱（Enter 保留預設）"
    key_env_prompt "Key 環境"
    base_env_prompt "Base 環境"
    model_env_prompt "Model 環境"
    api_key_prompt "API 金鑰"
    model_fetching "正在擷取模型清單..."
    models_available "可用模型："
    skip_option "跳過"
    default_model_prompt "預設模型"
    add_profile_title "新增設定檔"
    add_key_title "新增金鑰"
    help_vault "金庫"
    help_profiles "設定檔"
    help_add "互動式新增"
    help_add_cli "CLI 新增"
    help_rotate_key "為現有設定檔新增/更新金鑰"
    help_remove "移除設定檔"
    help_list "列出所有設定檔"
    help_run "執行命令"
    help_help "說明"
    update_title "更新 TokenVault"
    update_prompt "要更新到版本 %s 嗎？"
    update_success "已更新至版本 %s"
    update_already_latest "已經是版本 %s"
    update_error "更新失敗：%s"
    update_cancelled "已取消更新"
)

# --- HELPERS ---
_tv_print()  { print -P "$1"; }
_tv_banner() {
    _tv_print "\n${_TV_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_TV_RST}"
    _tv_print " 💎 ${_TV_WHT}TokenVault${_TV_RST}  ${_TV_GRY}$1${_TV_RST}"
    _tv_print "${_TV_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_TV_RST}\n"
}

_tv_fmt_num() {
    local n=$(echo "${1:-0}" | sed 's/[^0-9]//g'); n=${n:-0}
    if   (( n > 999999 )); then printf "%.1fM" $(echo "$n / 1000000" | bc -l)
    elif (( n > 999    )); then printf "%.1fk" $(echo "$n / 1000"    | bc -l)
    else echo "$n"; fi
}

_tv_short_key() {
    local key="$1"
    [[ -z "$key" ]] && { printf ''; return 0; }
    local prefix="${key:0:5}"
    local suffix="$key"
    if (( ${#key} > 4 )); then
        suffix="${key: -4}"
    fi
    printf '%s..%s' "$prefix" "$suffix"
}

_tv_prompt_exit() {
    local status="$1" msg="${2:-Cancelled}"
    (( status == 2 )) && { _tv_print "  ${_TV_GRY}${msg}${_TV_RST}"; return 0; }
    return 1
}

_tv_verify_sha256() {
    local file="$1" expected="$2"
    [[ -z "$expected" ]] && return 0
    local actual
    if command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        actual=$(openssl dgst -sha256 "$file" 2>/dev/null | awk '{print $NF}')
    else
        return 2
    fi
    [[ "$actual" == "$expected" ]]
}

_tv_coerce_int() {
    local val="${1:-0}"
    val="${val//[^0-9-]/}"
    [[ -z "$val" || "$val" == "-" ]] && val="0"
    printf '%s' "$val"
}

_tv_write_json() {
    local file="$1" content="$2"
    local dir; dir=$(dirname "$file")
    local tmp
    tmp=$(_tv_mktemp "$dir/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    echo "$content" > "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

_tv_mktemp() {
    local tmpl="$1"
    local old_umask
    old_umask=$(umask)
    umask 077
    local tmp
    tmp=$(mktemp "$tmpl")
    local rc=$?
    umask "$old_umask"
    (( rc != 0 )) && return $rc
    printf '%s' "$tmp"
}

_tv_init() {
    [[ ! -d "$TV_DIR" ]]       && mkdir -p "$TV_DIR"       && chmod 700 "$TV_DIR"
    [[ ! -d "$TV_CACHE_DIR" ]] && mkdir -p "$TV_CACHE_DIR" && chmod 700 "$TV_CACHE_DIR"
    [[ ! -f "$TV_PROFILES" ]]  && echo "{}" > "$TV_PROFILES"
    [[ ! -f "$TV_MODELS" ]]    && echo "{}" > "$TV_MODELS"
    [[ ! -f "$TV_USAGE_LOG" ]] && touch "$TV_USAGE_LOG"
    rm -rf "$TV_WORKER_LOCK" 2>/dev/null
    if [[ -f "$TV_UNSAFE_FILE" ]]; then
        _TV_MASTER_KEY=$(cat "$TV_UNSAFE_FILE" 2>/dev/null)
        _TV_IS_UNSAFE=1
    fi
}

_tv_crypto() {
    local mode="$1"; shift
    [[ -z "$_TV_MASTER_KEY" ]] && return 1
    if [[ "$mode" == "enc" ]]; then
        local tmp
        tmp=$(_tv_mktemp "$TV_DIR/.vault_tmp.XXXXXX") || return 1
        chmod 600 "$tmp"
        echo "$1" | openssl enc -aes-256-cbc -a -pbkdf2 -salt \
            -pass fd:3 3< <(printf '%s' "$_TV_MASTER_KEY") > "$tmp" 2>/dev/null \
            && mv -f "$tmp" "$TV_VAULT" || { rm -f "$tmp"; return 1; }
        chmod 600 "$TV_VAULT"
    else
        [[ ! -f "$TV_VAULT" ]] && { echo "{}"; return 0; }
        openssl enc -aes-256-cbc -d -a -pbkdf2 \
            -pass fd:3 3< <(printf '%s' "$_TV_MASTER_KEY") \
            -in "$TV_VAULT" 2>/dev/null
    fi
}

tv_core_open() {
    [[ -n "${TV_CORE_OPENED:-}" ]] && return 0
    _tv_init
    TV_CORE_OPENED=1
}

tv_core_close() {
    TV_CORE_OPENED=""
}
