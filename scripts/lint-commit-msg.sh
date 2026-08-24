#!/usr/bin/env bash
# lint-commit-msg.sh — validate commit messages without rewriting them.
#
# Usage:
#   lint-commit-msg.sh <file>...            lint message files
#   lint-commit-msg.sh --range <base>..<head>   lint every commit in a range
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZE="$HERE/normalize-commit-msg.sh"

FAILED=0
CHECKED=0

lint_text() {
  local label="$1" text="$2" tmp
  tmp="$(mktemp)"
  printf '%s\n' "$text" > "$tmp"
  CHECKED=$((CHECKED + 1))
  if ! "$NORMALIZE" --check "$tmp" 2> >(sed 's/^/    /' >&2); then
    echo "  ✗ $label" >&2
    FAILED=$((FAILED + 1))
  fi
  rm -f "$tmp"
}

if [[ "${1:-}" == "--range" ]]; then
  RANGE="${2:?usage: lint-commit-msg.sh --range <base>..<head>}"
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    lint_text "${sha:0:8} $(git log -1 --pretty=%s "$sha")" "$(git log -1 --pretty=%B "$sha")"
  done < <(git log --format=%H "$RANGE")
else
  [[ $# -gt 0 ]] || { echo "usage: $(basename "$0") [--range <base>..<head>] <file>..." >&2; exit 2; }
  for f in "$@"; do
    CHECKED=$((CHECKED + 1))
    if ! "$NORMALIZE" --check "$f" 2> >(sed 's/^/    /' >&2); then
      echo "  ✗ $f" >&2
      FAILED=$((FAILED + 1))
    fi
  done
fi

if (( FAILED > 0 )); then
  echo "" >&2
  echo "❌ $FAILED of $CHECKED commit message(s) do not match the convention." >&2
  echo "   See docs/commit-messages.md" >&2
  exit 1
fi

echo "✅ $CHECKED commit message(s) conform to the convention."
