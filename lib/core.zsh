# Guard against double sourcing
[[ -n "${TV_CORE_LOADED:-}" ]] && return 0
typeset -g TV_CORE_LOADED=1

# --- HELPERS ---
_tv_print()  { print -P "$1"; }
_tv_banner() {
    _tv_print "\n${_TV_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_TV_RST}"
    _tv_print " 💎 ${_TV_WHT}TokenVault${_TV_RST}  ${_TV_GRY}$1${_TV_RST}"
    _tv_print "${_TV_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_TV_RST}\n"
}

_tv_fmt_num() {
    local n=$(echo "${1:-0}" | sed 's/[^0-9]//g'); n=${n:-0}
    if   (( n > 999999 )); then printf "%.1fM" $(( n * 10 / 10000000 )).$(( (n * 10 / 1000000) % 10 ))
    elif (( n > 999    )); then printf "%.1fk" $(( n * 10 / 10000 )).$(( (n * 10 / 1000) % 10 ))
    else echo "$n"; fi
}

_tv_short_key() {
    local key="$1"
    [[ -z "$key" ]] && { printf ''; return 0; }
    local len=${#key}
    if (( len <= 8 )); then
        printf '%s' "$key"
        return 0
    fi
    local prefix="${key:0:5}"
    local suffix="${key: -4}"
    printf '%s..%s' "$prefix" "$suffix"
}

_tv_prompt_exit() {
    local status="$1" msg="${2:-Cancelled}"
    (( status == 2 )) && { _tv_print "  ${_TV_GRY}${msg}${_TV_RST}"; return 0; }
    return 1
}

_tv_verify_sha256() {
    local file="$1" expected="$2"
    [[ -z "$expected" ]] && return 0
    local actual
    if command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        actual=$(openssl dgst -sha256 "$file" 2>/dev/null | awk '{print $NF}')
    else
        return 2
    fi
    [[ "$actual" == "$expected" ]]
}

_tv_coerce_int() {
    local val="${1:-0}"
    val="${val//[^0-9-]/}"
    [[ -z "$val" || "$val" == "-" ]] && val="0"
    printf '%s' "$val"
}

_tv_validate_id() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] && return 0
    _tv_print "  ${_TV_RED}✗ Invalid ID '${1}' — use letters, numbers, _ or -${_TV_RST}"
    return 1
}

_tv_write_json() {
    local file="$1" content="$2"
    local dir="${file:h}"
    local tmp
    tmp=$(_tv_mktemp "$dir/.json_tmp.XXXXXX") || return 1
    /bin/chmod 600 "$tmp"
    echo "$content" > "$tmp" && /bin/mv -f "$tmp" "$file" || { /bin/rm -f "$tmp"; return 1; }
}

_tv_mktemp() {
    local tmpl="$1"
    local old_umask
    old_umask=$(umask)
    umask 077
    local tmp
    tmp=$(/usr/bin/mktemp "$tmpl")
    local rc=$?
    umask "$old_umask"
    (( rc != 0 )) && return $rc
    printf '%s' "$tmp"
}

_tv_jq() {
    local jq_bin="${TV_JQ_BIN:-${commands[jq]:-/usr/bin/jq}}"
    "$jq_bin" "$@"
}

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

tv_core_open() {
    [[ -n "${TV_CORE_OPENED:-}" ]] && return 0
    _tv_init
    TV_CORE_OPENED=1
}

tv_core_close() {
    TV_CORE_OPENED=""
}
