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
# (e.g. a deprecation-suppressing shim that execs php directly) rather than
# the official launcher, and such wrappers don't forward WP_CLI_PHP_ARGS —
# the limit is silently dropped, leaving the default 128M to blow up
# PharData extraction on larger core tarballs. PHPRC is read by the php
# binary itself regardless of what wrapper `wp` resolves to, so write the
# limit to a php.ini in the caller-provided scratch dir and point PHPRC at
# it instead. Caller owns ini_dir and must create/clean it up.
wp_download_cmd() {
    local memory_limit="$1" ini_dir="$2" wp_bin
    wp_bin="$(command -v wp)" || return 1
    printf 'memory_limit = %s\n' "$memory_limit" > "$ini_dir/php.ini"
    printf "PHPRC='%s' '%s'" "$ini_dir" "$wp_bin"
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

# Second-route fallback: read the WordPress version off the canonical site's
# Dockerfile base image tag (e.g. "FROM wordpress:7.0.2-php8.4-fpm" -> "7.0.2").
# Unlike infer_wp_core_version, this needs no wp-cli and no core files on disk
# yet — useful when the canonical site has never had WP core downloaded
# locally, so its wp-load.php doesn't exist for wp-cli to introspect.
infer_wp_core_version_from_dockerfile() {
    local dockerfile="$1/Dockerfile" tag

    [[ -f "$dockerfile" ]] || return 1

    tag="$(grep -m1 -E '^FROM[[:space:]]+wordpress:' "$dockerfile" \
        | sed -E 's/^FROM[[:space:]]+wordpress:([^[:space:]]+).*/\1/')"
    [[ -n "$tag" ]] || return 1

    printf '%s\n' "${tag%%-*}"
}
