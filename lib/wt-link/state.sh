# shellcheck shell=bash
# state.sh — Per-worktree state file and global registry helpers for wt-link.
# Globals used: STATE_FILE, REGISTRY_FILE, REGISTRY_DIR (set by bin/wt-link before dispatch)

state_set() { echo "$1=$2" >> "$STATE_FILE"; }
state_get() { grep "^$1=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true; }

registry_get() {
    grep "^$1=" "$REGISTRY_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

registry_set() {
    mkdir -p "$REGISTRY_DIR"
    # Remove existing key then append new value (in-place update without sed -i portability issues)
    if [[ -f "$REGISTRY_FILE" ]]; then
        local tmp
        tmp="$(grep -v "^$1=" "$REGISTRY_FILE" || true)"
        echo "$tmp" > "$REGISTRY_FILE"
    fi
    echo "$1=$2" >> "$REGISTRY_FILE"
}

registry_clear_active() {
    [[ -f "$REGISTRY_FILE" ]] || return 0
    local tmp
    tmp="$(grep -v "^active=" "$REGISTRY_FILE" || true)"
    echo "$tmp" > "$REGISTRY_FILE"
}

registry_clear() {
    rm -f "$REGISTRY_FILE"
}
