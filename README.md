# wt-link

Mount or unmount a git worktree as a fully functional local [Laravel Herd](https://herd.laravel.com) WordPress site — instantly.

When developing on a feature branch using `git worktree`, the worktree directory is bare: no WordPress core, no wp-config, no plugins, no uploads, no built assets. `wt-link mount` wires all of that up in seconds so the branch is live at the same `.test` URL as your main site.

## Install

### Homebrew (recommended)

```bash
brew tap piqusy/tap
brew install wt-link
```

### Manual

Download `wt-link-<version>.tar.gz` from [Releases](https://github.com/piqusy/wt-link/releases), then:

```bash
tar -xzf wt-link-<version>.tar.gz
sudo cp bin/wt-link /usr/local/bin/
sudo cp -r lib/wt-link /usr/local/lib/
```

## Requirements

| Tool | Purpose |
|------|---------|
| [WP-CLI](https://wp-cli.org) (`wp`) | WordPress core download |
| [Laravel Herd](https://herd.laravel.com) (`herd`) | Local domain management |
| [Composer](https://getcomposer.org) | PHP dependency install (fallback only) |
| `bun` / `npm` / `yarn` / `pnpm` | JS dependency install and asset build (auto-detected) |
| `jq` | Parse `setup.json` |
| `rsync` | File sync (macOS built-in) |

## Usage

```
wt-link <command> [--cwd PATH] [--force] [--hard-copy]

Commands:
  mount             Set up a git worktree as a fully working local Herd site
  unmount           Tear down and restore the canonical site
  status            Show current link status
  rebuild-composer  Re-run composer install for all Eightshift packages
  rebuild-node      Re-run <pm> install + build for all Eightshift packages

Options:
  --cwd PATH   Run against a specific worktree directory (default: current dir)
  --force      Force re-mount even if already mounted
  --hard-copy  Hard-copy untracked plugins instead of symlinking (parallel cp -Rl)
```

### Examples

```bash
# Inside a worktree directory
wt-link mount

# Target a specific directory
wt-link mount --cwd ~/Sites/myproject.feature-branch

# Override the canonical site location
CANONICAL_SITE=~/Sites/myproject wt-link mount

# Force re-mount (e.g. after canonical site deps changed)
wt-link mount --force

# Hard-copy plugins instead of symlinking (filesystem-isolated, faster plugin activation)
wt-link mount --hard-copy

# Tear down
wt-link unmount

# Check status
wt-link status

# Rebuild PHP deps after a composer.json change
wt-link rebuild-composer

# Rebuild JS assets after a package.json change
wt-link rebuild-node
```

### Fish shell aliases

If you use Fish, add these to your config:

```fish
alias wlm 'wt-link mount'
alias wlu 'wt-link unmount'
alias wls 'wt-link status'
alias wlrc 'wt-link rebuild-composer'
alias wlrn 'wt-link rebuild-node'
```

## What `mount` does

1. **WP core** — Downloads WordPress (version from `setup.json`) or extracts from WP-CLI cache
2. **wp-config.php** — Copies from the canonical site
3. **Plugins** — Symlinks git-untracked plugins from the canonical site; use `--hard-copy` to hard-copy instead (parallel `cp -Rl`, useful when plugins need filesystem isolation between worktrees)
4. **Uploads** — Symlinks `wp-content/uploads` from the canonical site
5. **Eightshift packages** — For each theme/plugin with `eightshift-libs`:
   - Symlinks `vendor/` and `vendor_prefixed/` from the canonical site (falls back to `composer install` if canonical has none)
   - Runs `<pm> install` — package manager auto-detected from lockfile (`bun`, `yarn`, `pnpm`, or `npm`)
   - Runs `<pm> run build` for themes; skips build for plugins
6. **Herd link** — Runs `herd link <site-name>` so the worktree is live at `https://<site-name>.test/`

A `.worktree-link-state` file tracks everything created so `unmount` can reverse it precisely.

## What `unmount` does

Reverses all of the above: removes symlinks, hard-copied plugin directories, WP core files, wp-config, restores the Herd link to the canonical site, and deletes the state file.

## What `rebuild-composer` does

Re-runs `composer install` for every Eightshift package in the worktree. Useful after pulling changes that add or update PHP dependencies.

## What `rebuild-node` does

Re-runs `<pm> install` and `<pm> run build` for every Eightshift package in the worktree. Useful after pulling changes that add or update JS dependencies or after a failed build.

## Configuration

`wt-link` reads `setup.json` from the worktree root. Minimum required fields:

```json
{
  "urls": {
    "local": "https://mysite.test/"
  },
  "core": "6.7.2"
}
```

This is the standard [Eightshift](https://eightshift.com) project format.

## Development

The tool is split into a thin entry point and nine library modules:

```
bin/
  wt-link          # Entry point: arg parsing, project resolution, dispatch
lib/wt-link/
  ui.sh            # log/success/warn/error/step output helpers
  utils.sh         # require_cmd, require_pm, wp_clean
  project.sh       # find_project_root, detect_package_manager, find_* helpers
  state.sh         # State file and registry read/write helpers
  runtime.sh       # run_pm_install, run_pm_build, run_with_spinner, wait_for_herd
  mount.sh         # cmd_mount + 8 private _mount_* sub-functions
  unmount.sh       # cmd_unmount
  status.sh        # cmd_status
  rebuild.sh       # cmd_rebuild_composer, cmd_rebuild_node
```

To run from source without installing:

```bash
git clone https://github.com/piqusy/wt-link
cd wt-link
./bin/wt-link --help
```

## Shell prompt integration

Show a `⛓` symbol in your prompt when inside a mounted worktree.

### Starship

Add to `~/.config/starship.toml`:

```toml
[custom.wt-link]
command = "wt-link starship"
when = true
detect_files = [".worktree-link-state"]
format = "[$output]($style) "
style = "bold yellow"
ignore_timeout = true
```

### Powerlevel10k

Add to `~/.p10k.zsh`:

```zsh
function prompt_wt_link() {
  [[ -f .worktree-link-state ]] || return
  p10k segment -f yellow -t '⛓'
}
```

Then add `wt_link` to your prompt elements in the same file:

```zsh
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(... wt_link ...)
# or on the right:
# POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(... wt_link ...)
```

### Oh My Zsh

Add to `~/.zshrc` (after `source $ZSH/oh-my-zsh.sh`):

```zsh
function _wt_link_prompt() {
  [[ -f .worktree-link-state ]] && echo '⛓ '
}

RPROMPT='$(_wt_link_prompt)'"$RPROMPT"
```

Or add it to the left prompt by modifying your theme's `PROMPT` variable instead.

### Plain Bash / PS1

Add to `~/.bashrc` or `~/.bash_profile`:

```bash
_wt_link_prompt() {
  [[ -f .worktree-link-state ]] && printf '⛓ '
}

PS1='$(_wt_link_prompt)'"$PS1"
```

## License

MIT © Ivan Ramljak
