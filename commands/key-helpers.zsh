# Guard against double sourcing
[[ -n "${TV_KEY_HELPERS_LOADED:-}" ]] && return 0
typeset -g TV_KEY_HELPERS_LOADED=1

# --- KEY HELPER COMMANDS ---
# Quick key management commands

# tv-key-rotate: Add/rotate key for existing profile
tv-key-rotate() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "run_tv_unlock_first" "Run tv-unlock first")${_TV_RST}"; return 1; }
    
    local p_id="$1"
    [[ -z "$p_id" ]] && { print -Pn "  $(_tv_tr "rotate_key_prompt" "Profile ID to rotate key"): "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1
    
    local exists
    exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_trf "profile_not_found" "Profile not found: %s" "$p_id")${_TV_RST}"; return 1; }
    
    local rotate_title
    printf -v rotate_title "$(_tv_tr "rotate_key_title" "Rotate Key: %s")" "$p_id"
    _tv_banner "$rotate_title"
    
    local row
    row=$(jq -c --arg p "$p_id" '.[$p]' "$TV_PROFILES")
    local prov
    prov=$(echo "$row" | jq -r '.provider')
    local auth_mode
    auth_mode=$(echo "$row" | jq -r '.auth_mode // "key"')
    
    if [[ "$auth_mode" == "cli" ]]; then
        _tv_print "  ${_TV_YEL}⚠ $(_tv_tr "profile_cli_auth_no_rotate" "Profile uses CLI auth — no key to rotate")${_TV_RST}"
        return 0
    fi
    
    # Get new key
    printf "\n  %s: " "$(_tv_tr "new_api_key_prompt" "New API Key")"
    read -rs new_key
    echo ""
    new_key=${new_key//[[:space:]]/}
    [[ -z "$new_key" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "key_required" "Key required")${_TV_RST}"; return 1; }
    
    # Update vault
    local v
    v=$(_tv_crypto dec)
    _tv_crypto enc "$(echo "$v" | jq --arg p "$p_id" --arg k "$new_key" '.[$p] = $k')"
    
    # Update profile short key
    local short
    short=$(_tv_short_key "$new_key")
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" --arg s "$short" '.[$p].short = $s' "$TV_PROFILES" > "$tmp" \
        && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }
    
    _tv_print "\n  ${_TV_GRN}✓ $(_tv_trf "key_rotated_for" "Key rotated for [%s]" "$p_id")${_TV_RST}"
    _tv_spawn_worker
}

# tv-key-status: Show key status for all profiles
tv-key-status() {
    _tv_banner "Key Status"
    
    if [[ -z "$_TV_MASTER_KEY" ]]; then
        _tv_print "  ${_TV_RED}✗ $(_tv_tr "vault_locked_run_unlock" "Vault locked — run tv-unlock first")${_TV_RST}"
        return 1
    fi
    
    local vault
    vault=$(_tv_crypto dec)
    
    _tv_print "$(printf "  %-15s %-12s %-10s %-15s %-8s" "PROFILE" "PROVIDER" "AUTH" "KEY STATUS" "REMAIN")"
    _tv_print "  ${_TV_GRY}$(printf '%.0s─' {1..65})${_TV_RST}"
    
    jq -r 'to_entries[] | "\(.key)|\(.value.provider)|\(.value.auth_mode // "key")|\(.value.status)|\(.value.remain)"' \
        "$TV_PROFILES" | \
    while IFS='|' read -r id prov am st rem; do
        local key_status="no_key"
        if [[ "$am" == "cli" ]]; then
            key_status="cli_auth"
        else
            local has_key
            has_key=$(echo "$vault" | jq -r --arg p "$id" 'has($p)')
            if [[ "$has_key" == "true" ]]; then
                key_status="stored"
            fi
        fi
        
        local col="$_TV_GRN"
        [[ "$st" == "disabled"  ]] && col="$_TV_RED"
        [[ "$st" == "exhausted" ]] && col="$_TV_YEL"
        [[ "$key_status" == "no_key" ]] && col="$_TV_RED"
        
        _tv_print "$(printf "  %-15s %-12s %-10s ${col}%-15s${_TV_RST} %-8s" "$id" "$prov" "$am" "$key_status" "$rem")"
    done
}

# tv-add-key: Alias for tv-add with key focus
tv-add-key() {
    tv-add "$@"
}

# --- KEY HELPERS OPEN/CLOSE ---

tv_key_helpers_open() {
    [[ -n "${TV_KEY_HELPERS_OPENED:-}" ]] && return 0
    TV_KEY_HELPERS_OPENED=1
}

tv_key_helpers_close() {
    TV_KEY_HELPERS_OPENED=""
}
