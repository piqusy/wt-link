#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_FILE="$ROOT_DIR/lib/wt-link/mount.sh"
RUNTIME_FILE="$ROOT_DIR/lib/wt-link/runtime.sh"

if ! grep -Fq "php -d memory_limit=" "$MOUNT_FILE"; then
    echo "Expected wp fallback download to raise PHP memory_limit"
    exit 1
fi

if grep -F "core download --path=" "$MOUNT_FILE" | grep -Fq "2>/dev/null"; then
    echo "wp fallback download still hides WP-CLI stderr"
    exit 1
fi

if ! grep -Fq 'tail -20 "$tmp_out"' "$RUNTIME_FILE"; then
    echo "Expected spinner failure output to keep the last 20 lines"
    exit 1
fi

echo "PASS: wp fallback download keeps memory headroom and preserves diagnostics"
