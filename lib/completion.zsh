# Guard against double sourcing
[[ -n "${TV_COMPLETION_LOADED:-}" ]] && return 0
typeset -g TV_COMPLETION_LOADED=1

# Completion helper: get profile IDs from vault
_tv_get_profiles() {
    [[ -f "$TV_PROFILES" ]] && jq -r 'keys[]' "$TV_PROFILES" 2>/dev/null || true
}

# Main completion function
_tokenvault() {
    local cur prev words cword
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local cmd="${words[1]}"

    # Complete command names
    if [[ $cword -eq 1 ]]; then
        local cmds=(
            "tv-unlock:Unlock vault"
            "tv-lock:Lock vault"
            "tv-unsafe:Toggle unsafe mode"
            "tv-add:Add profile"
            "tv-remove:Remove profile"
            "tv-list:List profiles"
            "tv-dash:Dashboard"
            "tv-run:Run command"
            "tv-report:Report exhausted key"
            "tv-model-set:Set default model"
            "tv-model-list:List models"
            "tv-codex-sync:Sync Codex config"
            "tv-help:Show help"
        )
        COMPREPLY=($(compgen -W "${cmds[*]%:*}" -- "$cur"))
        return 0
    fi

    # Complete flags and arguments per command
    case "$cmd" in
        tv-add)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-ID -Prov -Auth -Base -QuotaAPI -Reset -Key -Model" -- "$cur"))
            fi
            case "$prev" in
                -Prov) COMPREPLY=($(compgen -W "anthropic openai gemini custom" -- "$cur")) ;;
                -Auth) COMPREPLY=($(compgen -W "key cli" -- "$cur")) ;;
                -Reset) COMPREPLY=($(compgen -W "daily payg" -- "$cur")) ;;
            esac
            ;;
        tv-remove|tv-report)
            if [[ $cword -eq 2 && ! "$cur" =~ ^- ]]; then
                COMPREPLY=($(compgen -W "$(_tv_get_profiles)" -- "$cur"))
            fi
            ;;
        tv-run)
            if [[ $cword -eq 2 && ! "$cur" =~ ^- ]]; then
                local profiles=$(_tv_get_profiles)
                COMPREPLY=($(compgen -W "auto $profiles" -- "$cur"))
            fi
            ;;
        tv-model-set)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-Prov -Tier -Model -Profile" -- "$cur"))
            fi
            case "$prev" in
                -Prov) COMPREPLY=($(compgen -W "anthropic openai gemini custom" -- "$cur")) ;;
                -Tier) COMPREPLY=($(compgen -W "haiku sonnet opus subagent default" -- "$cur")) ;;
                -Profile) COMPREPLY=($(compgen -W "$(_tv_get_profiles)" -- "$cur")) ;;
            esac
            ;;
        tv-model-list)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-Prov -Profile" -- "$cur"))
            fi
            case "$prev" in
                -Prov) COMPREPLY=($(compgen -W "anthropic openai gemini custom" -- "$cur")) ;;
                -Profile) COMPREPLY=($(compgen -W "$(_tv_get_profiles)" -- "$cur")) ;;
            esac
            ;;
        tv-codex-sync)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-Config -Force -DryRun -AllowWireApi -Yes -H" -- "$cur"))
            fi
            case "$prev" in
                -Config) COMPREPLY=($(compgen -f -- "$cur")) ;;
            esac
            ;;
    esac
}

# Register completion for zsh
if command -v compdef >/dev/null 2>&1; then
    compdef _tokenvault tv-unlock tv-lock tv-unsafe tv-add tv-remove tv-list tv-dash tv-run tv-report tv-model-set tv-model-list tv-codex-sync tv-help
fi
