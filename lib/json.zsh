# Guard against double sourcing
[[ -n "${TV_JSON_LOADED:-}" ]] && return 0
typeset -g TV_JSON_LOADED=1

# --- JSON UTILITIES ---
# Common JSON operations for TokenVault

# Safe jq wrapper with error handling
_tv_jq() {
    local input="$1"
    shift
    echo "$input" | jq "$@" 2>/dev/null
}

# Merge two JSON objects (second overrides first)
_tv_json_merge() {
    local base="$1" override="$2"
    echo "$base" | jq --argjson o "$override" '. * $o'
}

# Get nested JSON value by path
# Usage: _tv_json_get <json> <path> [default]
_tv_json_get() {
    local json="$1" path="$2" default="${3:-}"
    local result
    result=$(echo "$json" | jq -r "$path // empty" 2>/dev/null)
    [[ -z "$result" ]] && echo "$default" || echo "$result"
}

# Set nested JSON value by path
# Usage: _tv_json_set <json> <path> <value>
_tv_json_set() {
    local json="$1" path="$2" value="$3"
    echo "$json" | jq --arg v "$value" "$path = \$v" 2>/dev/null
}

# Delete key from JSON
# Usage: _tv_json_delete <json> <path>
_tv_json_delete() {
    local json="$1" path="$2"
    echo "$json" | jq "del($path)" 2>/dev/null
}

# Check if JSON has key
# Usage: _tv_json_has <json> <path>
_tv_json_has() {
    local json="$1" path="$2"
    local result
    result=$(echo "$json" | jq -r "has($path)" 2>/dev/null)
    [[ "$result" == "true" ]]
}

# Get JSON keys as array
# Usage: _tv_json_keys <json>
_tv_json_keys() {
    local json="$1"
    echo "$json" | jq -r 'keys[]' 2>/dev/null
}

# Get JSON array length
# Usage: _tv_json_length <json> [path]
_tv_json_length() {
    local json="$1" path="${2:-.}"
    echo "$json" | jq -r "$path | length" 2>/dev/null
}

# Iterate over JSON object entries
# Usage: _tv_json_each <json> <callback>
# Callback receives: key, value
_tv_json_each() {
    local json="$1" callback="$2"
    local keys
    keys=$(_tv_json_keys "$json")
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        local value
        value=$(echo "$json" | jq -c --arg k "$key" '.[$k]')
        eval "$callback" "$key" "$value"
    done <<< "$keys"
}

# Pretty print JSON
_tv_json_pretty() {
    local json="$1"
    echo "$json" | jq '.' 2>/dev/null || echo "$json"
}

# Minify JSON
_tv_json_minify() {
    local json="$1"
    echo "$json" | jq -c '.' 2>/dev/null || echo "$json"
}

# Validate JSON
_tv_json_validate() {
    local json="$1"
    echo "$json" | jq -e '.' >/dev/null 2>&1
}

# Create empty JSON object
_tv_json_object() {
    echo "{}"
}

# Create empty JSON array
_tv_json_array() {
    echo "[]"
}

# --- JSON OPEN/CLOSE ---

tv_json_open() {
    [[ -n "${TV_JSON_OPENED:-}" ]] && return 0
    TV_JSON_OPENED=1
}

tv_json_close() {
    TV_JSON_OPENED=""
}
