# Guard against double sourcing
[[ -n "${TV_SECURITY_LOADED:-}" ]] && return 0
typeset -g TV_SECURITY_LOADED=1

# --- SECRET REDACTION ---

# Redact known secret patterns from text
_tv_redact_secrets() {
    local text="$1"
    # Redact API keys (common patterns)
    text=$(echo "$text" | sed -E 's/(sk-[a-zA-Z0-9]{20,})/[REDACTED]/g')
    text=$(echo "$text" | sed -E 's/(sk-ant-[a-zA-Z0-9]{20,})/[REDACTED]/g')
    text=$(echo "$text" | sed -E 's/(AIza[a-zA-Z0-9_-]{35})/[REDACTED]/g')
    text=$(echo "$text" | sed -E 's/(Bearer [a-zA-Z0-9_.-]{20,})/Bearer [REDACTED]/g')
    text=$(echo "$text" | sed -E 's/(x-api-key: *)[a-zA-Z0-9_.-]{20,}/\1[REDACTED]/gi')
    # Redact Authorization headers
    text=$(echo "$text" | sed -E 's/(Authorization: *)[a-zA-Z0-9_.-]{20,}/\1[REDACTED]/gi')
    printf '%s' "$text"
}

# Redact secrets from JSON output
_tv_redact_json_secrets() {
    local json="$1"
    echo "$json" | jq -r '
        walk(
            if type == "string" then
                gsub("sk-[a-zA-Z0-9]{20,}"; "[REDACTED]") |
                gsub("sk-ant-[a-zA-Z0-9]{20,}"; "[REDACTED]") |
                gsub("AIza[a-zA-Z0-9_-]{35}"; "[REDACTED]")
            else . end
        )
    ' 2>/dev/null || echo "$json"
}

# Get secret source info without exposing value
_tv_secret_source_info() {
    local p_id="$1"
    [[ -z "$p_id" ]] && return 1
    
    local row
    row=$(jq -c --arg p "$p_id" '.[$p] // empty' "$TV_PROFILES" 2>/dev/null)
    [[ -z "$row" ]] && { echo "not_found"; return 1; }
    
    local auth_mode
    auth_mode=$(echo "$row" | jq -r '.auth_mode // "key"')
    local prov
    prov=$(echo "$row" | jq -r '.provider // "unknown"')
    
    if [[ "$auth_mode" == "cli" ]]; then
        echo "cli_auth:${prov}"
    else
        local has_key="no"
        if [[ -n "$_TV_MASTER_KEY" ]]; then
            local vault_key
            vault_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$p_id" '.[$p] // empty' 2>/dev/null)
            [[ -n "$vault_key" ]] && has_key="yes"
        fi
        echo "vault:${prov}:${has_key}"
    fi
}

# --- TERMINAL SAFETY ---

# Sanitize terminal control characters from output
_tv_sanitize_terminal() {
    local text="$1"
    # Remove ANSI escape sequences
    text=$(echo "$text" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g')
    # Remove other control characters except newline and tab
    text=$(echo "$text" | tr -d '\000-\010\013\014\016-\037\177')
    printf '%s' "$text"
}

# --- ENDPOINT SAFETY ---

# Check if URL is private/local (SSRF protection)
_tv_is_private_url() {
    local url="$1"
    # Extract hostname
    local host
    host=$(echo "$url" | sed -E 's|https?://([^/:]+).*|\1|' | tr '[:upper:]' '[:lower:]')
    
    # Check for localhost variants
    case "$host" in
        localhost|127.*|::1|0.0.0.0|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|169.254.*|*.local|*.internal)
            return 0
            ;;
    esac
    return 1
}

# Validate endpoint URL safety
_tv_validate_endpoint() {
    local url="$1" allow_private="${2:-0}"
    
    # Check URL scheme
    if [[ ! "$url" =~ ^https?:// ]]; then
        _tv_print "  ${_TV_RED}✗ Invalid URL scheme (must be http or https)${_TV_RST}"
        return 1
    fi
    
    # Check for HTTPS by default
    if [[ "$url" =~ ^http:// ]] && [[ "$allow_private" != "1" ]]; then
        _tv_print "  ${_TV_YEL}⚠ HTTP detected — HTTPS recommended for security${_TV_RST}"
    fi
    
    # Check for private endpoints
    if _tv_is_private_url "$url" && [[ "$allow_private" != "1" ]]; then
        _tv_print "  ${_TV_RED}✗ Private/local endpoint blocked (use --allow-private-endpoint to override)${_TV_RST}"
        return 1
    fi
    
    return 0
}

# --- SHELL SAFETY ---

# Safe read with IFS protection
_tv_safe_read() {
    local _var="$1" _prompt="${2:-}" _secret="${3:-0}"
    if [[ -n "$_prompt" ]]; then
        print -Pn "$_prompt"
    fi
    if [[ "$_secret" == "1" ]]; then
        IFS= read -rs "$_var"
        echo ""
    else
        IFS= read -r "$_var"
    fi
}

# Validate array index is within bounds
_tv_validate_array_index() {
    local idx="$1" max="$2"
    idx="${idx//[^0-9]/}"
    [[ -z "$idx" ]] && return 1
    (( idx >= 1 && idx <= max )) && return 0
    return 1
}

# Escape shell arguments safely
_tv_shell_escape() {
    local arg="$1"
    printf '%q' "$arg"
}

# --- CONFIG SAFETY ---

# Mark config as degraded/unsafe parse mode
typeset -g _TV_DEGRADED_PARSE="${_TV_DEGRADED_PARSE:-0}"

_tv_set_degraded_parse() {
    _TV_DEGRADED_PARSE=1
    _tv_print "  ${_TV_YEL}⚠ Degraded parse mode enabled — results may be inaccurate${_TV_RST}"
}

_tv_is_degraded_parse() {
    [[ "$_TV_DEGRADED_PARSE" == "1" ]]
}

# --- RESPONSE SAFETY ---

# Limit response size to prevent memory issues
_tv_limit_response() {
    local response="$1" max_size="${2:-1048576}"  # Default 1MB
    local size=${#response}
    if (( size > max_size )); then
        echo "${response:0:$max_size}"
        _tv_print "  ${_TV_YEL}⚠ Response truncated (${size} bytes > ${max_size} limit)${_TV_RST}"
    else
        echo "$response"
    fi
}

# --- SECURITY OPEN/CLOSE ---

tv_security_open() {
    [[ -n "${TV_SECURITY_OPENED:-}" ]] && return 0
    TV_SECURITY_OPENED=1
}

tv_security_close() {
    TV_SECURITY_OPENED=""
}
