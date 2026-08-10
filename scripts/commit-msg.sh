#!/usr/bin/env bash
# commit-msg hook for nightshift
#
# Normalizes the commit message in place, then validates it against the
# standard in docs/commit-messages.md.
#
# Install: make install-hooks
#          (or: ln -sf ../../scripts/commit-msg.sh .git/hooks/commit-msg)
# Skip once: git commit --no-verify
set -euo pipefail

MSG_FILE="${1:?commit-msg hook: expected a message file path}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if command -v commitmsg >/dev/null 2>&1; then
  run_commitmsg() { command commitmsg "$@"; }
elif command -v go >/dev/null 2>&1; then
  # Drop `go run`'s own "exit status N" line so the hook output stays clean.
  run_commitmsg() {
    local out rc=0
    out=$(go run ./cmd/commitmsg "$@" 2>&1) || rc=$?
    if [[ -n "$out" ]]; then
      grep -v '^exit status [0-9]*$' <<<"$out" >&2 || true
    fi
    return $rc
  }
else
  echo "🪡 commit-msg: neither 'commitmsg' nor 'go' found — skipping the check" >&2
  exit 0
fi

run_commitmsg normalize "$MSG_FILE"

if ! run_commitmsg lint "$MSG_FILE"; then
  cat >&2 <<'EOF'

The commit message does not follow the nightshift standard.
See docs/commit-messages.md, fix the message, and commit again.
To bypass this check once: git commit --no-verify
EOF
  exit 1
fi
