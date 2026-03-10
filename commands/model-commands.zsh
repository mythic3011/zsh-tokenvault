# Guard against double sourcing
[[ -n "${TV_MODEL_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_MODEL_COMMANDS_LOADED=1

tv-model-set() {
    local prov="" tier="" model="" p_id="" scope=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -Prov)    prov="$2";    shift 2 ;;
            -Tier)    tier="$2";    shift 2 ;;
            -Model)   model="$2";   shift 2 ;;
            -Profile) p_id="$2";    shift 2 ;;
            *)        shift ;;
        esac
    done

    if [[ -z "$scope" ]]; then
        if [[ -n "$p_id" ]]; then
            scope="profile"
        elif [[ -n "$prov" || -n "$tier" || -n "$model" ]]; then
            scope="provider"
        fi
    fi

    [[ -n "$p_id" ]] && { _tv_validate_id "$p_id" || return 1; }

    _tv_banner "Set Default Model"
    _tv_menu scope "Apply to" 1 \
        "provider" "(set default for all keys of a provider)" \
        "profile"  "(override for one specific profile)"

    if [[ "$scope" == "provider" ]]; then
        _tv_menu prov "Provider" 1 \
            "anthropic" "" "openai" "" "gemini" "" "custom" ""

        if [[ "$prov" == "anthropic" ]]; then
            _tv_menu tier "Tier" 1 \
                "haiku"   "(fast / cheap)" \
                "sonnet"  "(balanced)" \
                "opus"    "(powerful)" \
                "subagent" "(Claude Code subagent)"
        else
            tier="default"
        fi

        _tv_print "\n  ${_TV_GRY}Fetching model list for ${prov}...${_TV_RST}"
        local _vault_key=""
        if [[ -n "$_TV_MASTER_KEY" ]]; then
            local _pid
            _pid=$(jq -r --arg pv "$prov" \
                'to_entries | map(select(.value.provider==$pv and .value.status=="active")) | .[0].key // empty' \
                "$TV_PROFILES")
            [[ -n "$_pid" ]] && _vault_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$_pid" '.[$p] // empty')
            local _base
            _base=$(jq -r --arg p "$_pid" '.[$p].base_url // ""' "$TV_PROFILES" 2>/dev/null)
        fi
        _tv_pick_model model "$prov" "${_base:-}" "$_vault_key"
        [[ -z "$model" ]] && { _tv_print "  ${_TV_YEL}⚠ No model selected${_TV_RST}"; return 1; }

        local tmp
        tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
        chmod 600 "$tmp"
        jq --arg pv "$prov" --arg t "$tier" --arg m "$model" \
            '.[$pv][$t] = $m' "$TV_MODELS" > "$tmp" && mv -f "$tmp" "$TV_MODELS" || { rm -f "$tmp"; return 1; }
        _tv_print "\n  ${_TV_GRN}✓ ${prov}.${tier} = ${model}${_TV_RST}"
    else
        if [[ -z "$p_id" ]]; then
            _tv_print "\n  Profiles:"
            local i=1
            local -a _pids
            jq -r 'keys[]' "$TV_PROFILES" | while IFS= read -r pid; do
                local st
                st=$(jq -r --arg p "$pid" '.[$p].status' "$TV_PROFILES")
                _tv_print "  ${_TV_GRY}${i})${_TV_RST} $pid  ${_TV_GRY}($st)${_TV_RST}"
                _pids+=("$pid")
                (( ++i ))
            done
            local -a _pids2
            while IFS= read -r pid; do _pids2+=("$pid"); done < <(jq -r 'keys[]' "$TV_PROFILES")
            printf "\n  Choice: "
            read _c
            p_id="${_pids2[${_c}]}"
        fi
        [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ No profile selected${_TV_RST}"; return 1; }
        local exists
        exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
        [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }

        local _row
        _row=$(jq -c --arg p "$p_id" '.[$p]' "$TV_PROFILES")
        local _prov
        _prov=$(echo "$_row" | jq -r '.provider')
        local _base
        _base=$(echo "$_row" | jq -r '.base_url // ""')
        local _vault_key=""
        if [[ -n "$_TV_MASTER_KEY" ]]; then
            _vault_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$p_id" '.[$p] // empty')
        fi
        _tv_pick_model model "$_prov" "$_base" "$_vault_key"
        [[ -z "$model" ]] && { _tv_print "  ${_TV_YEL}⚠ No model selected${_TV_RST}"; return 1; }

        local tmp
        tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
        chmod 600 "$tmp"
        jq --arg p "$p_id" --arg m "$model" \
            '.[$p].default_model = $m' "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }
        _tv_print "\n  ${_TV_GRN}✓ [$p_id] default_model = ${model}${_TV_RST}"
    fi
}

tv-model-list() {
    local target_prov="" target_base="" target_key="" p_id="" prov=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -Prov)    prov="$2";  shift 2 ;;
            -Profile) p_id="$2"; shift 2 ;;
            *)        shift ;;
        esac
    done

    _tv_banner "Models"
    _tv_print "  ${_TV_WHT}Current provider defaults:${_TV_RST}"
    if [[ "$(cat "$TV_MODELS")" == "{}" ]]; then
        _tv_print "  ${_TV_GRY}(none configured)${_TV_RST}"
    else
        jq -r 'to_entries[] | "  \(.key): " + (.value | to_entries | map("\(.key)=\(.value)") | join("  "))' "$TV_MODELS" | \
        while IFS= read -r line; do _tv_print "  ${_TV_GRY}${line}${_TV_RST}"; done
    fi
    echo ""

    if [[ -n "$p_id" ]]; then
        local row
        row=$(jq -c --arg p "$p_id" '.[$p] // empty' "$TV_PROFILES")
        [[ -z "$row" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }
        target_prov=$(echo "$row" | jq -r '.provider')
        target_base=$(echo "$row" | jq -r '.base_url // ""')
        [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
        target_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$p_id" '.[$p] // empty')
    elif [[ -n "$prov" ]]; then
        target_prov="$prov"
        [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
        local vault
        vault=$(_tv_crypto dec)
        local pid
        pid=$(jq -r --arg pv "$prov" \
            'to_entries | map(select(.value.provider==$pv and .value.status=="active")) | .[0].key // empty' \
            "$TV_PROFILES")
        [[ -z "$pid" ]] && { _tv_print "  ${_TV_RED}✗ No active profile for: $prov${_TV_RST}"; return 1; }
        target_base=$(jq -r --arg p "$pid" '.[$p].base_url // ""' "$TV_PROFILES")
        target_key=$(echo "$vault" | jq -r --arg p "$pid" '.[$p] // empty')
    else
        _tv_menu _fetch_scope "Fetch live model list from" 1 \
            "provider" "(by provider name)" \
            "profile"  "(by profile ID)" \
            "skip"     "(just show config above)"
        if [[ "$_fetch_scope" == "skip" ]]; then return 0; fi

        if [[ "$_fetch_scope" == "provider" ]]; then
            _tv_menu target_prov "Provider" 1 \
                "anthropic" "" "openai" "" "gemini" "" "custom" ""
            [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
            local vault
            vault=$(_tv_crypto dec)
            local pid
            pid=$(jq -r --arg pv "$target_prov" \
                'to_entries | map(select(.value.provider==$pv and .value.status=="active")) | .[0].key // empty' \
                "$TV_PROFILES")
            [[ -z "$pid" ]] && { _tv_print "  ${_TV_RED}✗ No active profile for: $target_prov${_TV_RST}"; return 1; }
            target_base=$(jq -r --arg p "$pid" '.[$p].base_url // ""' "$TV_PROFILES")
            target_key=$(echo "$vault" | jq -r --arg p "$pid" '.[$p] // empty')
        else
            _tv_print "\n  Profiles:"
            local -a _pids2
            local i=1
            while IFS= read -r pid; do
                local st
                st=$(jq -r --arg p "$pid" '.[$p].status' "$TV_PROFILES")
                _tv_print "  ${_TV_GRY}${i})${_TV_RST} $pid  ${_TV_GRY}($st)${_TV_RST}"
                _pids2+=("$pid")
                (( ++i ))
            done < <(jq -r 'keys[]' "$TV_PROFILES")
            printf "\n  Choice: "
            read _c
            local sel="${_pids2[${_c}]}"
            [[ -z "$sel" ]] && return 1
            local row
            row=$(jq -c --arg p "$sel" '.[$p]' "$TV_PROFILES")
            target_prov=$(echo "$row" | jq -r '.provider')
            target_base=$(echo "$row" | jq -r '.base_url // ""')
            [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
            target_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$sel" '.[$p] // empty')
        fi
    fi

    _tv_print "  ${_TV_GRY}Fetching from ${target_prov}...${_TV_RST}"
    local model_list
    model_list=$(_tv_fetch_models "$target_prov" "$target_base" "$target_key")
    if [[ -z "$model_list" ]]; then
        _tv_print "  ${_TV_RED}✗ Could not fetch model list${_TV_RST}"
        return 1
    fi
    _tv_print "  ${_TV_GRN}✓ Available models:${_TV_RST}\n"
    local i=1
    while IFS= read -r m; do
        _tv_print "  ${_TV_GRY}${i})${_TV_RST} $m"
        (( ++i ))
    done <<< "$model_list"
    echo ""
}

tv-codex-sync() {
    local config_path="" force=0 dry_run=0 allow_wire_api=0 yes=0 show_help=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -Config|--config) config_path="$2"; shift 2 ;;
            -Force|--force) force=1; shift ;;
            -DryRun|--dry-run) dry_run=1; shift ;;
            -AllowWireApi|--allow-wire-api) allow_wire_api=1; shift ;;
            -Yes|--yes) yes=1; shift ;;
            -H|--help|--h) show_help=1; shift ;;
            *) _tv_print "  ${_TV_RED}✗ Unknown flag: $1${_TV_RST}"; return 1 ;;
        esac
    done

    if [[ "$show_help" == "1" ]]; then
        _tv_print "  ${_TV_WHT}tv-codex-sync${_TV_RST} [-Config path] [-AllowWireApi] [-Force] [-DryRun] [-Yes]"
        _tv_print "    Read Codex config and mirror its provider/model settings into TokenVault profiles."
        _tv_print "    Config search order: CLI flag > \$CODEX_CONFIG > \$CODEX_HOME/config.toml > \$HOME/.codex/config.toml."
        return 0
    fi

    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }

    local resolved_config="$config_path"
    if [[ -z "$resolved_config" ]]; then
        if [[ -n "$CODEX_CONFIG" ]]; then
            resolved_config="$CODEX_CONFIG"
        elif [[ -n "$CODEX_HOME" ]]; then
            resolved_config="${CODEX_HOME%/}/config.toml"
        else
            resolved_config="${HOME}/.codex/config.toml"
        fi
    fi

    _tv_print "  ${_TV_GRN}Reading Codex config from ${resolved_config}${_TV_RST}"
    local codex_data
    codex_data=$(_tv_read_codex_config "$resolved_config")
    local ok
    ok=$(echo "$codex_data" | jq -r '.ok // "false"')
    if [[ "$ok" != "true" ]]; then
        local err msg
        err=$(echo "$codex_data" | jq -r '.error // "unknown_error"')
        msg=$(echo "$codex_data" | jq -r '.message // ""')
        _tv_print "  ${_TV_RED}✗ Codex config load failed (${err})${_TV_RST}"
        [[ -n "$msg" ]] && _tv_print "    ${_TV_RED}${msg}${_TV_RST}"
        return 1
    fi

    local provider_count
    provider_count=$(echo "$codex_data" | jq -r '.providers | length')
    if (( provider_count == 0 )); then
        _tv_print "  ${_TV_YEL}⚠ Codex config does not declare any providers${_TV_RST}"
        return 1
    fi

    if [[ "$dry_run" == "0" && "$yes" != "1" ]]; then
        _tv_print "  ${_TV_GRY}Will sync ${provider_count} provider(s) into TokenVault${_TV_RST}"
        local _confirm
        printf "  Proceed with sync? (y/N): "
        read _confirm
        [[ "$_confirm" =~ ^[Yy]$ ]] || { _tv_print "  ${_TV_GRY}Cancelled${_TV_RST}"; return 0; }
    fi

    local profiles_json
    profiles_json=$(cat "$TV_PROFILES" 2>/dev/null || echo "{}")
    local updated_profiles="$profiles_json"
    local models_json
    models_json=$(cat "$TV_MODELS" 2>/dev/null || echo "{}")
    local updated_models="$models_json"
    local models_dirty=0
    local ops=0

    while IFS= read -r provider; do
        local provider_name
        provider_name=$(echo "$provider" | jq -r '.name // ""')
        [[ -z "$provider_name" ]] && continue
        local profile_id="codex-${provider_name}"
        _tv_validate_id "$profile_id" || { _tv_print "  ${_TV_RED}✗ Invalid profile id: ${profile_id}${_TV_RST}"; return 1; }
        local provider_type="custom"
        local requires_openai
        requires_openai=$(echo "$provider" | jq -r '.requires_openai_auth // false')
        [[ "$requires_openai" == "true" ]] && provider_type="openai"

        local base_url
        base_url=$(echo "$provider" | jq -r '.base_url // ""')
        if [[ -z "$base_url" ]]; then
            local wire_api
            wire_api=$(echo "$provider" | jq -r '.wire_api // ""')
            if [[ -n "$wire_api" ]]; then
                if [[ "$allow_wire_api" == "1" ]]; then
                    if [[ "$wire_api" =~ ^https?:// ]]; then
                        _tv_print "  ${_TV_YEL}⚠ Skipping ${provider_name}: wire_api must be a path, not a URL${_TV_RST}"
                        continue
                    fi
                    base_url="https://code.ppchat.vip/v1/${wire_api}"
                else
                    _tv_print "  ${_TV_YEL}⚠ Skipping ${provider_name}: no base_url set (use -AllowWireApi to derive)${_TV_RST}"
                    continue
                fi
            else
                _tv_print "  ${_TV_YEL}⚠ Skipping ${provider_name}: needs base_url or wire_api${_TV_RST}"
                continue
            fi
        fi

        local default_model
        default_model=$(echo "$provider" | jq -r '.default_model // ""')
        if [[ -z "$default_model" ]]; then
            local global_provider global_model
            global_provider=$(echo "$codex_data" | jq -r '.global.model_provider // ""')
            global_model=$(echo "$codex_data" | jq -r '.global.model // ""')
            [[ "$global_provider" == "$provider_name" && -n "$global_model" ]] && default_model="$global_model"
        fi

        local env_map
        if [[ "$provider_type" == "openai" ]]; then
            env_map=$(jq -n '{key:"OPENAI_API_KEY",token:"",base:"OPENAI_BASE_URL",model:"OPENAI_DEFAULT_MODEL"}')
        else
            env_map=$(jq -n '{key:"CUSTOM_API_KEY",token:"",base:"CUSTOM_BASE_URL",model:"CUSTOM_DEFAULT_MODEL"}')
        fi

        local existing_source
        existing_source=$(echo "$updated_profiles" | jq -r --arg p "$profile_id" 'if has($p) then .[$p].source // "" else "" end')
        if [[ -n "$existing_source" && "$existing_source" != "codex-sync" && "$force" != "1" ]]; then
            _tv_print "  ${_TV_YEL}Skipping ${profile_id} (manual profile exists)${_TV_RST}"
            continue
        fi

        local profile_entry
        profile_entry=$(jq -n --arg provider "$provider_type" --arg short "$provider_name" --arg auth "key" --arg rt "daily" --arg qa "" --arg bu "$base_url" --arg dm "$default_model" --arg source "codex-sync" --argjson env_map "$env_map" \
            '{provider:$provider, short:$short, auth_mode:$auth, reset_type:$rt, quota_api:$qa, base_url:$bu, default_model:$dm, env_map:$env_map, status:"active", remain:0, reset_at:"", last_checked:"", source:$source}')

        updated_profiles=$(echo "$updated_profiles" | jq --arg p "$profile_id" --argjson entry "$profile_entry" '.[$p] = $entry')

        if [[ "$force" == "1" && -n "$existing_source" && "$existing_source" != "codex-sync" ]]; then
            _tv_print "  ${_TV_GRN}Overwriting ${profile_id} (force)${_TV_RST}"
        fi

        (( ++ops ))

        if [[ -n "$default_model" ]]; then
            updated_models=$(echo "$updated_models" | jq --arg prov "$provider_type" --arg model "$default_model" '.[$prov].codex = $model')
            models_dirty=1
        fi

        local verb="Updated"
        [[ -z "$existing_source" ]] && verb="Added"
        _tv_print "  ${_TV_GRN}${verb} ${profile_id}${_TV_RST}"
    done < <(echo "$codex_data" | jq -c '.providers[]')

    if (( ops == 0 )); then
        _tv_print "  ${_TV_YEL}No Codex-managed profiles were changed${_TV_RST}"
        return 0
    fi

    if [[ "$dry_run" == "1" ]]; then
        _tv_print "  ${_TV_GRY}Dry run: ${ops} profile(s) would have been synced${_TV_RST}"
        return 0
    fi

    _tv_write_json "$TV_PROFILES" "$updated_profiles" || { _tv_print "  ${_TV_RED}✗ Failed to write profiles${_TV_RST}"; return 1; }
    if [[ "$models_dirty" == "1" ]]; then
        _tv_write_json "$TV_MODELS" "$updated_models" || _tv_print "  ${_TV_YEL}⚠ Could not update models.json${_TV_RST}"
    fi

    _tv_print "  ${_TV_GRN}Synced ${ops} Codex provider(s)${_TV_RST}"
    _tv_spawn_worker
}
