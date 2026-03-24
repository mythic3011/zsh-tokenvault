# Guard against double sourcing
[[ -n "${TV_VERSIONING_LOADED:-}" ]] && return 0
typeset -g TV_VERSIONING_LOADED=1

# --- VERSION MANAGEMENT ---
# Handles app version, schema version, and adapter versions
# Default data loaded from providers/version_default.json

typeset -g TV_VERSION_FILE="${TV_DIR}/version.json"
typeset -g TV_VERSION_DEFAULT_FILE="${TV_PLUGIN_DIR:-${TV_PLUGIN_PATH:A:h}}/providers/version_default.json"

# Initialize version file from external default
_tv_init_versioning() {
    if [[ ! -f "$TV_VERSION_FILE" ]]; then
        if [[ -f "$TV_VERSION_DEFAULT_FILE" ]]; then
            cp "$TV_VERSION_DEFAULT_FILE" "$TV_VERSION_FILE"
        else
            echo '{"app_version":"7.0","schema_version":1,"adapters":{}}' > "$TV_VERSION_FILE"
        fi
        chmod 600 "$TV_VERSION_FILE"
    fi
}

# Get app version
tv_version() {
    local json_output="${1:-0}"
    
    if [[ ! -f "$TV_VERSION_FILE" ]]; then
        if [[ "$json_output" == "1" ]]; then
            jq -n '{app_version: "7.0", schema_version: 1}'
        else
            _tv_print "  ${_TV_WHT}TokenVault${_TV_RST} ${_TV_GRY}v7.0${_TV_RST}"
        fi
        return 0
    fi
    
    if [[ "$json_output" == "1" ]]; then
        cat "$TV_VERSION_FILE"
    else
        local app_ver schema_ver
        app_ver=$(jq -r '.app_version // "unknown"' "$TV_VERSION_FILE")
        schema_ver=$(jq -r '.schema_version // 0' "$TV_VERSION_FILE")
        _tv_print "  ${_TV_WHT}TokenVault${_TV_RST} ${_TV_GRY}v${app_ver}${_TV_RST} ${_TV_GRY}(schema: ${schema_ver})${_TV_RST}"
        
        # Show adapter versions
        local adapters
        adapters=$(jq -r '.adapters | to_entries[] | "\(.key): \(.value.adapter_version)"' "$TV_VERSION_FILE" 2>/dev/null)
        if [[ -n "$adapters" ]]; then
            _tv_print "  ${_TV_GRY}Adapters:${_TV_RST}"
            while IFS= read -r line; do
                _tv_print "    ${_TV_GRY}${line}${_TV_RST}"
            done <<< "$adapters"
        fi
    fi
}

# Get adapter version
# Usage: _tv_get_adapter_version <adapter_id>
_tv_get_adapter_version() {
    local adapter_id="$1"
    [[ ! -f "$TV_VERSION_FILE" ]] && echo "unknown" && return 0
    jq -r --arg id "$adapter_id" '.adapters[$id].adapter_version // "unknown"' "$TV_VERSION_FILE"
}

# Get adapter compatibility info
# Usage: _tv_get_adapter_compat <adapter_id>
_tv_get_adapter_compat() {
    local adapter_id="$1"
    [[ ! -f "$TV_VERSION_FILE" ]] && echo "{}" && return 0
    jq -c --arg id "$adapter_id" '.adapters[$id].compat // {}' "$TV_VERSION_FILE"
}

# Check adapter compatibility
# Usage: _tv_check_adapter_compat <adapter_id> <agent_version>
_tv_check_adapter_compat() {
    local adapter_id="$1" agent_version="$2"
    local compat
    compat=$(_tv_get_adapter_compat "$adapter_id")
    
    local min_version max_version
    min_version=$(echo "$compat" | jq -r '.min_agent_version // "0.0.0"')
    max_version=$(echo "$compat" | jq -r '.max_tested_agent_version // "999.x"')
    
    # Simple version comparison (major.minor.patch)
    local IFS='.'
    local -a agent_arr min_arr max_arr
    read -ra agent_arr <<< "$agent_version"
    read -ra min_arr <<< "$min_version"
    read -ra max_arr <<< "$max_version"
    
    # Check minimum
    local i=0
    while (( i < 3 )); do
        local a=${agent_arr[$i]:-0} m=${min_arr[$i]:-0}
        if (( a < m )); then
            echo "below_minimum"
            return 1
        elif (( a > m )); then
            break
        fi
        (( i++ ))
    done
    
    # Check maximum (ignore 'x' wildcards)
    i=0
    while (( i < 3 )); do
        local a=${agent_arr[$i]:-0} m=${max_arr[$i]:-0}
        [[ "${max_arr[$i]}" == "x" || "${max_arr[$i]}" == "*" ]] && break
        if (( a > m )); then
            echo "above_maximum"
            return 1
        elif (( a < m )); then
            break
        fi
        (( i++ ))
    done
    
    echo "compatible"
    return 0
}

# Update schema version with migration
# Usage: _tv_migrate_schema <target_version>
_tv_migrate_schema() {
    local target="$1"
    [[ ! -f "$TV_VERSION_FILE" ]] && return 1
    
    local current
    current=$(jq -r '.schema_version // 0' "$TV_VERSION_FILE")
    
    if (( current >= target )); then
        _tv_print "  ${_TV_GRY}Schema already at version ${current}${_TV_RST}"
        return 0
    fi
    
    _tv_print "  ${_TV_GRY}Migrating schema from v${current} to v${target}...${_TV_RST}"
    
    # Backup before migration
    cp "$TV_VERSION_FILE" "${TV_VERSION_FILE}.bak.$(date +%s)"
    
    # Update schema version
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    
    jq --argjson ver "$target" '.schema_version = $ver' "$TV_VERSION_FILE" > "$tmp" \
        && mv -f "$tmp" "$TV_VERSION_FILE" || { rm -f "$tmp"; return 1; }
    
    _tv_print "  ${_TV_GRN}✓ Schema migrated to v${target}${_TV_RST}"
}

# --- VERSIONING OPEN/CLOSE ---

tv_versioning_open() {
    [[ -n "${TV_VERSIONING_OPENED:-}" ]] && return 0
    _tv_init_versioning
    TV_VERSIONING_OPENED=1
}

tv_versioning_close() {
    TV_VERSIONING_OPENED=""
}
