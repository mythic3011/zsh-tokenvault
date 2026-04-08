# Guard against double sourcing
[[ -n "${TV_RUNTIME_POLICY_LOADED:-}" ]] && return 0
typeset -g TV_RUNTIME_POLICY_LOADED=1

# --- RUNTIME POLICY ---

_tv_runtime_policy_path() {
    local agent="$1" profile="$2"
    local roots
    roots=$(_tv_runtime_roots "$agent" "$profile" 1) || return 1
    echo "$roots" | _tv_jq -r '.config_root + "/policy.json"'
}

_tv_runtime_policy_scrublist_file() {
    local agent="$1" profile="$2"
    local roots
    roots=$(_tv_runtime_roots "$agent" "$profile" 1) || return 1
    echo "$roots" | _tv_jq -r '.config_root + "/env.scrublist"'
}

_tv_runtime_policy_allowlist_file() {
    local agent="$1" profile="$2"
    local roots
    roots=$(_tv_runtime_roots "$agent" "$profile" 1) || return 1
    echo "$roots" | _tv_jq -r '.config_root + "/env.allowlist"'
}

_tv_runtime_policy_read() {
    local agent="$1" profile="$2"
    local path
    path=$(_tv_runtime_policy_path "$agent" "$profile") || return 1
    _tv_safe_read_file "$path"
}

_tv_runtime_policy_write() {
    local agent="$1" profile="$2" content="$3"
    local path
    path=$(_tv_runtime_policy_path "$agent" "$profile") || return 1
    _tv_write_json "$path" "$content"
}

_tv_runtime_policy_bootstrap_from_profile() {
    local agent="$1" profile="$2" row="$3"
    local path
    path=$(_tv_runtime_policy_path "$agent" "$profile") || return 1

    local auth_mode launch_mode
    auth_mode=$(echo "$row" | _tv_jq -r '.auth_mode // "key"')
    launch_mode="api"
    [[ "$auth_mode" == "cli" ]] && launch_mode="oauth"

    local scrublist='["OPENAI_API_KEY","OPENAI_BASE_URL","OPENAI_API_BASE","OPENAI_DEFAULT_MODEL","OPENAI_ORG_ID","OPENAI_ORGANIZATION"]'
    local allowlist='["CODEX_HOME"]'

    local policy
    policy=$(_tv_jq -n \
        --arg launch_mode "$launch_mode" \
        --arg global_shadow_policy "forbid-conflict" \
        --arg mixed_state_policy "hard-fail" \
        --argjson env_scrublist "$scrublist" \
        --argjson env_allowlist "$allowlist" \
        '{
            launch_mode: $launch_mode,
            global_shadow_policy: $global_shadow_policy,
            mixed_state_policy: $mixed_state_policy,
            env_scrublist: $env_scrublist,
            env_allowlist: $env_allowlist
        }')

    _tv_runtime_policy_write "$agent" "$profile" "$policy" || return 1

    local scrublist_file allowlist_file
    scrublist_file=$(_tv_runtime_policy_scrublist_file "$agent" "$profile") || return 1
    allowlist_file=$(_tv_runtime_policy_allowlist_file "$agent" "$profile") || return 1

    _tv_atomic_write "$scrublist_file" "$(echo "$policy" | _tv_jq -r '.env_scrublist[]')" || return 1
    _tv_atomic_write "$allowlist_file" "$(echo "$policy" | _tv_jq -r '.env_allowlist[]')" || return 1
}

_tv_runtime_bootstrap_from_profile() {
    local agent="$1" profile="$2" row="$3"
    _tv_runtime_manifest_bootstrap_from_profile "$agent" "$profile" "$row" || return 1
    _tv_runtime_policy_bootstrap_from_profile "$agent" "$profile" "$row" || return 1
}

tv_runtime_policy_open() {
    [[ -n "${TV_RUNTIME_POLICY_OPENED:-}" ]] && return 0
    TV_RUNTIME_POLICY_OPENED=1
}

tv_runtime_policy_close() {
    TV_RUNTIME_POLICY_OPENED=""
}
