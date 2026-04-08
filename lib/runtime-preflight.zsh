# Guard against double sourcing
[[ -n "${TV_RUNTIME_PREFLIGHT_LOADED:-}" ]] && return 0
typeset -g TV_RUNTIME_PREFLIGHT_LOADED=1

# --- RUNTIME PREFLIGHT ---

_tv_runtime_preflight_emit_reject() {
    local agent="$1" profile="$2" roots="$3" code="$4" stage="$5" details="${6:-{}}"
    local log_root=""

    if [[ -n "$roots" ]]; then
        log_root=$(echo "$roots" | _tv_jq -r '.log_root // empty' 2>/dev/null)
    fi
    [[ -z "$log_root" ]] && log_root="${TV_STATE_DIR}/logs/${agent}/${profile}"

    _tv_ensure_dir "$log_root" 700 || return 0
    print -r -- "$(_tv_jq -nc \
        --arg event "reject" \
        --arg code "$code" \
        --arg agent "$agent" \
        --arg profile "$profile" \
        --arg stage "$stage" \
        --argjson details "$details" \
        '{event:$event, code:$code, agent:$agent, profile:$profile, stage:$stage, details:$details}')" >> "${log_root}/audit.jsonl"
}

_tv_runtime_preflight_fail() {
    local agent="$1" profile="$2" roots="$3" code="$4" stage="$5" details="${6:-{}}"
    _tv_runtime_preflight_emit_reject "$agent" "$profile" "$roots" "$code" "$stage" "$details"
    _tv_jq -n \
        --arg code "$code" \
        --arg stage "$stage" \
        --argjson details "$details" \
        '{
            ok: false,
            code: $code,
            stage: $stage,
            details: $details
        }'
}

_tv_runtime_preflight_ok() {
    local roots="$1" manifest="$2" policy="$3" proof="$4" global_state="$5"
    _tv_jq -n \
        --argjson roots "$roots" \
        --argjson manifest "$manifest" \
        --argjson policy "$policy" \
        --argjson proof "$proof" \
        --argjson global_state "$global_state" \
        '{
            ok: true,
            code: "",
            stage: "ok",
            roots: $roots,
            manifest: $manifest,
            policy: $policy,
            proof: $proof,
            global_state: $global_state
        }'
}

_tv_runtime_preflight() {
    local agent="$1" profile="$2" row="$3"

    local roots
    roots=$(_tv_agent_resolve_roots "$agent" "$profile") || {
        _tv_runtime_preflight_fail "$agent" "$profile" "" "E_ROOT_RESOLUTION_FAILED" "resolve roots" '{}'
        return 0
    }

    local manifest_raw policy_raw
    manifest_raw=$(_tv_runtime_manifest_read "$agent" "$profile")
    [[ -z "$manifest_raw" ]] && {
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_MANIFEST_MISSING" "load manifest" '{}'
        return 0
    }
    policy_raw=$(_tv_runtime_policy_read "$agent" "$profile")
    [[ -z "$policy_raw" ]] && {
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_POLICY_MISSING" "load policy" '{}'
        return 0
    }

    local manifest policy
    manifest=$(echo "$manifest_raw" | _tv_jq -c '.')
    policy=$(echo "$policy_raw" | _tv_jq -c '.')

    local manifest_agent manifest_profile
    manifest_agent=$(echo "$manifest" | _tv_jq -r '.agent // ""')
    manifest_profile=$(echo "$manifest" | _tv_jq -r '.profile // ""')
    if [[ "$manifest_agent" != "$agent" || "$manifest_profile" != "$profile" ]]; then
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_MANIFEST_DRIFT" "load manifest" "$(_tv_jq -n --arg manifest_agent "$manifest_agent" --arg manifest_profile "$manifest_profile" '{manifest_agent:$manifest_agent, manifest_profile:$manifest_profile}')"
        return 0
    fi

    local profile_state
    profile_state=$(_tv_agent_detect_profile_state "$agent" "$profile" "$roots" "$row" "$policy")
    if [[ "$(echo "$profile_state" | _tv_jq -r '.ok // "false"')" != "true" ]]; then
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_PROFILE_STATE_MISMATCH" "inspect observed profile artifacts" "$(echo "$profile_state" | _tv_jq -c '.details // .')"
        return 0
    fi

    local env_conflicts
    env_conflicts=$(_tv_agent_detect_env_conflicts "$agent" "$profile" "$roots" "$row" "$policy")
    if [[ "$(echo "$env_conflicts" | _tv_jq -r '.ok // "false"')" != "true" ]]; then
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_ENV_CONFLICT" "inspect runtime env" "$(echo "$env_conflicts" | _tv_jq -c '.details // .')"
        return 0
    fi

    local proof
    proof=$(_tv_agent_effective_resolution_proof "$agent" "$profile" "$roots" "$row" "$policy")
    if [[ "$(echo "$proof" | _tv_jq -r '.proof_complete // "false"')" != "true" ]]; then
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_RESOLUTION_PROOF_FAILED" "build effective resolution proof" "$(echo "$proof" | _tv_jq -c '.')"
        return 0
    fi

    local global_state
    global_state=$(_tv_agent_detect_global_state "$agent" "$profile" "$roots" "$row" "$policy")

    local mode_state
    mode_state=$(_tv_agent_check_mode_invariants "$agent" "$profile" "$roots" "$row" "$policy")
    if [[ "$(echo "$mode_state" | _tv_jq -r '.ok // "false"')" != "true" ]]; then
        _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_MODE_INVARIANT_VIOLATION" "evaluate mode invariants" "$(echo "$mode_state" | _tv_jq -c '.details // .')"
        return 0
    fi

    local shadow_policy reachable_count detected_count
    shadow_policy=$(echo "$policy" | _tv_jq -r '.global_shadow_policy // "forbid-conflict"')
    reachable_count=$(echo "$proof" | _tv_jq '(.reachable_global_paths // []) | length')
    detected_count=$(echo "$global_state" | _tv_jq '(.detected_global_artifacts // []) | length')

    case "$shadow_policy" in
        forbid-exists)
            if (( detected_count > 0 )); then
                _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_GLOBAL_SHADOW_CONFLICT" "evaluate shadow policy and conflict policy" "$(echo "$global_state" | _tv_jq -c '.')"
                return 0
            fi
            ;;
        forbid-conflict|shadow-ignore)
            if (( reachable_count > 0 )); then
                _tv_runtime_preflight_fail "$agent" "$profile" "$roots" "E_GLOBAL_SHADOW_CONFLICT" "evaluate shadow policy and conflict policy" "$(echo "$proof" | _tv_jq -c '.')"
                return 0
            fi
            ;;
    esac

    _tv_runtime_preflight_ok "$roots" "$manifest" "$policy" "$proof" "$global_state"
}

tv_runtime_preflight_open() {
    [[ -n "${TV_RUNTIME_PREFLIGHT_OPENED:-}" ]] && return 0
    TV_RUNTIME_PREFLIGHT_OPENED=1
}

tv_runtime_preflight_close() {
    TV_RUNTIME_PREFLIGHT_OPENED=""
}
