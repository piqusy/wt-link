#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_FILE="$ROOT_DIR/lib/wt-link/mount.sh"

expected_line='            run_with_spinner "Downloading WordPress ${WP_VERSION}…" \'
grep -Fq "$expected_line" "$MOUNT_FILE" || {
    echo "Expected braced WP_VERSION in download spinner message"
    exit 1
}

if grep -R -n -E '\$[A-Za-z_][A-Za-z0-9_]*…' "$ROOT_DIR/bin" "$ROOT_DIR/lib" >/dev/null; then
    echo "Found unsafe shell variable interpolation before a Unicode ellipsis"
    grep -R -n -E '\$[A-Za-z_][A-Za-z0-9_]*…' "$ROOT_DIR/bin" "$ROOT_DIR/lib"
    exit 1
fi

output="$(bash -u -c 'WP_VERSION=6.8.5; printf "%s\n" "Downloading WordPress ${WP_VERSION}…"')"
[[ "$output" == "Downloading WordPress 6.8.5…" ]] || {
    echo "Unexpected expansion output: $output"
    exit 1
}

echo "PASS: braced variable interpolation stays safe under set -u"
