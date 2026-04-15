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
    tomllib = None


def parse_value(raw_value):
    value = raw_value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    return value


def parse_minimal_toml(raw_text):
    config = {}
    current = config

    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if "#" in line:
            line = line.split("#", 1)[0].rstrip()
            if not line:
                continue

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            if section.startswith("model_providers."):
                name = section.split(".", 1)[1]
                config.setdefault("model_providers", {})
                config["model_providers"].setdefault(name, {})
                current = config["model_providers"][name]
            else:
                config.setdefault(section, {})
                current = config[section]
            continue

        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        current[key.strip()] = parse_value(value)

    return config

try:
    if tomllib is not None:
        config = tomllib.loads(raw)
    else:
        config = parse_minimal_toml(raw)
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
    local _label
    _label=$(_tv_tr "$_prompt" "$_prompt")
    if [[ -n "$_default" ]]; then
        print -Pn "  ${_label} [${_TV_GRY}${_default}${_TV_RST}]: "
    else
        print -Pn "  ${_label}: "
    fi
    if [[ "$_secret" == "1" ]]; then
        read -rs _val
        echo ""
    else
        read _val
    fi
    [[ -z "$_val" && -n "$_default" ]] && _val="$_default"
    printf -v "$_var" '%s' "$_val"
}

# _tv_menu <varname> <title> <default_index> item1 desc1 item2 desc2 ...
_tv_menu() {
    local _var="$1" _title="$2" _def="$3"
    shift 3
    [[ -n "${(P)_var}" ]] && return 0
    local _label
    _label=$(_tv_tr "$_title" "$_title")
    _tv_print "\n  ${_label}:"
    local -a _vals _descs
    local i=1
    while [[ $# -ge 2 ]]; do
        _vals+=("$1")
        _descs+=("$2")
        local _desc
        _desc=$(_tv_tr "${_descs[$i]}" "${_descs[$i]}")
        _tv_print "  ${_TV_GRY}${i})${_TV_RST} ${_vals[$i]}  ${_TV_GRY}${_desc}${_TV_RST}"
        (( ++i ))
        shift 2
    done
    printf "\n  %s [%s]: " "$(_tv_tr "choice_prompt" "Choice")" "${_def}"
    read _c
    local _idx="${_c:-$_def}"
    _idx="${_idx//[^0-9]/}"
    [[ -z "$_idx" ]] && _idx="$_def"
    local _chosen="${_vals[${_idx}]:-${_vals[${_def}]}}"
    printf -v "$_var" '%s' "$_chosen"
}

# _tv_pick_model <varname> <prov> <base_url> <key>
_tv_pick_model() {
    local _var="$1" _prov="$2" _base="$3" _key="$4"
    [[ -n "${(P)_var}" ]] && return 0
    _tv_print "\n  ${_TV_GRY}$(_tv_tr "model_fetching" "Fetching model list...")${_TV_RST}"
    local _list
    _list=$(_tv_fetch_models "$_prov" "$_base" "$_key")
    if [[ -n "$_list" ]]; then
        _tv_print "  ${_TV_GRN}✓ $(_tv_tr "got_model_list" "Got model list")${_TV_RST}\n"
        local -a _mlist
        local i=1
        while IFS= read -r m; do
            _tv_print "  ${_TV_GRY}${i})${_TV_RST} $m"
            _mlist+=("$m")
            (( ++i ))
        done <<< "$_list"
        _tv_print "  ${_TV_GRY}0)${_TV_RST} $(_tv_tr "skip_option" "Skip")"
        printf "\n  %s [0]: " "$(_tv_tr "default_model_prompt" "Default model")"
        read _c
        local _cidx="${_c:-0}"
        _cidx="${_cidx//[^0-9]/}"
        if [[ "${_cidx:-0}" != "0" && -n "${_mlist[${_cidx}]}" ]]; then
            printf -v "$_var" '%s' "${_mlist[${_cidx}]}"
        fi
    else
        _tv_print "  ${_TV_YEL}⚠ $(_tv_tr "model_fetch_failed_manual" "Could not fetch — enter manually")${_TV_RST}"
        printf "  %s: " "$(_tv_tr "model_id_prompt" "Model ID (blank to skip)")"
        read _m
        [[ -n "$_m" ]] && printf -v "$_var" '%s' "$_m"
    fi
}

_tv_confirm() {
    local _prompt="$1"
    local _default="${2:-y/N}"
    local _response
    print -Pn "  $(_tv_tr "$_prompt" "$_prompt") (${_default}): "
    read _response
    [[ "$_response" =~ ^[Yy]$ ]]
}

tv_ui_open() {
    [[ -n "${TV_UI_OPENED:-}" ]] && return 0
    TV_UI_OPENED=1
}

tv_ui_close() {
    TV_UI_OPENED=""
}
