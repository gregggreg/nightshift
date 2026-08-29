#!/usr/bin/env bash
# commit-msg hook for nightshift
# Install: make install-hooks  (or: ln -sf ../../scripts/commit-msg.sh .git/hooks/commit-msg)
#
# Validates the commit message against the format defined in
# internal/commitmsg. Skip with: git commit --no-verify
set -euo pipefail

MSG_FILE="${1:?usage: commit-msg.sh <message-file>}"

REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "🪡 commit-msg check"

# Prefer this repository's own binary, then its source, and only then a
# globally installed nightshift — and that one only if it actually knows the
# commit-msg subcommand, so an older install elsewhere on PATH cannot fail the
# hook with a confusing "unknown command" error.
if [[ -x "$REPO_ROOT/nightshift" ]]; then
  RUNNER=("$REPO_ROOT/nightshift")
elif command -v go >/dev/null 2>&1; then
  RUNNER=(go run "$REPO_ROOT/cmd/nightshift")
elif command -v nightshift >/dev/null 2>&1 &&
  nightshift commit-msg --print-spec >/dev/null 2>&1; then
  RUNNER=(nightshift)
else
  echo "  – skipped (no nightshift binary with commit-msg support, no go toolchain)"
  exit 0
fi

if "${RUNNER[@]}" commit-msg --check "$MSG_FILE"; then
  echo "✅ commit message OK"
  exit 0
fi

echo ""
echo "❌ Commit message rejected."
echo "   Rewrite it automatically with:"
echo "     ${RUNNER[*]} commit-msg --fix \"$MSG_FILE\""
echo "   Or skip this check with: git commit --no-verify"
exit 1
