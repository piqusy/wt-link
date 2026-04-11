# shellcheck shell=bash
# project.sh — Project discovery helpers for wt-link.
# Globals used: WP_CONTENT, CANONICAL_WP_CONTENT (set by bin/wt-link before dispatch)

# Walk up from $1 until setup.json is found, but stop at the git repo root.
# Echoes the directory containing setup.json and returns 0 on success.
find_project_root() {
    local dir="$1"
    local ceiling
    ceiling="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "/")"
    while true; do
        if [[ -f "$dir/setup.json" ]]; then
            echo "$dir"
            return 0
        fi
        # Do not go above the git repo root
        if [[ "$dir" == "$ceiling" || "$dir" == "/" ]]; then
            return 1
        fi
        dir="$(dirname "$dir")"
    done
}

# Eightshift packages: themes/plugins containing a composer.json that references
# infinum/eightshift-libs.
find_eightshift_packages() {
    local base_dirs=("$WP_CONTENT/themes" "$WP_CONTENT/plugins")
    local packages=()
    for base in "${base_dirs[@]}"; do
        [[ -d "$base" ]] || continue
        for dir in "$base"/*/; do
            [[ -f "$dir/composer.json" ]] || continue
            if grep -q "eightshift-libs\|EightshiftBoilerplate\|infinum" "$dir/composer.json" 2>/dev/null; then
                packages+=("$dir")
            fi
        done
    done
    printf '%s\n' "${packages[@]}"
}

# Plugins not tracked in git — need to be symlinked from canonical.
find_untracked_plugins() {
    local plugins_dir="$WP_CONTENT/plugins"
    local canonical_plugins="$CANONICAL_WP_CONTENT/plugins"
    [[ -d "$canonical_plugins" ]] || return

    for plugin_dir in "$canonical_plugins"/*/; do
        local plugin_name
        plugin_name="$(basename "$plugin_dir")"
        local dest="$plugins_dir/$plugin_name"

        # Skip if already present (tracked in git or already symlinked)
        [[ -e "$dest" ]] && continue

        # Also skip the symlink itself (in case canonical has symlinks pointing elsewhere)
        echo "$plugin_dir"
    done

    # Also link index.php if missing
    local idx="$plugins_dir/index.php"
    local canonical_idx="$canonical_plugins/index.php"
    [[ ! -e "$idx" && -f "$canonical_idx" ]] && echo "$canonical_idx"
}

# Lockfile takes priority over package.json "packageManager" field.
detect_package_manager() {
    local dir="$1"
    if [[ -f "$dir/bun.lockb" ]] || [[ -f "$dir/bun.lock" ]]; then
        echo "bun"
    elif [[ -f "$dir/yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "$dir/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "$dir/package-lock.json" ]]; then
        echo "npm"
    elif [[ -f "$dir/package.json" ]]; then
        local pm_field
        pm_field="$(jq -r '.packageManager // empty' "$dir/package.json" 2>/dev/null || true)"
        case "$pm_field" in
            bun@*)  echo "bun"  ;;
            yarn@*) echo "yarn" ;;
            pnpm@*) echo "pnpm" ;;
            npm@*)  echo "npm"  ;;
            *)      echo "bun"  ;;
        esac
    else
        echo "bun"
    fi
}
