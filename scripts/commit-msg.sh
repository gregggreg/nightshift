#!/usr/bin/env bash
# commit-msg hook for nightshift
# Install: make install-hooks  (or: ln -sf ../../scripts/commit-msg.sh .git/hooks/commit-msg)
#
# Normalizes the commit message in place, then validates it. Set
# NORMALIZE_COMMIT_MSG=0 to bypass both steps for a single commit, or use
# `git commit --no-verify`.
set -euo pipefail

if [[ "${NORMALIZE_COMMIT_MSG:-1}" == "0" ]]; then
  exit 0
fi

MSG_FILE="$1"
ROOT="$(git rev-parse --show-toplevel)"

"$ROOT/scripts/normalize-commit-msg.sh" "$MSG_FILE"
"$ROOT/scripts/validate-commit-msg.sh" "$MSG_FILE"
