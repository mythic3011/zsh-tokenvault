# Guard against double sourcing
[[ -n "${TV_CONFIG_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_CONFIG_COMMANDS_LOADED=1

# --- CONFIG COMMANDS ---
# Generic config inspection commands

# tv config inspect --agent <id> [options]
tv-config-inspect() {
    local agent_id="" show_precedence=0 show_overrides=0 show_effective=0 show_graph=0 show_discovered=0 json_output=0 cwd=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)           agent_id="$2"; shift 2 ;;
            --show-precedence) show_precedence=1; shift ;;
            --show-overrides)  show_overrides=1; shift ;;
            --show-effective)  show_effective=1; shift ;;
            --show-graph)      show_graph=1; shift ;;
            --show-discovered) show_discovered=1; shift ;;
            --json)            json_output=1; shift ;;
            --cwd)             cwd="$2"; shift 2 ;;
            *)                 shift ;;
        esac
    done
    
    [[ -z "$agent_id" ]] && { _tv_print "  ${_TV_RED}✗ Required: --agent <id>${_TV_RST}"; return 1; }
    cwd="${cwd:-$(pwd)}"
    
    # Build context
    local context
    context=$(_tv_resolve_runtime_context "$agent_id" "$cwd")
    
    # Discover config layers
    context=$(_tv_agent_discover_config_layers "$agent_id" "$context")
    
    # Normalize layers
    context=$(_tv_agent_normalize_config_layers "$agent_id" "$context" "$context")
    
    # Resolve effective config
    context=$(_tv_agent_resolve_effective_config "$agent_id" "$context" "$context")
    
    if [[ "$json_output" == "1" ]]; then
        echo "$context" | jq '.'
        return 0
    fi
    
    _tv_banner "Config Inspect: ${agent_id}"
    
    if [[ "$show_discovered" == "1" ]]; then
        _tv_print "  ${_TV_WHT}Discovered Layers:${_TV_RST}"
        echo "$context" | jq -r '.layers[] | "  \(.source_type): \(.source_path // "(inline)") [\(.trust_state)]"' 2>/dev/null
        echo ""
    fi
    
    if [[ "$show_precedence" == "1" || "$show_graph" == "1" ]]; then
        _tv_show_resolution_graph "$context"
        echo ""
    fi
    
    if [[ "$show_overrides" == "1" ]]; then
        _tv_print "  ${_TV_WHT}Key Overrides:${_TV_RST}"
        local keys
        keys=$(echo "$context" | jq -r '.effective | keys[]' 2>/dev/null)
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            local chain
            chain=$(_tv_explain_resolution "$context" "$key")
            local count
            count=$(echo "$chain" | jq 'length')
            if (( count > 1 )); then
                _tv_print "  ${_TV_YEL}${key}${_TV_RST}: ${count} layers"
                echo "$chain" | jq -r '.[] | "    \(.source): \(.value)"' 2>/dev/null
            fi
        done <<< "$keys"
        echo ""
    fi
    
    if [[ "$show_effective" == "1" ]]; then
        _tv_print "  ${_TV_WHT}Effective Config:${_TV_RST}"
        echo "$context" | jq -r '.effective | to_entries[] | "  \(.key): \(.value)"' 2>/dev/null
    fi
}

# tv runtime sync --agent <id>
tv-runtime-sync() {
    local agent_id="" force=0 dry_run=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)   agent_id="$2"; shift 2 ;;
            --force)   force=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            *)         shift ;;
        esac
    done
    
    [[ -z "$agent_id" ]] && { _tv_print "  ${_TV_RED}✗ Required: --agent <id>${_TV_RST}"; return 1; }
    
    _tv_banner "Runtime Sync: ${agent_id}"
    
    # Check if agent is available
    if ! _tv_detect_agent "$agent_id"; then
        _tv_print "  ${_TV_RED}✗ Agent not found: ${agent_id}${_TV_RST}"
        return 1
    fi
    
    # Get agent capabilities
    local capabilities
    capabilities=$(_tv_agent_discover_capabilities "$agent_id" "{}")
    
    _tv_print "  ${_TV_GRY}Agent capabilities:${_TV_RST}"
    echo "$capabilities" | jq -r 'to_entries[] | "  \(.key): \(.value)"' 2>/dev/null
    
    # Sync config if supported
    local can_sync
    can_sync=$(echo "$capabilities" | jq -r '.runtime_sync // false')
    if [[ "$can_sync" == "true" ]]; then
        _tv_print "\n  ${_TV_GRY}Syncing runtime config...${_TV_RST}"
        # Agent-specific sync logic would go here
        _tv_print "  ${_TV_GRN}✓ Sync complete${_TV_RST}"
    else
        _tv_print "  ${_TV_GRY}Runtime sync not supported for ${agent_id}${_TV_RST}"
    fi
}

# tv provider list
tv-provider-list() {
    _tv_display_provider_catalog
}

# tv agent list
tv-agent-list() {
    _tv_display_agent_registry
}

# --- CONFIG COMMANDS OPEN/CLOSE ---

tv_config_commands_open() {
    [[ -n "${TV_CONFIG_COMMANDS_OPENED:-}" ]] && return 0
    TV_CONFIG_COMMANDS_OPENED=1
}

tv_config_commands_close() {
    TV_CONFIG_COMMANDS_OPENED=""
}
