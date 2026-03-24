# Guard against double sourcing
[[ -n "${TV_CATALOG_LOADED:-}" ]] && return 0
typeset -g TV_CATALOG_LOADED=1

# --- PROVIDER CATALOG ---
# Data-driven provider catalog loaded from providers/catalog.json

typeset -g TV_PROVIDER_CATALOG_FILE="${TV_PLUGIN_DIR:-${TV_PLUGIN_PATH:A:h}}/providers/catalog.json"
typeset -g _TV_PROVIDER_CATALOG=""

# Load provider catalog from JSON
_tv_load_provider_catalog() {
    if [[ -z "$_TV_PROVIDER_CATALOG" ]]; then
        if [[ -f "$TV_PROVIDER_CATALOG_FILE" ]]; then
            _TV_PROVIDER_CATALOG=$(cat "$TV_PROVIDER_CATALOG_FILE")
        else
            _TV_PROVIDER_CATALOG="{}"
        fi
    fi
    printf '%s' "$_TV_PROVIDER_CATALOG"
}

# Get provider info from catalog
# Usage: _tv_provider_info <provider_id>
_tv_provider_info() {
    local provider_id="$1"
    local catalog
    catalog=$(_tv_load_provider_catalog)
    echo "$catalog" | jq -c --arg id "$provider_id" '.[$id] // empty'
}

# Get provider display name
# Usage: _tv_provider_display_name <provider_id>
_tv_provider_display_name() {
    local provider_id="$1"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "$provider_id" && return 0
    echo "$info" | jq -r '.display_name // "'"$provider_id"'"'
}

# Get provider default base URL
# Usage: _tv_provider_default_base_url <provider_id>
_tv_provider_default_base_url() {
    local provider_id="$1"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "" && return 0
    echo "$info" | jq -r '.default_base_url // ""'
}

# Get provider env map
# Usage: _tv_provider_env_map <provider_id>
_tv_provider_env_map() {
    local provider_id="$1"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "{}" && return 0
    echo "$info" | jq -c '.env_map // {}'
}

# Get provider model endpoint
# Usage: _tv_provider_model_endpoint <provider_id>
_tv_provider_model_endpoint() {
    local provider_id="$1"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "/v1/models" && return 0
    echo "$info" | jq -r '.model_endpoint // "/v1/models"'
}

# Get provider auth strategy
# Usage: _tv_provider_auth_strategy <provider_id>
_tv_provider_auth_strategy() {
    local provider_id="$1"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "bearer" && return 0
    echo "$info" | jq -r '.auth_strategy // "bearer"'
}

# Get provider auth headers
# Usage: _tv_provider_auth_headers <provider_id> <api_key>
_tv_provider_auth_headers() {
    local provider_id="$1" api_key="$2"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "{}" && return 0
    
    local headers
    headers=$(echo "$info" | jq -c '.auth_headers // {}')
    
    # Replace {key} placeholder with actual key
    echo "$headers" | jq --arg key "$api_key" '
        with_entries(.value |= gsub("\\{key\\}"; $key))
    '
}

# Get provider wire API style
# Usage: _tv_provider_wire_api <provider_id>
_tv_provider_wire_api() {
    local provider_id="$1"
    local info
    info=$(_tv_provider_info "$provider_id")
    [[ -z "$info" ]] && echo "openai_compat" && return 0
    echo "$info" | jq -r '.wire_api // "openai_compat"'
}

# List all provider IDs in catalog
# Usage: _tv_catalog_provider_ids
_tv_catalog_provider_ids() {
    local catalog
    catalog=$(_tv_load_provider_catalog)
    echo "$catalog" | jq -r 'keys[]'
}

# List all providers with display names
# Usage: _tv_catalog_list_providers
_tv_catalog_list_providers() {
    local catalog
    catalog=$(_tv_load_provider_catalog)
    echo "$catalog" | jq -r 'to_entries[] | "\(.key)|\(.value.display_name)|\(.value.provider_type)"'
}

# Display provider catalog
# Usage: _tv_display_provider_catalog
_tv_display_provider_catalog() {
    _tv_banner "Provider Catalog"
    
    local catalog
    catalog=$(_tv_load_provider_catalog)
    
    local count
    count=$(echo "$catalog" | jq 'keys | length')
    
    if (( count == 0 )); then
        _tv_print "  ${_TV_GRY}(no providers in catalog)${_TV_RST}"
        return 0
    fi
    
    _tv_print "$(printf "  %-15s %-20s %-15s %-30s" "ID" "DISPLAY NAME" "TYPE" "DEFAULT URL")"
    _tv_print "  ${_TV_GRY}$(printf '%.0s─' {1..85})${_TV_RST}"
    
    echo "$catalog" | jq -r 'to_entries[] | "\(.key)|\(.value.display_name)|\(.value.provider_type)|\(.value.default_base_url // "")"' | \
    while IFS='|' read -r id name type url; do
        _tv_print "$(printf "  %-15s %-20s %-15s %-30s" "$id" "$name" "$type" "$url")"
    done
}

# Validate provider catalog entry
# Usage: _tv_validate_provider_entry <provider_json>
_tv_validate_provider_entry() {
    local entry="$1"
    
    # Check required fields
    local id display_name provider_type
    id=$(echo "$entry" | jq -r '.id // empty')
    display_name=$(echo "$entry" | jq -r '.display_name // empty')
    provider_type=$(echo "$entry" | jq -r '.provider_type // empty')
    
    if [[ -z "$id" ]]; then
        _tv_print "  ${_TV_RED}✗ Missing required field: id${_TV_RST}"
        return 1
    fi
    if [[ -z "$display_name" ]]; then
        _tv_print "  ${_TV_RED}✗ Missing required field: display_name${_TV_RST}"
        return 1
    fi
    if [[ -z "$provider_type" ]]; then
        _tv_print "  ${_TV_RED}✗ Missing required field: provider_type${_TV_RST}"
        return 1
    fi
    
    # Check env_map structure
    local env_map
    env_map=$(echo "$entry" | jq -c '.env_map // {}')
    local has_key
    has_key=$(echo "$env_map" | jq -r 'has("key")')
    if [[ "$has_key" != "true" ]]; then
        _tv_print "  ${_TV_YEL}⚠ env_map missing 'key' field${_TV_RST}"
    fi
    
    _tv_print "  ${_TV_GRN}✓ Provider entry valid: ${id}${_TV_RST}"
    return 0
}

# --- CATALOG OPEN/CLOSE ---

tv_catalog_open() {
    [[ -n "${TV_CATALOG_OPENED:-}" ]] && return 0
    TV_CATALOG_OPENED=1
}

tv_catalog_close() {
    TV_CATALOG_OPENED=""
}
