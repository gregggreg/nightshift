#!/usr/bin/env sh
# commit-msg hook for nightshift.
# Install: make install-hooks  (or: ln -sf ../../scripts/commit-msg.sh .git/hooks/commit-msg)
#
# Normalizes the commit message in place, then validates it. Safe deviations
# (trailing period, capitalized type or verb, spacing) are fixed silently;
# anything the normalizer cannot fix is rejected with an explanation.
set -eu

# Resolve $0 through any symlinks so the script finds its siblings when it is
# installed as .git/hooks/commit-msg.
cm_self=$0
while [ -L "$cm_self" ]; do
	cm_link=$(readlink "$cm_self")
	case "$cm_link" in
	/*) cm_self=$cm_link ;;
	*) cm_self=$(dirname -- "$cm_self")/$cm_link ;;
	esac
done
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$cm_self")" && pwd)
MSG_FILE=$1

BEFORE=$(cat "$MSG_FILE")
"$SCRIPT_DIR/normalize-commit-msg.sh" "$MSG_FILE"
AFTER=$(cat "$MSG_FILE")

if [ "$BEFORE" != "$AFTER" ]; then
	echo "🪡 commit-msg: normalized commit message"
fi

exec "$SCRIPT_DIR/validate-commit-msg.sh" "$MSG_FILE"
