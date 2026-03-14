# =============================================================================
# 💎 TokenVault v7.0: Local API Gateway Edition
# ==============================================================================

if [[ -z "${ZSH_VERSION:-}" ]]; then
    return 0
fi

typeset -g TV_PLUGIN_PATH="${TV_PLUGIN_PATH:-${(%):-%N}}"
typeset -g TV_PLUGIN_DIR="${TV_PLUGIN_DIR:-${TV_PLUGIN_PATH:A:h}}"
typeset -g TV_PLUGIN_LIB_DIR="${TV_PLUGIN_LIB_DIR:-$TV_PLUGIN_DIR/lib}"
typeset -g TV_PLUGIN_COMMANDS_DIR="${TV_PLUGIN_COMMANDS_DIR:-$TV_PLUGIN_DIR/commands}"

[[ -f "$TV_PLUGIN_LIB_DIR/config.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/config.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/i18n.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/i18n.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/core.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/core.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/models.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/models.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/ui.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/ui.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/prompt.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/prompt.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/auth.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/auth.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/completion.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/completion.zsh"
for tv_command_file in "$TV_PLUGIN_COMMANDS_DIR"/*.zsh(N); do
    source "$tv_command_file"
done

if typeset -f tv_core_open &>/dev/null; then
    tv_core_open
fi
if typeset -f tv_ui_open &>/dev/null; then
    tv_ui_open
fi
if typeset -f tv_models_open &>/dev/null; then
    tv_models_open
fi
if typeset -f tv_prompt_open &>/dev/null; then
    tv_prompt_open
fi
if typeset -f tv_auth_open &>/dev/null; then
    tv_auth_open
fi
if typeset -f tv_key_helpers_open &>/dev/null; then
    tv_key_helpers_open
fi

autoload -Uz add-zsh-hook
add-zsh-hook precmd tv_render
