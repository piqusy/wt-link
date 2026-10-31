#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'find "$tmp_dir" -depth -delete' EXIT

source "$ROOT_DIR/lib/wt-link/utils.sh"
source "$ROOT_DIR/lib/wt-link/mount.sh"

plugin_source="$tmp_dir/canonical/wp-content/plugins/example-plugin"
WP_CONTENT="$tmp_dir/worktree/wp-content"
# shellcheck disable=SC2034
LIB_DIR="$ROOT_DIR/lib/wt-link" HARD_COPY=1
state_file="$tmp_dir/state"
mkdir -p "$plugin_source" "$WP_CONTENT/plugins"
printf 'canonical version\n' > "$plugin_source/plugin.php"

find_untracked_plugins() { printf '%s\n' "$plugin_source"; }
run_with_spinner() { shift; "$@"; }
success() { :; }
step() { :; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
state_set() { printf '%s=%s\n' "$1" "$2" >> "$state_file"; }

_mount_plugins

plugin_copy="$WP_CONTENT/plugins/example-plugin/plugin.php"
[[ -f "$plugin_copy" ]]
[[ ! "$plugin_source/plugin.php" -ef "$plugin_copy" ]]
[[ "$(cat "$plugin_copy")" == 'canonical version' ]]
grep -q '^plugin_copied_example-plugin=1$' "$state_file"

printf 'worktree version\n' > "$plugin_copy"
[[ "$(cat "$plugin_source/plugin.php")" == 'canonical version' ]]
printf 'updated canonical version\n' > "$plugin_source/plugin.php"
[[ "$(cat "$plugin_copy")" == 'worktree version' ]]

composer_package="$tmp_dir/worktree/wp-content/themes/example-theme"
canonical_package="$tmp_dir/canonical/wp-content/themes/example-theme"
mkdir -p "$composer_package" "$canonical_package/vendor" "$canonical_package/vendor-prefixed"
printf 'canonical dependency\n' > "$canonical_package/vendor/autoload.php"
printf 'canonical prefixed dependency\n' > "$canonical_package/vendor-prefixed/autoload.php"
copy_tree_cow "$canonical_package/vendor" "$composer_package/vendor"
copy_tree_cow "$canonical_package/vendor-prefixed" "$composer_package/vendor-prefixed"

[[ ! "$canonical_package/vendor/autoload.php" -ef "$composer_package/vendor/autoload.php" ]]
[[ ! "$canonical_package/vendor-prefixed/autoload.php" -ef "$composer_package/vendor-prefixed/autoload.php" ]]
printf 'worktree dependency\n' > "$composer_package/vendor/autoload.php"
[[ "$(cat "$canonical_package/vendor/autoload.php")" == 'canonical dependency' ]]

echo 'PASS: plugin and Composer dependency copies are independent'

