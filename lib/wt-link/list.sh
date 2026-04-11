# shellcheck shell=bash
# list.sh — cmd_list for wt-link.
# Globals used: REGISTRY_DIR (set by bin/wt-link before dispatch)

cmd_list() {
    local dir="$REGISTRY_DIR"
    if [[ ! -d "$dir" ]]; then
        warn "No registry found at $dir"
        return 0
    fi

    local any=0
    for f in "$dir"/*.active; do
        [[ -f "$f" ]] && { any=1; break; }
    done

    if [[ $any -eq 0 ]]; then
        warn "No sites registered yet. Run 'wt-link mount' in a worktree first."
        return 0
    fi

    printf "%-20s  %-45s  %s\n" "SITE" "ACTIVE WORKTREE" "DOMAIN"
    printf "%-20s  %-45s  %s\n" \
        "────────────────────" \
        "─────────────────────────────────────────────" \
        "──────────────────"

    for f in "$dir"/*.active; do
        [[ -f "$f" ]] || continue
        local site active domain indicator
        site="$(basename "$f" .active)"
        active="$(grep "^active=" "$f" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
        domain="$site.test"
        indicator=""
        [[ -n "$active" ]] && indicator=" ●"
        printf "%-20s  %-45s  %s%s\n" \
            "$site" \
            "${active:-(none)}" \
            "$domain" \
            "$indicator"
    done
}
