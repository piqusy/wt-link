# shellcheck shell=bash
# unmount.sh — cmd_unmount for wt-link.
# Globals used: SITE_NAME, WORKTREE_ROOT, CANONICAL_SITE, WP_CONTENT,
#   STATE_FILE, REGISTRY_FILE, REGISTRY_DIR (set by bin/wt-link before dispatch)

cmd_unmount() {
    require_cmd herd

    local has_state=0
    [[ -f "$STATE_FILE" ]] && has_state=1

    if [[ $has_state -eq 0 ]]; then
        warn "No state file found — proceeding with best-effort cleanup (WP core and wp-config.php will NOT be removed)"
        echo ""
    fi

    log "Unmounting worktree: $WORKTREE_ROOT"
    echo "  Canonical: $CANONICAL_SITE"
    echo ""

    # 1. Herd unlink ─────────────────────────────────────────────────────────────
    local reg_active restored_domain=""
    reg_active="$(registry_get active)"

    if [[ -n "$reg_active" && "$reg_active" != "$WORKTREE_ROOT" ]]; then
        # Another worktree currently owns the domain — skip Herd restore, only clean local files
        warn "Domain $SITE_NAME.test is owned by another worktree — skipping Herd restore"
        echo -e "  Active owner: $reg_active"
    else
        # This worktree owns the domain (or there's no registry) — restore canonical
        local canonical_target
        canonical_target="$(registry_get canonical)"
        # Fallback chain: registry canonical → CANONICAL_SITE env → bare unlink
        if [[ -n "$canonical_target" && -d "$canonical_target" ]]; then
            run_with_spinner "Restoring $SITE_NAME.test to canonical via Herd…" \
                bash -c "cd '$canonical_target' && herd link '$SITE_NAME'" \
                || warn "herd link restore failed — canonical may not be live"
            success "herd link restored to canonical: $canonical_target"
            restored_domain="$SITE_NAME.test"
        elif [[ -d "$CANONICAL_SITE" ]]; then
            run_with_spinner "Restoring $SITE_NAME.test to canonical via Herd…" \
                bash -c "cd '$CANONICAL_SITE' && herd link '$SITE_NAME'" \
                || warn "herd link restore failed — canonical may not be live"
            success "herd link restored to canonical: $CANONICAL_SITE"
            restored_domain="$SITE_NAME.test"
        else
            herd unlink "$SITE_NAME" 2>/dev/null || warn "herd unlink had errors"
            success "herd unlink done"
        fi
        registry_clear_active
    fi


    # 2. Remove uploads symlink ──────────────────────────────────────────────────
    local uploads_dest="$WP_CONTENT/uploads"
    if [[ -L "$uploads_dest" ]]; then
        rm "$uploads_dest"
        success "uploads symlink removed"
    fi

    # 3. Remove untracked plugins (symlinks by default; hard-copy dirs when --hard-copy was used) ──
    local plugins_dir="$WP_CONTENT/plugins"
    local removed_plugins=0
    if [[ -d "$plugins_dir" ]]; then
        local canonical_plugins="$CANONICAL_WP_CONTENT/plugins"
        for entry in "$plugins_dir"/*; do
            local entry_name
            entry_name="$(basename "$entry")"
            # Only remove if the same name exists in canonical (i.e. it was linked/copied from there)
            [[ -e "$canonical_plugins/$entry_name" || -L "$canonical_plugins/$entry_name" ]] || continue
            # Remove symlinks (default mount) and hard-copy dirs (--hard-copy mount)
            # Skip real git-tracked directories that have no corresponding state key
            if [[ -L "$entry" ]]; then
                rm "$entry"
                removed_plugins=$((removed_plugins + 1))
            elif [[ -d "$entry" && $has_state -eq 1 ]]; then
                # Only remove dirs that mount actually created (legacy hard-copy or explicit --hard-copy)
                if [[ "$(state_get "plugin_copied_$entry_name")" == "1" ]]; then
                    rm -rf "$entry"
                    removed_plugins=$((removed_plugins + 1))
                fi
            fi
        done
    fi
    success "Removed $removed_plugins plugin copies/links"

    # 4. Remove vendor/, node_modules, and built public/ from Eightshift packages ─
    for pkg in $(find_eightshift_packages); do
        local pkg_basename
        pkg_basename="$(basename "$pkg")"
        for vendor_dir in vendor vendor-prefixed; do
            local vendor_dest="$pkg/$vendor_dir"
            if [[ -L "$vendor_dest" ]]; then
                rm "$vendor_dest"
                success "  $vendor_dir/ symlink removed: $pkg_basename"
            elif [[ -d "$vendor_dest" && $has_state -eq 1 && "$(state_get "vendor_copied_${pkg_basename}_${vendor_dir}")" == "1" ]]; then
                rm -rf "$vendor_dest"
                success "  $vendor_dir/ removed: $pkg_basename"
            fi
        done
        local node_modules_dest="$pkg/node_modules"
        if [[ -L "$node_modules_dest" || -d "$node_modules_dest" ]]; then
            rm -rf "$node_modules_dest"
            success "  node_modules removed: $pkg_basename"
        fi
        # Remove public/ if mount built it (state key present)
        if [[ $has_state -eq 1 && "$(state_get "public_built_$pkg_basename")" == "1" ]]; then
            local public_dest="$pkg/public"
            if [[ -d "$public_dest" ]]; then
                rm -rf "$public_dest"
                success "  public/ removed: $pkg_basename"
            fi
        fi
    done

    # 5. Remove WP core files — only if this script installed them ───────────────
    if [[ $has_state -eq 1 && "$(state_get wp_core_installed)" == "1" ]]; then
        step "Removing WP core files..."
        for d in wp-admin wp-includes; do
            [[ -d "$WORKTREE_ROOT/$d" ]] && rm -rf "${WORKTREE_ROOT:?}/$d"
        done
        local wp_root_files=(
            index.php wp-activate.php wp-blog-header.php wp-comments-post.php
            wp-cron.php wp-links-opml.php wp-load.php wp-login.php wp-mail.php
            wp-settings.php wp-signup.php wp-trackback.php xmlrpc.php
            wp-config-sample.php license.txt readme.html
        )
        for f in "${wp_root_files[@]}"; do
            [[ -f "$WORKTREE_ROOT/$f" ]] && rm "$WORKTREE_ROOT/$f"
        done
        success "WP core files removed"
    elif [[ $has_state -eq 0 ]]; then
        warn "WP core files left in place (no state file — manual cleanup required if needed)"
    fi

    # 6. Remove wp-config.php if we created it ───────────────────────────────────
    if [[ $has_state -eq 1 && "$(state_get wp_config_copied)" == "1" ]]; then
        rm -f "$WORKTREE_ROOT/wp-config.php"
        success "wp-config.php removed"
    elif [[ $has_state -eq 0 ]]; then
        warn "wp-config.php left in place (no state file — remove manually if needed)"
    fi

    # 7. Clean up state file ─────────────────────────────────────────────────────
    rm -f "$STATE_FILE"
    success "State file cleaned up"

    # Verify domain (Herd was triggered at step 1 — should be live by now) ───────
    if [[ -n "$restored_domain" ]]; then
        wait_for_herd "$restored_domain" 10
    fi

    echo ""
    success "Unmount complete. Canonical site restored at https://$SITE_NAME.test/"
}
