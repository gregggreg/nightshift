#!/usr/bin/env bash
#
# Opt in to the repository-managed git hooks in .githooks/.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
git config core.hooksPath .githooks
echo "✓ repository hooks enabled (core.hooksPath=.githooks)"
echo "  pre-commit : gofmt, go vet, go build"
echo "  commit-msg : normalize + validate Conventional Commit subjects"
echo "  disable with: git config --unset core.hooksPath"
