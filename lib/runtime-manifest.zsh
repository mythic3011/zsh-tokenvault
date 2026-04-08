# Guard against double sourcing
[[ -n "${TV_RUNTIME_MANIFEST_LOADED:-}" ]] && return 0
typeset -g TV_RUNTIME_MANIFEST_LOADED=1

# --- RUNTIME MANIFEST ---

_tv_runtime_manifest_path() {
    local agent="$1" profile="$2"
    local roots
    roots=$(_tv_runtime_roots "$agent" "$profile" 1) || return 1
    echo "$roots" | _tv_jq -r '.config_root + "/manifest.json"'
}

_tv_runtime_manifest_read() {
    local agent="$1" profile="$2"
    local path
    path=$(_tv_runtime_manifest_path "$agent" "$profile") || return 1
    _tv_safe_read_file "$path"
}

_tv_runtime_manifest_write() {
    local agent="$1" profile="$2" content="$3"
    local path
    path=$(_tv_runtime_manifest_path "$agent" "$profile") || return 1
    _tv_write_json "$path" "$content"
}

_tv_runtime_manifest_bootstrap_from_profile() {
    local agent="$1" profile="$2" row="$3"
    local path
    path=$(_tv_runtime_manifest_path "$agent" "$profile") || return 1

    local provider auth_mode now created_at
    provider=$(echo "$row" | _tv_jq -r '.provider // "unknown"')
    auth_mode=$(echo "$row" | _tv_jq -r '.auth_mode // "key"')
    now=$(/bin/date -u +%FT%TZ)
    created_at="$now"
    if [[ -f "$path" ]]; then
        created_at=$(_tv_jq -r '.created_at // empty' "$path" 2>/dev/null)
        [[ -z "$created_at" || "$created_at" == "null" ]] && created_at="$now"
    fi

    local manifest
    manifest=$(_tv_jq -n \
        --arg schema_version "1" \
        --arg agent "$agent" \
        --arg profile "$profile" \
        --arg provider "$provider" \
        --arg auth_mode "$auth_mode" \
        --arg created_at "$created_at" \
        --arg updated_at "$now" \
        '{
            schema_version: $schema_version,
            agent: $agent,
            profile: $profile,
            provider: $provider,
            auth_mode: $auth_mode,
            created_at: $created_at,
            updated_at: $updated_at
        }')

    _tv_runtime_manifest_write "$agent" "$profile" "$manifest"
}

tv_runtime_manifest_open() {
    [[ -n "${TV_RUNTIME_MANIFEST_OPENED:-}" ]] && return 0
    TV_RUNTIME_MANIFEST_OPENED=1
}

tv_runtime_manifest_close() {
    TV_RUNTIME_MANIFEST_OPENED=""
}
