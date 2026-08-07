#!/usr/bin/env bash
set -euo pipefail

# Regression: when setup.json has no `core` key and wp-cli cannot infer a
# version (no wp-load.php anywhere yet), wt-link falls back to parsing the
# WordPress version off the canonical site's Dockerfile base image tag.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# shellcheck source=../lib/wt-link/utils.sh
source "$ROOT_DIR/lib/wt-link/utils.sh"

cat > "$tmp_dir/Dockerfile" <<'EOF'
FROM wordpress:7.0.2-php8.4-fpm

WORKDIR /usr/src/wordpress
EOF

version="$(infer_wp_core_version_from_dockerfile "$tmp_dir")"
[[ "$version" == "7.0.2" ]] || {
    echo "FAIL: expected 7.0.2, got '$version'" >&2
    exit 1
}

# No Dockerfile at all — should fail rather than echo garbage.
if infer_wp_core_version_from_dockerfile "$tmp_dir/does-not-exist" &>/dev/null; then
    echo "FAIL: expected failure when Dockerfile is missing" >&2
    exit 1
fi

# Dockerfile without a `FROM wordpress:` line — should fail, not match unrelated stages.
cat > "$tmp_dir/Dockerfile" <<'EOF'
FROM node:20 AS builder
FROM php:8.4-fpm
EOF
if infer_wp_core_version_from_dockerfile "$tmp_dir" &>/dev/null; then
    echo "FAIL: expected failure when no FROM wordpress: line is present" >&2
    exit 1
fi

if ! grep -Fq 'infer_wp_core_version_from_dockerfile' "$ROOT_DIR/bin/wt-link"; then
    echo "FAIL: expected bin/wt-link to wire up the Dockerfile fallback"
    exit 1
fi

echo "PASS: WP version falls back to the canonical Dockerfile's base image tag"
