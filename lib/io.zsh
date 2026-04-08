# Guard against double sourcing
[[ -n "${TV_IO_LOADED:-}" ]] && return 0
typeset -g TV_IO_LOADED=1

# --- I/O UTILITIES ---
# Common I/O operations for TokenVault

# Atomic file write
# Usage: _tv_atomic_write <file> <content>
_tv_atomic_write() {
    local file="$1" content="$2"
    local dir="${file:h}"
    local tmp
    tmp=$(_tv_mktemp "$dir/.atomic_tmp.XXXXXX") || return 1
    /bin/chmod 600 "$tmp"
    echo "$content" > "$tmp" && /bin/mv -f "$tmp" "$file" || { /bin/rm -f "$tmp"; return 1; }
}

# Safe file read with default
# Usage: _tv_safe_read_file <file> [default]
_tv_safe_read_file() {
    local file="$1" default="${2:-}"
    if [[ -f "$file" ]]; then
        print -r -- "$(<"$file")"
    else
        echo "$default"
    fi
}

# Ensure directory exists with proper permissions
# Usage: _tv_ensure_dir <dir> [mode]
_tv_ensure_dir() {
    local dir="$1" mode="${2:-700}"
    local mkdir_bin="${commands[mkdir]:-/bin/mkdir}"
    local chmod_bin="${commands[chmod]:-/bin/chmod}"
    if [[ ! -d "$dir" ]]; then
        "$mkdir_bin" -p "$dir" || return 1
        "$chmod_bin" "$mode" "$dir" || return 1
    fi
}

# Check if file is older than N seconds
# Usage: _tv_is_file_stale <file> <max_age_seconds>
_tv_is_file_stale() {
    local file="$1" max_age="$2"
    [[ ! -f "$file" ]] && return 0
    
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    (( age > max_age ))
}

# Get file size in bytes
# Usage: _tv_file_size <file>
_tv_file_size() {
    local file="$1"
    [[ ! -f "$file" ]] && echo 0 && return 0
    stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null || echo 0
}

# Read file with size limit
# Usage: _tv_read_limited <file> <max_bytes>
_tv_read_limited() {
    local file="$1" max_bytes="$2"
    [[ ! -f "$file" ]] && return 1
    head -c "$max_bytes" "$file"
}

# Create backup of file
# Usage: _tv_backup_file <file> [backup_dir]
_tv_backup_file() {
    local file="$1" backup_dir="${2:-$(dirname "$file")}"
    [[ ! -f "$file" ]] && return 1
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/$(basename "$file").bak.${timestamp}"
    cp "$file" "$backup_file"
    echo "$backup_file"
}

# List files matching pattern
# Usage: _tv_list_matching <dir> <pattern>
_tv_list_matching() {
    local dir="$1" pattern="$2"
    [[ ! -d "$dir" ]] && return 0
    find "$dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null
}

# Clean old temp files
# Usage: _tv_clean_temp [max_age_hours]
_tv_clean_temp() {
    local max_age="${1:-24}"
    local temp_dir="${TV_CACHE_DIR}"
    [[ ! -d "$temp_dir" ]] && return 0
    
    find "$temp_dir" -name ".tmp_*" -mmin "+$(( max_age * 60 ))" -delete 2>/dev/null
    find "$temp_dir" -name ".json_tmp.*" -mmin "+$(( max_age * 60 ))" -delete 2>/dev/null
    find "$temp_dir" -name ".vault_tmp.*" -mmin "+$(( max_age * 60 ))" -delete 2>/dev/null
}

# --- I/O OPEN/CLOSE ---

tv_io_open() {
    [[ -n "${TV_IO_OPENED:-}" ]] && return 0
    _tv_ensure_dir "$TV_DIR"
    _tv_ensure_dir "$TV_CACHE_DIR"
    TV_IO_OPENED=1
}

tv_io_close() {
    TV_IO_OPENED=""
}
