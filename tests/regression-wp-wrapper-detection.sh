#!/usr/bin/env bash
set -euo pipefail

# Regression: wrappers can ignore WP_CLI_PHP_ARGS, and PHP launchers can
# override both PHPRC and PHP_INI_SCAN_DIR. WP-CLI must raise the limit after
# PHP has loaded its configuration and before it runs the download command.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_FILE="$ROOT_DIR/lib/wt-link/mount.sh"

error() { echo "$*" >&2; exit 1; }
# shellcheck source=../lib/wt-link/utils.sh
source "$ROOT_DIR/lib/wt-link/utils.sh"

fake_bin="$(mktemp -d)"
ini_dir="$(mktemp -d)"
trap 'rm -rf "$fake_bin" "$ini_dir"' EXIT

# Model a wrapper that ignores WP_CLI_PHP_ARGS and a PHP configuration that
# sets a lower limit. Emulate WP-CLI loading the --require file before running
# a command, including on PHP launchers that replace PHP_INI_SCAN_DIR.
cat > "$fake_bin/wp" <<'EOF'
#!/usr/bin/env bash
case "$1" in --require=*) required_file="${1#--require=}" ;; *) exit 1 ;; esac
php -d memory_limit=128M -d precision=13 -r 'require $argv[1]; echo ini_get("memory_limit") . " " . ini_get("precision");' "$required_file"
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
    *--require=*) ;;
    *)
        echo "FAIL: expected wp_download_cmd to load the memory override before the command"
        exit 1
        ;;
esac

[[ -f "$ini_dir/memory-limit.php" ]] || error "FAIL: expected wp_download_cmd to write a memory override"

reported="$(bash -c "$cmd")"
[[ "$reported" == "512M 13" ]] || error "FAIL: wrapper's php process did not apply the raised memory_limit and retain existing settings (got '$reported')"

# Mount must verify core actually landed, regardless of invocation path
if ! grep -Fq 'WP_CORE_MARKER" ]] || error' "$MOUNT_FILE"; then
    echo "FAIL: mount no longer asserts wp-load.php exists after core download"
    exit 1
fi

echo "PASS: wp_download_cmd raises memory_limit before the command, surviving wrappers and PHP configuration overrides"
