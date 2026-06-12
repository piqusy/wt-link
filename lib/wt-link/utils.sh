# shellcheck shell=bash
# utils.sh — Prerequisite helpers for wt-link.

require_cmd() {
    command -v "$1" &>/dev/null || error "Required command not found: $1"
}

require_pm() {
    command -v "$1" &>/dev/null || error "Package manager '$1' not found. Install it or ensure it is on PATH."
}

# Build the wp-cli invocation prefix for core download, with a raised PHP
# memory limit. `command -v wp` may resolve to a shell wrapper around wp-cli
# rather than the PHP file itself — running `php <wrapper>` makes PHP print
# the wrapper text verbatim and exit 0, silently downloading nothing. Only
# prefix with `php -d` when the resolved binary is actually a PHP script;
# otherwise invoke it directly and pass the limit via WP_CLI_PHP_ARGS
# (honored by the official wp launcher, harmless elsewhere).
wp_download_cmd() {
    local memory_limit="$1" wp_bin
    wp_bin="$(command -v wp)" || return 1
    if head -1 "$wp_bin" | grep -q 'php'; then
        printf "php -d memory_limit=%s '%s'" "$memory_limit" "$wp_bin"
    else
        printf "WP_CLI_PHP_ARGS='-d memory_limit=%s' '%s'" "$memory_limit" "$wp_bin"
    fi
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
