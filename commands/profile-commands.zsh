# Guard against double sourcing
[[ -n "${TV_PROFILE_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_PROFILE_COMMANDS_LOADED=1

# CLI: tv-add [-ID id] [-Prov anthropic|openai|gemini|custom] [-Auth cli|key]
#             [-Base url] [-QuotaAPI url] [-Reset daily|payg] [-Key apikey]
#             [-Model model-id]
tv-add() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "run_tv_unlock_first" "Run tv-unlock first")${_TV_RST}"; return 1; }

    local p_id="" prov="" auth_mode="" reset_type="" base_url="" quota_api="" k="" default_model="" cli_mode=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ID)       cli_mode=1; p_id="$2";        shift 2 ;;
            -Prov)     cli_mode=1; prov="$2";        shift 2 ;;
            -Auth)     cli_mode=1; auth_mode="$2";   shift 2 ;;
            -Base)     cli_mode=1; base_url="$2";    shift 2 ;;
            -QuotaAPI) cli_mode=1; quota_api="$2";   shift 2 ;;
            -Reset)    cli_mode=1; reset_type="$2";  shift 2 ;;
            -Key)      cli_mode=1; k="$2";           shift 2 ;;
            -Model)    cli_mode=1; default_model="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    _tv_banner "$(_tv_tr "add_profile_title" "Add Profile")"
    if [[ "$cli_mode" == "1" ]]; then
        [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "required_id_flag" "Required: -ID")${_TV_RST}"; return 1; }
    else
        _tv_ask p_id "profile_id_prompt"
    fi
    [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "required_value" "Required")${_TV_RST}"; return 1; }
    _tv_validate_id "$p_id" || return 1

    if [[ "$cli_mode" == "1" ]]; then
        [[ -z "$prov" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "required_provider_flag" "Required: -Prov")${_TV_RST}"; return 1; }
    else
        _tv_menu prov "provider_title" 1 \
            "anthropic" "(Anthropic / Claude)" \
            "openai"    "(OpenAI / Codex)" \
            "gemini"    "(Google Gemini)" \
            "custom"    "(any other provider)"
    fi

    if [[ "$prov" != "custom" && -z "$auth_mode" ]]; then
        if [[ "$cli_mode" == "1" ]]; then
            auth_mode="key"
        else
            _tv_menu auth_mode "auth_mode_title" 1 \
                "cli" "(provider's own login — no key stored)" \
                "key" "(inject API key via env vars)"
        fi
        reset_type="official"
    else
        auth_mode="${auth_mode:-key}"
        [[ "$prov" == "custom" && -z "$reset_type" ]] && reset_type=""
    fi

    if [[ "$auth_mode" == "key" ]]; then
        if [[ "$cli_mode" != "1" ]]; then
            _tv_ask base_url "base_url_prompt"
        fi
        if [[ "$prov" == "custom" || -n "$base_url" ]]; then
            if [[ "$cli_mode" == "1" ]]; then
                quota_api="${quota_api:-$TV_QUOTA_API_URL}"
                reset_type="${reset_type:-daily}"
            else
                _tv_ask quota_api "quota_api_prompt" "$TV_QUOTA_API_URL"
                _tv_menu reset_type "reset_type_title" 1 \
                    "daily" "(auto re-enable after quota resets)" \
                    "payg"  "(disable permanently when exhausted)"
            fi
        fi
    fi

    local env_key env_token env_base env_model
    case "$prov" in
        anthropic) env_key="ANTHROPIC_API_KEY"; env_token="ANTHROPIC_AUTH_TOKEN"; env_base="ANTHROPIC_BASE_URL"; env_model="ANTHROPIC_MODEL" ;;
        openai)    env_key="OPENAI_API_KEY";    env_token="";                      env_base="OPENAI_BASE_URL";    env_model="OPENAI_DEFAULT_MODEL" ;;
        gemini)    env_key="GEMINI_API_KEY";    env_token="";                      env_base="";                   env_model="GEMINI_DEFAULT_MODEL" ;;
        *)         env_key="CUSTOM_API_KEY";    env_token="";                      env_base="CUSTOM_BASE_URL";    env_model="CUSTOM_DEFAULT_MODEL" ;;
    esac
    if [[ "$cli_mode" != "1" ]]; then
        _tv_print "\n  ${_TV_GRY}$(_tv_tr "env_vars_header" "Env var names (Enter = keep default)")${_TV_RST}"
        _tv_ask env_key   "key_env_prompt"   "$env_key"
        _tv_ask env_base  "base_env_prompt"  "$env_base"
        _tv_ask env_model "model_env_prompt" "$env_model"
    fi

    if [[ "$auth_mode" == "key" && -z "$k" ]]; then
        if [[ "$cli_mode" == "1" ]]; then
            _tv_print "  ${_TV_RED}✗ $(_tv_tr "required_key_flag" "Required: -Key")${_TV_RST}"
            return 1
        else
            printf "\n  %s: " "$(_tv_tr "api_key_prompt" "API Key")"
            read -rs k
            echo ""
            k=${k//[[:space:]]/}
            [[ -z "$k" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "key_required" "Key required")${_TV_RST}"; return 1; }
        fi
    fi

    if [[ "$cli_mode" != "1" && "$auth_mode" == "key" && -n "$k" ]]; then
        _tv_pick_model default_model "$prov" "$base_url" "$k"
    fi

    local v
    v=$(_tv_crypto dec)
    _tv_crypto enc "$(echo "$v" | jq --arg p "$p_id" --arg k "$k" \
        '.[$p] = (if $k != "" then $k else .[$p] end)')"

    local short=""
    [[ -n "$k" ]] && short=$(_tv_short_key "$k")
    local env_map
    env_map=$(jq -n \
        --arg ek "$env_key" --arg et "$env_token" \
        --arg eb "$env_base" --arg em "$env_model" \
        '{key:$ek, token:$et, base:$eb, model:$em}')
    local new_profile
    new_profile=$(jq -n \
        --arg prov "$prov" --arg short "$short" \
        --arg auth "${auth_mode:-key}" --arg rt "${reset_type:-daily}" \
        --arg qa "${quota_api:-}" --arg bu "${base_url:-}" \
        --arg dm "${default_model:-}" --argjson em "$env_map" \
        '{provider:$prov, short:$short, auth_mode:$auth, reset_type:$rt,
          quota_api:$qa, base_url:$bu, default_model:$dm,
          env_map:$em, status:"active", remain:0, reset_at:"", last_checked:""}')
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" --argjson prof "$new_profile" \
        '.[$p] = $prof' "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }

    _tv_print "\n  ${_TV_GRN}✓ Profile ${_TV_WHT}[$p_id]${_TV_RST}${_TV_GRN} added (${prov} / ${auth_mode:-key})${_TV_RST}"
    _tv_spawn_worker
}

tv-report() {
    local p_id="$1"
    [[ -z "$p_id" ]] && { print -Pn "  $(_tv_tr "report_profile_prompt" "Profile ID to report"): "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1

    local exists
    exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_trf "profile_not_found" "Profile not found: %s" "$p_id")${_TV_RST}"; return 1; }

    local confirm_prompt
    printf -v confirm_prompt "$(_tv_tr "exhausted_confirm" "Mark [%s] as exhausted?")" "$p_id"
    _tv_confirm "$confirm_prompt" || { _tv_print "  ${_TV_GRY}$(_tv_tr "cancelled" "Cancelled")${_TV_RST}"; return 0; }

    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" \
        '.[$p].status = "exhausted" | .[$p].remain = 0' \
        "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }

    rm -f "$TV_PROMPT_CACHE"
    _tv_print "  ${_TV_YEL}⚠ $(_tv_trf "profile_marked_exhausted" "[%s] marked exhausted" "$p_id")${_TV_RST}"
    _tv_spawn_worker
}

tv-remove() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_tr "run_tv_unlock_first" "Run tv-unlock first")${_TV_RST}"; return 1; }
    local p_id="$1"
    [[ -z "$p_id" ]] && { print -Pn "  $(_tv_tr "remove_profile_prompt" "Profile ID to remove"): "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1

    local exists
    exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ $(_tv_trf "profile_not_found" "Profile not found: %s" "$p_id")${_TV_RST}"; return 1; }

    local remove_prompt
    printf -v remove_prompt "$(_tv_tr "remove_profile_confirm" "Remove profile [%s]? This cannot be undone.")" "$p_id"
    _tv_confirm "$remove_prompt" || { _tv_print "  ${_TV_GRY}$(_tv_tr "cancelled" "Cancelled")${_TV_RST}"; return 0; }

    local v
    v=$(_tv_crypto dec)
    _tv_crypto enc "$(echo "$v" | jq --arg p "$p_id" 'del(.[$p])')"
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" 'del(.[$p])' "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }
    _tv_print "  ${_TV_YEL}✓ $(_tv_trf "profile_removed" "Profile [%s] removed" "$p_id")${_TV_RST}"
    _tv_spawn_worker
}

tv-list() {
    _tv_banner "Profiles"
    jq -r 'to_entries[] | "\(.key)|\(.value.provider)|\(.value.auth_mode // "key")|\(.value.status)|\(.value.short // "cli")|\(.value.remain)"' \
        "$TV_PROFILES" | \
    while IFS='|' read -r id prov am st short rem; do
        local col="${_TV_GRN}"
        [[ "$st" == "disabled"  ]] && col="${_TV_RED}"
        [[ "$st" == "exhausted" ]] && col="${_TV_YEL}"
        [[ "$am" == "cli"       ]] && col="${_TV_BLU}"
        local rem_str=""
        [[ "$am" == "key" && "$st" == "active" ]] && rem_str=" ${_TV_GRY}$(_tv_fmt_num "$rem")${_TV_RST}"
        _tv_print "  ${col}●${_TV_RST} ${_TV_WHT}${id}${_TV_RST}  ${_TV_GRY}${prov}/${am}${_TV_RST}  ${short}${rem_str}"
    done
    echo ""
}

tv-help() {
    _tv_banner "$(_tv_tr "help_help" "Help")"
    _tv_print "  ${_TV_WHT}$(_tv_tr "help_vault" "Vault")${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-unlock${_TV_RST}                        $(_tv_tr "help_unlock" "Unlock vault")"
    _tv_print "  ${_TV_CYA}tv-lock${_TV_RST}                          $(_tv_tr "help_lock" "Lock vault")"
    _tv_print "  ${_TV_CYA}tv-unsafe${_TV_RST}                        $(_tv_tr "help_unsafe" "Toggle persist-key-to-disk")\n"
    _tv_print "  ${_TV_WHT}$(_tv_tr "help_profiles" "Profiles")${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-add${_TV_RST}                           $(_tv_tr "help_add" "Interactive add")"
    _tv_print "  ${_TV_CYA}tv-add${_TV_RST} ${_TV_GRY}-ID x -Prov p -Auth a -Base u -Key k${_TV_RST}  $(_tv_tr "help_add_cli" "CLI add")"
    _tv_print "  ${_TV_CYA}tv-remove${_TV_RST} ${_TV_GRY}[-ID id]${_TV_RST}              $(_tv_tr "help_remove" "Remove profile")"
    _tv_print "  ${_TV_CYA}tv-list${_TV_RST}                          $(_tv_tr "help_list" "List all profiles")"
    _tv_print "  ${_TV_CYA}tv-dash${_TV_RST}                          $(_tv_tr "help_dash" "Dashboard + pool totals")\n"
    _tv_print "  ${_TV_WHT}$(_tv_tr "help_run" "Run")${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-run auto${_TV_RST} ${_TV_GRY}<cmd>${_TV_RST}               $(_tv_tr "help_run_auto" "Best key per provider, inject all")"
    _tv_print "  ${_TV_CYA}tv-run${_TV_RST} ${_TV_GRY}<id> <cmd>${_TV_RST}               $(_tv_tr "help_run_named" "Named profile")"
    _tv_print "  ${_TV_CYA}tv-report${_TV_RST} ${_TV_GRY}[-ID id]${_TV_RST}              $(_tv_tr "help_report" "Mark exhausted after 429")\n"
    _tv_print "  ${_TV_WHT}$(_tv_tr "help_models" "Models")${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-model-list${_TV_RST}                    $(_tv_tr "help_model_list" "Interactive — show config + fetch live list")"
    _tv_print "  ${_TV_CYA}tv-model-list${_TV_RST} ${_TV_GRY}-Prov p${_TV_RST}           $(_tv_tr "help_model_list_by_provider" "Fetch by provider")"
    _tv_print "  ${_TV_CYA}tv-model-list${_TV_RST} ${_TV_GRY}-Profile id${_TV_RST}        $(_tv_tr "help_model_list_by_profile" "Fetch by profile")"
    _tv_print "  ${_TV_CYA}tv-model-set${_TV_RST}                     $(_tv_tr "help_model_set" "Interactive — provider or profile level")"
    _tv_print "  ${_TV_CYA}tv-model-set${_TV_RST} ${_TV_GRY}-Prov p -Tier t -Model m${_TV_RST}  $(_tv_tr "help_model_set_provider" "Provider-level")"
    _tv_print "  ${_TV_CYA}tv-model-set${_TV_RST} ${_TV_GRY}-Profile id -Model m${_TV_RST}       $(_tv_tr "help_model_set_profile" "Profile-level override")"
    _tv_print "  ${_TV_CYA}tv-codex-sync${_TV_RST} ${_TV_GRY}[-Config path] [-AllowWireApi] [-Force] [-DryRun] [-Yes]${_TV_RST}  $(_tv_tr "help_codex_sync" "Mirror Codex model/provider config")"
    echo ""
}
