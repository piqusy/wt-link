# Changelog

## [2.0.0] — 2026-04-11

### Breaking Changes
- **Modular architecture** — the single-file `bin/wt-link` script has been split into a thin entry point + nine library modules under `lib/wt-link/`. Installations from the old single-file release no longer apply; install via Homebrew or the new `.tar.gz` tarball.
- **No more `install.sh`** — the curl-based installer has been removed. Install via Homebrew (`brew install piqusy/tap/wt-link`) or manually from the release tarball.
- **Release artifact is now a tarball** — `wt-link-<version>.tar.gz` contains `bin/wt-link` + `lib/wt-link/*.sh`. The bare `wt-link` binary artifact is no longer published.

### Added
- `lib/wt-link/ui.sh` — output helpers: `log`, `success`, `warn`, `error`, `step`
- `lib/wt-link/utils.sh` — `require_cmd`, `require_pm`, `wp_clean`
- `lib/wt-link/project.sh` — `find_project_root`, `find_eightshift_packages`, `find_untracked_plugins`, `detect_package_manager`
- `lib/wt-link/state.sh` — state file and registry read/write helpers
- `lib/wt-link/runtime.sh` — `run_pm_install`, `run_pm_build`, `run_with_spinner`, `wait_for_herd`
- `lib/wt-link/mount.sh` — `cmd_mount` decomposed into 8 private `_mount_*` sub-functions for readability
- `lib/wt-link/unmount.sh` — `cmd_unmount`
- `lib/wt-link/status.sh` — `cmd_status`
- `lib/wt-link/rebuild.sh` — `cmd_rebuild_composer`, `cmd_rebuild_node`
- **Development layout** — `bin/wt-link` automatically resolves `LIB_DIR` relative to the script directory, so the tool runs from a cloned repo without any install step.

### Changed
- `bin/wt-link` is now ~220 lines (down from ~700): shebang, colour vars, LIB_DIR resolution, module sourcing, arg parsing, project resolution, and dispatch only.
- Build step now always builds for themes, always skips for plugins (previously skipped if `public/manifest.json` existed, risking stale assets).
- `herd link` now removes the existing Herd symlink before re-linking, fixing silent no-op when switching between worktrees for the same site name.
- Untracked plugins are hard-copied (`cp -Rl`) from the canonical site instead of symlinked, ensuring filesystem isolation between worktrees.

## [1.7.1] — 2026-04-10

### Fixed
- `unmount` no longer removes `vendor/` or `vendor-prefixed/` directories that were not created by `mount`. Real directories are now only deleted when a state key (`vendor_copied_<pkg>_<dir>=1`) confirms mount placed them. Previously the `elif -d` branch would `rm -rf` any existing vendor dir unconditionally, risking data loss on canonical or tracked projects.
- `mount` now records `vendor_copied_<pkg>_<vendor_dir>=1` in the state file for each hardlink-copied vendor directory so `unmount` can reverse exactly what was done.



### Added
- **`rebuild-composer` command** — deletes `vendor/` and `vendor-prefixed/` from all Eightshift packages, then restores them via hardlink copy from canonical (or `composer install` fallback). Useful after pulling upstream composer changes.
- **`rebuild-node` command** — deletes `node_modules/` and `public/` from all Eightshift packages, reinstalls JS deps, and rebuilds assets. Auto-detects package manager per package.
- Fish aliases `wlrc` (rebuild-composer) and `wlrn` (rebuild-node) documented in help output.

### Changed
- **`vendor/` and `vendor-prefixed/` are now hardlink-copied instead of symlinked** — `cp -Rl` creates a hardlink tree (zero extra disk on APFS), and PHP `__FILE__` resolves to the real worktree path rather than traversing a symlink to the canonical repo. Existing legacy symlinks are transparently upgraded on next mount.
- Mount detects legacy symlinks for `vendor/`/`vendor-prefixed/` and replaces them with hardlink copies automatically.
- Unmount now removes real `vendor/`/`vendor-prefixed/` directories (previously only removed symlinks).

### Fixed
- All silent exit points caused by `set -euo pipefail` now produce error messages:
  - `--cwd` with a non-existent directory now errors with `"Directory not found: <path>"` instead of exiting silently.
  - Unguarded `run_with_spinner` calls for WP core extract and download now `error()` on failure.
  - Unguarded `cp` for `wp-config.php` now errors on failure.
  - `ln -s` for plugin symlinks now warns and continues instead of aborting silently.
  - `ln -s` for uploads symlink now warns instead of aborting silently.
  - `wp_clean core version` in `cmd_status` now has `|| true` guard to prevent silent crash when WP-CLI is unavailable.
  - `(( i++ ))` in spinner loop replaced with `i=$(( i + 1 ))` to avoid spurious `set -e` exit when `i=0`.
  - `(( elapsed += interval ))` in `wait_for_herd` now guarded with `|| true`.

## [1.6.2] — 2026-04-10

### Fixed
- `herd link` in `mount` now runs with an explicit `cd` into the worktree root before calling `herd link`, matching the pattern used in `unmount`. Previously, `herd link` was called from the caller's `pwd`, which caused the Herd symlink to point to the wrong directory when the shell's working directory differed from the worktree root.
- Replaced `-V` short flag for `--version` with `-v` for consistency.

## [1.6.1] — 2026-04-10

### Fixed
- Show spinner during `herd link` on mount for visual feedback while nginx reloads
- Abort mount with hard error if `herd link` fails instead of silently continuing
- Replace manual `ln -sfn` symlink on unmount with `herd link` to trigger Herd nginx reload and fix 404s after unmount
- Warn instead of silently swallowing errors from `herd unlink` fallback on unmount

## [1.6.0] — 2026-04-10

### Added
- **Spinners for long-running steps** — WP core download/extract, `composer install`, package manager install, and package manager build now show a braille spinner (`⠋⠙⠹…`) while running in the background. On failure, the last 5 lines of output are printed to aid debugging.

### Changed
- `wait_for_herd` in unmount moved to after all cleanup steps, mirroring mount's pattern — Herd's nginx config reload now happens in the background during teardown rather than blocking it.

## [1.5.0] — 2026-04-10

### Added
- **Domain availability check** — after `herd link` (mount) and `herd unlink` (unmount), wt-link polls both `http://` and `https://` with a braille spinner until the domain responds or a 10s timeout is reached. Any non-zero HTTP response counts as live; a warning is shown on timeout.

### Changed
- **Herd link moved to step 1 of mount** — the domain is now registered with Herd at the very beginning of mount so Herd's nginx config reloads in the background while WP core, composer deps, node_modules, and the asset build run. The domain poll at the end acts as a verification gate and typically returns immediately.

## [1.4.0] — 2026-04-10

### Added
- **Global mount registry** — a per-site registry file (`~/.config/wt-link/<site>.active`) now tracks which worktree currently owns the Herd link. This prevents two worktrees silently competing for the same `.test` domain.
- **Mount ownership check** — mounting a worktree when another worktree already owns the domain warns the user and exits. Pass `--force` / `-f` to override and steal the link.
- **Registry in `status`** — `wt-link status` now shows the registry canonical path and active owner alongside local state.

### Changed
- Herd link restore target is now stored in the global registry (`canonical=`) instead of the per-worktree state file (`herd_previous_target`). Unmount reads the registry to restore the canonical site; per-worktree state no longer needs to track this.
- **Code organisation** — section headers renamed to consistent `UPPER CASE`; `Helpers` split into `OUTPUT` and `PREREQUISITES`; `WP_CORE_MARKER`, `STATE FILE`, and `GLOBAL REGISTRY` merged into a single `STATE & REGISTRY` block.

## [1.3.4] — 2026-04-10

### Fixed
- **Herd link restore on fresh mount** — when no pre-existing Herd link existed at mount time, `unmount` would run `herd unlink` leaving `site.test` unresolved. Mount now records the canonical site as the restore target; unmount falls back to re-linking canonical when no saved target is present.
- **Re-mount clobbers restore target** — mounting the same worktree twice would overwrite `herd_previous_target` with the worktree path itself, causing unmount to restore to the wrong location. The target is now written only once (first mount wins).
- **`node_modules/` left behind after unmount** — `pm install` creates a real directory, not a symlink. Unmount now removes it unconditionally with `rm -rf`.
- **`public/` not cleaned on unmount** — mount now always runs `pm build` and tracks `public_built_<pkg>` in state; unmount removes the built `public/` directory when that key is present. The previous rsync copy-from-canonical fallback is removed.

## [1.3.3] — 2026-04-10

### Fixed
- **Package manager detection now recognises `bun.lock`** — Bun's text-format lockfile (`bun.lock`) is now detected alongside the legacy binary `bun.lockb`. Projects without either lockfile now default to `bun` instead of `npm`.

## [1.3.2] — 2026-04-10

### Fixed
- **`vendor-prefixed/` not symlinked** — mount/unmount were using `vendor_prefixed` (underscore) but Eightshift projects always use `vendor-prefixed` (hyphen, Strauss default). The prefixed-vendor symlink was silently skipped on every mount.

## [1.3.1] — 2026-04-09

### Fixed
- **Subdirectory invocation** — `mount`, `unmount`, and `status` now traverse up from the current directory to find `setup.json`, stopping at the git repo root. Previously, the commands only worked when invoked from the exact worktree root.

## [1.3.0] — 2026-04-09

### Changed
- **Package manager auto-detection** — `bun` is no longer required globally. `mount` now detects the package manager per Eightshift package by inspecting lockfiles in priority order: `bun.lockb` → `yarn.lock` → `pnpm-lock.yaml` → `package-lock.json` → `package.json` `.packageManager` field → fallback `npm`.
- **Composer deps symlinked from canonical** — `vendor/` and `vendor-prefixed/` are now symlinked from the canonical site instead of running `composer install` (falls back to `composer install` if the canonical has no `vendor/`).
- **`node_modules` always rebuilt** — `bun install` (or the detected PM) now always runs; the "already installed" skip is removed.
- **`status` shows detected PM** — each Eightshift package line now includes `pm:<name>`.
- **`unmount` cleans vendor symlinks** — `vendor/` and `vendor-prefixed/` symlinks are now removed on unmount.

## [1.2.0] — 2026-04-09

### Changed
- **Composer deps symlinked** — `vendor/` and `vendor-prefixed/` are symlinked from the canonical site's equivalent package; `composer install` is only run as a fallback.
- **`node_modules` always rebuilt** — removed the skip-if-present check; `bun install` always runs.
- **`unmount` removes vendor symlinks** — added cleanup of `vendor/` and `vendor-prefixed/` symlinks.

## [1.1.0] — 2026-04-09

### Changed
- `node_modules` is now rebuilt via `bun install` instead of being symlinked from the canonical site, giving each worktree independent JS deps.

## [1.0.0] — 2026-04-09

Initial release.
