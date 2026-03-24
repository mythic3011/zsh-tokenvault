# Guard against double sourcing
[[ -n "${TV_I18N_LOADED:-}" ]] && return 0
typeset -g TV_I18N_LOADED=1

# --- I18N MODULE ---
# Loads translations from external JSON files in i18n/ directory
# Easy to update and extend without modifying core code

typeset -g TV_LANG="${TV_LANG:-${LANG:-en}}"
TV_LANG="${TV_LANG%%.*}"

typeset -g TV_I18N_DIR="${TV_PLUGIN_DIR:-${TV_PLUGIN_PATH:A:h}}/i18n"
typeset -gA _TV_I18N_CACHE=()

# Detect locale
_tv_i18n_locale() {
    local lang="${TV_LANG:-${LANG:-en}}"
    lang="${lang%%.*}"
    lang=${lang//_/\-}
    lang=${lang:l}
    case "$lang" in
        zh-hk|zh-hant-hk|zh-hant) echo "zh_hk" ;;
        zh-tw) echo "zh_tw" ;;
        zh-cn|zh-hans) echo "zh_cn" ;;
        *) echo "en" ;;
    esac
}

# Load translations from JSON file
_tv_i18n_load() {
    local locale="$1"
    local cache_key="i18n_${locale}"
    
    # Return cached if available
    [[ -n "${_TV_I18N_CACHE[$cache_key]:-}" ]] && return 0
    
    local json_file="${TV_I18N_DIR}/${locale}.json"
    
    # Fallback to English if locale file not found
    if [[ ! -f "$json_file" ]]; then
        json_file="${TV_I18N_DIR}/en.json"
    fi
    
    # Still not found, use empty
    if [[ ! -f "$json_file" ]]; then
        _TV_I18N_CACHE[$cache_key]="{}"
        return 0
    fi
    
    # Load and cache
    _TV_I18N_CACHE[$cache_key]=$(cat "$json_file")
}

# Translate a key
# Usage: _tv_tr <key> [default]
_tv_tr() {
    local key="$1" default="${2:-$1}"
    local locale="$(_tv_i18n_locale)"
    
    # Load translations
    _tv_i18n_load "$locale"
    
    local cache_key="i18n_${locale}"
    local translations="${_TV_I18N_CACHE[$cache_key]:-{}}"
    
    # Try to get translation
    local text
    text=$(echo "$translations" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null)
    
    if [[ -n "$text" ]]; then
        printf '%s' "$text"
    else
        printf '%s' "$default"
    fi
}

# Translate with sprintf-style formatting
# Usage: _tv_trf <key> <args...>
_tv_trf() {
    local key="$1"
    shift
    local template
    template=$(_tv_tr "$key")
    printf "$template" "$@"
}

# List available locales
_tv_i18n_list_locales() {
    [[ ! -d "$TV_I18N_DIR" ]] && return 0
    find "$TV_I18N_DIR" -name "*.json" -type f 2>/dev/null | \
        sed 's|.*/||; s|\.json$||' | sort
}

# Reload translations (useful after updates)
_tv_i18n_reload() {
    _TV_I18N_CACHE=()
}

# --- I18N OPEN/CLOSE ---

tv_i18n_open() {
    [[ -n "${TV_I18N_OPENED:-}" ]] && return 0
    TV_I18N_OPENED=1
}

tv_i18n_close() {
    TV_I18N_OPENED=""
}
