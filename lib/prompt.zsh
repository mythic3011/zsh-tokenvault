# Guard against double sourcing
[[ -n "${TV_PROMPT_LOADED:-}" ]] && return 0
typeset -g TV_PROMPT_LOADED=1

_tv_spawn_worker() {
    mkdir "$TV_WORKER_LOCK" 2>/dev/null || return 0

    (
        trap 'rm -rf "$TV_WORKER_LOCK" 2>/dev/null' EXIT

        local RST="%f%k%b" RED="%F{196}" GRN="%F{46}" YEL="%F{226}"
        local GRY="%F{240}" CYA="%F{51}" BLU="%F{39}" WHT="%F{255}"

        if [[ -z "$_TV_MASTER_KEY" ]]; then
            echo "\n🔒 ${GRY}Vault Locked${RST}" > "$TV_PROMPT_CACHE"
            exit 0
        fi

        local profiles
        profiles=$(cat "$TV_PROFILES" 2>/dev/null)
        local vault_json
        vault_json=$(_tv_crypto dec)
        local updated="$profiles"
        local pool_rem=0
        local active_provs=""
        local best_json="{}"

        if [[ -n "$profiles" && "$profiles" != "{}" && -n "$vault_json" ]]; then
            for p in $(echo "$profiles" | jq -r 'keys[]'); do
                local row
                row=$(echo "$profiles" | jq -c --arg p "$p" '.[$p]')
                local raw_key
                raw_key=$(echo "$vault_json" | jq -r --arg p "$p" '.[$p] // empty')
                local quota_api
                quota_api=$(echo "$row" | jq -r '.quota_api // empty')
                local reset_type
                reset_type=$(echo "$row" | jq -r '.reset_type // "daily"')
                local cur_status
                cur_status=$(echo "$row" | jq -r '.status // "active"')
                local prov
                prov=$(echo "$row" | jq -r '.provider // "custom"')

                if [[ "$reset_type" == "official" ]]; then
                    updated=$(echo "$updated" | jq --arg p "$p" '.[$p].status = "active"')
                    continue
                fi

                [[ -z "$raw_key" ]] && continue

                local st="$cur_status" rem=0 reset_at=""

                if [[ -n "$quota_api" ]]; then
                    st="active"
                    local resp
                    resp=$(curl -s -L -m 2 --connect-timeout 2 -G "$quota_api" \
                        --data-urlencode "token_key=$raw_key" -d "page=1" -d "page_size=1")
                    if echo "$resp" | jq -e '.data.token_info' &>/dev/null; then
                        st=$(echo "$resp" | jq -r '.data.token_info.status.type // "active"')
                        rem=$(echo "$resp" | jq -r '.data.token_info.remain_quota_display // 0' | sed 's/[^0-9]//g')
                        reset_at=$(echo "$resp" | jq -r '.data.token_info.reset_at // empty')
                    else
                        st="DEAD"
                        rem=0
                    fi
                    rem=${rem:-0}

                    if [[ "$st" != "active" ]]; then
                        [[ "$reset_type" == "payg" ]] && st="disabled" || st="exhausted"
                    elif [[ "$cur_status" == "exhausted" && "$st" == "active" ]]; then
                        st="active"
                    fi
                fi

                updated=$(echo "$updated" | jq \
                    --arg p "$p" --arg st "$st" --argjson r "${rem%%.*}" \
                    --arg ra "${reset_at:-}" \
                    '.[$p].status=$st | .[$p].remain=$r | .[$p].last_checked=(now|todate) |
                     if $ra != "" then .[$p].reset_at=$ra else . end')

                if [[ "$st" == "active" ]]; then
                    local cur_best_rem
                    cur_best_rem=$(echo "$best_json" | jq -r --arg pv "$prov" '.[$pv].rem // -1')
                    if (( rem > cur_best_rem )); then
                        local short
                        short=$(echo "$row" | jq -r '.short // ""')
                        best_json=$(echo "$best_json" | jq \
                            --arg pv "$prov" --arg sh "$short" --argjson r "${rem%%.*}" \
                            '.[$pv] = {rem:$r, short:$sh}')
                    fi
                    pool_rem=$(( pool_rem + ${rem%%.*} ))
                    local prov_initial="${prov[1,1]}"
                    active_provs+="${(U)prov_initial} "
                fi
            done
        fi

        _tv_write_json "$TV_PROFILES" "$updated"

        local out="\n"
        [[ "$_TV_IS_UNSAFE" == "1" ]] && out+="%K{196}%F{255} ⚠ UNSAFE %k%f "

        local n_active
        n_active=$(echo "$best_json" | jq 'keys | length')
        if (( n_active == 0 )); then
            out+="💀 ${RED}No active keys${RST}"
        else
            local top_prov
            top_prov=$(echo "$best_json" | jq -r 'to_entries | sort_by(-.value.rem) | .[0].key')
            local top_rem
            top_rem=$(echo "$best_json" | jq -r --arg p "$top_prov" '.[$p].rem')
            local top_short
            top_short=$(echo "$best_json" | jq -r --arg p "$top_prov" '.[$p].short')
            local k_col=$GRN
            (( top_rem < 1000 )) && k_col=$YEL
            (( top_rem == 0  )) && k_col=$RED
            out+="🛡️  ${k_col}${top_short}${RST} ${GRY}::${RST} ${k_col}$(_tv_fmt_num "$top_rem")${RST}"
            out+=" ${GRY}|${RST} 💎 ${CYA}$(_tv_fmt_num "$pool_rem")${RST}"
            [[ -n "$active_provs" ]] && out+=" ${GRY}[${active_provs% }]${RST}"
        fi

        echo -e "$out" > "$TV_PROMPT_CACHE"
    ) &!
}

tv_render() {
    local now
    now=$(date +%s)
    (( now == _TV_LAST_RENDER_TIME )) && return
    _TV_LAST_RENDER_TIME=$now
    local mtime
    mtime=$(stat -f %m "$TV_PROMPT_CACHE" 2>/dev/null || \
            stat -c %Y "$TV_PROMPT_CACHE" 2>/dev/null || echo 0)
    local midnight
    midnight=$(date -v0H -v0M -v1S +%s 2>/dev/null || \
               date -d "00:00:01" +%s 2>/dev/null || echo 0)
    if [[ ! -f "$TV_PROMPT_CACHE" || \
          $(( now - mtime )) -gt 180 || \
          ( $now -ge $midnight && $mtime -lt $midnight ) ]]; then
        _tv_spawn_worker
    fi
    [[ -f "$TV_PROMPT_CACHE" ]] && print -P "$(cat "$TV_PROMPT_CACHE")"
}

tv_prompt_open() {
    [[ -n "${TV_PROMPT_OPENED:-}" ]] && return 0
    TV_PROMPT_OPENED=1
}

tv_prompt_close() {
    TV_PROMPT_OPENED=""
}
