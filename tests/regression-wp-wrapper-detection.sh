#!/usr/bin/env bash
set -euo pipefail

# Regression: `command -v wp` resolving to a custom wrapper (e.g. a
# deprecation-suppressing shim that execs php directly) must still receive
# the raised PHP memory limit. WP_CLI_PHP_ARGS is only honored by the
# official wp-cli launcher script — a wrapper that execs php itself silently
# drops it, leaving the default 128M limit and failing PharData extraction
# on larger core tarballs. PHPRC is read by the php binary itself regardless
# of the wrapper, so wp_download_cmd must use that instead.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_FILE="$ROOT_DIR/lib/wt-link/mount.sh"

error() { echo "$*" >&2; exit 1; }
# shellcheck source=../lib/wt-link/utils.sh
source "$ROOT_DIR/lib/wt-link/utils.sh"

fake_bin="$(mktemp -d)"
ini_dir="$(mktemp -d)"
trap 'rm -rf "$fake_bin" "$ini_dir"' EXIT

# A wrapper that ignores WP_CLI_PHP_ARGS entirely (like a real-world
# deprecation-suppressing shim would) but still honors PHPRC, since that is
# read by the php binary itself, not forwarded by the wrapper.
cat > "$fake_bin/wp" <<'EOF'
#!/usr/bin/env bash
php -r 'echo ini_get("memory_limit");'
EOF
chmod +x "$fake_bin/wp"

cmd="$(PATH="$fake_bin:$PATH" wp_download_cmd 512M "$ini_dir")"

case "$cmd" in
    php\ *)
        echo "FAIL: wrapper wp would be executed via php (silent no-op)"
        exit 1
        ;;
esac

case "$cmd" in
    *PHPRC=*) ;;
    *)
        echo "FAIL: expected wp_download_cmd to set PHPRC so the limit survives wrapper scripts"
        exit 1
        ;;
esac

[[ -f "$ini_dir/php.ini" ]] || error "FAIL: expected wp_download_cmd to write a php.ini into ini_dir"
grep -Fq "memory_limit = 512M" "$ini_dir/php.ini" || error "FAIL: php.ini does not raise memory_limit"

reported="$(bash -c "$cmd")"
[[ "$reported" == "512M" ]] || error "FAIL: wrapper's php process did not see the raised memory_limit (got '$reported')"

# Mount must verify core actually landed, regardless of invocation path
if ! grep -Fq 'WP_CORE_MARKER" ]] || error' "$MOUNT_FILE"; then
    echo "FAIL: mount no longer asserts wp-load.php exists after core download"
    exit 1
fi

echo "PASS: wp_download_cmd raises memory_limit via PHPRC, surviving wrapper scripts that drop WP_CLI_PHP_ARGS"
