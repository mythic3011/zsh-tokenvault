# Guard against double sourcing
[[ -n "${TV_COMPLETION_LOADED:-}" ]] && return 0
typeset -g TV_COMPLETION_LOADED=1

_tokenvault() {
    local cur prev words cword
    _get_comp_words_by_ref -n : cur prev words cword

    local cmd="${words[1]}"

    case "$cmd" in
        tv-unlock|tv-lock|tv-unsafe|tv-list|tv-dash|tv-help)
            # No arguments for these commands
            return 0
            ;;
        tv-add)
            # Flags: -ID -Prov -Auth -Base -QuotaAPI -Reset -Key -Model
            case "$prev" in
                -Prov)
                    COMPREPLY=($(compgen -W "anthropic openai gemini custom" -- "$cur"))
                    return 0
                    ;;
                -Auth)
                    COMPREPLY=($(compgen -W "key cli" -- "$cur"))
                    return 0
                    ;;
                -Reset)
                    COMPREPLY=($(compgen -W "daily payg" -- "$cur"))
                    return 0
                    ;;
                -ID|-Base|-QuotaAPI|-Key|-Model)
                    # These take arbitrary values
                    return 0
                    ;;
            esac
            # Complete flag names
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-ID -Prov -Auth -Base -QuotaAPI -Reset -Key -Model" -- "$cur"))
            fi
            return 0
            ;;
        tv-remove)
            # First arg: profile-id
            if (( cword == 2 )); then
                _tv_complete_profile_ids
            fi
            return 0
            ;;
        tv-run)
            # First arg: profile-id or "auto"
            if (( cword == 2 )); then
                local profiles
                profiles=$(compgen -W "auto" -- "$cur")
                if [[ -f "$TV_PROFILES" ]]; then
                    profiles+=$'\n'$(jq -r 'keys[]' "$TV_PROFILES" 2>/dev/null | grep -F "$cur")
                fi
                COMPREPLY=($(echo "$profiles" | sort -u))
            fi
            # Rest: command and args (no completion)
            return 0
            ;;
        tv-report)
            # First arg: profile-id
            if (( cword == 2 )); then
                _tv_complete_profile_ids
            fi
            return 0
            ;;
        tv-model-set)
            # Flags: -Prov -Tier -Model -Profile
            case "$prev" in
                -Prov)
                    COMPREPLY=($(compgen -W "anthropic openai gemini custom" -- "$cur"))
                    return 0
                    ;;
                -Tier)
                    COMPREPLY=($(compgen -W "haiku sonnet opus subagent" -- "$cur"))
                    return 0
                    ;;
                -Profile)
                    _tv_complete_profile_ids
                    return 0
                    ;;
                -Model)
                    # Arbitrary model name
                    return 0
                    ;;
            esac
            # Complete flag names
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-Prov -Tier -Model -Profile" -- "$cur"))
            fi
            return 0
            ;;
        tv-model-list)
            # Flags: -Prov -Profile
            case "$prev" in
                -Prov)
                    COMPREPLY=($(compgen -W "anthropic openai gemini custom" -- "$cur"))
                    return 0
                    ;;
                -Profile)
                    _tv_complete_profile_ids
                    return 0
                    ;;
            esac
            # Complete flag names
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-Prov -Profile" -- "$cur"))
            fi
            return 0
            ;;
        tv-codex-sync)
            # Flags: -Config -Force -DryRun -AllowWireApi -Yes
            case "$prev" in
                -Config)
                    # File path completion
                    _filedir
                    return 0
                    ;;
                -Force|-DryRun|-AllowWireApi|-Yes)
                    # Boolean flags, no args
                    return 0
                    ;;
            esac
            # Complete flag names
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-Config -Force -DryRun -AllowWireApi -Yes" -- "$cur"))
            fi
            return 0
            ;;
    esac

    return 0
}

_tv_complete_profile_ids() {
    local profiles=""
    if [[ -f "$TV_PROFILES" ]]; then
        profiles=$(jq -r 'keys[]' "$TV_PROFILES" 2>/dev/null)
    fi
    COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
}

# Register compdef for all tv-* commands (only if compdef is available)
if typeset -f compdef >/dev/null 2>&1; then
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
fi
