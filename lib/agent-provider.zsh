# Guard against double sourcing
[[ -n "${TV_AGENT_PROVIDER_LOADED:-}" ]] && return 0
typeset -g TV_AGENT_PROVIDER_LOADED=1

# --- AGENT PROVIDER INTERFACE ---
# Each agent provider must implement these functions:
#   tv_agent_<id>_detect <context>
#   tv_agent_<id>_discover_config_layers <context>
#   tv_agent_<id>_normalize_config_layers <raw_layers> <context>
#   tv_agent_<id>_resolve_effective_config <layers> <context>
#   tv_agent_<id>_discover_capabilities <context>
#   tv_agent_<id>_fetch_models <context>
#   tv_agent_<id>_normalize_models <raw_models> <context>
#   tv_agent_<id>_detect_version <context>
#   tv_agent_<id>_check_update <context>

# --- AGENT PROVIDER BASE ---

# Register an agent provider
# Usage: _tv_register_agent_provider <id> <display_name> <config_provider> <capability_provider>
_tv_register_agent_provider() {
    local id="$1" display_name="$2" config_provider="$3" capability_provider="$4"
    
    local registry_file="${TV_DIR}/agent_registry.json"
    if [[ ! -f "$registry_file" ]]; then
        echo "{}" > "$registry_file"
    fi
    
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    
    jq --arg id "$id" \
       --arg name "$display_name" \
       --arg cp "$config_provider" \
       --arg cap "$capability_provider" \
       '.[$id] = {
           display_name: $name,
           config_provider: $cp,
           capability_provider: $cap,
           registered_at: (now | todate)
       }' "$registry_file" > "$tmp" && mv -f "$tmp" "$registry_file" || { rm -f "$tmp"; return 1; }
}

# Get agent provider info
# Usage: _tv_get_agent_provider <id>
_tv_get_agent_provider() {
    local id="$1"
    local registry_file="${TV_DIR}/agent_registry.json"
    [[ ! -f "$registry_file" ]] && return 1
    jq -c --arg id "$id" '.[$id] // empty' "$registry_file"
}

# List all registered agent providers
# Usage: _tv_list_agent_providers
_tv_list_agent_providers() {
    local registry_file="${TV_DIR}/agent_registry.json"
    [[ ! -f "$registry_file" ]] && echo "{}" && return 0
    cat "$registry_file"
}

# Detect if an agent is available
# Usage: _tv_detect_agent <agent_id> [context]
_tv_detect_agent() {
    local agent_id="$1" context="${2:-{}}"
    
    # Check if agent-specific detect function exists
    if typeset -f "tv_agent_${agent_id}_detect" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_detect" "$context"
        return $?
    fi
    
    # Fallback: check if agent command exists
    case "$agent_id" in
        codex)
            command -v codex >/dev/null 2>&1
            ;;
        claude-code)
            command -v claude >/dev/null 2>&1
            ;;
        aider)
            command -v aider >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Discover config layers for an agent
# Usage: _tv_agent_discover_config_layers <agent_id> <context>
_tv_agent_discover_config_layers() {
    local agent_id="$1" context="$2"
    
    if typeset -f "tv_agent_${agent_id}_discover_config_layers" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_discover_config_layers" "$context"
        return $?
    fi
    
    # Fallback to generic resolver
    _tv_discover_config_layers "$context"
}

# Normalize config layers for an agent
# Usage: _tv_agent_normalize_config_layers <agent_id> <raw_layers> <context>
_tv_agent_normalize_config_layers() {
    local agent_id="$1" raw_layers="$2" context="$3"
    
    if typeset -f "tv_agent_${agent_id}_normalize_config_layers" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_normalize_config_layers" "$raw_layers" "$context"
        return $?
    fi
    
    # Fallback: pass through
    echo "$raw_layers"
}

# Resolve effective config for an agent
# Usage: _tv_agent_resolve_effective_config <agent_id> <layers> <context>
_tv_agent_resolve_effective_config() {
    local agent_id="$1" layers="$2" context="$3"
    
    if typeset -f "tv_agent_${agent_id}_resolve_effective_config" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_resolve_effective_config" "$layers" "$context"
        return $?
    fi
    
    # Fallback to generic resolver
    _tv_resolve_effective_config "$context"
}

# Discover capabilities for an agent
# Usage: _tv_agent_discover_capabilities <agent_id> <context>
_tv_agent_discover_capabilities() {
    local agent_id="$1" context="$2"
    
    if typeset -f "tv_agent_${agent_id}_discover_capabilities" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_discover_capabilities" "$context"
        return $?
    fi
    
    # Return default capabilities
    jq -n '{
        config_inspect: true,
        runtime_sync: true,
        model_list: true,
        version_detect: true,
        update_check: true
    }'
}

# Fetch models for an agent
# Usage: _tv_agent_fetch_models <agent_id> <context>
_tv_agent_fetch_models() {
    local agent_id="$1" context="$2"
    
    if typeset -f "tv_agent_${agent_id}_fetch_models" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_fetch_models" "$context"
        return $?
    fi
    
    # Fallback: use generic model fetch
    local prov
    prov=$(echo "$context" | jq -r '.provider // "custom"')
    local base_url
    base_url=$(echo "$context" | jq -r '.base_url // empty')
    local api_key
    api_key=$(echo "$context" | jq -r '.api_key // empty')
    
    _tv_fetch_models "$prov" "$base_url" "$api_key"
}

# Normalize models for an agent
# Usage: _tv_agent_normalize_models <agent_id> <raw_models> <context>
_tv_agent_normalize_models() {
    local agent_id="$1" raw_models="$2" context="$3"
    
    if typeset -f "tv_agent_${agent_id}_normalize_models" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_normalize_models" "$raw_models" "$context"
        return $?
    fi
    
    # Fallback: convert to ModelDescriptor format
    local i=0
    local result="[]"
    while IFS= read -r model_id; do
        [[ -z "$model_id" ]] && continue
        result=$(echo "$result" | jq \
            --arg id "$model_id" \
            --arg agent "$agent_id" \
            '. += [{
                provider_id: $agent,
                endpoint_id: "default",
                canonical_id: $id,
                provider_model_id: $id,
                deployment_id: "",
                aliases: [$id],
                family: "unknown",
                modality: "text",
                lifecycle_state: "active",
                context_window_hint: 0,
                raw: {}
            }]')
        (( i++ ))
    done <<< "$raw_models"
    
    printf '%s' "$result"
}

# Detect version for an agent
# Usage: _tv_agent_detect_version <agent_id> <context>
_tv_agent_detect_version() {
    local agent_id="$1" context="$2"
    
    if typeset -f "tv_agent_${agent_id}_detect_version" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_detect_version" "$context"
        return $?
    fi
    
    # Fallback: try to get version from command
    case "$agent_id" in
        codex)
            codex --version 2>/dev/null | head -1 || echo "unknown"
            ;;
        claude-code)
            claude --version 2>/dev/null | head -1 || echo "unknown"
            ;;
        aider)
            aider --version 2>/dev/null | head -1 || echo "unknown"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check for updates for an agent
# Usage: _tv_agent_check_update <agent_id> <context>
_tv_agent_check_update() {
    local agent_id="$1" context="$2"
    
    if typeset -f "tv_agent_${agent_id}_check_update" >/dev/null 2>&1; then
        "tv_agent_${agent_id}_check_update" "$context"
        return $?
    fi
    
    # Return no update available by default
    jq -n '{
        has_update: false,
        current_version: "unknown",
        latest_version: "unknown",
        channel: "stable"
    }'
}

# --- AGENT PROVIDER OPEN/CLOSE ---

tv_agent_provider_open() {
    [[ -n "${TV_AGENT_PROVIDER_OPENED:-}" ]] && return 0
    TV_AGENT_PROVIDER_OPENED=1
}

tv_agent_provider_close() {
    TV_AGENT_PROVIDER_OPENED=""
}
