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
