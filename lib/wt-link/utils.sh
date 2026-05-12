# shellcheck shell=bash
# utils.sh — Prerequisite helpers for wt-link.

require_cmd() {
    command -v "$1" &>/dev/null || error "Required command not found: $1"
}

require_pm() {
    command -v "$1" &>/dev/null || error "Package manager '$1' not found. Install it or ensure it is on PATH."
}

# wp-cli outputs deprecation notices to stdout (not stderr) starting with a
# leading newline. Strip empty lines, deprecation lines, and trailing whitespace.
wp_clean() {
    wp "$@" 2>/dev/null | grep -v -e '^[[:space:]]*$' -e 'Deprecated' | head -1 | tr -d '\n'
}

infer_wp_core_version() {
    local path version

    command -v wp &>/dev/null || return 1

    for path in "$@"; do
        [[ -n "$path" && -f "$path/wp-load.php" ]] || continue

        version="$(wp_clean core version --path="$path" || true)"
        if [[ -n "$version" ]]; then
            printf '%s\n' "$version"
            return 0
        fi
    done

    return 1
}
