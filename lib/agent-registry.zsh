# Guard against double sourcing
[[ -n "${TV_AGENT_REGISTRY_LOADED:-}" ]] && return 0
typeset -g TV_AGENT_REGISTRY_LOADED=1

# --- AGENT REGISTRY ---
# Manages the registry of available agents and their adapters
# Registry can be fetched from GitHub or updated via tv-update-registry command
# Default data loaded from providers/agent_registry_default.json

typeset -g TV_AGENT_REGISTRY_FILE="${TV_DIR}/agent_registry.json"
typeset -g TV_AGENT_REGISTRY_CACHE="${TV_CACHE_DIR}/agent_registry_cache.json"
typeset -g TV_AGENT_REGISTRY_REMOTE="${TV_AGENT_REGISTRY_REMOTE:-https://raw.githubusercontent.com/mythic3011/tokenvault/main/providers/agent_registry.json}"
typeset -g TV_AGENT_REGISTRY_TTL="${TV_AGENT_REGISTRY_TTL:-86400}"  # 24 hours default
typeset -g TV_AGENT_REGISTRY_DEFAULT_FILE="${TV_PLUGIN_DIR:-${TV_PLUGIN_PATH:A:h}}/providers/agent_registry_default.json"

# Initialize agent registry (from cache, local, or remote)
_tv_init_agent_registry() {
    # If local file exists and is recent, use it
    if [[ -f "$TV_AGENT_REGISTRY_FILE" ]]; then
        local now mtime age
        now=$(date +%s)
        mtime=$(stat -f %m "$TV_AGENT_REGISTRY_FILE" 2>/dev/null || stat -c %Y "$TV_AGENT_REGISTRY_FILE" 2>/dev/null || echo 0)
        age=$(( now - mtime ))
        
        # If file is fresh enough, use it
        if (( age < TV_AGENT_REGISTRY_TTL )); then
            return 0
        fi
    fi
    
    # Try to fetch from remote
    if _tv_fetch_agent_registry; then
        return 0
    fi
    
    # Fallback: copy from external default file
    if [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]]; then
        if [[ -f "$TV_AGENT_REGISTRY_DEFAULT_FILE" ]]; then
            cp "$TV_AGENT_REGISTRY_DEFAULT_FILE" "$TV_AGENT_REGISTRY_FILE"
        else
            echo '{}' > "$TV_AGENT_REGISTRY_FILE"
        fi
        chmod 600 "$TV_AGENT_REGISTRY_FILE"
    fi
}

# Fetch agent registry from remote GitHub source
_tv_fetch_agent_registry() {
    local url="$TV_AGENT_REGISTRY_REMOTE"
    [[ -z "$url" ]] && return 1
    
    local resp
    resp=$(curl -s -L -m 10 --connect-timeout 5 "$url" 2>/dev/null)
    
    # Validate JSON response
    if echo "$resp" | jq -e '.' >/dev/null 2>&1; then
        # Cache the response
        echo "$resp" > "$TV_AGENT_REGISTRY_CACHE"
        chmod 600 "$TV_AGENT_REGISTRY_CACHE"
        
        # Update local registry (merge with local customizations)
        if [[ -f "$TV_AGENT_REGISTRY_FILE" ]]; then
            local tmp
            tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
            chmod 600 "$tmp"
            
            # Merge: remote as base, local overrides preserved
            jq -s '.[0] * .[1]' "$TV_AGENT_REGISTRY_CACHE" "$TV_AGENT_REGISTRY_FILE" > "$tmp" \
                && mv -f "$tmp" "$TV_AGENT_REGISTRY_FILE" || { rm -f "$tmp"; return 1; }
        else
            cp "$TV_AGENT_REGISTRY_CACHE" "$TV_AGENT_REGISTRY_FILE"
            chmod 600 "$TV_AGENT_REGISTRY_FILE"
        fi
        return 0
    fi
    return 1
}

# Force update agent registry from remote
tv-update-registry() {
    _tv_banner "Update Agent Registry"
    _tv_print "  ${_TV_GRY}Fetching from ${TV_AGENT_REGISTRY_REMOTE}...${_TV_RST}"
    
    if _tv_fetch_agent_registry; then
        local count
        count=$(jq 'keys | length' "$TV_AGENT_REGISTRY_FILE" 2>/dev/null || echo 0)
        _tv_print "  ${_TV_GRN}✓ Registry updated (${count} agents)${_TV_RST}"
    else
        _tv_print "  ${_TV_RED}✗ Failed to fetch registry from remote${_TV_RST}"
        return 1
    fi
}

# Get agent info from registry
# Usage: _tv_get_agent_info <agent_id>
_tv_get_agent_info() {
    local agent_id="$1"
    [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]] && return 1
    jq -c --arg id "$agent_id" '.[$id] // empty' "$TV_AGENT_REGISTRY_FILE"
}

# List all registered agents
# Usage: _tv_list_agents
_tv_list_agents() {
    if [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]]; then
        echo "{}"
        return 0
    fi
    cat "$TV_AGENT_REGISTRY_FILE"
}

# List agent IDs only
# Usage: _tv_list_agent_ids
_tv_list_agent_ids() {
    if [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]]; then
        return 0
    fi
    jq -r 'keys[]' "$TV_AGENT_REGISTRY_FILE"
}

# Check if agent is registered
# Usage: _tv_is_agent_registered <agent_id>
_tv_is_agent_registered() {
    local agent_id="$1"
    [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]] && return 1
    local exists
    exists=$(jq -r --arg id "$agent_id" 'has($id)' "$TV_AGENT_REGISTRY_FILE")
    [[ "$exists" == "true" ]]
}

# Register a new agent
# Usage: _tv_register_agent <agent_id> <display_name> [config_provider] [capability_provider]
_tv_register_agent() {
    local agent_id="$1" display_name="$2"
    local config_provider="${3:-$agent_id}"
    local capability_provider="${4:-$agent_id}"
    local version_provider="${5:-$agent_id}"
    local updater="${6:-manual}"
    local health_checker="${7:-$agent_id}"
    
    _tv_init_agent_registry
    
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    
    jq --arg id "$agent_id" \
       --arg name "$display_name" \
       --arg cp "$config_provider" \
       --arg cap "$capability_provider" \
       --arg vp "$version_provider" \
       --arg up "$updater" \
       --arg hc "$health_checker" \
       '.[$id] = {
           display_name: $name,
           config_provider: $cp,
           capability_provider: $cap,
           version_provider: $vp,
           updater: $up,
           health_checker: $hc,
           registered_at: (now | todate)
       }' "$TV_AGENT_REGISTRY_FILE" > "$tmp" \
       && mv -f "$tmp" "$TV_AGENT_REGISTRY_FILE" || { rm -f "$tmp"; return 1; }
    
    _tv_print "  ${_TV_GRN}✓ Agent ${_TV_WHT}${agent_id}${_TV_RST}${_TV_GRN} registered${_TV_RST}"
}

# Unregister an agent
# Usage: _tv_unregister_agent <agent_id>
_tv_unregister_agent() {
    local agent_id="$1"
    [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]] && return 1
    
    local exists
    exists=$(jq -r --arg id "$agent_id" 'has($id)' "$TV_AGENT_REGISTRY_FILE")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Agent not found: ${agent_id}${_TV_RST}"; return 1; }
    
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    
    jq --arg id "$agent_id" 'del(.[$id])' "$TV_AGENT_REGISTRY_FILE" > "$tmp" \
       && mv -f "$tmp" "$TV_AGENT_REGISTRY_FILE" || { rm -f "$tmp"; return 1; }
    
    _tv_print "  ${_TV_YEL}✓ Agent ${_TV_WHT}${agent_id}${_TV_RST}${_TV_YEL} unregistered${_TV_RST}"
}

# Get agent config provider
# Usage: _tv_get_agent_config_provider <agent_id>
_tv_get_agent_config_provider() {
    local agent_id="$1"
    local info
    info=$(_tv_get_agent_info "$agent_id")
    [[ -z "$info" ]] && echo "$agent_id" && return 0
    echo "$info" | jq -r '.config_provider // "'"$agent_id"'"'
}

# Get agent capability provider
# Usage: _tv_get_agent_capability_provider <agent_id>
_tv_get_agent_capability_provider() {
    local agent_id="$1"
    local info
    info=$(_tv_get_agent_info "$agent_id")
    [[ -z "$info" ]] && echo "$agent_id" && return 0
    echo "$info" | jq -r '.capability_provider // "'"$agent_id"'"'
}

# Get agent version provider
# Usage: _tv_get_agent_version_provider <agent_id>
_tv_get_agent_version_provider() {
    local agent_id="$1"
    local info
    info=$(_tv_get_agent_info "$agent_id")
    [[ -z "$info" ]] && echo "$agent_id" && return 0
    echo "$info" | jq -r '.version_provider // "'"$agent_id"'"'
}

# Get agent updater
# Usage: _tv_get_agent_updater <agent_id>
_tv_get_agent_updater() {
    local agent_id="$1"
    local info
    info=$(_tv_get_agent_info "$agent_id")
    [[ -z "$info" ]] && echo "manual" && return 0
    echo "$info" | jq -r '.updater // "manual"'
}

# Display agent registry
# Usage: _tv_display_agent_registry
_tv_display_agent_registry() {
    _tv_banner "Agent Registry"
    
    if [[ ! -f "$TV_AGENT_REGISTRY_FILE" ]]; then
        _tv_print "  ${_TV_GRY}(no agents registered)${_TV_RST}"
        return 0
    fi
    
    _tv_print "$(printf "  %-15s %-20s %-15s %-10s" "AGENT" "DISPLAY NAME" "CONFIG PROVIDER" "UPDATER")"
    _tv_print "  ${_TV_GRY}$(printf '%.0s─' {1..65})${_TV_RST}"
    
    jq -r 'to_entries[] | "\(.key)|\(.value.display_name)|\(.value.config_provider)|\(.value.updater)"' \
        "$TV_AGENT_REGISTRY_FILE" | \
    while IFS='|' read -r id name cp updater; do
        _tv_print "$(printf "  %-15s %-20s %-15s %-10s" "$id" "$name" "$cp" "$updater")"
    done
}

# --- AGENT REGISTRY OPEN/CLOSE ---

tv_agent_registry_open() {
    [[ -n "${TV_AGENT_REGISTRY_OPENED:-}" ]] && return 0
    _tv_init_agent_registry
    TV_AGENT_REGISTRY_OPENED=1
}

tv_agent_registry_close() {
    TV_AGENT_REGISTRY_OPENED=""
}
