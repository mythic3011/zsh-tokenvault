# Guard against double sourcing
[[ -n "${TV_RESOLVER_LOADED:-}" ]] && return 0
typeset -g TV_RESOLVER_LOADED=1

# --- CONFIG LAYER TYPES ---
typeset -g TV_LAYER_BUILTIN="builtin"
typeset -g TV_LAYER_SYSTEM="system"
typeset -g TV_LAYER_USER="user"
typeset -g TV_LAYER_PROJECT="project"
typeset -g TV_LAYER_PROFILE="profile"
typeset -g TV_LAYER_CLI="cli"
typeset -g TV_LAYER_ENV="env"

# --- TRUST STATES ---
typeset -g TV_TRUST_TRUSTED="trusted"
typeset -g TV_TRUST_UNTRUSTED="untrusted"
typeset -g TV_TRUST_IMPLICIT="implicit"
typeset -g TV_TRUST_UNKNOWN="unknown"

# Resolve runtime context for an agent
# Usage: _tv_resolve_runtime_context <agent_id> [cwd] [profile] [cli_overrides_json]
_tv_resolve_runtime_context() {
    local agent_id="$1" cwd="${2:-$(pwd)}" profile="${3:-}" cli_overrides="${4:-{}}"
    
    local context
    context=$(jq -n \
        --arg agent "$agent_id" \
        --arg cwd "$cwd" \
        --arg profile "$profile" \
        --argjson cli "$cli_overrides" \
        '{
            agent: $agent,
            cwd: $cwd,
            profile: $profile,
            cli_overrides: $cli,
            layers: [],
            effective: {},
            resolution_time: (now | todate)
        }')
    
    printf '%s' "$context"
}

# Discover config layers for an agent
# Usage: _tv_discover_config_layers <context_json>
_tv_discover_config_layers() {
    local context="$1"
    local agent_id
    agent_id=$(echo "$context" | jq -r '.agent')
    local cwd
    cwd=$(echo "$context" | jq -r '.cwd')
    
    local layers="[]"
    
    # Layer 1: Built-in defaults
    layers=$(echo "$layers" | jq \
        --arg type "$TV_LAYER_BUILTIN" \
        --arg trust "$TV_TRUST_TRUSTED" \
        '. += [{
            id: "builtin",
            source_type: $type,
            source_path: "",
            trust_state: $trust,
            precedence_rank: 1,
            active: true,
            skip_reason: "",
            values: {}
        }]')
    
    # Layer 2: System config
    local system_config="/etc/tokenvault/config.json"
    if [[ -f "$system_config" ]]; then
        layers=$(echo "$layers" | jq \
            --arg type "$TV_LAYER_SYSTEM" \
            --arg path "$system_config" \
            --arg trust "$TV_TRUST_TRUSTED" \
            '. += [{
                id: "system",
                source_type: $type,
                source_path: $path,
                trust_state: $trust,
                precedence_rank: 2,
                active: true,
                skip_reason: "",
                values: {}
            }]')
    fi
    
    # Layer 3: User config
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/tokenvault/config.json"
    if [[ -f "$user_config" ]]; then
        layers=$(echo "$layers" | jq \
            --arg type "$TV_LAYER_USER" \
            --arg path "$user_config" \
            --arg trust "$TV_TRUST_TRUSTED" \
            '. += [{
                id: "user",
                source_type: $type,
                source_path: $path,
                trust_state: $trust,
                precedence_rank: 3,
                active: true,
                skip_reason: "",
                values: {}
            }]')
    fi
    
    # Layer 4: Project configs (walk from cwd to root)
    local project_rank=4
    local check_dir="$cwd"
    while [[ "$check_dir" != "/" && "$check_dir" != "." ]]; do
        local project_config="$check_dir/.tokenvault/config.json"
        if [[ -f "$project_config" ]]; then
            local trust_state="$TV_TRUST_UNTRUSTED"
            # Check if project is trusted
            if [[ -f "$check_dir/.tokenvault/trusted" ]]; then
                trust_state="$TV_TRUST_TRUSTED"
            fi
            
            layers=$(echo "$layers" | jq \
                --arg type "$TV_LAYER_PROJECT" \
                --arg path "$project_config" \
                --arg trust "$trust_state" \
                --argjson rank "$project_rank" \
                --arg id "project:${check_dir}" \
                '. += [{
                    id: $id,
                    source_type: $type,
                    source_path: $path,
                    trust_state: $trust,
                    precedence_rank: $rank,
                    active: true,
                    skip_reason: "",
                    values: {}
                }]')
            (( project_rank++ ))
        fi
        check_dir="${check_dir:h}"
    done
    
    # Layer 5: Profile config
    local profile_id
    profile_id=$(echo "$context" | jq -r '.profile // empty')
    if [[ -n "$profile_id" ]]; then
        local profile_row
        profile_row=$(jq -c --arg p "$profile_id" '.[$p] // empty' "$TV_PROFILES" 2>/dev/null)
        if [[ -n "$profile_row" ]]; then
            layers=$(echo "$layers" | jq \
                --arg type "$TV_LAYER_PROFILE" \
                --arg id "profile:${profile_id}" \
                --arg trust "$TV_TRUST_TRUSTED" \
                --argjson rank "$project_rank" \
                --argjson values "$profile_row" \
                '. += [{
                    id: $id,
                    source_type: $type,
                    source_path: "",
                    trust_state: $trust,
                    precedence_rank: $rank,
                    active: true,
                    skip_reason: "",
                    values: $values
                }]')
            (( project_rank++ ))
        fi
    fi
    
    # Layer 6: CLI overrides
    local cli_overrides
    cli_overrides=$(echo "$context" | jq -c '.cli_overrides // {}')
    local cli_keys
    cli_keys=$(echo "$cli_overrides" | jq -r 'keys | length')
    if (( cli_keys > 0 )); then
        layers=$(echo "$layers" | jq \
            --arg type "$TV_LAYER_CLI" \
            --arg trust "$TV_TRUST_TRUSTED" \
            --argjson rank "$project_rank" \
            --argjson values "$cli_overrides" \
            '. += [{
                id: "cli",
                source_type: $type,
                source_path: "",
                trust_state: $trust,
                precedence_rank: $rank,
                active: true,
                skip_reason: "",
                values: $values
            }]')
    fi
    
    # Update context with discovered layers
    echo "$context" | jq --argjson layers "$layers" '.layers = $layers'
}

# Normalize config layers
# Usage: _tv_normalize_config_layers <context_json>
_tv_normalize_config_layers() {
    local context="$1"
    # For now, just pass through - normalization is agent-specific
    echo "$context"
}

# Resolve effective config from layers
# Usage: _tv_resolve_effective_config <context_json>
_tv_resolve_effective_config() {
    local context="$1"
    
    # Merge layers in precedence order (lowest to highest)
    local effective="{}"
    local layers
    layers=$(echo "$context" | jq -c '.layers | sort_by(.precedence_rank)')
    
    local count
    count=$(echo "$layers" | jq 'length')
    local i=0
    while (( i < count )); do
        local layer
        layer=$(echo "$layers" | jq -c ".[$i]")
        local active
        active=$(echo "$layer" | jq -r '.active')
        local values
        values=$(echo "$layer" | jq -c '.values // {}')
        
        if [[ "$active" == "true" && "$values" != "{}" ]]; then
            effective=$(echo "$effective" | jq --argjson v "$values" '. * $v')
        fi
        (( i++ ))
    done
    
    echo "$context" | jq --argjson eff "$effective" '.effective = $eff'
}

# Explain resolution for a specific key
# Usage: _tv_explain_resolution <context_json> <key>
_tv_explain_resolution() {
    local context="$1" key="$2"
    
    local layers
    layers=$(echo "$context" | jq -c '.layers | sort_by(.precedence_rank)')
    
    local chain="[]"
    local count
    count=$(echo "$layers" | jq 'length')
    local i=0
    while (( i < count )); do
        local layer
        layer=$(echo "$layers" | jq -c ".[$i]")
        local active
        active=$(echo "$layer" | jq -r '.active')
        local values
        values=$(echo "$layer" | jq -c '.values // {}')
        local has_key
        has_key=$(echo "$values" | jq -r --arg k "$key" 'has($k)')
        
        if [[ "$active" == "true" && "$has_key" == "true" ]]; then
            local value
            value=$(echo "$values" | jq -r --arg k "$key" '.[$k]')
            local source_type
            source_type=$(echo "$layer" | jq -r '.source_type')
            local source_path
            source_path=$(echo "$layer" | jq -r '.source_path')
            local trust_state
            trust_state=$(echo "$layer" | jq -r '.trust_state')
            
            chain=$(echo "$chain" | jq \
                --arg src "$source_type" \
                --arg path "$source_path" \
                --arg trust "$trust_state" \
                --arg val "$value" \
                '. += [{source: $src, path: $path, trust: $trust, value: $val}]')
        fi
        (( i++ ))
    done
    
    printf '%s' "$chain"
}

# Show resolution graph
# Usage: _tv_show_resolution_graph <context_json>
_tv_show_resolution_graph() {
    local context="$1"
    
    local layers
    layers=$(echo "$context" | jq -c '.layers | sort_by(.precedence_rank)')
    
    _tv_print "  ${_TV_WHT}Resolution Graph:${_TV_RST}"
    
    local count
    count=$(echo "$layers" | jq 'length')
    local i=0
    while (( i < count )); do
        local layer
        layer=$(echo "$layers" | jq -c ".[$i]")
        local source_type
        source_type=$(echo "$layer" | jq -r '.source_type')
        local source_path
        source_path=$(echo "$layer" | jq -r '.source_path')
        local trust_state
        trust_state=$(echo "$layer" | jq -r '.trust_state')
        local active
        active=$(echo "$layer" | jq -r '.active')
        local skip_reason
        skip_reason=$(echo "$layer" | jq -r '.skip_reason // empty')
        
        local indent=""
        local j=0
        while (( j < i )); do
            indent+="  "
            (( j++ ))
        done
        
        local status_icon="✓"
        local status_col="$_TV_GRN"
        if [[ "$active" != "true" ]]; then
            status_icon="✗"
            status_col="$_TV_RED"
        fi
        
        local trust_icon=""
        case "$trust_state" in
            trusted)   trust_icon="🔒" ;;
            untrusted) trust_icon="⚠️" ;;
        esac
        
        local path_display=""
        [[ -n "$source_path" ]] && path_display=" ${_TV_GRY}${source_path}${_TV_RST}"
        
        _tv_print "  ${indent}${status_col}${status_icon}${_TV_RST} ${trust_icon} ${_TV_WHT}${source_type}${_TV_RST}${path_display}"
        
        if [[ -n "$skip_reason" ]]; then
            _tv_print "  ${indent}  ${_TV_GRY}${skip_reason}${_TV_RST}"
        fi
        (( i++ ))
    done
}

# --- RESOLVER OPEN/CLOSE ---

tv_resolver_open() {
    [[ -n "${TV_RESOLVER_OPENED:-}" ]] && return 0
    TV_RESOLVER_OPENED=1
}

tv_resolver_close() {
    TV_RESOLVER_OPENED=""
}
