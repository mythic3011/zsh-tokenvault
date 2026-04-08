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

_tv_codex_runtime_home() {
    local roots="$1"
    echo "$roots" | _tv_jq -r '.state_root + "/home"'
}

_tv_codex_runtime_config_path() {
    local roots="$1"
    echo "$roots" | _tv_jq -r '.state_root + "/home/config.toml"'
}

_tv_codex_global_candidates_json() {
    local global_home="$1" current_home="$2"
    local runtime_home="$3"
    local candidates='[]'

    local -a global_candidates
    global_candidates=(
        "$global_home/config.toml:api-config"
        "$global_home/auth.json:oauth-session"
        "$global_home/history.jsonl:history"
        "$global_home/logs:logs"
        "$global_home/caches:caches"
    )

    local entry path artifact_class
    for entry in "${global_candidates[@]}"; do
        path="${entry%%:*}"
        artifact_class="${entry#*:}"
        if [[ -e "$path" ]]; then
            candidates=$(echo "$candidates" | _tv_jq \
                --arg path "$path" \
                --arg artifact_class "$artifact_class" \
                '. + [{path:$path, class:$artifact_class, source:"default_home"}]')
        fi
    done

    if [[ -n "$current_home" && "$current_home" != "$runtime_home" ]]; then
        local -a current_candidates
        current_candidates=(
            "$current_home:home-override"
            "$current_home/config.toml:api-config"
            "$current_home/auth.json:oauth-session"
            "$current_home/history.jsonl:history"
            "$current_home/logs:logs"
            "$current_home/caches:caches"
        )
        for entry in "${current_candidates[@]}"; do
            path="${entry%%:*}"
            artifact_class="${entry#*:}"
            if [[ -e "$path" ]]; then
                candidates=$(echo "$candidates" | _tv_jq \
                    --arg path "$path" \
                    --arg artifact_class "$artifact_class" \
                    '. + [{path:$path, class:$artifact_class, source:"env_home"}]')
            fi
        done
    fi

    echo "$candidates" | _tv_jq 'unique_by(.path + ":" + .class + ":" + .source)'
}

_tv_codex_detect_keychain_auth_surfaces() {
    local services_csv="${TV_CODEX_KEYCHAIN_SERVICES:-codex,com.openai.codex,OpenAI Codex}"

    if [[ "$OSTYPE" != darwin* ]] || ! command -v security >/dev/null 2>&1; then
        _tv_jq -n '{
            available: false,
            detection_scope: "unsupported",
            checked_services: [],
            detected_surfaces: []
        }'
        return 0
    fi

    local checked='[]'
    local detected='[]'
    local service
    for service in ${(s:,:)services_csv}; do
        [[ -z "$service" ]] && continue
        checked=$(echo "$checked" | _tv_jq --arg service "$service" '. + [$service]')
        if /usr/bin/security find-generic-password -s "$service" >/dev/null 2>&1 \
            || /usr/bin/security find-internet-password -s "$service" >/dev/null 2>&1; then
            detected=$(echo "$detected" | _tv_jq --arg service "$service" '. + [{service:$service, class:"oauth-session", source:"macos_keychain"}]')
        fi
    done

    _tv_jq -n \
        --argjson checked "$checked" \
        --argjson detected "$detected" \
        '{
            available: true,
            detection_scope: "macos_service_probe",
            checked_services: $checked,
            detected_surfaces: $detected
        }'
}

_tv_codex_classify_global_conflicts() {
    local launch_mode="$1" artifact_evidence="$2" auth_surfaces="$3"
    local conflicts='[]'

    local artifact_conflicts='[]'
    if [[ "$launch_mode" == "oauth" ]]; then
        artifact_conflicts=$(echo "$artifact_evidence" | _tv_jq '[.[] | select(.class == "api-config")]')
    elif [[ "$launch_mode" == "api" ]]; then
        artifact_conflicts=$(echo "$artifact_evidence" | _tv_jq '[.[] | select(.class == "oauth-session")]')
    fi

    conflicts=$(echo "$conflicts" | _tv_jq --argjson more "$artifact_conflicts" '. + $more')

    if [[ "$launch_mode" == "api" ]]; then
        conflicts=$(echo "$conflicts" | _tv_jq --argjson more "$auth_surfaces" '. + $more')
    fi

    echo "$conflicts" | _tv_jq 'unique'
}

tv_agent_codex_resolve_roots() {
    local profile="$1"
    _tv_runtime_roots "codex" "$profile" 1
}

tv_agent_codex_detect_profile_state() {
    local profile="$1" roots="$2" row="$3" policy="$4"
    local runtime_home
    runtime_home=$(_tv_codex_runtime_home "$roots")
    _tv_ensure_dir "$runtime_home" 700 || return 1

    local artifacts='[]'
    [[ -f "$runtime_home/auth.json" ]] && artifacts=$(echo "$artifacts" | _tv_jq '. + ["oauth-session"]')
    [[ -f "$runtime_home/config.toml" ]] && artifacts=$(echo "$artifacts" | _tv_jq '. + ["api-config"]')

    _tv_jq -n --argjson artifacts "$artifacts" '{
        ok: true,
        details: {
            observed_profile_artifacts: $artifacts
        }
    }'
}

tv_agent_codex_detect_global_state() {
    local profile="$1" roots="$2" row="$3" policy="$4"
    local global_home="${HOME}/.codex"
    local runtime_home
    runtime_home=$(_tv_codex_runtime_home "$roots")
    local current_home="${CODEX_HOME:-}"
    local launch_mode
    launch_mode=$(echo "$policy" | _tv_jq -r '.launch_mode // "api"')

    local artifact_evidence
    artifact_evidence=$(_tv_codex_global_candidates_json "$global_home" "$current_home" "$runtime_home")

    local keychain_state
    keychain_state=$(_tv_codex_detect_keychain_auth_surfaces)
    local keychain_detected
    keychain_detected=$(echo "$keychain_state" | _tv_jq -c '.detected_surfaces // []')

    local conflicts
    conflicts=$(_tv_codex_classify_global_conflicts "$launch_mode" "$artifact_evidence" "$keychain_detected")

    _tv_jq -n \
        --argjson artifacts "$artifact_evidence" \
        --argjson keychain "$keychain_detected" \
        --argjson conflicts "$conflicts" \
        --arg env_codex_home "${CODEX_HOME:-}" \
        --arg runtime_home "$runtime_home" \
        --arg launch_mode "$launch_mode" \
        --arg detection_scope "$(echo "$keychain_state" | _tv_jq -r '.detection_scope // "unknown"')" \
        --argjson keychain_available "$(echo "$keychain_state" | _tv_jq '.available // false')" \
        --argjson checked_services "$(echo "$keychain_state" | _tv_jq '.checked_services // []')" \
        '{
            detected_global_artifacts: ($artifacts | map(.path)),
            classified_global_artifacts: $artifacts,
            detected_global_auth_surfaces: $keychain,
            conflicting_global_artifacts: $conflicts,
            details: {
                launch_mode: $launch_mode,
                env_codex_home: $env_codex_home,
                runtime_home: $runtime_home,
                keychain_detection_available: $keychain_available,
                keychain_detection_scope: $detection_scope,
                keychain_checked_services: $checked_services
            }
        }'
}

tv_agent_codex_detect_env_conflicts() {
    local profile="$1" roots="$2" row="$3" policy="$4"
    local scrublist
    scrublist=$(echo "$policy" | _tv_jq -c '.env_scrublist // []')
    local present='[]'

    local var
    for var in $(echo "$scrublist" | _tv_jq -r '.[]'); do
        if [[ -n "${(P)var:-}" ]]; then
            present=$(echo "$present" | _tv_jq --arg key "$var" '. + [$key]')
        fi
    done

    _tv_jq -n --argjson present "$present" '{
        ok: (($present | length) == 0),
        details: {
            present_scrubbable_env: $present
        }
    }'
}

tv_agent_codex_effective_resolution_proof() {
    local profile="$1" roots="$2" row="$3" policy="$4"
    local runtime_home
    runtime_home=$(_tv_codex_runtime_home "$roots")
    local runtime_config
    runtime_config=$(_tv_codex_runtime_config_path "$roots")
    _tv_ensure_dir "$runtime_home" 700 || return 1

    _tv_jq -n \
        --arg resolved_home_path "$runtime_home" \
        --arg config_path "$runtime_config" \
        --arg auth_path "$runtime_home/auth.json" \
        '{
            resolved_home_path: $resolved_home_path,
            resolved_config_paths: [$config_path],
            resolved_auth_paths: [$auth_path],
            reachable_global_paths: [],
            proof_complete: true
        }'
}

tv_agent_codex_write_api_config() {
    local profile="$1" roots="$2" row="$3" policy="$4" api_key="$5"
    local runtime_home runtime_config provider_name base_url default_model
    runtime_home=$(_tv_codex_runtime_home "$roots")
    runtime_config=$(_tv_codex_runtime_config_path "$roots")
    _tv_ensure_dir "$runtime_home" 700 || return 1

    provider_name="tokenvault"
    base_url=$(echo "$row" | _tv_jq -r '.base_url // ""')
    default_model=$(echo "$row" | _tv_jq -r '.default_model // ""')
    [[ -z "$base_url" || "$base_url" == "null" ]] && base_url=$(_tv_provider_default_base_url "openai")

    local config_lines
    printf -v config_lines 'model_provider = "%s"\n' "$provider_name"
    if [[ -n "$default_model" && "$default_model" != "null" ]]; then
        printf -v config_lines '%smodel = "%s"\n' "$config_lines" "$default_model"
    fi
    printf -v config_lines '%s\n[model_providers.%s]\n' "$config_lines" "$provider_name"
    printf -v config_lines '%sbase_url = "%s"\n' "$config_lines" "$base_url"
    printf -v config_lines '%srequires_openai_auth = true\n' "$config_lines"
    if [[ -n "$default_model" && "$default_model" != "null" ]]; then
        printf -v config_lines '%smodel = "%s"\n' "$config_lines" "$default_model"
    fi

    _tv_atomic_write "$runtime_config" "$config_lines" || {
        _tv_jq -n '{ok:false, details:{reason:"failed_to_write_runtime_config"}}'
        return 0
    }
    chmod 600 "$runtime_config" 2>/dev/null || true

    _tv_jq -n \
        --arg runtime_home "$runtime_home" \
        --arg runtime_config "$runtime_config" \
        --arg api_key "$api_key" \
        '{
            ok: true,
            runtime_home: $runtime_home,
            runtime_config: $runtime_config,
            env: {
                OPENAI_API_KEY: $api_key
            }
        }'
}

tv_agent_codex_prepare_oauth_runtime() {
    local profile="$1" roots="$2" row="$3" policy="$4"
    local runtime_home
    runtime_home=$(_tv_codex_runtime_home "$roots")
    _tv_ensure_dir "$runtime_home" 700 || return 1

    jq -n --arg runtime_home "$runtime_home" '{
        ok: true,
        runtime_home: $runtime_home
    }'
}

tv_agent_codex_check_mode_invariants() {
    local profile="$1" roots="$2" row="$3" policy="$4"
    local runtime_home
    runtime_home=$(_tv_codex_runtime_home "$roots")
    local launch_mode
    launch_mode=$(echo "$policy" | _tv_jq -r '.launch_mode // "api"')

    local has_config="false"
    local has_auth="false"
    [[ -f "$runtime_home/config.toml" ]] && has_config="true"
    [[ -f "$runtime_home/auth.json" ]] && has_auth="true"

    if [[ "$launch_mode" == "oauth" && "$has_config" == "true" ]]; then
        _tv_jq -n '{
            ok: false,
            details: {
                reason: "oauth_profile_has_api_config"
            }
        }'
        return 0
    fi

    if [[ "$launch_mode" == "api" && "$has_auth" == "true" ]]; then
        _tv_jq -n '{
            ok: false,
            details: {
                reason: "api_profile_has_oauth_session"
            }
        }'
        return 0
    fi

    _tv_jq -n --arg launch_mode "$launch_mode" --argjson has_config "$has_config" --argjson has_auth "$has_auth" '{
        ok: true,
        details: {
            launch_mode: $launch_mode,
            has_config: $has_config,
            has_auth: $has_auth
        }
    }'
}

# --- CODEX OPEN/CLOSE ---

tv_agent_codex_open() {
    [[ -n "${TV_AGENT_CODEX_OPENED:-}" ]] && return 0
    TV_AGENT_CODEX_OPENED=1
}

tv_agent_codex_close() {
    TV_AGENT_CODEX_OPENED=""
}
