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

# --- Core modules (load order matters) ---
[[ -f "$TV_PLUGIN_LIB_DIR/config.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/config.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/i18n.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/i18n.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/core.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/core.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/security.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/security.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/json.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/json.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/io.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/io.zsh"

# --- Feature modules ---
[[ -f "$TV_PLUGIN_LIB_DIR/models.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/models.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/ui.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/ui.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/prompt.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/prompt.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/auth.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/auth.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/resolver.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/resolver.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/endpoint-spec.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/endpoint-spec.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/catalog.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/catalog.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/versioning.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/versioning.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/updater.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/updater.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/agent-provider.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/agent-provider.zsh"
[[ -f "$TV_PLUGIN_LIB_DIR/agent-registry.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/agent-registry.zsh"

# --- Agent adapters ---
for tv_agent_file in "$TV_PLUGIN_LIB_DIR/agents"/*.zsh(N); do
    source "$tv_agent_file"
done

# --- Completion (load last) ---
[[ -f "$TV_PLUGIN_LIB_DIR/completion.zsh" ]] && source "$TV_PLUGIN_LIB_DIR/completion.zsh"

# --- Command modules ---
for tv_command_file in "$TV_PLUGIN_COMMANDS_DIR"/*.zsh(N); do
    source "$tv_command_file"
done

# --- Initialize modules ---
if typeset -f tv_core_open &>/dev/null; then
    tv_core_open
fi
if typeset -f tv_security_open &>/dev/null; then
    tv_security_open
fi
if typeset -f tv_json_open &>/dev/null; then
    tv_json_open
fi
if typeset -f tv_io_open &>/dev/null; then
    tv_io_open
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
if typeset -f tv_resolver_open &>/dev/null; then
    tv_resolver_open
fi
if typeset -f tv_endpoint_spec_open &>/dev/null; then
    tv_endpoint_spec_open
fi
if typeset -f tv_catalog_open &>/dev/null; then
    tv_catalog_open
fi
if typeset -f tv_versioning_open &>/dev/null; then
    tv_versioning_open
fi
if typeset -f tv_updater_open &>/dev/null; then
    tv_updater_open
fi
if typeset -f tv_agent_provider_open &>/dev/null; then
    tv_agent_provider_open
fi
if typeset -f tv_agent_registry_open &>/dev/null; then
    tv_agent_registry_open
fi
if typeset -f tv_key_helpers_open &>/dev/null; then
    tv_key_helpers_open
fi

autoload -Uz add-zsh-hook
add-zsh-hook precmd tv_render
