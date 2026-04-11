# shellcheck shell=bash
# mount.sh — cmd_mount and its 8 private sub-functions for wt-link.
# Globals used: SITE_NAME, WORKTREE_ROOT, CANONICAL_SITE, WP_CONTENT,
#   CANONICAL_WP_CONTENT, WP_VERSION, STATE_FILE, REGISTRY_FILE, REGISTRY_DIR,
#   WP_CORE_MARKER, FORCE, BOLD, RESET (set by bin/wt-link before dispatch)

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

    # Ensure state file always exists after mount (even if everything was already present)
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
        echo ""
        warn "Domain ${BOLD}$SITE_NAME.test${RESET} is currently mounted to another worktree:"
        echo -e "  Active: $reg_active"
        echo ""
        if [[ $FORCE -eq 1 ]]; then
            warn "  --force: switching domain to this worktree"
        else
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
}

_mount_plugins() {
    step "Hard-copying untracked plugins from canonical site..."
    local copied_count=0
    while IFS= read -r plugin_path; do
        [[ -z "$plugin_path" ]] && continue
        local plugin_name
        plugin_name="$(basename "$plugin_path")"
        local dest="$WP_CONTENT/plugins/$plugin_name"

        if [[ -e "$dest" || -L "$dest" ]]; then
            : # already present (tracked in git, previously copied, or symlinked)
        else
            # Resolve symlinks in canonical before hardlink-copying
            local real_src
            real_src="$(realpath "$plugin_path" 2>/dev/null || echo "$plugin_path")"
            if [[ -d "$real_src" ]]; then
                cp -Rl "$real_src" "$dest" \
                    || { warn "  Failed to copy $plugin_name — skipping"; continue; }
            elif [[ -f "$real_src" ]]; then
                cp -l "$real_src" "$dest" \
                    || { warn "  Failed to copy $plugin_name — skipping"; continue; }
            else
                warn "  $plugin_name — source not found, skipping"
                continue
            fi
            echo "    copied: $plugin_name"
            copied_count=$((copied_count + 1))
        fi
    done < <(find_untracked_plugins)
    success "Plugins: $copied_count newly copied"
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

_mount_eightshift_pkgs() {
    local packages
    mapfile -t packages < <(find_eightshift_packages)

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No Eightshift packages found"
    fi

    for pkg in "${packages[@]}"; do
        local pkg_name
        pkg_name="$(basename "$pkg")"
        # Determine if pkg is a theme or plugin
        local pkg_type="package"
        [[ "$pkg" == *"/themes/"* ]] && pkg_type="theme"
        [[ "$pkg" == *"/plugins/"* ]] && pkg_type="plugin"

        log "Setting up $pkg_type: $pkg_name"

        # Resolve canonical package path for vendor symlinking
        local canonical_pkg=""
        if [[ "$pkg_type" == "theme" ]]; then
            canonical_pkg="$CANONICAL_WP_CONTENT/themes/$pkg_name"
        elif [[ "$pkg_type" == "plugin" ]]; then
            canonical_pkg="$CANONICAL_WP_CONTENT/plugins/$pkg_name"
        fi

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

        # node_modules — always rebuild so the worktree gets its own fresh deps
        local pm
        pm="$(detect_package_manager "$pkg")"
        require_pm "$pm"
        local node_modules_dest="$pkg/node_modules"
        [[ -L "$node_modules_dest" ]] && rm "$node_modules_dest"
        run_with_spinner "  $pm install…" \
            run_pm_install "$pm" "$pkg" || warn "  $pm install had warnings"
        success "  node_modules: installed via $pm"

        # build — always run for themes; plugins ship pre-built
        if [[ "$pkg_type" == "theme" ]]; then
            run_with_spinner "  $pm run build…" \
                run_pm_build "$pm" "$pkg" || warn "  build had errors — check manually"
            state_set "public_built_$pkg_name" "1"
            success "  build: done"
        else
            success "  build: skipped (plugin)"
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
    _mount_validate
    _mount_herd_link
    _mount_wp_core
    _mount_wp_config
    _mount_plugins
    _mount_uploads
    _mount_eightshift_pkgs
    _mount_verify
}
