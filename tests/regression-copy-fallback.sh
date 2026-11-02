#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'find "$tmp_dir" -depth -delete' EXIT

source "$ROOT_DIR/lib/wt-link/utils.sh"
source_dir="$tmp_dir/canonical/plugin"
shim_dir="$tmp_dir/bin"
mkdir -p "$source_dir" "$shim_dir"
printf 'canonical file\n' > "$source_dir/plugin.php"

cat > "$shim_dir/cp" <<'SH'
#!/usr/bin/env bash
destination="${@: -1}"

if [[ "${1-}" == '--reflink=auto' || "${COPY_TEST_SCENARIO-}" == 'fallback-fails' ]]; then
    mkdir -p "$destination"
    printf 'partial copy\n' > "$destination/partial-copy"
    exit 1
fi

exec /bin/cp "$@"
SH
chmod +x "$shim_dir/cp"
PATH="$shim_dir:$PATH"
export PATH
uname() { printf 'Linux\n'; }

COPY_TEST_SCENARIO=clone-fails
export COPY_TEST_SCENARIO
copy_tree_cow "$source_dir" "$tmp_dir/worktree/plugin"
[[ -f "$tmp_dir/worktree/plugin/plugin.php" ]]
[[ ! -e "$tmp_dir/worktree/plugin/partial-copy" ]]
[[ ! "$source_dir/plugin.php" -ef "$tmp_dir/worktree/plugin/plugin.php" ]]
printf 'worktree file\n' > "$tmp_dir/worktree/plugin/plugin.php"
[[ "$(cat "$source_dir/plugin.php")" == 'canonical file' ]]

ln -s "$source_dir" "$tmp_dir/canonical/plugin-link"
copy_tree_cow "$tmp_dir/canonical/plugin-link" "$tmp_dir/worktree/plugin-link"
[[ ! -L "$tmp_dir/worktree/plugin-link" ]]
printf 'fallback worktree file\n' > "$tmp_dir/worktree/plugin-link/plugin.php"
[[ "$(cat "$source_dir/plugin.php")" == 'canonical file' ]]

COPY_TEST_SCENARIO=fallback-fails
if copy_tree_cow "$source_dir" "$tmp_dir/failed/plugin"; then
    echo 'Expected the full-copy fallback to fail' >&2
    exit 1
fi
[[ ! -e "$tmp_dir/failed/plugin" ]]
[[ "$(cat "$source_dir/plugin.php")" == 'canonical file' ]]

echo 'PASS: partial clone falls back cleanly; failed fallback leaves no destination'
