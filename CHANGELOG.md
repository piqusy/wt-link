# Changelog

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
