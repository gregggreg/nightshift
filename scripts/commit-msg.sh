#!/usr/bin/env bash
# commit-msg hook for nightshift — normalizes the message in place.
# Install: make install-hooks
# Skip once: git commit --no-verify
set -euo pipefail

# Resolve via the repo root rather than $BASH_SOURCE: git invokes this through
# the .git/hooks/commit-msg symlink, so dirname would point at .git/hooks.
ROOT="$(git rev-parse --show-toplevel)"
exec "$ROOT/scripts/normalize-commit-msg.sh" "$1"
