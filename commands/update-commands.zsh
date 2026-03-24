# Guard against double sourcing
[[ -n "${TV_UPDATE_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_UPDATE_COMMANDS_LOADED=1

# --- UPDATE COMMANDS ---
# Self-update and adapter update commands

# tv self update [options]
tv-self-update-cmd() {
    local action="${1:---check}"
    tv-self-update "$action"
}

# tv adapter update --agent <id>
tv-adapter-update() {
    local agent_id="" force=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent_id="$2"; shift 2 ;;
            --force) force=1; shift ;;
            *)       shift ;;
        esac
    done
    
    [[ -z "$agent_id" ]] && { _tv_print "  ${_TV_RED}✗ Required: --agent <id>${_TV_RST}"; return 1; }
    
    _tv_banner "Adapter Update: ${agent_id}"
    
    # Check current version
    local current_version
    current_version=$(_tv_get_adapter_version "$agent_id")
    _tv_print "  ${_TV_GRY}Current adapter version: ${current_version}${_TV_RST}"
    
    # Check for agent updates
    local update_info
    update_info=$(_tv_agent_check_update "$agent_id" "{}")
    
    local has_update
    has_update=$(echo "$update_info" | jq -r '.has_update // false')
    
    if [[ "$has_update" == "true" ]]; then
        local latest_version
        latest_version=$(echo "$update_info" | jq -r '.latest_version // "unknown"')
        _tv_print "  ${_TV_YEL}⚠ Update available: ${current_version} → ${latest_version}${_TV_RST}"
        
        if [[ "$force" != "1" ]]; then
            read "?  Install update? (y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { _tv_print "  ${_TV_GRY}Cancelled${_TV_RST}"; return 0; }
        fi
        
        # Update adapter version in version file
        local tmp
        tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
        chmod 600 "$tmp"
        
        jq --arg id "$agent_id" --arg ver "$latest_version" \
            '.adapters[$id].adapter_version = $ver' "$TV_VERSION_FILE" > "$tmp" \
            && mv -f "$tmp" "$TV_VERSION_FILE" || { rm -f "$tmp"; return 1; }
        
        _tv_print "  ${_TV_GRN}✓ Adapter updated to ${latest_version}${_TV_RST}"
    else
        _tv_print "  ${_TV_GRN}✓ Adapter is up to date${_TV_RST}"
    fi
}

# tv update registry
tv-update-registry-cmd() {
    tv-update-registry
}

# --- UPDATE COMMANDS OPEN/CLOSE ---

tv_update_commands_open() {
    [[ -n "${TV_UPDATE_COMMANDS_OPENED:-}" ]] && return 0
    TV_UPDATE_COMMANDS_OPENED=1
}

tv_update_commands_close() {
    TV_UPDATE_COMMANDS_OPENED=""
}
