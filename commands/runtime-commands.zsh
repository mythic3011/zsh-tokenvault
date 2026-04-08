# Guard against double sourcing
[[ -n "${TV_RUNTIME_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_RUNTIME_COMMANDS_LOADED=1

tv-run() {
    emulate -L zsh
    setopt localoptions noxtrace noverbose typesetsilent
    path=(${(s/:/)PATH})

    _tv_run_print() { print -P -- "$1" >&2; }
    _tv_runtime_log_event() {
        local file="$1" content="$2"
        local dir
        dir=$(dirname "$file")
        _tv_ensure_dir "$dir" 700 || return 1
        print -r -- "$content" >> "$file"
    }

    [[ $# -lt 2 ]] && { _tv_run_print "  ${_TV_GRY}$(_tv_tr "tv_run_usage" "Usage: tv-run <id|auto> <cmd...>")${_TV_RST}"; return 1; }
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_run_print "  ${_TV_RED}✗ $(_tv_tr "run_tv_unlock_first" "Run tv-unlock first")${_TV_RST}"; return 1; }

    local target="$1"
    shift
    [[ "$target" != "auto" ]] && { _tv_validate_id "$target" || return 1; }
    local vault
    vault=$(_tv_crypto dec)
    local profiles
    profiles=$(cat "$TV_PROFILES" 2>/dev/null)
    local models_cfg
    models_cfg=$(cat "$TV_MODELS" 2>/dev/null || echo "{}")

    if [[ "$target" == "auto" ]]; then
        local -a env_cmd
        env_cmd=(env)
        local buckets="{}"
        for p in $(echo "$profiles" | jq -r 'keys[]'); do
            local row
            row=$(echo "$profiles" | jq -c --arg p "$p" '.[$p]')
            local st
            st=$(echo "$row" | jq -r '.status // "active"')
            local rt
            rt=$(echo "$row" | jq -r '.reset_type // "daily"')
            local prov
            prov=$(echo "$row" | jq -r '.provider')
            [[ "$rt" == "official" ]] && continue
            [[ "$st" != "active" ]] && continue
            local rem
            rem=$(echo "$row" | jq -r '.remain // 0')
            local cur_rem
            cur_rem=$(echo "$buckets" | jq -r --arg pv "$prov" '.[$pv].remain // -1')
            if (( rem > cur_rem )); then
                local raw_key
                raw_key=$(echo "$vault" | jq -r --arg p "$p" '.[$p] // empty')
                [[ -z "$raw_key" ]] && continue
                buckets=$(echo "$buckets" | jq \
                    --arg pv "$prov" --arg id "$p" --arg k "$raw_key" \
                    --arg bu "$(echo "$row" | jq -r '.base_url // ""')" \
                    --arg dm "$(echo "$row" | jq -r '.default_model // ""')" \
                    --argjson em "$(echo "$row" | jq -c '.env_map // {}')" \
                    --argjson r "$rem" \
                    '.[$pv] = {id:$id, key:$k, base_url:$bu, default_model:$dm, env_map:$em, remain:$r}')
            fi
        done

        local n_buckets
        n_buckets=$(echo "$buckets" | jq 'keys | length')

        for prov in $(echo "$profiles" | jq -r '[.[].provider] | unique[]'); do
            local unset_var="_TV_UNSET_${prov}[@]"
            for v in "${(P)unset_var}"; do
                env_cmd+=("-u" "$v")
            done
        done
        for v in "${_TV_UNSET_anthropic[@]}" "${_TV_UNSET_openai[@]}" "${_TV_UNSET_gemini[@]}"; do
            env_cmd+=("-u" "$v")
        done

        if (( n_buckets == 0 )); then
            _tv_run_print "  ${_TV_YEL}⚠ $(_tv_tr "no_active_custom_keys" "No active custom keys — using system session")${_TV_RST}"
        else
            for prov in $(echo "$buckets" | jq -r 'keys[]'); do
                local winner
                winner=$(echo "$buckets" | jq -c --arg pv "$prov" '.[$pv]')
                local winner_id
                winner_id=$(echo "$winner" | jq -r '.id')
                local winner_rem
                winner_rem=$(echo "$winner" | jq -r '.remain')
                local k
                k=$(echo "$winner" | jq -r '.key')
                _tv_run_print "  ${_TV_GRN}✓ ${prov}${_TV_RST}  ${_TV_GRY}→${_TV_RST} ${_TV_WHT}${winner_id}${_TV_RST}  ${_TV_GRY}($(_tv_fmt_num "$winner_rem") remaining)${_TV_RST}"
                local bu
                bu=$(echo "$winner" | jq -r '.base_url // ""')
                local dm
                dm=$(echo "$winner" | jq -r '.default_model // ""')
                local em
                em=$(echo "$winner" | jq -c '.env_map // {}')

                local env_key
                env_key=$(echo "$em" | jq -r '.key   // empty')
                local env_token
                env_token=$(echo "$em" | jq -r '.token // empty')
                local env_base
                env_base=$(echo "$em" | jq -r '.base  // empty')
                local env_model
                env_model=$(echo "$em" | jq -r '.model // empty')

                [[ -n "$env_key"   ]] && env_cmd+=("${env_key}=$k")
                [[ -n "$env_token" ]] && env_cmd+=("${env_token}=$k")
                [[ -n "$env_base" && -n "$bu" ]] && env_cmd+=("${env_base}=$bu")

                local final_model="$dm"
                if [[ -z "$final_model" ]]; then
                    final_model=$(echo "$models_cfg" | jq -r --arg pv "$prov" '.[$pv].default // empty')
                fi
                [[ -n "$env_model" && -n "$final_model" ]] && env_cmd+=("${env_model}=$final_model")

                if [[ "$prov" == "anthropic" ]]; then
                    local haiku
                    haiku=$(echo "$models_cfg" | jq -r '.anthropic.haiku   // empty')
                    local sonnet
                    sonnet=$(echo "$models_cfg" | jq -r '.anthropic.sonnet  // empty')
                    local opus
                    opus=$(echo "$models_cfg" | jq -r '.anthropic.opus    // empty')
                    local subagent
                    subagent=$(echo "$models_cfg" | jq -r '.anthropic.subagent // empty')
                    [[ -n "$haiku"    ]] && env_cmd+=("ANTHROPIC_DEFAULT_HAIKU_MODEL=$haiku")
                    [[ -n "$sonnet"   ]] && env_cmd+=("ANTHROPIC_DEFAULT_SONNET_MODEL=$sonnet")
                    [[ -n "$opus"     ]] && env_cmd+=("ANTHROPIC_DEFAULT_OPUS_MODEL=$opus")
                    [[ -n "$subagent" ]] && env_cmd+=("CLAUDE_CODE_SUBAGENT_MODEL=$subagent")
                fi
            done
        fi

        echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"mode\":\"auto\",\"cmd\":\"$1\"}" >> "$TV_USAGE_LOG"
        "${env_cmd[@]}" "$@"
    else
        local row
        row=$(echo "$profiles" | jq -c --arg p "$target" '.[$p] // empty')
        [[ -z "$row" ]] && { _tv_run_print "  ${_TV_RED}✗ $(_tv_trf "profile_not_found" "Profile not found: %s" "$target")${_TV_RST}"; return 1; }

        local auth_mode
        auth_mode=$(echo "$row" | jq -r '.auth_mode // "key"')
        local prov
        prov=$(echo "$row" | jq -r '.provider')
        local command_name="${1:t}"

        if [[ "$command_name" == "codex" && ( "$auth_mode" == "cli" || "$auth_mode" == "key" ) ]]; then
            _tv_runtime_bootstrap_from_profile "codex" "$target" "$row" || {
                _tv_run_print "  ${_TV_RED}✗ $(_tv_trf "runtime_bootstrap_failed" "Failed to materialize runtime policy for profile: %s" "$target")${_TV_RST}"
                return 1
            }

            local preflight
            preflight=$(_tv_runtime_preflight "codex" "$target" "$row")
            if [[ "$(echo "$preflight" | jq -r '.ok // "false"')" != "true" ]]; then
                local fail_code
                fail_code=$(echo "$preflight" | jq -r '.code // "unknown"')
                _tv_run_print "  ${_TV_RED}✗ $(_tv_tr "runtime_preflight_failed" "Runtime preflight failed")${_TV_RST}"
                _tv_run_print "  ${_TV_GRY}$(_tv_trf "runtime_preflight_code" "Code: %s" "$fail_code")${_TV_RST}"
                return 1
            fi

            local roots policy
            roots=$(echo "$preflight" | jq -c '.roots')
            policy=$(echo "$preflight" | jq -c '.policy')
            local runtime_home log_root
            log_root=$(echo "$roots" | jq -r '.log_root')

            local -a env_cmd
            env_cmd=(env)
            local scrub_var
            for scrub_var in $(echo "$policy" | jq -r '.env_scrublist[]?'); do
                env_cmd+=("-u" "$scrub_var")
            done
            if [[ "$auth_mode" == "cli" ]]; then
                local prepared
                prepared=$(_tv_agent_prepare_oauth_runtime "codex" "$target" "$roots" "$row" "$policy")
                if [[ "$(echo "$prepared" | jq -r '.ok // "false"')" != "true" ]]; then
                    _tv_run_print "  ${_TV_RED}✗ $(_tv_trf "runtime_prepare_failed" "Failed to prepare runtime for profile: %s" "$target")${_TV_RST}"
                    return 1
                fi
                runtime_home=$(echo "$prepared" | jq -r '.runtime_home // empty')
            else
                local k
                k=$(echo "$vault" | jq -r --arg p "$target" '.[$p] // empty')
                [[ -z "$k" ]] && { _tv_run_print "  ${_TV_RED}✗ $(_tv_trf "no_key_stored" "No key stored for: %s" "$target")${_TV_RST}"; return 1; }

                local written
                written=$(_tv_agent_write_api_config "codex" "$target" "$roots" "$row" "$policy" "$k")
                if [[ "$(echo "$written" | jq -r '.ok // "false"')" != "true" ]]; then
                    _tv_run_print "  ${_TV_RED}✗ $(_tv_trf "runtime_prepare_failed" "Failed to prepare runtime for profile: %s" "$target")${_TV_RST}"
                    return 1
                fi
                runtime_home=$(echo "$written" | jq -r '.runtime_home // empty')
                env_cmd+=("OPENAI_API_KEY=$k")
            fi

            env_cmd+=("CODEX_HOME=$runtime_home")

            _tv_runtime_log_event "${log_root}/usage.jsonl" "$(jq -nc --arg ts "$(date -u +%FT%TZ)" --arg profile "$target" --arg agent "codex" --arg mode "$(echo "$policy" | jq -r '.launch_mode // "unknown"')" --arg cmd "$command_name" '{ts:$ts, profile:$profile, agent:$agent, mode:$mode, cmd:$cmd}')" >/dev/null 2>&1
            "${env_cmd[@]}" "$@"
            return $?
        fi

        echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"profile\":\"$target\",\"provider\":\"$prov\",\"cmd\":\"$1\"}" >> "$TV_USAGE_LOG"

        if [[ "$auth_mode" == "cli" ]]; then
            "$@"
        else
            local -a env_cmd
            env_cmd=(env)
            local k
            k=$(echo "$vault" | jq -r --arg p "$target" '.[$p] // empty')
            [[ -z "$k" ]] && { _tv_run_print "  ${_TV_RED}✗ $(_tv_trf "no_key_stored" "No key stored for: %s" "$target")${_TV_RST}"; return 1; }

            local bu
            bu=$(echo "$row" | jq -r '.base_url // ""')
            local dm
            dm=$(echo "$row" | jq -r '.default_model // ""')
            local em
            em=$(echo "$row" | jq -c '.env_map // {}')
            local env_key
            env_key=$(echo "$em" | jq -r '.key   // empty')
            local env_token
            env_token=$(echo "$em" | jq -r '.token // empty')
            local env_base
            env_base=$(echo "$em" | jq -r '.base  // empty')
            local env_model
            env_model=$(echo "$em" | jq -r '.model // empty')

            local unset_var="_TV_UNSET_${prov}[@]"
            for v in "${(P)unset_var}"; do
                env_cmd+=("-u" "$v")
            done

            [[ -n "$env_key"   ]] && env_cmd+=("${env_key}=$k")
            [[ -n "$env_token" ]] && env_cmd+=("${env_token}=$k")
            [[ -n "$env_base" && -n "$bu" ]] && env_cmd+=("${env_base}=$bu")

            local final_model="$dm"
            [[ -z "$final_model" ]] && final_model=$(echo "$models_cfg" | jq -r --arg pv "$prov" '.[$pv].default // empty')
            [[ -n "$env_model" && -n "$final_model" ]] && env_cmd+=("${env_model}=$final_model")

            if [[ "$prov" == "anthropic" ]]; then
                local haiku
                haiku=$(echo "$models_cfg" | jq -r '.anthropic.haiku   // empty')
                local sonnet
                sonnet=$(echo "$models_cfg" | jq -r '.anthropic.sonnet  // empty')
                local opus
                opus=$(echo "$models_cfg" | jq -r '.anthropic.opus    // empty')
                local subagent
                subagent=$(echo "$models_cfg" | jq -r '.anthropic.subagent // empty')
                [[ -n "$haiku"    ]] && env_cmd+=("ANTHROPIC_DEFAULT_HAIKU_MODEL=$haiku")
                [[ -n "$sonnet"   ]] && env_cmd+=("ANTHROPIC_DEFAULT_SONNET_MODEL=$sonnet")
                [[ -n "$opus"     ]] && env_cmd+=("ANTHROPIC_DEFAULT_OPUS_MODEL=$opus")
                [[ -n "$subagent" ]] && env_cmd+=("CLAUDE_CODE_SUBAGENT_MODEL=$subagent")
            fi

            "${env_cmd[@]}" "$@"
        fi
    fi
}

tv-dash() {
    _tv_banner "$(_tv_tr "dashboard_title" "Dashboard")"
    _tv_print "$(printf "  %-14s %-12s %-6s %-8s %-10s %-10s %s" \
        "PROFILE" "PROVIDER" "AUTH" "RESET" "STATUS" "REMAIN" "MODEL")"
    _tv_print "  ${_TV_GRY}$(printf '%.0s─' {1..72})${_TV_RST}"

    jq -r 'to_entries[] | "\(.key)|\(.value.provider)|\(.value.auth_mode // "key")|\(.value.reset_type // "—")|\(.value.status)|\(.value.remain)|\(.value.default_model // "—")"' \
        "$TV_PROFILES" | \
    while IFS='|' read -r id prov am rt st rem dm; do
        local col="${_TV_GRN}"
        [[ "$st" == "DEAD"      ]] && col="${_TV_RED}"
        [[ "$st" == "disabled"  ]] && col="${_TV_RED}"
        [[ "$st" == "exhausted" ]] && col="${_TV_YEL}"
        [[ "$rt" == "official"  ]] && col="${_TV_BLU}"
        [[ "$am" == "cli"       ]] && col="${_TV_BLU}"
        (( rem < 1000 && rem > 0 )) && [[ "$st" == "active" ]] && col="${_TV_YEL}"
        local row
        row=$(printf "  %-14s %-12s %-6s %-8s %-10s %-10s %s" \
            "${_TV_WHT}${id}${_TV_RST}" \
            "${_TV_GRY}${prov}${_TV_RST}" \
            "${_TV_GRY}${am}${_TV_RST}" \
            "${_TV_GRY}${rt}${_TV_RST}" \
            "${col}${st}${_TV_RST}" \
            "$rem" \
            "${_TV_GRY}${dm}${_TV_RST}")
        _tv_print "$row"
    done
    echo ""

    _tv_print "  ${_TV_GRY}$(_tv_tr "pool_totals" "Pool totals:")${_TV_RST}"
    jq -r '
        to_entries
        | group_by(.value.provider)[]
        | {
            prov: .[0].value.provider,
            active: (map(select(.value.status=="active")) | length),
            total:  length,
            remain: (map(select(.value.status=="active") | .value.remain) | add // 0)
          }
        | "\(.prov)|\(.active)/\(.total)|\(.remain)"
    ' "$TV_PROFILES" | \
    while IFS='|' read -r prov ratio rem; do
        local col="${_TV_GRN}"
        (( rem < 1000 )) && col="${_TV_YEL}"
        (( rem == 0   )) && col="${_TV_RED}"
        local pool_line
        pool_line=$(printf "  %-12s keys: %-6s %s" \
            "${_TV_WHT}${prov}${_TV_RST}" \
            "${_TV_GRY}${ratio}${_TV_RST}" \
            "${col}$(_tv_fmt_num "$rem")${_TV_RST}")
        _tv_print "$pool_line"
    done
    echo ""
}
