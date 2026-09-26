#!/bin/sh
# stages: pre-commit pre-push ci
# desc: vendor/slax-kitchen must stay byte-identical to its pinned commit.
#
# Adapted from slax-kitchen @ 0dd1b531624148cf733138a0c0a02f152ab864ff (ci/checks/20-vendor-pristine.sh), which guards
# its own vendor/linux-live the same way.
#
# slax-kitchen is the engine this project is built on, pinned by commit. Only the
# POINTER may move, and a pointer that moves silently is the failure this prevents:
# every design decision in docs/ARCHITECTURE.md reasons about specific engine
# behaviour, so a bump has to be read as a diff. docs/UPSTREAM.md says when and how.
. "$(dirname "$0")/../lib.sh"

[ -e "$REPO_ROOT/vendor/slax-kitchen" ] || { note "vendor/slax-kitchen not present yet - skipping"; exit 0; }

# No file inside the submodule tree may be staged directly. Collect first: fail() on
# the right of a pipe runs in a subshell and never propagates.
check_files_nl | grep '^vendor/slax-kitchen/' > /tmp/.slaxwine-vendor.$$ || true
while IFS= read -r f; do
    [ -n "$f" ] && fail "vendor/ must stay pristine, do not commit into it: $f"
done < /tmp/.slaxwine-vendor.$$
rm -f /tmp/.slaxwine-vendor.$$

if git -C "$REPO_ROOT" submodule status vendor/slax-kitchen 2>/dev/null | grep -q '^+'; then
    fail "vendor/slax-kitchen has local modifications or a moved pointer"
    note "if the bump is intentional, read it as a diff and record it in docs/UPSTREAM.md"
fi
check_result
