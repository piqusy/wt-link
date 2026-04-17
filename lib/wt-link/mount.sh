# shellcheck shell=bash
# mount.sh — cmd_mount and its 8 private sub-functions for wt-link.
# Globals used: SITE_NAME, LOCAL_URL, WORKTREE_ROOT, CANONICAL_SITE, WP_CONTENT,
#   CANONICAL_WP_CONTENT, WP_VERSION, STATE_FILE, REGISTRY_FILE, REGISTRY_DIR,
#   WP_CORE_MARKER, SUBDOMAIN_LIST, FORCE, BOLD, RESET (set by bin/wt-link before dispatch)

# ── Private sub-functions ─────────────────────────────────────────────────────

_mount_validate() {
    require_cmd wp
    require_cmd herd
    require_cmd composer

    log "Mounting worktree as '$SITE_NAME' local site"
    echo "  Worktree : $WORKTREE_ROOT"
    echo "  Canonical: $CANONICAL_SITE"
    echo "  Domain   : $SITE_NAME.test"
    echo ""

    [[ -d "$CANONICAL_SITE" ]] || error "Canonical site not found: $CANONICAL_SITE\nSet CANONICAL_SITE= env var to override."

    # Migrate legacy state file from worktree root to registry dir (introduced in v1.8.0).
    # Compute the canonical new path directly (STATE_FILE may already be overridden to the
    # legacy path by the fallback in bin/wt-link, so we cannot rely on it here).
    local new_state="$REGISTRY_DIR/$SITE_NAME.$(basename "$WORKTREE_ROOT").state"
    local legacy_state="$WORKTREE_ROOT/.worktree-link-state"
    if [[ -f "$legacy_state" && ! -f "$new_state" ]]; then
        mkdir -p "$REGISTRY_DIR"
        mv "$legacy_state" "$new_state"
        STATE_FILE="$new_state"
    fi

    # Ensure state file always exists after mount (even if everything was already present)
    mkdir -p "$(dirname "$STATE_FILE")"
    touch "$STATE_FILE"
}

_mount_herd_link() {
    local herd_links_dir="$HOME/Library/Application Support/Herd/config/valet/Sites"
    local herd_link="$herd_links_dir/$SITE_NAME"

    # Ensure canonical is recorded in the registry (first time or if it was never set)
    local reg_canonical
    reg_canonical="$(registry_get canonical)"
    if [[ -z "$reg_canonical" ]]; then
        registry_set "canonical" "$CANONICAL_SITE"
    fi

    # Check if another worktree currently owns this domain
    local reg_active
    reg_active="$(registry_get active)"
    if [[ -n "$reg_active" && "$reg_active" != "$WORKTREE_ROOT" ]]; then
        if [[ $FORCE -eq 1 ]]; then
            step "Switching domain from $reg_active (--force)"
        elif [[ $YES -eq 1 ]]; then
            : # Silent — non-interactive hook context; proceed without any output
        else
            echo ""
            warn "Domain ${BOLD}$SITE_NAME.test${RESET} is currently mounted to another worktree:"
            echo -e "  Active: $reg_active"
            echo ""
            printf "  Switch domain to this worktree? [y/N] "
            local answer
            read -r answer
            if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
                echo ""
                warn "Aborted. Use --force to switch without prompting."
                echo ""
                echo -e "  To switch:     ${BOLD}wt-link mount --force${RESET}"
                echo -e "  To unmount:    cd $reg_active && wt-link unmount"
                echo ""
                exit 0
            fi
        fi
    fi

    if [[ -L "$herd_link" ]]; then
        local current_target
        current_target="$(readlink "$herd_link")"
        if [[ "$current_target" == "$WORKTREE_ROOT" ]]; then
            success "herd link already points to this worktree"
        else
            # herd link does not overwrite an existing symlink — remove first
            rm "$herd_link"
            run_with_spinner "Linking $SITE_NAME.test via Herd…" \
                bash -c "cd '$WORKTREE_ROOT' && herd link '$SITE_NAME'" || error "herd link failed — cannot mount without a working domain"
            success "herd link updated (was: $current_target)"
        fi
    else
        run_with_spinner "Linking $SITE_NAME.test via Herd…" \
            bash -c "cd '$WORKTREE_ROOT' && herd link '$SITE_NAME'" || error "herd link failed — cannot mount without a working domain"
        success "herd link created"
    fi

    # Update registry: this worktree now owns the domain
    registry_set "active" "$WORKTREE_ROOT"
    state_set "herd_linked" "1"

    # Secure via HTTPS if LOCAL_URL uses https:// (idempotent — skip if cert already exists)
    if [[ "$LOCAL_URL" == https://* ]]; then
        local certs_dir="$HOME/Library/Application Support/Herd/config/valet/Certificates"
        if [[ -f "$certs_dir/$SITE_NAME.crt" ]]; then
            success "HTTPS already secured"
        else
            step "Securing $SITE_NAME.test via Herd…"
            herd secure "$SITE_NAME" || warn "herd secure failed — HTTPS may not work"
            state_set "herd_secured" "1"
            success "HTTPS secured"
        fi
    fi
}

_mount_wp_core() {
    if [[ -f "$WP_CORE_MARKER" ]]; then
        success "WP core already present ($(wp_clean core version --path="$WORKTREE_ROOT" || echo 'unknown'))"
    else
        local wp_cache_gz="$HOME/.wp-cli/cache/core/wordpress-${WP_VERSION}-en_US.tar.gz"

        if [[ -f "$wp_cache_gz" ]]; then
            local tmp_dir
            tmp_dir="$(mktemp -d)"
            run_with_spinner "Extracting WordPress $WP_VERSION from cache…" \
                bash -c "tar xzf '$wp_cache_gz' -C '$tmp_dir' && rsync -a --exclude='wp-content' '$tmp_dir/wordpress/' '$WORKTREE_ROOT/'" \
                || error "Failed to extract WordPress $WP_VERSION from cache"
            rm -rf "$tmp_dir"
        else
            # Fallback: download via WP-CLI into a temp dir, then rsync
            local tmp_dir
            tmp_dir="$(mktemp -d)"
            run_with_spinner "Downloading WordPress $WP_VERSION…" \
                bash -c "wp core download --path='$tmp_dir' --version='$WP_VERSION' 2>/dev/null && rsync -a --exclude='wp-content' '$tmp_dir/' '$WORKTREE_ROOT/'" \
                || error "Failed to download WordPress $WP_VERSION"
            rm -rf "$tmp_dir"
        fi
        state_set "wp_core_installed" "1"
        success "WP core $WP_VERSION installed"
    fi
}

_mount_wp_config() {
    if [[ -f "$WORKTREE_ROOT/wp-config.php" ]]; then
        success "wp-config.php already present"
    else
        local canonical_config="$CANONICAL_SITE/wp-config.php"
        [[ -f "$canonical_config" ]] || error "wp-config.php not found in canonical site: $canonical_config"
        cp "$canonical_config" "$WORKTREE_ROOT/wp-config.php" \
            || error "Failed to copy wp-config.php from canonical site"
        state_set "wp_config_copied" "1"
        success "wp-config.php copied from canonical site"
    fi

    # In WP multisite, WP_HOME / WP_SITEURL constants in wp-config.php override the
    # per-blog siteurl/home options — every sub-site gets redirected to the main domain.
    # When subdomains are declared, strip these constants so each sub-site is resolved
    # from its own DB options instead.
    if [[ -n "${SUBDOMAIN_LIST:-}" ]]; then
        local cfg="$WORKTREE_ROOT/wp-config.php"
        if grep -q "WP_HOME\|WP_SITEURL" "$cfg" 2>/dev/null; then
            sed -i '' "/define.*'WP_HOME'/d; /define.*'WP_SITEURL'/d" "$cfg" \
                || warn "Could not strip WP_HOME/WP_SITEURL from wp-config.php"
            success "wp-config.php: removed WP_HOME/WP_SITEURL (multisite per-blog URLs now from DB)"
        fi
    fi
}

_mount_plugins() {
    # Globals: HARD_COPY (0=symlink default, 1=parallel hard-copy)
    local plugins=()
    while IFS= read -r p; do
        [[ -n "$p" ]] && plugins+=("$p")
    done < <(find_untracked_plugins)

    local total="${#plugins[@]}"
    if [[ $total -eq 0 ]]; then
        success "Plugins: nothing to link"
        return 0
    fi

    local new_count=0

    if [[ "$HARD_COPY" -eq 1 ]]; then
        # Parallel hard-copy: build a list of "src:::dest" pairs then xargs -P8
        local tmp_pairs
        tmp_pairs="$(mktemp)"
        for plugin_path in "${plugins[@]}"; do
            local plugin_name dest real_src
            plugin_name="$(basename "$plugin_path")"
            dest="$WP_CONTENT/plugins/$plugin_name"
            [[ -e "$dest" || -L "$dest" ]] && continue
            real_src="$(realpath "$plugin_path" 2>/dev/null || echo "$plugin_path")"
            [[ -e "$real_src" ]] || continue
            printf '%s:::%s\n' "$real_src" "$dest" >> "$tmp_pairs"
            new_count=$((new_count + 1))
        done

        if [[ $new_count -gt 0 ]]; then
            run_with_spinner "Hard-copying $new_count plugins (parallel)…" \
                bash -c '
                    xargs -P8 -I"{}" bash -c '"'"'
                        src="${1%%:::*}"; dest="${1##*:::}"
                        if [[ -d "$src" ]]; then cp -Rl "$src" "$dest"
                        else cp -l "$src" "$dest"; fi
                    '"'"' _ "{}" < "$1"
                ' _ "$tmp_pairs" \
                || warn "  Some plugins failed to copy — check above"

            # Record each hard-copied plugin in state for unmount
            while IFS= read -r pair; do
                local dest_name
                dest_name="$(basename "${pair##*:::}")"
                state_set "plugin_copied_$dest_name" "1"
            done < "$tmp_pairs"
        fi
        rm -f "$tmp_pairs"
        success "Plugins: $new_count newly hard-copied (parallel)"
    else
        # Default: symlink each plugin — fast enough to not need a spinner
        step "Symlinking $total untracked plugins…"
        for plugin_path in "${plugins[@]}"; do
            local plugin_name dest
            plugin_name="$(basename "$plugin_path")"
            dest="$WP_CONTENT/plugins/$plugin_name"
            if [[ -e "$dest" || -L "$dest" ]]; then
                : # already present
            else
                ln -s "$plugin_path" "$dest" \
                    || { warn "  Failed to symlink $plugin_name — skipping"; continue; }
                state_set "plugin_linked_$plugin_name" "1"
                new_count=$((new_count + 1))
            fi
        done
        success "Plugins: $new_count newly symlinked"
    fi
}

_mount_uploads() {
    local uploads_dest="$WP_CONTENT/uploads"
    local uploads_src="$CANONICAL_WP_CONTENT/uploads"
    if [[ -L "$uploads_dest" ]]; then
        success "uploads already symlinked"
    elif [[ -d "$uploads_dest" ]]; then
        warn "uploads dir already exists (not a symlink) — skipping"
    elif [[ -d "$uploads_src" ]]; then
        ln -s "$uploads_src" "$uploads_dest" \
            || warn "Failed to symlink uploads — skipping"
        state_set "uploads_linked" "1"
        success "uploads symlinked from canonical site"
    else
        warn "No uploads dir found in canonical site — skipping"
    fi
}

_mount_mu_plugin() {
    [[ "${NO_INDICATOR:-0}" == "1" ]] && return 0

    local mu_dir="$WP_CONTENT/mu-plugins"
    local indicator_file="$mu_dir/wt-link-indicator.php"
    local branch
    branch=$(git -C "$WORKTREE_ROOT" branch --show-current 2>/dev/null || basename "$WORKTREE_ROOT")

    if [[ -f "$indicator_file" ]]; then
        success "wt-link indicator already present"
        return
    fi

    if [[ ! -d "$mu_dir" ]]; then
        mkdir -p "$mu_dir"
        state_set "wt_link_mu_plugins_dir" "1"
    fi

    cat > "$indicator_file" << 'PHPEOF'
<?php
/* wt-link worktree indicator — auto-generated, do not edit */
defined('ABSPATH') || exit;
add_action('wp_footer',    'wt_link_indicator_render');
add_action('admin_footer', 'wt_link_indicator_render');
function wt_link_indicator_render() {
    $branch = 'BRANCH_PLACEHOLDER';
    echo '<div id="wt-link-indicator" style="'
        . 'position:fixed;bottom:0;left:50%;transform:translateX(-50%);'
        . 'background:#1e1e2e;color:#ffffff;padding:10px 10px 6px;font-family:monospace;'
        . 'font-size:12px;border-top-left-radius:12px;border-top-right-radius:12px;z-index:999999;'
        . 'box-shadow:0 2px 12px rgba(0,0,0,.5);cursor:pointer;user-select:none;'
        . 'white-space:nowrap;" onclick="this.remove()" title="click to dismiss">'
        . '&#x2387; ' . esc_html($branch)
        . '</div>';
}
PHPEOF

    sd 'BRANCH_PLACEHOLDER' "$branch" "$indicator_file"

    state_set "wt_link_indicator" "1"
    success "wt-link indicator injected (branch: $branch)"
}

_mount_eightshift_pkgs() {
    local packages
    mapfile -t packages < <(find_eightshift_packages)

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No Eightshift packages found"
        return 0
    fi

    # Phase 1: vendor/composer setup — sequential (state writes + filesystem ops must not interleave)
    local theme_pkgs=() theme_pms=()
    for pkg in "${packages[@]}"; do
        local pkg_name pkg_type canonical_pkg
        pkg_name="$(basename "$pkg")"
        pkg_type="package"
        [[ "$pkg" == *"/themes/"* ]] && pkg_type="theme"
        [[ "$pkg" == *"/plugins/"* ]] && pkg_type="plugin"

        log "Setting up $pkg_type: $pkg_name"

        canonical_pkg=""
        [[ "$pkg_type" == "theme" ]] && canonical_pkg="$CANONICAL_WP_CONTENT/themes/$pkg_name"
        [[ "$pkg_type" == "plugin" ]] && canonical_pkg="$CANONICAL_WP_CONTENT/plugins/$pkg_name"

        # composer deps — hardlink-copy vendor/ and vendor-prefixed/ from canonical
        # (cp -Rl creates a hardlink tree: zero extra disk on APFS, but PHP __FILE__
        #  resolves to the real worktree path — no symlink indirection issues)
        local composer_ok=0
        for vendor_dir in vendor vendor-prefixed; do
            local dest="$pkg/$vendor_dir"
            local src="$canonical_pkg/$vendor_dir"

            if [[ -L "$dest" ]]; then
                # Legacy symlink — replace with hardlink copy
                rm "$dest"
                if [[ -d "$src" ]]; then
                    run_with_spinner "  $vendor_dir/: converting symlink → hardlink copy…" \
                        cp -Rl "$src" "$dest" \
                        || { warn "  $vendor_dir/: hardlink copy failed, keeping without vendor"; continue; }
                    success "  $vendor_dir/: converted from symlink to hardlink copy"
                    state_set "vendor_copied_${pkg_name}_${vendor_dir}" "1"
                    [[ "$vendor_dir" == "vendor" ]] && composer_ok=1
                fi
            elif [[ -d "$dest" && ! -L "$dest" ]]; then
                [[ "$vendor_dir" == "vendor" ]] && { success "  vendor/: already present (local copy)"; composer_ok=1; }
                [[ "$vendor_dir" == "vendor-prefixed" ]] && success "  vendor-prefixed/: already present (local copy)"
            elif [[ -d "$src" ]]; then
                run_with_spinner "  $vendor_dir/: hardlink copy from canonical…" \
                    cp -Rl "$src" "$dest" \
                    || { warn "  $vendor_dir/: hardlink copy failed — will fall back to composer install"; continue; }
                success "  $vendor_dir/: hardlink copy from canonical"
                state_set "vendor_copied_${pkg_name}_${vendor_dir}" "1"
                [[ "$vendor_dir" == "vendor" ]] && composer_ok=1
            fi
            # vendor-prefixed/ is optional — no warning if absent in canonical
        done

        if [[ $composer_ok -eq 0 ]]; then
            if [[ -f "$pkg/vendor/autoload.php" ]]; then
                success "  composer: vendor/ already installed locally"
            else
                run_with_spinner "  composer install…" \
                    composer install --no-interaction --working-dir="$pkg" 2>/dev/null || warn "  composer install had warnings"
                success "  composer: done"
            fi
        fi

        if [[ "$pkg_type" == "theme" ]]; then
            local pm
            pm="$(detect_package_manager "$pkg")"
            require_pm "$pm"
            local node_modules_dest="$pkg/node_modules"
            [[ -L "$node_modules_dest" ]] && rm "$node_modules_dest"
            theme_pkgs+=("$pkg")
            theme_pms+=("$pm")
        else
            success "  node_modules + build: skipped (plugin ships pre-built)"
        fi
    done

    if [[ ${#theme_pkgs[@]} -eq 0 ]]; then
        return 0
    fi

    # Phase 2: node install — sequential (package managers share a global cache;
    # concurrent writes can corrupt it for npm/yarn classic)
    for i in "${!theme_pkgs[@]}"; do
        local pkg="${theme_pkgs[$i]}" pm="${theme_pms[$i]}"
        local pkg_name
        pkg_name="$(basename "${theme_pkgs[$i]}")"
        log "node_modules: $pkg_name"
        run_with_spinner "  $pm install…" \
            run_pm_install "$pm" "$pkg" || warn "  $pm install had warnings"
        success "  node_modules: installed via $pm"
    done

    # Phase 3: build — parallel (each theme compiles its own public/ from its own
    # node_modules; no shared mutable state between themes)
    local pids=() tmpfiles=() pkgnames=()
    for i in "${!theme_pkgs[@]}"; do
        local pkg="${theme_pkgs[$i]}" pm="${theme_pms[$i]}"
        local pkg_name tmp
        pkg_name="$(basename "$pkg")"
        tmp="$(mktemp)"
        tmpfiles+=("$tmp")
        pkgnames+=("$pkg_name")
        (
            run_pm_build "$pm" "$pkg" \
                && echo "OK: build done" \
                || { echo "WARN: build had errors — check manually"; exit 1; }
            state_set "public_built_$pkg_name" "1"
        ) >"$tmp" 2>&1 &
        pids+=($!)
    done

    local any_failed=0
    for i in "${!pids[@]}"; do
        echo ""
        log "Build: ${pkgnames[$i]}"
        if wait "${pids[$i]}"; then
            cat "${tmpfiles[$i]}"
            success "  ${pkgnames[$i]}: done"
        else
            cat "${tmpfiles[$i]}"
            warn "  ${pkgnames[$i]}: build failed — check output above"
            any_failed=1
        fi
        rm -f "${tmpfiles[$i]}"
    done

    [[ $any_failed -eq 0 ]] || return 1
}

_mount_herd_subdomains() {
    [[ -z "${SUBDOMAIN_LIST:-}" ]] && return 0

    local certs_dir="$HOME/Library/Application Support/Herd/config/valet/Certificates"
    local herd_links_dir="$HOME/Library/Application Support/Herd/config/valet/Sites"

    read -ra subdomains <<< "$SUBDOMAIN_LIST"
    local total="${#subdomains[@]}"
    step "Linking $total WPML subdomain(s)…"

    for sub in "${subdomains[@]}"; do
        local full_name="$sub.$SITE_NAME"
        local herd_link="$herd_links_dir/$full_name"

        if [[ -L "$herd_link" && "$(readlink "$herd_link")" == "$WORKTREE_ROOT" ]]; then
            success "  $full_name.test already linked"
        else
            [[ -L "$herd_link" ]] && rm "$herd_link"
            bash -c "cd '$WORKTREE_ROOT' && herd link '$full_name'" \
                || { warn "  herd link $full_name failed — skipping"; continue; }
            state_set "subdomain_linked_$sub" "1"
            success "  $full_name.test linked"
        fi

        if [[ "$LOCAL_URL" == https://* ]]; then
            if [[ -f "$certs_dir/$full_name.crt" ]]; then
                success "  $full_name.test already secured"
            else
                herd secure "$full_name" || warn "  herd secure $full_name failed"
                state_set "subdomain_secured_$sub" "1"
                success "  $full_name.test secured"
            fi
        fi
    done
}

_mount_verify() {
    # Verify domain (Herd was triggered at step 1 — should be live by now)
    wait_for_herd "$SITE_NAME.test" 10

    # DB upgrade check
    local db_version
    db_version="$(wp_clean core version --path="$WORKTREE_ROOT" || true)"
    echo ""
    success "Done! Site is live at https://$SITE_NAME.test/"
    echo ""
    echo -e "  WP version : ${BOLD}$db_version${RESET}"
    echo -e "  Theme      : $(wp_clean theme list --path="$WORKTREE_ROOT" --status=active --field=name || echo '(unknown)')"
    echo ""
    warn "If this is a WP version upgrade, visit https://$SITE_NAME.test/wp-admin/ to run the DB upgrade."
    echo ""
    echo -e "  Unmount with: ${BOLD}wt-link unmount${RESET}  or  ${BOLD}wlu${RESET}"
}

# ── Public dispatcher ─────────────────────────────────────────────────────────

cmd_mount() {
    # Capture previously-active worktree before we displace it, so the ERR trap
    # can tell the user how to restore it if the mount fails mid-way.
    local _prev_active
    _prev_active="$(registry_get active)"

    trap '
        local _ec=$?
        echo ""
        warn "Mount failed (exit $_ec) — rolling back…"
        echo ""
        cmd_unmount
        if [[ -n "$_prev_active" && "$_prev_active" != "$WORKTREE_ROOT" ]]; then
            echo ""
            warn "Domain was previously mounted to: $_prev_active"
            echo -e "  To restore it: ${BOLD}wt-link mount --cwd $_prev_active${RESET}"
            echo ""
        fi
    ' ERR
    _mount_validate
    _mount_herd_link
    _mount_herd_subdomains
    _mount_wp_core
    _mount_wp_config
    _mount_plugins
    _mount_uploads
    _mount_mu_plugin
    _mount_eightshift_pkgs
    _mount_verify
    trap - ERR
}
