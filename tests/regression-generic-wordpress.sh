#!/usr/bin/env bash
set -euo pipefail

# Regression: standard WordPress sites without an Eightshift package must mount
# without Composer. Composer is only needed when an Eightshift package has no
# reusable vendor directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rmdir "$tmp_dir/wp-content/themes/plain-theme" "$tmp_dir/wp-content/themes" "$tmp_dir/wp-content" "$tmp_dir"' EXIT

# shellcheck source=../lib/wt-link/project.sh
source "$ROOT_DIR/lib/wt-link/project.sh"
# shellcheck source=../lib/wt-link/mount.sh
source "$ROOT_DIR/lib/wt-link/mount.sh"

WP_CONTENT="$tmp_dir/wp-content"
mkdir -p "$WP_CONTENT/themes/plain-theme"

warn() { :; }
require_cmd() {
    echo "FAIL: generic WordPress project unexpectedly required $1" >&2
    exit 1
}

_mount_eightshift_pkgs

echo "PASS: generic WordPress project skips Eightshift and Composer setup"
