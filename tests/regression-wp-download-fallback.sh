#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_FILE="$ROOT_DIR/lib/wt-link/mount.sh"
RUNTIME_FILE="$ROOT_DIR/lib/wt-link/runtime.sh"
UTILS_FILE="$ROOT_DIR/lib/wt-link/utils.sh"

if ! grep -Fq "memory_limit=" "$UTILS_FILE"; then
    echo "Expected wp download invocation to raise PHP memory_limit"
    exit 1
fi

if ! grep -Fq 'wp_download_cmd' "$MOUNT_FILE"; then
    echo "Expected wp fallback download to build its invocation via wp_download_cmd"
    exit 1
fi

if grep -F "core download --path=" "$MOUNT_FILE" | grep -Fq "2>/dev/null"; then
    echo "wp fallback download still hides WP-CLI stderr"
    exit 1
fi

if ! grep -Fq 'wp_cache_zip' "$MOUNT_FILE" || ! grep -Fq "unzip -q" "$MOUNT_FILE"; then
    echo "Expected cached WordPress zip archives to be extracted before downloading"
    exit 1
fi

if ! grep -Fq 'tail -20 "$tmp_out"' "$RUNTIME_FILE"; then
    echo "Expected spinner failure output to keep the last 20 lines"
    exit 1
fi

echo "PASS: wp fallback download keeps memory headroom and preserves diagnostics"
