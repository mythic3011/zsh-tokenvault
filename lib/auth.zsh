# Guard against double sourcing
[[ -n "${TV_AUTH_LOADED:-}" ]] && return 0
typeset -g TV_AUTH_LOADED=1

tv-unlock() {
    read -rs "?🔑 Master Password: " pass
    echo ""
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
    _TV_MASTER_KEY=""
    _TV_IS_UNSAFE=0
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

tv_auth_open() {
    [[ -n "${TV_AUTH_OPENED:-}" ]] && return 0
    TV_AUTH_OPENED=1
}

tv_auth_close() {
    TV_AUTH_OPENED=""
}
