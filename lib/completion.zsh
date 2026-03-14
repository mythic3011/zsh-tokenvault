# Guard against double sourcing
[[ -n "${TV_COMPLETION_LOADED:-}" ]] && return 0
typeset -g TV_COMPLETION_LOADED=1

# Completion helper: get profile IDs from vault
_tv_get_profiles() {
    [[ -f "$TV_PROFILES" ]] && jq -r 'keys[]' "$TV_PROFILES" 2>/dev/null || true
}

# Main completion function for zsh
_tokenvault() {
    local cmd="$1"
    local cur="${words[CURRENT]}"
    local prev="${words[CURRENT-1]}"

    case "$cmd" in
        tv-add)
            _arguments \
                '-ID[Profile ID]:id:' \
                '-Prov[Provider]:(anthropic openai gemini custom)' \
                '-Auth[Auth mode]:(key cli)' \
                '-Base[Base URL]:url:' \
                '-QuotaAPI[Quota API URL]:url:' \
                '-Reset[Reset type]:(daily payg)' \
                '-Key[API Key]:key:' \
                '-Model[Default model]:model:'
            ;;
        tv-remove|tv-report)
            _arguments \
                ':profile:($(_tv_get_profiles))'
            ;;
        tv-run)
            if [[ $CURRENT -eq 2 ]]; then
                local profiles=$(_tv_get_profiles)
                _values 'profile or auto' auto $profiles
            fi
            ;;
        tv-model-set)
            _arguments \
                '-Prov[Provider]:(anthropic openai gemini custom)' \
                '-Tier[Tier]:(haiku sonnet opus subagent default)' \
                '-Model[Model]:model:' \
                '-Profile[Profile]:profile:($(_tv_get_profiles))'
            ;;
        tv-model-list)
            _arguments \
                '-Prov[Provider]:(anthropic openai gemini custom)' \
                '-Profile[Profile]:profile:($(_tv_get_profiles))'
            ;;
        tv-codex-sync)
            _arguments \
                '-Config[Config file]:file:_files' \
                '-Force[Force overwrite]' \
                '-DryRun[Dry run]' \
                '-AllowWireApi[Allow wire API]' \
                '-Yes[Skip confirmation]' \
                '-H[Show help]'
            ;;
    esac
}

# Register completion for all tv-* commands
if (( ${+functions[compdef]} )); then
    compdef _tokenvault tv-unlock tv-lock tv-unsafe tv-add tv-remove tv-list tv-dash tv-run tv-report tv-model-set tv-model-list tv-codex-sync tv-help
fi

