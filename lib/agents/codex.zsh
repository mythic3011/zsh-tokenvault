# Guard against double sourcing
[[ -n "${TV_AGENT_CODEX_LOADED:-}" ]] && return 0
typeset -g TV_AGENT_CODEX_LOADED=1

# --- CODEX AGENT ADAPTER ---
# Implements the agent provider interface for OpenAI Codex CLI

# Detect if Codex is available
tv_agent_codex_detect() {
    local context="${1:-{}}"
    command -v codex >/dev/null 2>&1
}

# Discover config layers for Codex
# Follows official precedence: CLI > profile > trusted project > user > system > builtin
tv_agent_codex_discover_config_layers() {
    local context="$1"
    local cwd
    cwd=$(echo "$context" | jq -r '.cwd // "."')
    local profile
    profile=$(echo "$context" | jq -r '.profile // empty')
    
    local layers="[]"
    local rank=1
    
    # Layer 1: Built-in defaults
    layers=$(echo "$layers" | jq \
        --argjson rank "$rank" \
        '. += [{
            id: "codex:builtin",
            agent: "codex",
            source_type: "builtin",
            source_path: "",
            trust_state: "trusted",
            precedence_rank: $rank,
            active: true,
            skip_reason: "",
            values: {}
        }]')
    (( rank++ ))
    
    # Layer 2: System config
    local system_config="/etc/codex/config.toml"
    if [[ -f "$system_config" ]]; then
        layers=$(echo "$layers" | jq \
            --argjson rank "$rank" \
            --arg path "$system_config" \
            '. += [{
                id: "codex:system",
                agent: "codex",
                source_type: "system",
                source_path: $path,
                trust_state: "trusted",
                precedence_rank: $rank,
                active: true,
                skip_reason: "",
                values: {}
            }]')
        (( rank++ ))
    fi
    
    # Layer 3: User config
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/codex/config.toml"
    if [[ -f "$user_config" ]]; then
        layers=$(echo "$layers" | jq \
            --argjson rank "$rank" \
            --arg path "$user_config" \
            '. += [{
                id: "codex:user",
                agent: "codex",
                source_type: "user",
                source_path: $path,
                trust_state: "trusted",
                precedence_rank: $rank,
                active: true,
                skip_reason: "",
                values: {}
            }]')
        (( rank++ ))
    fi
    
    # Layer 4: Project configs (walk from cwd to root, closest wins)
    local check_dir="$cwd"
    local -a project_configs
    while [[ "$check_dir" != "/" && "$check_dir" != "." ]]; do
        local project_config="$check_dir/.codex/config.toml"
        if [[ -f "$project_config" ]]; then
            project_configs=("$project_config" "${project_configs[@]}")
        fi
        check_dir="${check_dir:h}"
    done
    
    for project_config in "${project_configs[@]}"; do
        local project_dir
        project_dir=$(dirname "$(dirname "$project_config")")
        local trust_state="untrusted"
        
        # Check if project is trusted
        if [[ -f "$project_dir/.codex/trusted" ]] || [[ -f "$project_dir/.git/config" ]]; then
            trust_state="trusted"
        fi
        
        layers=$(echo "$layers" | jq \
            --argjson rank "$rank" \
            --arg path "$project_config" \
            --arg trust "$trust_state" \
            --arg id "codex:project:${project_dir}" \
            '. += [{
                id: $id,
                agent: "codex",
                source_type: "project",
                source_path: $path,
                trust_state: $trust,
                precedence_rank: $rank,
                active: true,
                skip_reason: "",
                values: {}
            }]')
        (( rank++ ))
    done
    
    # Layer 5: Profile config
    if [[ -n "$profile" ]]; then
        local profile_row
        profile_row=$(jq -c --arg p "$profile" '.[$p] // empty' "$TV_PROFILES" 2>/dev/null)
        if [[ -n "$profile_row" ]]; then
            layers=$(echo "$layers" | jq \
                --argjson rank "$rank" \
                --arg profile "$profile" \
                --argjson values "$profile_row" \
                '. += [{
                    id: "codex:profile:\($profile)",
                    agent: "codex",
                    source_type: "profile",
                    source_path: "",
                    trust_state: "trusted",
                    precedence_rank: $rank,
                    active: true,
                    skip_reason: "",
                    values: $values
                }]')
            (( rank++ ))
        fi
    fi
    
    printf '%s' "$layers"
}

# Normalize config layers for Codex
tv_agent_codex_normalize_config_layers() {
    local raw_layers="$1" context="$2"
    
    # Parse each layer's config file and merge into values
    local count
    count=$(echo "$raw_layers" | jq 'length')
    local result="[]"
    
    local i=0
    while (( i < count )); do
        local layer
        layer=$(echo "$raw_layers" | jq -c ".[$i]")
        local source_path
        source_path=$(echo "$layer" | jq -r '.source_path // empty')
        local source_type
        source_type=$(echo "$layer" | jq -r '.source_type')
        
        local values="{}"
        if [[ -n "$source_path" && -f "$source_path" ]]; then
            # Use the existing TOML parser from ui.zsh
            if typeset -f _tv_read_codex_config >/dev/null 2>&1; then
                local parsed
                parsed=$(_tv_read_codex_config "$source_path")
                local ok
                ok=$(echo "$parsed" | jq -r '.ok // false')
                if [[ "$ok" == "true" ]]; then
                    values=$(echo "$parsed" | jq -c 'del(.ok)')
                fi
            fi
        fi
        
        layer=$(echo "$layer" | jq --argjson v "$values" '.values = $v')
        result=$(echo "$result" | jq --argjson l "$layer" '. += [$l]')
        (( i++ ))
    done
    
    printf '%s' "$result"
}

# Resolve effective config for Codex
tv_agent_codex_resolve_effective_config() {
    local layers="$1" context="$2"
    
    # Merge layers in precedence order
    local effective="{}"
    local sorted
    sorted=$(echo "$layers" | jq -c 'sort_by(.precedence_rank)')
    
    local count
    count=$(echo "$sorted" | jq 'length')
    local i=0
    while (( i < count )); do
        local layer
        layer=$(echo "$sorted" | jq -c ".[$i]")
        local active
        active=$(echo "$layer" | jq -r '.active')
        local trust_state
        trust_state=$(echo "$layer" | jq -r '.trust_state')
        local values
        values=$(echo "$layer" | jq -c '.values // {}')
        
        # Skip untrusted project configs
        if [[ "$active" == "true" && "$trust_state" != "untrusted" && "$values" != "{}" ]]; then
            effective=$(echo "$effective" | jq --argjson v "$values" '. * $v')
        fi
        (( i++ ))
    done
    
    printf '%s' "$effective"
}

# Discover capabilities for Codex
tv_agent_codex_discover_capabilities() {
    local context="$1"
    
    jq -n '{
        config_inspect: true,
        runtime_sync: true,
        model_list: true,
        version_detect: true,
        update_check: true,
        provider_types: ["openai", "custom"],
        wire_api_styles: ["openai_compat", "responses"],
        auth_strategies: ["api_key", "cli"],
        config_format: "toml"
    }'
}

# Fetch models for Codex
tv_agent_codex_fetch_models() {
    local context="$1"
    local prov
    prov=$(echo "$context" | jq -r '.provider // "openai"')
    local base_url
    base_url=$(echo "$context" | jq -r '.base_url // empty')
    local api_key
    api_key=$(echo "$context" | jq -r '.api_key // empty')
    
    _tv_fetch_models "$prov" "$base_url" "$api_key"
}

# Normalize models for Codex
tv_agent_codex_normalize_models() {
    local raw_models="$1" context="$2"
    
    local result="[]"
    while IFS= read -r model_id; do
        [[ -z "$model_id" ]] && continue
        
        # Determine model family
        local family="unknown"
        case "$model_id" in
            gpt-4*|o1*|o3*) family="gpt" ;;
            codex*|code*)     family="codex" ;;
            *)                family="other" ;;
        esac
        
        result=$(echo "$result" | jq \
            --arg id "$model_id" \
            --arg family "$family" \
            '. += [{
                provider_id: "codex",
                endpoint_id: "default",
                canonical_id: $id,
                provider_model_id: $id,
                deployment_id: "",
                aliases: [$id],
                family: $family,
                modality: "text",
                lifecycle_state: "active",
                context_window_hint: 0,
                raw: {}
            }]')
    done <<< "$raw_models"
    
    printf '%s' "$result"
}

# Detect Codex version
tv_agent_codex_detect_version() {
    local context="$1"
    
    if command -v codex >/dev/null 2>&1; then
        codex --version 2>/dev/null | head -1 || echo "unknown"
    else
        echo "not_installed"
    fi
}

# Check for Codex updates
tv_agent_codex_check_update() {
    local context="$1"
    
    local current_version
    current_version=$(_tv_agent_detect_version "codex" "$context")
    
    # Check npm for updates
    if command -v npm >/dev/null 2>&1; then
        local latest
        latest=$(npm view @openai/codex version 2>/dev/null || echo "unknown")
        
        if [[ "$latest" != "unknown" && "$current_version" != "$latest" ]]; then
            jq -n \
                --arg current "$current_version" \
                --arg latest "$latest" \
                '{
                    has_update: true,
                    current_version: $current,
                    latest_version: $latest,
                    channel: "stable",
                    update_command: "npm install -g @openai/codex@latest"
                }'
        else
            jq -n \
                --arg current "$current_version" \
                '{
                    has_update: false,
                    current_version: $current,
                    latest_version: $current,
                    channel: "stable"
                }'
        fi
    else
        jq -n \
            --arg current "$current_version" \
            '{
                has_update: false,
                current_version: $current,
                latest_version: "unknown",
                channel: "stable",
                note: "npm not available for update check"
            }'
    fi
}

# --- CODEX OPEN/CLOSE ---

tv_agent_codex_open() {
    [[ -n "${TV_AGENT_CODEX_OPENED:-}" ]] && return 0
    TV_AGENT_CODEX_OPENED=1
}

tv_agent_codex_close() {
    TV_AGENT_CODEX_OPENED=""
}
