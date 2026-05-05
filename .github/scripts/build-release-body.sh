#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: build-release-body.sh <version> <body-file> <changelog-file>}"
BODY_FILE="${2:?Usage: build-release-body.sh <version> <body-file> <changelog-file>}"
CHANGELOG_FILE="${3:?Usage: build-release-body.sh <version> <body-file> <changelog-file>}"

awk -v ver="$VERSION" '
    $0 ~ "^## \\[" ver "\\]" { flag=1 }
    flag && $0 ~ "^## \\[" && $0 !~ "^## \\[" ver "\\]" { exit }
    flag { print }
' CHANGELOG.md > "$CHANGELOG_FILE"

if [[ ! -s "$CHANGELOG_FILE" ]]; then
    echo "Missing changelog entry for version $VERSION in CHANGELOG.md" >&2
    exit 1
fi

{
    echo "## Changelog"
    echo
    cat "$CHANGELOG_FILE"
    echo
    echo "## Install"
    echo
    echo '```bash'
    echo 'brew tap piqusy/tap'
    echo 'brew install piqusy/tap/wt-link'
    echo '```'
    echo
    echo '### Manual download'
    echo
    echo "Download \`wt-link-${VERSION}.tar.gz\` below, then:"
    echo
    echo '```bash'
    echo "tar -xzf wt-link-${VERSION}.tar.gz"
    echo 'sudo cp bin/wt-link /usr/local/bin/'
    echo 'sudo cp -r lib/wt-link /usr/local/lib/'
    echo '```'
    echo
    echo 'Verify checksum:'
    echo '```bash'
    echo "sha256sum -c wt-link-${VERSION}.tar.gz.sha256"
    echo '```'
} > "$BODY_FILE"
