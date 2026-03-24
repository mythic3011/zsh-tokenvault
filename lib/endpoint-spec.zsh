# Guard against double sourcing
[[ -n "${TV_ENDPOINT_SPEC_LOADED:-}" ]] && return 0
typeset -g TV_ENDPOINT_SPEC_LOADED=1

# --- ENDPOINT SPECIFICATION ---
# Declarative endpoint capability specs for API operations

# Define endpoint operation types
typeset -g TV_OP_MODELS_LIST="models.list"
typeset -g TV_OP_QUOTA_GET="quota.get"
typeset -g TV_OP_HEALTH_PING="health.ping"
typeset -g TV_OP_CHAT_SEND="chat.send"

# Create endpoint spec
# Usage: _tv_create_endpoint_spec <operation> <method> <path> [options_json]
_tv_create_endpoint_spec() {
    local operation="$1" method="$2" path="$3" options="${4:-{}}"
    
    jq -n \
        --arg op "$operation" \
        --arg method "$method" \
        --arg path "$path" \
        --argjson opts "$options" \
        '{
            operation: $op,
            method: $method,
            path: $path,
            auth_binding: ($opts.auth_binding // "bearer"),
            request_template: ($opts.request_template // {}),
            response_transform: ($opts.response_transform // {}),
            pagination: ($opts.pagination // {}),
            error_map: ($opts.error_map // {}),
            rate_limit: ($opts.rate_limit // {})
        }'
}

# Get default endpoint specs for common providers
_tv_get_default_endpoint_specs() {
    cat << 'EOF'
{
    "anthropic": {
        "models.list": {
            "operation": "models.list",
            "method": "GET",
            "path": "/v1/models",
            "auth_binding": "x-api-key",
            "response_transform": {
                "items_path": ".data",
                "id_path": ".id"
            }
        }
    },
    "openai": {
        "models.list": {
            "operation": "models.list",
            "method": "GET",
            "path": "/v1/models",
            "auth_binding": "bearer",
            "response_transform": {
                "items_path": ".data",
                "id_path": ".id"
            }
        }
    },
    "gemini": {
        "models.list": {
            "operation": "models.list",
            "method": "GET",
            "path": "/v1/models",
            "auth_binding": "query_param",
            "response_transform": {
                "items_path": ".models",
                "id_path": ".name"
            }
        }
    },
    "openai_compat": {
        "models.list": {
            "operation": "models.list",
            "method": "GET",
            "path": "/v1/models",
            "auth_binding": "bearer",
            "response_transform": {
                "items_path": ".data",
                "id_path": ".id"
            }
        }
    }
}
EOF
}

# Apply response transform to extract models
# Usage: _tv_apply_response_transform <response> <transform_spec>
_tv_apply_response_transform() {
    local response="$1" transform="$2"
    
    local items_path id_path
    items_path=$(echo "$transform" | jq -r '.items_path // ".data"')
    id_path=$(echo "$transform" | jq -r '.id_path // ".id"')
    
    echo "$response" | jq -r "${items_path}[] | ${id_path}" 2>/dev/null
}

# Validate endpoint URL against spec
# Usage: _tv_validate_endpoint_spec <url> <spec>
_tv_validate_endpoint_spec() {
    local url="$1" spec="$2"
    
    local method path
    method=$(echo "$spec" | jq -r '.method // "GET"')
    path=$(echo "$spec" | jq -r '.path // "/"')
    
    # Check URL ends with expected path
    if [[ ! "$url" =~ ${path}$ ]]; then
        _tv_print "  ${_TV_YEL}⚠ URL does not match expected path: ${path}${_TV_RST}"
    fi
    
    return 0
}

# Build request from spec
# Usage: _tv_build_request <spec> <params_json>
_tv_build_request() {
    local spec="$1" params="$2"
    
    local method path auth_binding
    method=$(echo "$spec" | jq -r '.method // "GET"')
    path=$(echo "$spec" | jq -r '.path // "/"')
    auth_binding=$(echo "$spec" | jq -r '.auth_binding // "bearer"')
    
    jq -n \
        --arg method "$method" \
        --arg path "$path" \
        --arg auth "$auth_binding" \
        --argjson params "$params" \
        '{
            method: $method,
            path: $path,
            auth_binding: $auth,
            params: $params
        }'
}

# --- ENDPOINT SPEC OPEN/CLOSE ---

tv_endpoint_spec_open() {
    [[ -n "${TV_ENDPOINT_SPEC_OPENED:-}" ]] && return 0
    TV_ENDPOINT_SPEC_OPENED=1
}

tv_endpoint_spec_close() {
    TV_ENDPOINT_SPEC_OPENED=""
}
