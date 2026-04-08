# Guard against double sourcing
[[ -n "${TV_COMPLETION_LOADED:-}" ]] && return 0
typeset -g TV_COMPLETION_LOADED=1

_tv_completion_profile_ids() {
    local -a profiles
    if [[ -f "$TV_PROFILES" ]]; then
        profiles=(${(f)"$(jq -r 'keys[]' "$TV_PROFILES" 2>/dev/null)"})
    fi
    (( ${#profiles[@]} )) && compadd -- "${profiles[@]}"
}

_tv_completion_agent_ids() {
    local -a agents common
    common=(codex claude-code aider)
    agents=("${common[@]}")
    if [[ -f "$TV_AGENT_REGISTRY_FILE" ]]; then
        agents+=(${(f)"$(jq -r 'keys[]' "$TV_AGENT_REGISTRY_FILE" 2>/dev/null)"})
    fi
    (( ${#agents[@]} )) && compadd -U -- "${agents[@]}"
}

_tokenvault() {
    emulate -L zsh
    setopt localoptions noshwordsplit noksharrays

    local cmd="$service"

    case "$cmd" in
        tv-unlock|tv-lock|tv-unsafe|tv-list|tv-dash|tv-help|tv-key-status|tv-provider-list|tv-agent-list|tv-update-registry-cmd)
            return 0
            ;;
        tv-add|tv-add-key)
            _arguments -s \
                '-ID[profile id]:profile id:' \
                '-Prov[provider]:provider:(anthropic openai gemini custom)' \
                '-Auth[auth mode]:auth mode:(key cli)' \
                '-Base[base URL]:base URL:' \
                '-QuotaAPI[quota API URL]:quota API URL:' \
                '-Reset[reset strategy]:reset strategy:(daily payg)' \
                '-Key[API key]:API key:' \
                '-Model[default model]:model:'
            return
            ;;
        tv-remove|tv-report|tv-key-rotate)
            if (( CURRENT == 2 )); then
                _tv_completion_profile_ids
            fi
            return 0
            ;;
        tv-run)
            if (( CURRENT == 2 )); then
                local -a profiles
                profiles=(auto)
                if [[ -f "$TV_PROFILES" ]]; then
                    profiles+=(${(f)"$(jq -r 'keys[]' "$TV_PROFILES" 2>/dev/null)"})
                fi
                compadd -U -- "${profiles[@]}"
            fi
            return 0
            ;;
        tv-model-set)
            _arguments -s \
                '-Prov[provider]:provider:(anthropic openai gemini custom)' \
                '-Tier[tier]:tier:(haiku sonnet opus subagent)' \
                '-Model[model name]:model:' \
                '-Profile[profile id]:profile id:_tv_completion_profile_ids'
            return
            ;;
        tv-model-list)
            _arguments -s \
                '-Prov[provider]:provider:(anthropic openai gemini custom)' \
                '-Profile[profile id]:profile id:_tv_completion_profile_ids'
            return
            ;;
        tv-codex-sync)
            _arguments -s \
                '-Config[config path]:config path:_files' \
                '-Force[force sync]' \
                '-DryRun[dry run]' \
                '-AllowWireApi[allow wire API providers]' \
                '-Yes[skip confirmation]'
            return
            ;;
        tv-config-inspect)
            _arguments -s \
                '--agent[agent id]:agent id:_tv_completion_agent_ids' \
                '--show-precedence[show precedence graph]' \
                '--show-overrides[show key override chain]' \
                '--show-effective[show effective config]' \
                '--show-graph[show resolution graph]' \
                '--show-discovered[show discovered layers]' \
                '--json[emit JSON]' \
                '--cwd[target directory]:directory:_files -/'
            return
            ;;
        tv-runtime-sync)
            _arguments -s \
                '--agent[agent id]:agent id:_tv_completion_agent_ids' \
                '--force[force sync]' \
                '--dry-run[dry run]'
            return
            ;;
        tv-self-update-cmd)
            _arguments '--check[check for updates]' '--install[install updates]' '--rollback[rollback latest backup]'
            return
            ;;
        tv-adapter-update)
            _arguments -s \
                '--agent[agent id]:agent id:_tv_completion_agent_ids' \
                '--force[force update]'
            return
            ;;
        tv-version-cmd)
            _arguments '--json[emit JSON]'
            return
            ;;
        tv-version-check-compat)
            _arguments -s \
                '--agent[agent id]:agent id:_tv_completion_agent_ids' \
                '--version[agent version]:version:'
            return
            ;;
    esac

    return 0
}

# Register completion only in interactive shells once the completion system exists.
if [[ -o interactive ]] && typeset -f compdef >/dev/null 2>&1; then
    compdef _tokenvault tv-unlock
    compdef _tokenvault tv-lock
    compdef _tokenvault tv-unsafe
    compdef _tokenvault tv-add
    compdef _tokenvault tv-remove
    compdef _tokenvault tv-list
    compdef _tokenvault tv-dash
    compdef _tokenvault tv-run
    compdef _tokenvault tv-report
    compdef _tokenvault tv-model-set
    compdef _tokenvault tv-model-list
    compdef _tokenvault tv-codex-sync
    compdef _tokenvault tv-help
    compdef _tokenvault tv-config-inspect
    compdef _tokenvault tv-runtime-sync
    compdef _tokenvault tv-self-update-cmd
    compdef _tokenvault tv-adapter-update
    compdef _tokenvault tv-version-cmd
    compdef _tokenvault tv-version-check-compat
    compdef _tokenvault tv-key-rotate
    compdef _tokenvault tv-key-status
    compdef _tokenvault tv-add-key
    compdef _tokenvault tv-provider-list
    compdef _tokenvault tv-agent-list
    compdef _tokenvault tv-update-registry-cmd
fi
