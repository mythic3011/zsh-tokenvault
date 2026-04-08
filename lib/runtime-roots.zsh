# Guard against double sourcing
[[ -n "${TV_RUNTIME_ROOTS_LOADED:-}" ]] && return 0
typeset -g TV_RUNTIME_ROOTS_LOADED=1

# --- RUNTIME ROOTS ---

_tv_runtime_roots() {
    local agent="$1" profile="$2" ensure="${3:-1}"

    [[ -z "$agent" || -z "$profile" ]] && return 1

    local config_root="${TV_DIR}/agents/${agent}/${profile}"
    local state_root="${TV_STATE_DIR}/agents/${agent}/${profile}"
    local cache_root="${TV_CACHE_DIR}/agents/${agent}/${profile}"
    local log_root="${TV_STATE_DIR}/logs/${agent}/${profile}"

    if [[ "$ensure" == "1" ]]; then
        _tv_ensure_dir "$config_root" 700 || return 1
        _tv_ensure_dir "$state_root" 700 || return 1
        _tv_ensure_dir "$cache_root" 700 || return 1
        _tv_ensure_dir "$log_root" 700 || return 1
    fi

    _tv_jq -n \
        --arg agent "$agent" \
        --arg profile "$profile" \
        --arg config_root "$config_root" \
        --arg state_root "$state_root" \
        --arg cache_root "$cache_root" \
        --arg log_root "$log_root" \
        '{
            agent: $agent,
            profile: $profile,
            config_root: $config_root,
            state_root: $state_root,
            cache_root: $cache_root,
            log_root: $log_root
        }'
}

tv_runtime_roots_open() {
    [[ -n "${TV_RUNTIME_ROOTS_OPENED:-}" ]] && return 0
    _tv_ensure_dir "$TV_STATE_DIR" 700
    TV_RUNTIME_ROOTS_OPENED=1
}

tv_runtime_roots_close() {
    TV_RUNTIME_ROOTS_OPENED=""
}
