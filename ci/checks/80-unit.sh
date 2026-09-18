#!/bin/sh
# Adapted from slax-kitchen @ 8adfca617cecae8681b719fa7b3684b172726131 (ci/checks/80-unit.sh). ONE difference, and it is the
# `# desc:` line only -- the code below is byte-identical. Upstream's reads "the recipe
# engine's pure logic", which this repo does not have: it owns no engine code (see
# docs/ARCHITECTURE.md). What tests/unit/ holds here is the recipe-content half, and the
# desc line is printed on every gate run, so it should say what it actually checks.
# Re-adapt on a submodule bump; see docs/UPSTREAM.md.
# stages: pre-commit pre-push ci
# desc: Unit tests over recipe content -- no ISO, no engine, milliseconds.
. "$(dirname "$0")/../lib.sh"

for t in "$REPO_ROOT"/tests/unit/test_*.py; do
    [ -f "$t" ] || continue
    python3 "$t" >/dev/null 2>/tmp/.kitchen-unit.$$ || {
        fail "$(basename "$t")"
        sed 's/^/      /' /tmp/.kitchen-unit.$$ >&2
    }
    rm -f /tmp/.kitchen-unit.$$
done
check_result
