# Guard against double sourcing
[[ -n "${TV_MODELS_LIB_LOADED:-}" ]] && return 0
typeset -g TV_MODELS_LIB_LOADED=1

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

    models=$(echo "$resp" | jq -r '.data[]?.id // .models[]?.name // empty' 2>/dev/null)
    [[ -z "$models" ]] && return 1
    echo "$models"
}

tv_models_open() {
    [[ -n "${TV_MODELS_LIB_OPENED:-}" ]] && return 0
    TV_MODELS_LIB_OPENED=1
}

tv_models_close() {
    TV_MODELS_LIB_OPENED=""
}
