# shellcheck shell=bash
# rebuild.sh — cmd_rebuild_composer and cmd_rebuild_node for wt-link.
# Globals used: CANONICAL_WP_CONTENT (set by bin/wt-link before dispatch)

cmd_rebuild_composer() {
    require_cmd composer

    local packages
    mapfile -t packages < <(find_eightshift_packages)

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No Eightshift packages found"
        exit 0
    fi

    log "Rebuilding composer deps for ${#packages[@]} package(s)"
    echo ""

    for pkg in "${packages[@]}"; do
        local pkg_name
        pkg_name="$(basename "$pkg")"
        local pkg_type="package"
        [[ "$pkg" == *"/themes/"* ]] && pkg_type="theme"
        [[ "$pkg" == *"/plugins/"* ]] && pkg_type="plugin"

        [[ "$pkg_type" == "plugin" ]] && continue

        log "  [$pkg_type] $pkg_name"

        # Resolve canonical package path for hardlink-copy fallback
        local canonical_pkg=""
        if [[ "$pkg_type" == "theme" ]]; then
            canonical_pkg="$CANONICAL_WP_CONTENT/themes/$pkg_name"
        elif [[ "$pkg_type" == "plugin" ]]; then
            canonical_pkg="$CANONICAL_WP_CONTENT/plugins/$pkg_name"
        fi

        for vendor_dir in vendor vendor-prefixed; do
            local dest="$pkg/$vendor_dir"
            if [[ -L "$dest" || -d "$dest" ]]; then
                step "  Removing $vendor_dir/…"
                rm -rf "$dest"
                success "  $vendor_dir/ removed"
            fi
        done

        # Re-copy from canonical (hardlink) or composer install
        local rebuilt=0
        for vendor_dir in vendor vendor-prefixed; do
            local dest="$pkg/$vendor_dir"
            local src="$canonical_pkg/$vendor_dir"
            if [[ -d "$src" ]]; then
                run_with_spinner "  $vendor_dir/: hardlink copy from canonical…" \
                    cp -Rl "$src" "$dest" \
                    || { warn "  $vendor_dir/: hardlink copy failed"; continue; }
                success "  $vendor_dir/: hardlink copy done"
                [[ "$vendor_dir" == "vendor" ]] && rebuilt=1
            fi
        done

        if [[ $rebuilt -eq 0 ]]; then
            run_with_spinner "  composer install…" \
                composer install --no-interaction --working-dir="$pkg" 2>/dev/null \
                || warn "  composer install had warnings"
            success "  composer install done"
        fi
    done

    echo ""
    success "Composer rebuild complete"
}

cmd_rebuild_node() {
    local packages
    mapfile -t packages < <(find_eightshift_packages)

    if [[ ${#packages[@]} -eq 0 ]]; then
        warn "No Eightshift packages found"
        exit 0
    fi

    log "Rebuilding node deps + assets for ${#packages[@]} package(s)"
    echo ""

    for pkg in "${packages[@]}"; do
        local pkg_name
        pkg_name="$(basename "$pkg")"
        local pkg_type="package"
        [[ "$pkg" == *"/themes/"* ]] && pkg_type="theme"
        [[ "$pkg" == *"/plugins/"* ]] && pkg_type="plugin"

        [[ "$pkg_type" == "plugin" ]] && continue

        log "  [$pkg_type] $pkg_name"

        # Remove node_modules
        local node_modules="$pkg/node_modules"
        if [[ -L "$node_modules" || -d "$node_modules" ]]; then
            step "  Removing node_modules/…"
            rm -rf "$node_modules"
            success "  node_modules/ removed"
        fi

        # Remove public/
        local public_dir="$pkg/public"
        if [[ -d "$public_dir" ]]; then
            step "  Removing public/…"
            rm -rf "$public_dir"
            success "  public/ removed"
        fi

        local pm
        pm="$(detect_package_manager "$pkg")"
        require_pm "$pm"

        run_with_spinner "  $pm install…" \
            run_pm_install "$pm" "$pkg" \
            || warn "  $pm install had warnings"
        success "  node_modules: installed via $pm"

        run_with_spinner "  $pm run build…" \
            run_pm_build "$pm" "$pkg" \
            || warn "  build had errors — check manually"
        success "  build: done"
    done

    echo ""
    success "Node rebuild complete"
}
