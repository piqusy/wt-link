# shellcheck shell=bash
# project.sh — Project discovery helpers for wt-link.
# Globals used: WP_CONTENT, CANONICAL_WP_CONTENT, CANONICAL_SITE (set by bin/wt-link before dispatch)

# Walk up from $1 until setup.json is found, but stop at the git repo root.
# Echoes the directory containing setup.json and returns 0 on success.
#
# Fallback: some WordPress projects have no setup.json (it is an Eightshift
# convention, not a WP requirement). When none is found, fall back to the
# highest ancestor that still looks like a WP install (has a wp-content/ dir)
# so those projects can be mounted too — the site URL is then inferred rather
# than read from setup.json (see resolve_inferred_site_name). Projects with
# neither marker are treated as non-WP and skipped by the caller.
find_project_root() {
    local dir="$1"
    local ceiling wp_fallback=""
    ceiling="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "/")"
    while true; do
        if [[ -f "$dir/setup.json" ]]; then
            echo "$dir"
            return 0
        fi
        # Remember the WP-looking dir closest to the repo root as a fallback.
        [[ -d "$dir/wp-content" ]] && wp_fallback="$dir"
        # Do not go above the git repo root
        if [[ "$dir" == "$ceiling" || "$dir" == "/" ]]; then
            break
        fi
        dir="$(dirname "$dir")"
    done
    if [[ -n "$wp_fallback" ]]; then
        echo "$wp_fallback"
        return 0
    fi
    return 1
}

# Best-effort site name for projects without a setup.json URL. The name must be
# STABLE across every worktree of a repo, because all worktrees share a single
# Herd .test domain and `mount` just toggles which one it points at. Order:
#   1. basename of CANONICAL_SITE when the caller set it explicitly (env var)
#   2. the git main worktree's dir name (identical from every linked worktree)
#   3. the given directory's own basename (non-git / detached fallback)
# Echoes the bare site name (no scheme, no .test suffix).
resolve_inferred_site_name() {
    local worktree_root="$1"
    if [[ -n "${CANONICAL_SITE:-}" ]]; then
        basename "$CANONICAL_SITE"
        return 0
    fi
    local main_worktree
    main_worktree="$(git -C "$worktree_root" worktree list --porcelain 2>/dev/null \
        | sed -n 's/^worktree //p' | head -1)"
    if [[ -n "$main_worktree" ]]; then
        basename "$main_worktree"
        return 0
    fi
    basename "$worktree_root"
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

# Root-level runtime files that should be copied from canonical when missing.
# Includes wt-link config files and .env variants, but skips example templates.
find_copyable_root_files() {
    [[ -d "$CANONICAL_SITE" ]] || return

    local path base
    for path in \
        "$CANONICAL_SITE/wt-link.json" \
        "$CANONICAL_SITE/wt-link.local.json" \
        "$CANONICAL_SITE/.env"
    do
        [[ -f "$path" ]] && echo "$path"
    done

    shopt -s nullglob
    for path in "$CANONICAL_SITE"/.env.*; do
        [[ -f "$path" ]] || continue
        base="$(basename "$path")"
        case "$base" in
            .env.example|.env.*.example)
                continue
                ;;
        esac
        echo "$path"
    done
    shopt -u nullglob
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
