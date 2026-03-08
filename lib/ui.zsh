# Guard against double sourcing
[[ -n "${TV_UI_LOADED:-}" ]] && return 0
typeset -g TV_UI_LOADED=1

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

# _tv_ask <varname> <prompt> [default] [secret]
# If varname already set (non-empty), skip prompt and use existing value.
_tv_ask() {
    local _var="$1" _prompt="$2" _default="${3:-}" _secret="${4:-}"
    [[ -n "${(P)_var}" ]] && return 0
    local _val
    if [[ -n "$_default" ]]; then
        print -Pn "  ${_prompt} [${_TV_GRY}${_default}${_TV_RST}]: "
    else
        print -Pn "  ${_prompt}: "
    fi
    if [[ "$_secret" == "1" ]]; then
        read -rs _val
        echo ""
    else
        read _val
    fi
    [[ -z "$_val" && -n "$_default" ]] && _val="$_default"
    eval "${_var}=\$_val"
}

# _tv_menu <varname> <title> <default_index> item1 desc1 item2 desc2 ...
_tv_menu() {
    local _var="$1" _title="$2" _def="$3"
    shift 3
    [[ -n "${(P)_var}" ]] && return 0
    _tv_print "\n  ${_title}:"
    local -a _vals _descs
    local i=1
    while [[ $# -ge 2 ]]; do
        _vals+=("$1")
        _descs+=("$2")
        _tv_print "  ${_TV_GRY}${i})${_TV_RST} ${_vals[$i]}  ${_TV_GRY}${_descs[$i]}${_TV_RST}"
        (( i++ ))
        shift 2
    done
    printf "\n  Choice [${_def}]: "
    read _c
    local _idx="${_c:-$_def}"
    eval "${_var}=\${_vals[${_idx}]:-\${_vals[${_def}]}}"
}

# _tv_pick_model <varname> <prov> <base_url> <key>
_tv_pick_model() {
    local _var="$1" _prov="$2" _base="$3" _key="$4"
    [[ -n "${(P)_var}" ]] && return 0
    _tv_print "\n  ${_TV_GRY}Fetching model list...${_TV_RST}"
    local _list
    _list=$(_tv_fetch_models "$_prov" "$_base" "$_key")
    if [[ -n "$_list" ]]; then
        _tv_print "  ${_TV_GRN}✓ Got model list${_TV_RST}\n"
        local -a _mlist
        local i=1
        while IFS= read -r m; do
            _tv_print "  ${_TV_GRY}${i})${_TV_RST} $m"
            _mlist+=("$m")
            (( i++ ))
        done <<< "$_list"
        _tv_print "  ${_TV_GRY}0)${_TV_RST} Skip"
        printf "\n  Default model [0]: "
        read _c
        if [[ "${_c:-0}" != "0" && -n "${_mlist[${_c}]}" ]]; then
            eval "${_var}=\${_mlist[${_c}]}"
        fi
    else
        _tv_print "  ${_TV_YEL}⚠ Could not fetch — enter manually${_TV_RST}"
        printf "  Model ID (blank to skip): "
        read _m
        [[ -n "$_m" ]] && eval "${_var}=\$_m"
    fi
}

tv_ui_open() {
    [[ -n "${TV_UI_OPENED:-}" ]] && return 0
    TV_UI_OPENED=1
}

tv_ui_close() {
    TV_UI_OPENED=""
}
