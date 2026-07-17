#!/usr/bin/env bash
set -euo pipefail

# Regression: unmount must select the registry's active worktree rather than
# cleaning the canonical site or an inactive sibling used to invoke the command.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT_LINK="$ROOT_DIR/bin/wt-link"

sandbox="$(mktemp -d)"
fake_bin="$sandbox/bin"
mkdir -p "$fake_bin"
trap 'rm -rf "$sandbox"' EXIT

cat > "$fake_bin/herd" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$PWD" "$*" >> "$HERD_LOG"
EOF
chmod +x "$fake_bin/herd"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '200'
EOF
chmod +x "$fake_bin/curl"

error() { echo "FAIL: $*" >&2; exit 1; }

run_case() {
    local invocation="$1"
    local fixture="$sandbox/$invocation"
    local canonical="$fixture/canonical"
    local active="$fixture/active"
    local inactive="$fixture/inactive"
    local home="$fixture/home"
    local herd_log="$fixture/herd.log"

    mkdir -p "$canonical/wp-content"
    git init -q "$canonical"
    git -C "$canonical" config user.email wt-link@example.test
    git -C "$canonical" config user.name wt-link
    printf '%s\n' '{"urls":{"local":"https://demo.test/"}}' > "$canonical/setup.json"
    git -C "$canonical" add setup.json wp-content
    git -C "$canonical" commit -qm initial
    git -C "$canonical" worktree add -q -b active "$active"
    git -C "$canonical" worktree add -q -b inactive "$inactive"

    touch "$canonical/wp-config.php" "$inactive/wp-config.php" "$active/wp-config.php"
    mkdir -p "$home/.config/wt-link"
    printf 'active=%s\ncanonical=%s\n' "$active" "$canonical" > "$home/.config/wt-link/demo.active"
    printf 'wp_config_copied=1\n' > "$home/.config/wt-link/demo.active.state"

    local current="$canonical"
    [[ "$invocation" == "inactive" ]] && current="$inactive"
    local output
    output="$(HOME="$home" CANONICAL_SITE="$canonical" HERD_LOG="$herd_log" PATH="$fake_bin:$PATH" "$WT_LINK" unmount --cwd "$current")"

    [[ "$output" == *"Unmounting worktree: $active"* ]] || error "$invocation invocation did not select the active worktree"
    [[ ! -e "$active/wp-config.php" ]] || error "$invocation invocation left active worktree cleanup behind"
    [[ -e "$canonical/wp-config.php" ]] || error "$invocation invocation modified canonical wp-config.php"
    [[ -e "$inactive/wp-config.php" ]] || error "$invocation invocation modified inactive worktree wp-config.php"
    [[ ! -e "$home/.config/wt-link/demo.active.state" ]] || error "$invocation invocation left active state behind"
    grep -Fqx "$canonical link demo" "$herd_log" >/dev/null || error "$invocation invocation did not restore Herd from canonical site"
}

run_case canonical
run_case inactive

echo "PASS: unmount selects the active worktree from canonical and inactive sibling directories"
