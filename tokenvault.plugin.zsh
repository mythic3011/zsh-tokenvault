# =============================================================================
# 💎 TokenVault v7.0: Local API Gateway Edition
# ==============================================================================

if [[ -z "${ZSH_VERSION:-}" ]]; then
    return 0
fi

typeset -g TV_PLUGIN_DIR="${TV_PLUGIN_DIR:-${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/tokenvault}"
typeset -g TV_PLUGIN_PATH="${TV_PLUGIN_PATH:-$TV_PLUGIN_DIR/tokenvault.plugin.zsh}"
typeset -g TV_PLUGIN_LIB_DIR="${TV_PLUGIN_LIB_DIR:-$TV_PLUGIN_DIR/lib}"
typeset -g TV_PLUGIN_COMMANDS_DIR="${TV_PLUGIN_COMMANDS_DIR:-$TV_PLUGIN_DIR/commands}"

[[ -f "$TV_PLUGIN_LIB_DIR/core.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/core.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/ui.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/ui.zsh"
[[ -f "$TV_PLUGIN_COMMANDS_DIR/key-helpers.zsh" ]] && source "$TV_PLUGIN_COMMANDS_DIR/key-helpers.zsh"

if typeset -f tv_core_open &>/dev/null; then
    tv_core_open
fi
if typeset -f tv_ui_open &>/dev/null; then
    tv_ui_open
fi
if typeset -f tv_key_helpers_open &>/dev/null; then
    tv_key_helpers_open
fi

# --- ENV UNSET LISTS  ---
_TV_UNSET_anthropic=(
    ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    ANTHROPIC_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
    ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL
    CLAUDE_CODE_SUBAGENT_MODEL
)
_TV_UNSET_openai=(
    OPENAI_API_KEY OPENAI_BASE_URL OPENAI_API_BASE OPENAI_DEFAULT_MODEL
)
_TV_UNSET_gemini=(
    GEMINI_API_KEY GEMINI_DEFAULT_MODEL GOOGLE_API_KEY
)

# --- INIT ---
_tv_init() {
    [[ ! -d "$TV_DIR" ]]       && mkdir -p "$TV_DIR"       && chmod 700 "$TV_DIR"
    [[ ! -d "$TV_CACHE_DIR" ]] && mkdir -p "$TV_CACHE_DIR" && chmod 700 "$TV_CACHE_DIR"
    [[ ! -f "$TV_PROFILES" ]]  && echo "{}" > "$TV_PROFILES"
    [[ ! -f "$TV_MODELS" ]]    && echo "{}" > "$TV_MODELS"
    [[ ! -f "$TV_USAGE_LOG" ]] && touch "$TV_USAGE_LOG"
    rm -rf "$TV_WORKER_LOCK" 2>/dev/null
    if [[ -f "$TV_UNSAFE_FILE" ]]; then
        _TV_MASTER_KEY=$(cat "$TV_UNSAFE_FILE" 2>/dev/null)
        _TV_IS_UNSAFE=1
    fi
}
_tv_init

# --- HELPERS ---
_tv_print()  { print -P "$1"; }
_tv_banner() {
    _tv_print "\n${_TV_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_TV_RST}"
    _tv_print " 💎 ${_TV_WHT}TokenVault${_TV_RST}  ${_TV_GRY}$1${_TV_RST}"
    _tv_print "${_TV_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_TV_RST}\n"
}

_tv_fmt_num() {
    local n=$(echo "${1:-0}" | sed 's/[^0-9]//g'); n=${n:-0}
    if   (( n > 999999 )); then printf "%.1fM" $(echo "$n / 1000000" | bc -l)
    elif (( n > 999    )); then printf "%.1fk" $(echo "$n / 1000"    | bc -l)
    else echo "$n"; fi
}

# Atomic write helper — temp file in same dir to ensure same-fs mv
_tv_write_json() {
    local file="$1" content="$2"
    local dir; dir=$(dirname "$file")
    local tmp
    tmp=$(_tv_mktemp "$dir/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    echo "$content" > "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

_tv_mktemp() {
    local tmpl="$1"
    local old_umask
    old_umask=$(umask)
    umask 077
    local tmp
    tmp=$(mktemp "$tmpl")
    local rc=$?
    umask "$old_umask"
    (( rc != 0 )) && return $rc
    printf '%s' "$tmp"
}

_tv_read_codex_config() {
    local config_path="$1"
    python3 - <<'PY' "$config_path"
import json
import pathlib
import sys

args = sys.argv[1:]
if not args:
    print(json.dumps({"ok": False, "error": "missing_path"}))
    sys.exit(0)

path = pathlib.Path(args[0])
if not path.exists():
    print(json.dumps({"ok": False, "error": "file_not_found", "config_path": str(path)}))
    sys.exit(0)

try:
    raw = path.read_text()
except Exception as exc:
    print(json.dumps({"ok": False, "error": "read_error", "message": str(exc)}))
    sys.exit(0)

try:
    import tomllib
except ModuleNotFoundError:
    print(json.dumps({"ok": False, "error": "missing_tomllib"}))
    sys.exit(0)

try:
    config = tomllib.loads(raw)
except Exception as exc:
    print(json.dumps({"ok": False, "error": "parse_error", "message": str(exc)}))
    sys.exit(0)

global_model = config.get("model", "")
global_provider = config.get("model_provider", "")
providers = []
for name, info in config.get("model_providers", {}).items():
    providers.append({
        "name": name,
        "base_url": info.get("base_url", ""),
        "wire_api": info.get("wire_api", ""),
        "requires_openai_auth": bool(info.get("requires_openai_auth", False)),
        "default_model": info.get("model", ""),
    })

for provider in providers:
    if not provider["default_model"] and provider["name"] == global_provider and global_model:
        provider["default_model"] = global_model

output = {
    "ok": True,
    "global": {"model_provider": global_provider, "model": global_model},
    "providers": providers,
}
print(json.dumps(output))
PY
}

# Input validation — profile IDs must be alphanumeric + _ -
_tv_validate_id() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] && return 0
    _tv_print "  ${_TV_RED}✗ Invalid ID '${1}' — use letters, numbers, _ or -${_TV_RST}"
    return 1
}

# _tv_ask <varname> <prompt> [default] [secret]
# If varname already set (non-empty), skip prompt and use existing value.
# Sets the variable in the caller's scope via printf/read pattern.
_tv_ask() {
	local _var="$1" _prompt="$2" _default="${3:-}" _secret="${4:-}"
	# already provided (e.g. via CLI arg) — skip
	[[ -n "${(P)_var}" ]] && return 0
	local _val
	if [[ -n "$_default" ]]; then
	    print -Pn "  ${_prompt} [${_TV_GRY}${_default}${_TV_RST}]: "
	else
	    print -Pn "  ${_prompt}: "
	fi
    if [[ "$_secret" == "1" ]]; then
        read -rs _val; echo ""
    else
        read _val
    fi
    [[ -z "$_val" && -n "$_default" ]] && _val="$_default"
    eval "${_var}=\$_val"
}

# _tv_menu <varname> <title> <default_index> item1 desc1 item2 desc2 ...
# Shows numbered menu, sets varname to chosen item value.
# If varname already set, skip menu.
_tv_menu() {
    local _var="$1" _title="$2" _def="$3"; shift 3
    [[ -n "${(P)_var}" ]] && return 0
    _tv_print "\n  ${_title}:"
    local -a _vals _descs
    local i=1
    while [[ $# -ge 2 ]]; do
        _vals+=("$1"); _descs+=("$2")
        _tv_print "  ${_TV_GRY}${i})${_TV_RST} ${_vals[$i]}  ${_TV_GRY}${_descs[$i]}${_TV_RST}"
        (( i++ )); shift 2
    done
    printf "\n  Choice [${_def}]: "; read _c
    local _idx="${_c:-$_def}"
    eval "${_var}=\${_vals[${_idx}]:-\${_vals[${_def}]}}"
}

# _tv_pick_model <varname> <prov> <base_url> <key>
# Shows model list from API (or prompts manually). Sets varname to chosen model.
# If varname already set, skip.
_tv_pick_model() {
    local _var="$1" _prov="$2" _base="$3" _key="$4"
    [[ -n "${(P)_var}" ]] && return 0
    _tv_print "\n  ${_TV_GRY}Fetching model list...${_TV_RST}"
    local _list=$(_tv_fetch_models "$_prov" "$_base" "$_key")
    if [[ -n "$_list" ]]; then
        _tv_print "  ${_TV_GRN}✓ Got model list${_TV_RST}\n"
        local -a _mlist; local i=1
        while IFS= read -r m; do
            _tv_print "  ${_TV_GRY}${i})${_TV_RST} $m"
            _mlist+=("$m"); (( i++ ))
        done <<< "$_list"
        _tv_print "  ${_TV_GRY}0)${_TV_RST} Skip"
        printf "\n  Default model [0]: "; read _c
        if [[ "${_c:-0}" != "0" && -n "${_mlist[${_c}]}" ]]; then
            eval "${_var}=\${_mlist[${_c}]}"
        fi
    else
        _tv_print "  ${_TV_YEL}⚠ Could not fetch — enter manually${_TV_RST}"
        printf "  Model ID (blank to skip): "; read _m
        [[ -n "$_m" ]] && eval "${_var}=\$_m"
    fi
}

# --- CRYPTO ---
# Key passed via stdin fd to avoid exposure in process listing (ps aux)
_tv_crypto() {
    local mode="$1"; shift
    [[ -z "$_TV_MASTER_KEY" ]] && return 1
    if [[ "$mode" == "enc" ]]; then
        local tmp
        tmp=$(_tv_mktemp "$TV_DIR/.vault_tmp.XXXXXX") || return 1
        chmod 600 "$tmp"
        echo "$1" | openssl enc -aes-256-cbc -a -pbkdf2 -salt \
            -pass fd:3 3< <(printf '%s' "$_TV_MASTER_KEY") > "$tmp" 2>/dev/null \
            && mv -f "$tmp" "$TV_VAULT" || { rm -f "$tmp"; return 1; }
        chmod 600 "$TV_VAULT"
    else
        [[ ! -f "$TV_VAULT" ]] && { echo "{}"; return 0; }
        openssl enc -aes-256-cbc -d -a -pbkdf2 \
            -pass fd:3 3< <(printf '%s' "$_TV_MASTER_KEY") \
            -in "$TV_VAULT" 2>/dev/null
    fi
}

# --- AUTH ---
tv-unlock() {
    read -rs "?🔑 Master Password: " pass; echo ""
    _TV_MASTER_KEY="$pass"
    _tv_crypto dec &>/dev/null || {
        _TV_MASTER_KEY=""
        _tv_print "  ${_TV_RED}✗ Wrong password${_TV_RST}"
        return 1
    }
    _tv_print "  ${_TV_GRN}✓ Vault unlocked${_TV_RST}"
    _tv_spawn_worker
}

tv-lock() {
    _TV_MASTER_KEY=""; _TV_IS_UNSAFE=0
    rm -f "$TV_UNSAFE_FILE" "$TV_PROMPT_CACHE"
    _tv_print "  ${_TV_GRY}🔒 Vault locked${_TV_RST}"
    _tv_spawn_worker
}

tv-unsafe() {
    if [[ "$_TV_IS_UNSAFE" == "1" ]]; then
        tv-lock
    else
        _tv_print "  ${_TV_RED}⚠  UNSAFE MODE — master key will be saved to disk${_TV_RST}"
        read "?  Confirm? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 1
        [[ -z "$_TV_MASTER_KEY" ]] && tv-unlock
        echo "$_TV_MASTER_KEY" > "$TV_UNSAFE_FILE" && chmod 600 "$TV_UNSAFE_FILE"
        _TV_IS_UNSAFE=1
        _tv_spawn_worker
    fi
}

# --- ASYNC WORKER ---
_tv_spawn_worker() {
    (
        mkdir "$TV_WORKER_LOCK" 2>/dev/null || exit 0
        trap 'rm -rf "$TV_WORKER_LOCK" 2>/dev/null' EXIT

        local RST="%f%k%b" RED="%F{196}" GRN="%F{46}" YEL="%F{226}"
        local GRY="%F{240}" CYA="%F{51}" BLU="%F{39}" WHT="%F{255}"

        if [[ -z "$_TV_MASTER_KEY" ]]; then
            echo "\n🔒 ${GRY}Vault Locked${RST}" > "$TV_PROMPT_CACHE"; exit 0
        fi

        local profiles=$(cat "$TV_PROFILES" 2>/dev/null)
        local vault_json=$(_tv_crypto dec)
        local updated="$profiles"
        local pool_rem=0
        local active_provs=""
        # per-provider best key tracking: prov -> {rem, short, st}
        local best_json="{}"

        if [[ -n "$profiles" && "$profiles" != "{}" && -n "$vault_json" ]]; then
            for p in $(echo "$profiles" | jq -r 'keys[]'); do
                local row=$(echo "$profiles" | jq -c --arg p "$p" '.[$p]')
                local raw_key=$(echo "$vault_json" | jq -r --arg p "$p" '.[$p] // empty')
                local quota_api=$(echo "$row" | jq -r '.quota_api // empty')
                local reset_type=$(echo "$row" | jq -r '.reset_type // "daily"')
                local cur_status=$(echo "$row" | jq -r '.status // "active"')
                local prov=$(echo "$row" | jq -r '.provider // "custom"')

                # official cli profiles — always active, no quota check
                if [[ "$reset_type" == "official" ]]; then
                    updated=$(echo "$updated" | jq \
                        --arg p "$p" \
                        '.[$p].status = "active"')
                    continue
                fi

                [[ -z "$raw_key" ]] && continue

                local st="active" rem=0 reset_at=""

                if [[ -n "$quota_api" ]]; then
                    local resp=$(curl -s -L -m 2 --connect-timeout 2 -G "$quota_api" \
                        --data-urlencode "token_key=$raw_key" -d "page=1" -d "page_size=1")
                    if echo "$resp" | jq -e '.data.token_info' &>/dev/null; then
                        st=$(echo "$resp" | jq -r '.data.token_info.status.type // "active"')
                        rem=$(echo "$resp" | jq -r '.data.token_info.remain_quota_display // 0' | sed 's/[^0-9]//g')
                        reset_at=$(echo "$resp" | jq -r '.data.token_info.reset_at // empty')
                    else
                        st="DEAD"; rem=0
                    fi
                fi

                rem=${rem:-0}

                # lifecycle rules
                if [[ "$st" != "active" ]]; then
                    [[ "$reset_type" == "payg" ]] && st="disabled" || st="exhausted"
                elif [[ "$cur_status" == "exhausted" && "$st" == "active" ]]; then
                    st="active"  # quota restored
                fi

                updated=$(echo "$updated" | jq \
                    --arg p "$p" --arg st "$st" --argjson r "${rem%%.*}" \
                    --arg ra "${reset_at:-}" \
                    '.[$p].status=$st | .[$p].remain=$r | .[$p].last_checked=(now|todate) |
                     if $ra != "" then .[$p].reset_at=$ra else . end')

                # track best per provider
                if [[ "$st" == "active" ]]; then
                    local cur_best_rem=$(echo "$best_json" | jq -r --arg pv "$prov" '.[$pv].rem // -1')
                    if (( rem > cur_best_rem )); then
                        local short=$(echo "$row" | jq -r '.short // ""')
                        best_json=$(echo "$best_json" | jq \
                            --arg pv "$prov" --arg sh "$short" --argjson r "${rem%%.*}" \
                            '.[$pv] = {rem:$r, short:$sh}')
                    fi
                    pool_rem=$(( pool_rem + ${rem%%.*} ))
                    active_provs+="${prov[0:1]:u} "
                fi
            done
        fi

        _tv_write_json "$TV_PROFILES" "$updated"

        # render prompt line
        local out="\n"
        [[ "$_TV_IS_UNSAFE" == "1" ]] && out+="%K{196}%F{255} ⚠ UNSAFE %k%f "

        local n_active=$(echo "$best_json" | jq 'keys | length')
        if (( n_active == 0 )); then
            out+="💀 ${RED}No active keys${RST}"
        else
            # show best key short + pool total
            local top_prov=$(echo "$best_json" | jq -r 'to_entries | sort_by(-.value.rem) | .[0].key')
            local top_rem=$(echo "$best_json" | jq -r --arg p "$top_prov" '.[$p].rem')
            local top_short=$(echo "$best_json" | jq -r --arg p "$top_prov" '.[$p].short')
            local k_col=$GRN
            (( top_rem < 1000 )) && k_col=$YEL
            (( top_rem == 0  )) && k_col=$RED
            out+="🛡️  ${k_col}${top_short}${RST} ${GRY}::${RST} ${k_col}$(_tv_fmt_num $top_rem)${RST}"
            out+=" ${GRY}|${RST} 💎 ${CYA}$(_tv_fmt_num $pool_rem)${RST}"
            [[ -n "$active_provs" ]] && out+=" ${GRY}[${active_provs% }]${RST}"
        fi

        echo -e "$out" > "$TV_PROMPT_CACHE"
    ) &!
}

# --- UI RENDERER ---
tv_render() {
    local now=$(date +%s)
    (( now == _TV_LAST_RENDER_TIME )) && return
    _TV_LAST_RENDER_TIME=$now
    local mtime=$(stat -f %m "$TV_PROMPT_CACHE" 2>/dev/null || \
                  stat -c %Y "$TV_PROMPT_CACHE" 2>/dev/null || echo 0)
    local midnight=$(date -v0H -v0M -v1S +%s 2>/dev/null || \
                     date -d "00:00:01" +%s 2>/dev/null || echo 0)
    if [[ ! -f "$TV_PROMPT_CACHE" || \
          $(( now - mtime )) -gt 180 || \
          ( $now -ge $midnight && $mtime -lt $midnight ) ]]; then
        _tv_spawn_worker
    fi
    [[ -f "$TV_PROMPT_CACHE" ]] && print -P "$(cat "$TV_PROMPT_CACHE")"
}

# --- MODEL FETCH HELPER ---
_tv_fetch_models() {
    local prov="$1" base_url="$2" key="$3"
    local url models

    case "$prov" in
        anthropic) url="${base_url:-https://api.anthropic.com}/v1/models" ;;
        openai)    url="${base_url:-https://api.openai.com}/v1/models" ;;
        gemini)    url="https://generativelanguage.googleapis.com/v1/models" ;;
        *)         url="${base_url}/v1/models" ;;
    esac

    [[ -z "$url" || "$url" == "/v1/models" ]] && return 1

    local resp
    if [[ "$prov" == "anthropic" ]]; then
        resp=$(curl -s -m 5 "$url" \
            -H "x-api-key: $key" \
            -H "anthropic-version: 2023-06-01" 2>/dev/null)
    elif [[ "$prov" == "gemini" ]]; then
        resp=$(curl -s -m 5 "${url}?key=$key" 2>/dev/null)
    else
        resp=$(curl -s -m 5 "$url" \
            -H "Authorization: Bearer $key" 2>/dev/null)
    fi

    # try OpenAI format first (.data[].id), then Gemini (.models[].name)
    models=$(echo "$resp" | jq -r '.data[]?.id // .models[]?.name // empty' 2>/dev/null)
    [[ -z "$models" ]] && return 1
    echo "$models"
}

# --- TV-ADD ---
# CLI: tv-add [-ID id] [-Prov anthropic|openai|gemini|custom] [-Auth cli|key]
#             [-Base url] [-QuotaAPI url] [-Reset daily|payg] [-Key apikey]
#             [-Model model-id]
tv-add() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }

    # parse CLI args
    local p_id="" prov="" auth_mode="" reset_type="" base_url="" quota_api="" k="" default_model=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ID)       p_id="$2";        shift 2 ;;
            -Prov)     prov="$2";        shift 2 ;;
            -Auth)     auth_mode="$2";   shift 2 ;;
            -Base)     base_url="$2";    shift 2 ;;
            -QuotaAPI) quota_api="$2";   shift 2 ;;
            -Reset)    reset_type="$2";  shift 2 ;;
            -Key)      k="$2";           shift 2 ;;
            -Model)    default_model="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    _tv_banner "Add Profile"

    # 1. Profile ID
    _tv_ask p_id "Profile ID"
    [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ Required${_TV_RST}"; return 1; }
    _tv_validate_id "$p_id" || return 1

    # 2. Provider
    _tv_menu prov "Provider" 1 \
        "anthropic" "(Anthropic / Claude)" \
        "openai"    "(OpenAI / Codex)" \
        "gemini"    "(Google Gemini)" \
        "custom"    "(any other provider)"

    # 3. Auth mode
    if [[ "$prov" != "custom" && -z "$auth_mode" ]]; then
        _tv_menu auth_mode "Auth mode" 1 \
            "cli" "(provider's own login — no key stored)" \
            "key" "(inject API key via env vars)"
        reset_type="official"
    else
        auth_mode="${auth_mode:-key}"
        [[ "$prov" == "custom" && -z "$reset_type" ]] && reset_type=""
    fi

    # 4. Base URL + Quota API + Reset type (key mode only)
    if [[ "$auth_mode" == "key" ]]; then
        _tv_ask base_url "Proxy / Base URL (blank = official endpoint)"

        if [[ "$prov" == "custom" || -n "$base_url" ]]; then
            _tv_ask quota_api "Quota check API URL" "$TV_QUOTA_API_URL"
            _tv_menu reset_type "Reset type" 1 \
                "daily" "(auto re-enable after quota resets)" \
                "payg"  "(disable permanently when exhausted)"
        fi
    fi

    # 5. Env var defaults per provider
    local env_key env_token env_base env_model
    case "$prov" in
        anthropic) env_key="ANTHROPIC_API_KEY"; env_token="ANTHROPIC_AUTH_TOKEN"; env_base="ANTHROPIC_BASE_URL"; env_model="ANTHROPIC_MODEL" ;;
        openai)    env_key="OPENAI_API_KEY";    env_token="";                      env_base="OPENAI_BASE_URL";    env_model="OPENAI_DEFAULT_MODEL" ;;
        gemini)    env_key="GEMINI_API_KEY";    env_token="";                      env_base="";                   env_model="GEMINI_DEFAULT_MODEL" ;;
        *)         env_key="CUSTOM_API_KEY";    env_token="";                      env_base="CUSTOM_BASE_URL";    env_model="CUSTOM_DEFAULT_MODEL" ;;
    esac
    _tv_print "\n  ${_TV_GRY}Env var names (Enter = keep default)${_TV_RST}"
    _tv_ask env_key   "Key env"   "$env_key"
    _tv_ask env_base  "Base env"  "$env_base"
    _tv_ask env_model "Model env" "$env_model"

    # 6. API Key
    if [[ "$auth_mode" == "key" && -z "$k" ]]; then
        printf "\n  API Key: "; read -rs k; echo ""
        k=${k//[[:space:]]/}
        [[ -z "$k" ]] && { _tv_print "  ${_TV_RED}✗ Key required${_TV_RST}"; return 1; }
    fi

    # 7. Model selection (shared helper)
    [[ "$auth_mode" == "key" && -n "$k" ]] && _tv_pick_model default_model "$prov" "$base_url" "$k"

    # 8. Save
    local v=$(_tv_crypto dec)
    _tv_crypto enc "$(echo "$v" | jq --arg p "$p_id" --arg k "$k" \
        '.[$p] = (if $k != "" then $k else .[$p] end)')"

    local short="${k:+${k[0:5]}..${k[-4:]}}"
    local env_map=$(jq -n \
        --arg ek "$env_key" --arg et "$env_token" \
        --arg eb "$env_base" --arg em "$env_model" \
        '{key:$ek, token:$et, base:$eb, model:$em}')
    local new_profile=$(jq -n \
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

# --- TV-RUN ---
tv-run() {
    [[ $# -lt 2 ]] && { _tv_print "  ${_TV_GRY}Usage: tv-run <id|auto> <cmd...>${_TV_RST}"; return 1; }
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }

    local target="$1"; shift
    # validate named profile IDs (not "auto")
    [[ "$target" != "auto" ]] && { _tv_validate_id "$target" || return 1; }
    local vault=$(_tv_crypto dec)
    local profiles=$(cat "$TV_PROFILES" 2>/dev/null)
    local models_cfg=$(cat "$TV_MODELS" 2>/dev/null || echo "{}")

    # --- Step 1: resolve target ---
    if [[ "$target" == "auto" ]]; then
        # bucket: per provider, pick active key with highest remain
        # returns JSON: {prov: {id, key, base_url, env_map, default_model, remain}}
        local buckets="{}"
        for p in $(echo "$profiles" | jq -r 'keys[]'); do
            local row=$(echo "$profiles" | jq -c --arg p "$p" '.[$p]')
            local st=$(echo "$row" | jq -r '.status // "active"')
            local rt=$(echo "$row" | jq -r '.reset_type // "daily"')
            local prov=$(echo "$row" | jq -r '.provider')
            [[ "$rt" == "official" ]] && continue
            [[ "$st" != "active" ]] && continue
            local rem=$(echo "$row" | jq -r '.remain // 0')
            local cur_rem=$(echo "$buckets" | jq -r --arg pv "$prov" '.[$pv].remain // -1')
            if (( rem > cur_rem )); then
                local raw_key=$(echo "$vault" | jq -r --arg p "$p" '.[$p] // empty')
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

        local n_buckets=$(echo "$buckets" | jq 'keys | length')

        # Step 2: unset all known provider envs (clear .zshrc residue)
        for prov in $(echo "$profiles" | jq -r '[.[].provider] | unique[]'); do
            local unset_var="_TV_UNSET_${prov}[@]"
            for v in "${(P)unset_var}"; do unset "$v"; done
        done
        # always unset common ones
        for v in "${_TV_UNSET_anthropic[@]}" "${_TV_UNSET_openai[@]}" "${_TV_UNSET_gemini[@]}"; do
            unset "$v"
        done

        if (( n_buckets == 0 )); then
            # no active custom keys — fall through to system session (official CLI)
            _tv_print "  ${_TV_YEL}⚠ No active custom keys — using system session${_TV_RST}"
        else
            # Step 3: inject per bucket
            for prov in $(echo "$buckets" | jq -r 'keys[]'); do
                local winner=$(echo "$buckets" | jq -c --arg pv "$prov" '.[$pv]')
                local winner_id=$(echo "$winner" | jq -r '.id')
                local winner_rem=$(echo "$winner" | jq -r '.remain')
                local k=$(echo "$winner" | jq -r '.key')
                _tv_print "  ${_TV_GRN}✓ ${prov}${_TV_RST}  ${_TV_GRY}→${_TV_RST} ${_TV_WHT}${winner_id}${_TV_RST}  ${_TV_GRY}($(_tv_fmt_num $winner_rem) remaining)${_TV_RST}"
                local bu=$(echo "$winner" | jq -r '.base_url // ""')
                local dm=$(echo "$winner" | jq -r '.default_model // ""')
                local em=$(echo "$winner" | jq -c '.env_map // {}')

                local env_key=$(echo "$em"   | jq -r '.key   // empty')
                local env_token=$(echo "$em" | jq -r '.token // empty')
                local env_base=$(echo "$em"  | jq -r '.base  // empty')
                local env_model=$(echo "$em" | jq -r '.model // empty')

                [[ -n "$env_key"   ]] && export "${env_key}=$k"
                [[ -n "$env_token" ]] && export "${env_token}=$k"
                [[ -n "$env_base" && -n "$bu" ]] && export "${env_base}=$bu"

                # model: profile override > models.json provider default
                local final_model="$dm"
                if [[ -z "$final_model" ]]; then
                    final_model=$(echo "$models_cfg" | jq -r --arg pv "$prov" '.[$pv].default // empty')
                fi
                [[ -n "$env_model" && -n "$final_model" ]] && export "${env_model}=$final_model"

                # anthropic-specific model aliases
                if [[ "$prov" == "anthropic" ]]; then
                    local haiku=$(echo "$models_cfg"  | jq -r '.anthropic.haiku   // empty')
                    local sonnet=$(echo "$models_cfg" | jq -r '.anthropic.sonnet  // empty')
                    local opus=$(echo "$models_cfg"   | jq -r '.anthropic.opus    // empty')
                    local subagent=$(echo "$models_cfg" | jq -r '.anthropic.subagent // empty')
                    [[ -n "$haiku"   ]] && export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
                    [[ -n "$sonnet"  ]] && export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
                    [[ -n "$opus"    ]] && export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
                    [[ -n "$subagent" ]] && export CLAUDE_CODE_SUBAGENT_MODEL="$subagent"
                fi
            done
        fi

        echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"mode\":\"auto\",\"cmd\":\"$1\"}" >> "$TV_USAGE_LOG"
        "$@"

    else
        # --- named profile mode ---
        local row=$(echo "$profiles" | jq -c --arg p "$target" '.[$p] // empty')
        [[ -z "$row" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $target${_TV_RST}"; return 1; }

        local auth_mode=$(echo "$row" | jq -r '.auth_mode // "key"')
        local prov=$(echo "$row" | jq -r '.provider')

        echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"profile\":\"$target\",\"provider\":\"$prov\",\"cmd\":\"$1\"}" >> "$TV_USAGE_LOG"

        if [[ "$auth_mode" == "cli" ]]; then
            "$@"
        else
            local k=$(echo "$vault" | jq -r --arg p "$target" '.[$p] // empty')
            [[ -z "$k" ]] && { _tv_print "  ${_TV_RED}✗ No key stored for: $target${_TV_RST}"; return 1; }

            local bu=$(echo "$row" | jq -r '.base_url // ""')
            local dm=$(echo "$row" | jq -r '.default_model // ""')
            local em=$(echo "$row" | jq -c '.env_map // {}')
            local env_key=$(echo "$em"   | jq -r '.key   // empty')
            local env_token=$(echo "$em" | jq -r '.token // empty')
            local env_base=$(echo "$em"  | jq -r '.base  // empty')
            local env_model=$(echo "$em" | jq -r '.model // empty')

            # unset residue for this provider
            local unset_var="_TV_UNSET_${prov}[@]"
            for v in "${(P)unset_var}"; do unset "$v"; done

            [[ -n "$env_key"   ]] && local -x "${env_key}=$k"
            [[ -n "$env_token" ]] && local -x "${env_token}=$k"
            [[ -n "$env_base" && -n "$bu" ]] && local -x "${env_base}=$bu"

            local final_model="$dm"
            [[ -z "$final_model" ]] && \
                final_model=$(echo "$models_cfg" | jq -r --arg pv "$prov" '.[$pv].default // empty')
            [[ -n "$env_model" && -n "$final_model" ]] && local -x "${env_model}=$final_model"

            if [[ "$prov" == "anthropic" ]]; then
                local haiku=$(echo "$models_cfg"  | jq -r '.anthropic.haiku   // empty')
                local sonnet=$(echo "$models_cfg" | jq -r '.anthropic.sonnet  // empty')
                local opus=$(echo "$models_cfg"   | jq -r '.anthropic.opus    // empty')
                local subagent=$(echo "$models_cfg" | jq -r '.anthropic.subagent // empty')
                [[ -n "$haiku"    ]] && local -x ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
                [[ -n "$sonnet"   ]] && local -x ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
                [[ -n "$opus"     ]] && local -x ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
                [[ -n "$subagent" ]] && local -x CLAUDE_CODE_SUBAGENT_MODEL="$subagent"
            fi

            "$@"
        fi
    fi
}

# --- TV-REPORT (手動標記 429 / exhausted) ---
tv-report() {
    local p_id="$1"
    [[ -z "$p_id" ]] && { print -Pn "  Profile ID to report: "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1

    local exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }

    print -Pn "  Mark ${_TV_WHT}[$p_id]${_TV_RST} as exhausted? (y/N): "; read _confirm
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

# --- TV-REMOVE ---
tv-remove() {
    [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
    local p_id="$1"
    [[ -z "$p_id" ]] && { print -Pn "  Profile ID to remove: "; read p_id; }
    [[ -z "$p_id" ]] && return 1
    _tv_validate_id "$p_id" || return 1

    local exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
    [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }

    print -Pn "  ${_TV_RED}Remove${_TV_RST} profile ${_TV_WHT}[$p_id]${_TV_RST}? This cannot be undone. (y/N): "; read _confirm
    [[ "$_confirm" =~ ^[Yy]$ ]] || { _tv_print "  ${_TV_GRY}Cancelled${_TV_RST}"; return 0; }

    local v=$(_tv_crypto dec)
    _tv_crypto enc "$(echo "$v" | jq --arg p "$p_id" 'del(.[$p])')"
    local tmp
    tmp=$(_tv_mktemp "$TV_DIR/.json_tmp.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --arg p "$p_id" 'del(.[$p])' "$TV_PROFILES" > "$tmp" && mv -f "$tmp" "$TV_PROFILES" || { rm -f "$tmp"; return 1; }
    _tv_print "  ${_TV_YEL}✓ Profile ${_TV_WHT}[$p_id]${_TV_RST}${_TV_YEL} removed${_TV_RST}"
    _tv_spawn_worker
}

# --- TV-MODEL-SET ---
# Usage: tv-model-set <provider> <tier> <model-id>
# --- TV-MODEL-SET ---
# CLI: tv-model-set [-Prov p] [-Tier t] [-Model m]   → provider-level
#      tv-model-set [-Profile id] [-Model m]          → profile-level
# Interactive: tv-model-set (no args)
tv-model-set() {
    local prov="" tier="" model="" p_id="" scope=""

    # parse CLI args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -Prov)    prov="$2";    shift 2 ;;
            -Tier)    tier="$2";    shift 2 ;;
            -Model)   model="$2";   shift 2 ;;
            -Profile) p_id="$2";    shift 2 ;;
            *)        shift ;;
        esac
    done

    [[ -n "$p_id" ]] && { _tv_validate_id "$p_id" || return 1; }

    _tv_banner "Set Default Model"

    # 1. Scope: provider-level or profile-level
    _tv_menu scope "Apply to" 1 \
        "provider" "(set default for all keys of a provider)" \
        "profile"  "(override for one specific profile)"

    if [[ "$scope" == "provider" ]]; then
        # 2a. Pick provider
        _tv_menu prov "Provider" 1 \
            "anthropic" "" "openai" "" "gemini" "" "custom" ""

        # 2b. Pick tier (anthropic has named tiers; others just "default")
        if [[ "$prov" == "anthropic" ]]; then
            _tv_menu tier "Tier" 1 \
                "haiku"   "(fast / cheap)" \
                "sonnet"  "(balanced)" \
                "opus"    "(powerful)" \
                "subagent" "(Claude Code subagent)"
        else
            tier="default"
        fi

        # 2c. Pick model
        _tv_print "\n  ${_TV_GRY}Fetching model list for ${prov}...${_TV_RST}"
        local _vault_key=""
        if [[ -n "$_TV_MASTER_KEY" ]]; then
            local _pid=$(jq -r --arg pv "$prov" \
                'to_entries | map(select(.value.provider==$pv and .value.status=="active")) | .[0].key // empty' \
                "$TV_PROFILES")
            [[ -n "$_pid" ]] && _vault_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$_pid" '.[$p] // empty')
            local _base=$(jq -r --arg p "$_pid" '.[$p].base_url // ""' "$TV_PROFILES" 2>/dev/null)
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
        # 2a. Pick profile
        if [[ -z "$p_id" ]]; then
            _tv_print "\n  Profiles:"
            local i=1; local -a _pids
            jq -r 'keys[]' "$TV_PROFILES" | while IFS= read -r pid; do
                local st=$(jq -r --arg p "$pid" '.[$p].status' "$TV_PROFILES")
                _tv_print "  ${_TV_GRY}${i})${_TV_RST} $pid  ${_TV_GRY}($st)${_TV_RST}"
                _pids+=("$pid"); (( i++ ))
            done
            # rebuild array since subshell above doesn't export
            local -a _pids2
            while IFS= read -r pid; do _pids2+=("$pid"); done < <(jq -r 'keys[]' "$TV_PROFILES")
            printf "\n  Choice: "; read _c
            p_id="${_pids2[${_c}]}"
        fi
        [[ -z "$p_id" ]] && { _tv_print "  ${_TV_RED}✗ No profile selected${_TV_RST}"; return 1; }
        local exists=$(jq -r --arg p "$p_id" 'has($p)' "$TV_PROFILES")
        [[ "$exists" != "true" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }

        # 2b. Pick model
        local _row=$(jq -c --arg p "$p_id" '.[$p]' "$TV_PROFILES")
        local _prov=$(echo "$_row" | jq -r '.provider')
        local _base=$(echo "$_row" | jq -r '.base_url // ""')
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

# --- TV-MODEL-LIST ---
# CLI: tv-model-list [-Prov p | -Profile id]
# Interactive: tv-model-list (no args) → show current config, then offer to fetch
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

    # Show current models.json config first
    _tv_print "  ${_TV_WHT}Current provider defaults:${_TV_RST}"
    if [[ "$(cat "$TV_MODELS")" == "{}" ]]; then
        _tv_print "  ${_TV_GRY}(none configured)${_TV_RST}"
    else
        jq -r 'to_entries[] | "  \(.key): " + (.value | to_entries | map("\(.key)=\(.value)") | join("  "))' "$TV_MODELS" | \
        while IFS= read -r line; do _tv_print "  ${_TV_GRY}${line}${_TV_RST}"; done
    fi
    echo ""

    # Resolve target for live fetch
    if [[ -n "$p_id" ]]; then
        local row=$(jq -c --arg p "$p_id" '.[$p] // empty' "$TV_PROFILES")
        [[ -z "$row" ]] && { _tv_print "  ${_TV_RED}✗ Profile not found: $p_id${_TV_RST}"; return 1; }
        target_prov=$(echo "$row" | jq -r '.provider')
        target_base=$(echo "$row" | jq -r '.base_url // ""')
        [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
        target_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$p_id" '.[$p] // empty')

    elif [[ -n "$prov" ]]; then
        target_prov="$prov"
        [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
        local vault=$(_tv_crypto dec)
        local pid=$(jq -r --arg pv "$prov" \
            'to_entries | map(select(.value.provider==$pv and .value.status=="active")) | .[0].key // empty' \
            "$TV_PROFILES")
        [[ -z "$pid" ]] && { _tv_print "  ${_TV_RED}✗ No active profile for: $prov${_TV_RST}"; return 1; }
        target_base=$(jq -r --arg p "$pid" '.[$p].base_url // ""' "$TV_PROFILES")
        target_key=$(echo "$vault" | jq -r --arg p "$pid" '.[$p] // empty')

    else
        # interactive: ask which provider/profile to fetch
        _tv_menu _fetch_scope "Fetch live model list from" 1 \
            "provider" "(by provider name)" \
            "profile"  "(by profile ID)" \
            "skip"     "(just show config above)"
        if [[ "$_fetch_scope" == "skip" ]]; then return 0; fi

        if [[ "$_fetch_scope" == "provider" ]]; then
            _tv_menu target_prov "Provider" 1 \
                "anthropic" "" "openai" "" "gemini" "" "custom" ""
            [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
            local vault=$(_tv_crypto dec)
            local pid=$(jq -r --arg pv "$target_prov" \
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
                local st=$(jq -r --arg p "$pid" '.[$p].status' "$TV_PROFILES")
                _tv_print "  ${_TV_GRY}${i})${_TV_RST} $pid  ${_TV_GRY}($st)${_TV_RST}"
                _pids2+=("$pid"); (( i++ ))
            done < <(jq -r 'keys[]' "$TV_PROFILES")
            printf "\n  Choice: "; read _c
            local sel="${_pids2[${_c}]}"
            [[ -z "$sel" ]] && return 1
            local row=$(jq -c --arg p "$sel" '.[$p]' "$TV_PROFILES")
            target_prov=$(echo "$row" | jq -r '.provider')
            target_base=$(echo "$row" | jq -r '.base_url // ""')
            [[ -z "$_TV_MASTER_KEY" ]] && { _tv_print "  ${_TV_RED}✗ Run tv-unlock first${_TV_RST}"; return 1; }
            target_key=$(echo "$(_tv_crypto dec)" | jq -r --arg p "$sel" '.[$p] // empty')
        fi
    fi

    # Fetch + display
    _tv_print "  ${_TV_GRY}Fetching from ${target_prov}...${_TV_RST}"
    local model_list=$(_tv_fetch_models "$target_prov" "$target_base" "$target_key")
    if [[ -z "$model_list" ]]; then
        _tv_print "  ${_TV_RED}✗ Could not fetch model list${_TV_RST}"
        return 1
    fi
    _tv_print "  ${_TV_GRN}✓ Available models:${_TV_RST}\n"
    local i=1
    while IFS= read -r m; do
        _tv_print "  ${_TV_GRY}${i})${_TV_RST} $m"; (( i++ ))
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
        printf "  Proceed with sync? (y/N): "; read _confirm
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
            local global_provider
            local global_model
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

        (( ops++ ))

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

# --- TV-DASH ---
tv-dash() {
    _tv_banner "Dashboard"
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

    # show pool totals per provider
    _tv_print "  ${_TV_GRY}Pool totals:${_TV_RST}"
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
            "${col}$(_tv_fmt_num $rem)${_TV_RST}")
        _tv_print "$pool_line"
    done
    echo ""
}

# --- TV-LIST ---
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
        [[ "$am" == "key" && "$st" == "active" ]] && rem_str=" ${_TV_GRY}$(_tv_fmt_num $rem)${_TV_RST}"
        _tv_print "  ${col}●${_TV_RST} ${_TV_WHT}${id}${_TV_RST}  ${_TV_GRY}${prov}/${am}${_TV_RST}  ${short}${rem_str}"
    done
    echo ""
}

# --- TV-HELP ---
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

autoload -Uz add-zsh-hook
add-zsh-hook precmd tv_render
