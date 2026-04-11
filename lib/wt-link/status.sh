# shellcheck shell=bash
# status.sh — cmd_status for wt-link.
# Globals used: SITE_NAME, WORKTREE_ROOT, WP_CONTENT, STATE_FILE,
#   REGISTRY_FILE, WP_CORE_MARKER, BOLD, GREEN, YELLOW, RED, RESET
#   (set by bin/wt-link before dispatch)

cmd_status() {
    echo ""
    echo -e "${BOLD}Worktree Link Status${RESET}"
    echo "  Worktree : $WORKTREE_ROOT"
    echo "  Site name: $SITE_NAME"
    echo ""

    local herd_link="$HOME/Library/Application Support/Herd/config/valet/Sites/$SITE_NAME"

    echo -e "${BOLD}Herd:${RESET}"
    if [[ -L "$herd_link" ]]; then
        local target
        target="$(readlink "$herd_link")"
        if [[ "$target" == "$WORKTREE_ROOT" ]]; then
            echo -e "  ${GREEN}✓ herd link points HERE (this worktree)${RESET}"
        else
            echo -e "  ${YELLOW}⚠ herd link points to: $target${RESET}"
        fi
    else
        echo -e "  ${RED}✗ no herd link found${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Registry ($SITE_NAME):${RESET}"
    local reg_canonical reg_active
    reg_canonical="$(registry_get canonical)"
    reg_active="$(registry_get active)"
    if [[ -f "$REGISTRY_FILE" ]]; then
        echo -e "  canonical : ${reg_canonical:-${YELLOW}(not set)${RESET}}"
        if [[ -z "$reg_active" ]]; then
            echo -e "  active    : ${GREEN}(none — canonical is live)${RESET}"
        elif [[ "$reg_active" == "$WORKTREE_ROOT" ]]; then
            echo -e "  active    : ${GREEN}THIS worktree${RESET}"
        else
            echo -e "  active    : ${YELLOW}$reg_active${RESET}"
        fi
    else
        echo -e "  ${YELLOW}⚠ no registry file (no worktree has been mounted yet for $SITE_NAME)${RESET}"
    fi

    echo ""
    echo -e "${BOLD}WordPress core:${RESET}"
    if [[ -f "$WP_CORE_MARKER" ]]; then
        local _wpcv
        _wpcv="$(wp_clean core version --path="$WORKTREE_ROOT" || true)"
        echo -e "  ${GREEN}✓ present ($_wpcv)${RESET}"
    else
        echo -e "  ${RED}✗ not installed${RESET}"
    fi

    echo ""
    echo -e "${BOLD}wp-config.php:${RESET}"
    if [[ -f "$WORKTREE_ROOT/wp-config.php" ]]; then
        echo -e "  ${GREEN}✓ present${RESET}"
    else
        echo -e "  ${RED}✗ missing${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Eightshift packages:${RESET}"
    for pkg in $(find_eightshift_packages); do
        local pkg_name
        pkg_name="$(basename "$pkg")"
        local pkg_type="package"
        [[ "$pkg" == *"/themes/"* ]] && pkg_type="theme"
        [[ "$pkg" == *"/plugins/"* ]] && pkg_type="plugin"

        local vendor_ok="-" node_ok="-" build_ok="-"
        [[ -f "$pkg/vendor/autoload.php" ]] && vendor_ok="${GREEN}✓${RESET}" || vendor_ok="${RED}✗${RESET}"
        [[ -d "$pkg/node_modules" ]] && node_ok="${GREEN}✓${RESET}" || node_ok="${RED}✗${RESET}"
        [[ -f "$pkg/public/manifest.json" ]] && build_ok="${GREEN}✓${RESET}" || build_ok="${RED}✗${RESET}"
        local pm_detected
        pm_detected="$(detect_package_manager "$pkg")"

        echo -e "  [$pkg_type] $pkg_name  pm:$pm_detected  vendor:$vendor_ok  node_modules:$node_ok  build:$build_ok"
    done

    echo ""
    echo -e "${BOLD}Untracked plugins:${RESET}"
    local plugin_count=0
    if [[ -d "$WP_CONTENT/plugins" ]]; then
        local canonical_plugins="$CANONICAL_WP_CONTENT/plugins"
        for entry in "$WP_CONTENT/plugins"/*; do
            local entry_name
            entry_name="$(basename "$entry")"
            [[ -e "$canonical_plugins/$entry_name" || -L "$canonical_plugins/$entry_name" ]] || continue
            { [[ -L "$entry" ]] || [[ -d "$entry" ]]; } && plugin_count=$((plugin_count + 1))
        done
    fi
    echo "  $plugin_count copied"

    echo ""
    echo -e "${BOLD}State file:${RESET}"
    if [[ -f "$STATE_FILE" ]]; then
        echo -e "  ${GREEN}✓ present${RESET} ($STATE_FILE)"
    else
        echo -e "  ${YELLOW}⚠ not found (was mount ever run?)${RESET}"
    fi
    echo ""
}
