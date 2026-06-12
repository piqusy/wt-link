#!/usr/bin/env bash
set -euo pipefail

# Regression: `command -v wp` resolving to a bash wrapper around wp-cli must
# not be invoked as `php <wrapper>` — PHP prints the wrapper text verbatim and
# exits 0, so core download silently produces nothing and mount reports
# success on an empty worktree (Herd then 404s).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_FILE="$ROOT_DIR/lib/wt-link/mount.sh"

error() { echo "$*" >&2; exit 1; }
# shellcheck source=../lib/wt-link/utils.sh
source "$ROOT_DIR/lib/wt-link/utils.sh"

fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

# Case 1: wp is a bash wrapper — must be invoked directly, never via php
cat > "$fake_bin/wp" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/true "$@"
EOF
chmod +x "$fake_bin/wp"

cmd="$(PATH="$fake_bin:$PATH" wp_download_cmd 512M)"
case "$cmd" in
    php\ *)
        echo "FAIL: bash wrapper wp would be executed via php (silent no-op)"
        exit 1
        ;;
esac

# Case 2: wp is a PHP script/phar — php -d memory_limit prefix must be kept
cat > "$fake_bin/wp" <<'EOF'
#!/usr/bin/env php
<?php exit(0);
EOF
chmod +x "$fake_bin/wp"

cmd="$(PATH="$fake_bin:$PATH" wp_download_cmd 512M)"
case "$cmd" in
    php\ -d\ memory_limit=512M*) ;;
    *)
        echo "FAIL: PHP wp-cli no longer gets the raised memory_limit prefix"
        exit 1
        ;;
esac

# Mount must verify core actually landed, regardless of invocation path
if ! grep -Fq 'WP_CORE_MARKER" ]] || error' "$MOUNT_FILE"; then
    echo "FAIL: mount no longer asserts wp-load.php exists after core download"
    exit 1
fi

echo "PASS: wrapper wp invoked directly, php wp keeps memory prefix, mount asserts core landed"
