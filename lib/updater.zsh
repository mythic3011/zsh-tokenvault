# Guard against double sourcing
[[ -n "${TV_UPDATER_LOADED:-}" ]] && return 0
typeset -g TV_UPDATER_LOADED=1

# --- SECURE UPDATER ---
# Handles self-update with checksum verification and rollback

typeset -g TV_UPDATE_MANIFEST_URL="${TV_UPDATE_MANIFEST_URL:-https://raw.githubusercontent.com/user/tokenvault/main/release/latest.json}"
typeset -g TV_UPDATE_CHANNEL="${TV_UPDATE_CHANNEL:-stable}"

# Fetch update manifest
_tv_fetch_update_manifest() {
    local url="$TV_UPDATE_MANIFEST_URL"
    [[ -z "$url" ]] && return 1
    
    local resp
    resp=$(curl -s -L -m 10 --connect-timeout 5 "$url" 2>/dev/null)
    
    if echo "$resp" | jq -e '.' >/dev/null 2>&1; then
        printf '%s' "$resp"
        return 0
    fi
    return 1
}

# Check for updates
tv-self-update() {
    local action="${1:---check}"
    
    case "$action" in
        --check)
            _tv_banner "$(_tv_tr "check_for_updates_title" "Check for Updates")"
            _tv_print "  ${_TV_GRY}$(_tv_trf "checking_url" "Checking %s..." "$TV_UPDATE_MANIFEST_URL")${_TV_RST}"
            
            local manifest
            manifest=$(_tv_fetch_update_manifest)
            if [[ -z "$manifest" ]]; then
                _tv_print "  ${_TV_RED}✗ $(_tv_tr "could_not_fetch_update_manifest" "Could not fetch update manifest")${_TV_RST}"
                return 1
            fi
            
            local latest_version current_version
            latest_version=$(echo "$manifest" | jq -r '.version // "unknown"')
            current_version=$(jq -r '.app_version // "7.0"' "$TV_VERSION_FILE" 2>/dev/null || echo "7.0")
            
            local channel
            channel=$(echo "$manifest" | jq -r '.channel // "stable"')
            
            if [[ "$latest_version" == "$current_version" ]]; then
                _tv_print "  ${_TV_GRN}✓ $(_tv_trf "already_at_version" "Already at version %s" "$current_version")${_TV_RST}"
            else
                _tv_print "  ${_TV_YEL}⚠ $(_tv_trf "update_available_channel" "Update available: %s → %s (%s)" "$current_version" "$latest_version" "$channel")${_TV_RST}"
                local notes
                notes=$(echo "$manifest" | jq -r '.notes // empty')
                [[ -n "$notes" ]] && _tv_print "  ${_TV_GRY}${notes}${_TV_RST}"
            fi
            ;;
        
        --install)
            _tv_banner "$(_tv_tr "install_update_title" "Install Update")"
            
            local manifest
            manifest=$(_tv_fetch_update_manifest)
            if [[ -z "$manifest" ]]; then
                _tv_print "  ${_TV_RED}✗ $(_tv_tr "could_not_fetch_update_manifest" "Could not fetch update manifest")${_TV_RST}"
                return 1
            fi
            
            local latest_version download_url checksum
            latest_version=$(echo "$manifest" | jq -r '.version // empty')
            download_url=$(echo "$manifest" | jq -r '.download_url // empty')
            checksum=$(echo "$manifest" | jq -r '.checksum // empty')
            
            if [[ -z "$latest_version" || -z "$download_url" ]]; then
                _tv_print "  ${_TV_RED}✗ $(_tv_tr "invalid_manifest_missing_fields" "Invalid manifest: missing version or download_url")${_TV_RST}"
                return 1
            fi
            
            # Verify checksum if provided
            if [[ -n "$checksum" ]]; then
                _tv_print "  ${_TV_GRY}$(_tv_tr "verifying_checksum" "Verifying checksum...")${_TV_RST}"
                # Download to temp file and verify
                local tmp_file
                tmp_file=$(_tv_mktemp "$TV_DIR/.update_tmp.XXXXXX") || return 1
                
                curl -s -L -m 60 "$download_url" -o "$tmp_file" 2>/dev/null
                if ! _tv_verify_sha256 "$tmp_file" "$checksum"; then
                    rm -f "$tmp_file"
                    _tv_print "  ${_TV_RED}✗ $(_tv_tr "checksum_verification_failed" "Checksum verification failed")${_TV_RST}"
                    return 1
                fi
                _tv_print "  ${_TV_GRN}✓ $(_tv_tr "checksum_verified" "Checksum verified")${_TV_RST}"
            fi
            
            # Backup current installation
            local backup_dir="${TV_DIR}/backup/$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir"
            cp -r "$TV_PLUGIN_DIR"/* "$backup_dir/" 2>/dev/null
            _tv_print "  ${_TV_GRY}$(_tv_trf "backup_created" "Backup created: %s" "$backup_dir")${_TV_RST}"
            
            # Install update
            _tv_print "  ${_TV_GRY}$(_tv_tr "installing_update" "Installing update...")${_TV_RST}"
            # Implementation depends on distribution method (git pull, tar extract, etc.)
            _tv_print "  ${_TV_YEL}⚠ $(_tv_tr "update_install_not_implemented" "Update installation not yet implemented")${_TV_RST}"
            ;;
        
        --rollback)
            _tv_banner "$(_tv_tr "rollback_title" "Rollback")"
            
            local backup_dir
            backup_dir=$(ls -td "${TV_DIR}/backup/"* 2>/dev/null | head -1)
            
            if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
                _tv_print "  ${_TV_RED}✗ $(_tv_tr "no_backup_found" "No backup found")${_TV_RST}"
                return 1
            fi
            
            _tv_print "  ${_TV_GRY}$(_tv_trf "rolling_back_to" "Rolling back to: %s" "$backup_dir")${_TV_RST}"
            cp -r "$backup_dir"/* "$TV_PLUGIN_DIR/" 2>/dev/null
            _tv_print "  ${_TV_GRN}✓ $(_tv_tr "rollback_complete" "Rollback complete")${_TV_RST}"
            ;;
        
        *)
            _tv_print "  ${_TV_GRY}$(_tv_tr "tv_self_update_usage" "Usage: tv-self-update [--check|--install|--rollback]")${_TV_RST}"
            ;;
    esac
}

# --- UPDATER OPEN/CLOSE ---

tv_updater_open() {
    [[ -n "${TV_UPDATER_OPENED:-}" ]] && return 0
    TV_UPDATER_OPENED=1
}

tv_updater_close() {
    TV_UPDATER_OPENED=""
}
