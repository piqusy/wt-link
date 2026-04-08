#!/usr/bin/env bash
# wt-link installer
# Usage: curl -fsSL https://raw.githubusercontent.com/piqusy/wt-link/main/install.sh | bash

set -euo pipefail

REPO="piqusy/wt-link"
INSTALL_DIR="${WT_LINK_INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="wt-link"

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

log()     { echo -e "${BOLD}${CYAN}▶ $*${RESET}"; }
success() { echo -e "${GREEN}✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✗ $*${RESET}" >&2; exit 1; }

# ── Detect latest version ────────────────────────────────────────────────────

get_latest_version() {
    if command -v curl &>/dev/null; then
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name"' \
            | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    elif command -v wget &>/dev/null; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name"' \
            | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    else
        error "curl or wget is required to install wt-link"
    fi
}

# ── Download ─────────────────────────────────────────────────────────────────

download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$dest"
    else
        wget -qO "$dest" "$url"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    log "Installing wt-link..."
    echo ""

    # Determine version to install
    local version="${WT_LINK_VERSION:-}"
    if [[ -z "$version" ]]; then
        log "Fetching latest version..."
        version="$(get_latest_version)"
        [[ -n "$version" ]] || error "Could not determine latest version. Set WT_LINK_VERSION= to specify one."
    fi

    local download_url="https://github.com/${REPO}/releases/download/${version}/wt-link"
    local install_path="$INSTALL_DIR/$BINARY_NAME"

    echo "  Version : $version"
    echo "  Install : $install_path"
    echo ""

    # Create install directory if needed
    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
        success "Created $INSTALL_DIR"
    fi

    # Download the binary
    log "Downloading wt-link ${version}..."
    local tmp_file
    tmp_file="$(mktemp)"
    download_file "$download_url" "$tmp_file"

    # Install
    mv "$tmp_file" "$install_path"
    chmod +x "$install_path"

    success "Installed wt-link $version to $install_path"
    echo ""

    # PATH check
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        warn "$INSTALL_DIR is not in your PATH."
        echo ""
        echo "  Add this to your shell config (~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish):"
        echo ""
        echo "    Bash/Zsh:  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo "    Fish:      fish_add_path \$HOME/.local/bin"
        echo ""
    else
        echo -e "  Run ${BOLD}wt-link --help${RESET} to get started."
        echo ""
    fi
}

main "$@"
