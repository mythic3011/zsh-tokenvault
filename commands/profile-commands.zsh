# Guard against double sourcing
[[ -n "${TV_PROFILE_COMMANDS_LOADED:-}" ]] && return 0
typeset -g TV_PROFILE_COMMANDS_LOADED=1

# CLI: tv-add [-ID id] [-Prov anthropic|openai|gemini|custom] [-Auth cli|key]
#             [-Base url] [-QuotaAPI url] [-Reset daily|payg] [-Key apikey]
#             [-Model model-id]
tv-add() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }

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

    _tv_banner "Add Profile"
    if [[ "$cli_mode" == "1" ]]; then
        [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ Required: -ID${_TV_RST}"; return 1; }
    else
        _tv_ask p_id "Profile ID"
    fi
    [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ Required${_TV_RST}"; return 1; }
    _tv_validate_id "$p_id" || return 1

    if [[ "$cli_mode" == "1" ]]; then
        [[ -z "$prov" ]] && { _tv_print "  ${_TV_RED}✗ Required: -Prov${_TV_RST}"; return 1; }
    else
        _tv_menu prov "Provider" 1 \
            "anthropic" "(Anthropic / Claude)" \
            "openai"    "(OpenAI / Codex)" \
            "gemini"    "(Google Gemini)" \
            "custom"    "(any other provider)"
    fi

    if [[ "$prov" != "custom" && -z "$auth_mode" ]]; then
        if [[ "$cli_mode" == "1" ]]; then
            auth_mode="key"
        else
            _tv_menu auth_mode "Auth mode" 1 \
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
            _tv_ask base_url "Proxy / Base URL (blank = official endpoint)"
        fi
        if [[ "$prov" == "custom" || -n "$base_url" ]]; then
            if [[ "$cli_mode" == "1" ]]; then
                quota_api="${quota_api:-$TV_QUOTA_API_URL}"
                reset_type="${reset_type:-daily}"
            else
                _tv_ask quota_api "Quota check API URL" "$TV_QUOTA_API_URL"
                _tv_menu reset_type "Reset type" 1 \
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
        _tv_print "\n  ${_TV_GRY}Env var names (Enter = keep default)${_TV_RST}"
        _tv_ask env_key   "Key env"   "$env_key"
        _tv_ask env_base  "Base env"  "$env_base"
        _tv_ask env_model "Model env" "$env_model"
    fi

    if [[ "$auth_mode" == "key" && -z "$k" ]]; then
        if [[ "$cli_mode" == "1" ]]; then
            _tv_print "  ${_TV_RED}✗ Required: -Key${_TV_RST}"
            return 1
        else
            printf "\n  API Key: "
            read -rs k
            echo ""
            k=${k//[[:space:]]/}
            [[ -z "$k" ]] && { _tv_print "  ${_TV_RED}✗ Key required${_TV_RST}"; return 1; }
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
    [[ -z "$p_id" ]] && { print -Pn "  Profile ID to report: "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1

    local exists
    exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }

    print -Pn "  Mark ${_TV_WHT}[$p_id]${_TV_RST} as exhausted? (y/N): "
    read _confirm
    [[ "$_confirm" =~ ^[Yy]$ ]] || { _tv_print "  ${_TV_GRY}Cancelled${_TV_RST}"; return 0; }

    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" \
        '.[$p].status = "exhausted" | .[$p].remain = 0' \
        "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }

    rm -f "$TV_PROMPT_CACHE"
    _tv_print "  ${_TV_YEL}⚠ [$p_id] marked exhausted${_TV_RST}"
    _tv_spawn_worker
}

tv-remove() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
    local p_id="$1"
    [[ -z "$p_id" ]] && { print -Pn "  Profile ID to remove: "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1

    local exists
    exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }

    print -Pn "  ${_TV_RED}Remove${_TV_RST} profile ${_TV_WHT}[$p_id]${_TV_RST}? This cannot be undone. (y/N): "
    read _confirm
    [[ "$_confirm" =~ ^[Yy]$ ]] || { _tv_print "  ${_TV_GRY}Cancelled${_TV_RST}"; return 0; }

    local v
    v=$(_tv_crypto dec)
    _tv_crypto enc "$(echo "$v" | jq --arg p "$p_id" 'del(.[$p])')"
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" 'del(.[$p])' "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }
    _tv_print "  ${_TV_YEL}✓ Profile ${_TV_WHT}[$p_id]${_TV_RST}${_TV_YEL} removed${_TV_RST}"
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
    _tv_banner "Help"
    _tv_print "  ${_TV_WHT}Vault${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-unlock${_TV_RST}                        Unlock vault"
    _tv_print "  ${_TV_CYA}tv-lock${_TV_RST}                          Lock vault"
    _tv_print "  ${_TV_CYA}tv-unsafe${_TV_RST}                        Toggle persist-key-to-disk\n"
    _tv_print "  ${_TV_WHT}Profiles${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-add${_TV_RST}                           Interactive add"
    _tv_print "  ${_TV_CYA}tv-add${_TV_RST} ${_TV_GRY}-ID x -Prov p -Auth a -Base u -Key k${_TV_RST}  CLI add"
    _tv_print "  ${_TV_CYA}tv-remove${_TV_RST} ${_TV_GRY}[-ID id]${_TV_RST}              Remove profile"
    _tv_print "  ${_TV_CYA}tv-list${_TV_RST}                          List all profiles"
    _tv_print "  ${_TV_CYA}tv-dash${_TV_RST}                          Dashboard + pool totals\n"
    _tv_print "  ${_TV_WHT}Run${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-run auto${_TV_RST} ${_TV_GRY}<cmd>${_TV_RST}               Best key per provider, inject all"
    _tv_print "  ${_TV_CYA}tv-run${_TV_RST} ${_TV_GRY}<id> <cmd>${_TV_RST}               Named profile"
    _tv_print "  ${_TV_CYA}tv-report${_TV_RST} ${_TV_GRY}[-ID id]${_TV_RST}              Mark exhausted after 429\n"
    _tv_print "  ${_TV_WHT}Models${_TV_RST}"
    _tv_print "  ${_TV_CYA}tv-model-list${_TV_RST}                    Interactive — show config + fetch live list"
    _tv_print "  ${_TV_CYA}tv-model-list${_TV_RST} ${_TV_GRY}-Prov p${_TV_RST}           Fetch by provider"
    _tv_print "  ${_TV_CYA}tv-model-list${_TV_RST} ${_TV_GRY}-Profile id${_TV_RST}        Fetch by profile"
    _tv_print "  ${_TV_CYA}tv-model-set${_TV_RST}                     Interactive — provider or profile level"
    _tv_print "  ${_TV_CYA}tv-model-set${_TV_RST} ${_TV_GRY}-Prov p -Tier t -Model m${_TV_RST}  Provider-level"
    _tv_print "  ${_TV_CYA}tv-model-set${_TV_RST} ${_TV_GRY}-Profile id -Model m${_TV_RST}       Profile-level override"
    _tv_print "  ${_TV_CYA}tv-codex-sync${_TV_RST} ${_TV_GRY}[-Config path] [-AllowWireApi] [-Force] [-DryRun] [-Yes]${_TV_RST}  Mirror Codex model/provider config"
    echo ""
}
