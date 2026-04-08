# wt-link

Mount or unmount a git worktree as a fully functional local [Laravel Herd](https://herd.laravel.com) WordPress site — instantly.

When developing on a feature branch using `git worktree`, the worktree directory is bare: no WordPress core, no wp-config, no plugins, no uploads, no built assets. `wt-link mount` wires all of that up in seconds so the branch is live at the same `.test` URL as your main site.

## Install

### Homebrew (recommended)

```bash
brew tap piqusy/tap
brew install wt-link
```

### curl

```bash
curl -fsSL https://raw.githubusercontent.com/piqusy/wt-link/main/install.sh | bash
```

Installs to `~/.local/bin/wt-link`. Set `WT_LINK_INSTALL_DIR` to override.

### Install a specific version

```bash
WT_LINK_VERSION=v1.0.0 curl -fsSL https://raw.githubusercontent.com/piqusy/wt-link/main/install.sh | bash
```

### Manual

Download the `wt-link` binary from [Releases](https://github.com/piqusy/wt-link/releases), make it executable, and place it on your `$PATH`:

```bash
chmod +x wt-link
mv wt-link ~/.local/bin/wt-link
```

## Requirements

| Tool | Purpose |
|------|---------|
| [WP-CLI](https://wp-cli.org) (`wp`) | WordPress core download |
| [Laravel Herd](https://herd.laravel.com) (`herd`) | Local domain management |
| [Composer](https://getcomposer.org) | PHP dependency install |
| [Bun](https://bun.sh) | JS dependency install and asset build |
| `jq` | Parse `setup.json` |
| `rsync` | File sync (macOS built-in) |

## Usage

```
wt-link <command> [--cwd PATH]

Commands:
  mount    Set up a git worktree as a fully working local Herd site
  unmount  Tear down and restore the canonical site
  status   Show current link status

Options:
  --cwd PATH   Run against a specific worktree directory (default: current dir)

Environment:
  CANONICAL_SITE   Override the canonical site path
                   (default: ~/Sites/<site-name> from setup.json)
```

### Examples

```bash
# Inside a worktree directory
wt-link mount

# Target a specific directory
wt-link mount --cwd ~/Sites/myproject.feature-branch

# Override the canonical site location
CANONICAL_SITE=~/Sites/myproject wt-link mount

# Tear down
wt-link unmount

# Check status
wt-link status
```

### Fish shell aliases

If you use Fish, add these to your config:

```fish
alias wlm 'wt-link mount'
alias wlu 'wt-link unmount'
alias wls 'wt-link status'
```

## What `mount` does

1. **WP core** — Downloads WordPress (version from `setup.json`) or extracts from WP-CLI cache
2. **wp-config.php** — Copies from the canonical site
3. **Plugins** — Symlinks git-untracked plugins from the canonical site
4. **Uploads** — Symlinks `wp-content/uploads` from the canonical site
5. **Eightshift packages** — For each theme/plugin with `eightshift-libs`:
   - Runs `composer install`
   - Symlinks `node_modules` from the canonical (or runs `bun install`)
   - Runs `bun run build` (or copies pre-built `public/` from canonical)
6. **Herd link** — Runs `herd link <site-name>` so the worktree is live at `https://<site-name>.test/`

A `.worktree-link-state` file tracks everything created so `unmount` can reverse it precisely.

## What `unmount` does

Reverses all of the above: removes symlinks, WP core files, wp-config, restores the Herd link to the canonical site, and deletes the state file.

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

## License

MIT © Ivan Ramljak
