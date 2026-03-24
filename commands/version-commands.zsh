# Guard against double sourcing
[[ -n "${TV_VERSION_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_VERSION_COMMANDS_LOADED=1

# --- VERSION COMMANDS ---
# Version display and management commands

# tv version [--json]
tv-version-cmd() {
    local json_output=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            *)      shift ;;
        esac
    done
    
    tv_version "$json_output"
}

# tv version check-compat --agent <id> --version <ver>
tv-version-check-compat() {
    local agent_id="" agent_version=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)   agent_id="$2"; shift 2 ;;
            --version) agent_version="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done
    
    [[ -z "$agent_id" ]] && { _tv_print "  ${_TV_RED}✗ Required: --agent <id>${_TV_RST}"; return 1; }
    [[ -z "$agent_version" ]] && { _tv_print "  ${_TV_RED}✗ Required: --version <ver>${_TV_RST}"; return 1; }
    
    _tv_banner "Compatibility Check"
    
    local result
    result=$(_tv_check_adapter_compat "$agent_id" "$agent_version")
    
    case "$result" in
        compatible)
            _tv_print "  ${_TV_GRN}✓ ${agent_id} v${agent_version} is compatible${_TV_RST}"
            ;;
        below_minimum)
            local compat
            compat=$(_tv_get_adapter_compat "$agent_id")
            local min_ver
            min_ver=$(echo "$compat" | jq -r '.min_agent_version // "unknown"')
            _tv_print "  ${_TV_RED}✗ ${agent_id} v${agent_version} is below minimum (v${min_ver})${_TV_RST}"
            ;;
        above_maximum)
            local compat
            compat=$(_tv_get_adapter_compat "$agent_id")
            local max_ver
            max_ver=$(echo "$compat" | jq -r '.max_tested_agent_version // "unknown"')
            _tv_print "  ${_TV_YEL}⚠ ${agent_id} v${agent_version} is above tested maximum (v${max_ver})${_TV_RST}"
            ;;
    esac
}

# --- VERSION COMMANDS OPEN/CLOSE ---

tv_version_commands_open() {
    [[ -n "${TV_VERSION_COMMANDS_OPENED:-}" ]] && return 0
    TV_VERSION_COMMANDS_OPENED=1
}

tv_version_commands_close() {
    TV_VERSION_COMMANDS_OPENED=""
}
