#!/bin/sh
# Adapted from slax-kitchen @ 337f7e79b2c2a65d0217cfb976a6654be0876e52 (ci/checks/80-unit.sh). TWO differences,
# both marked below; re-adapt on a submodule bump, see docs/UPSTREAM.md.
#
#   1. The `# desc:` line. Upstream's reads "the recipe engine's pure logic", which this repo
#      does not have: it owns no engine code (docs/ARCHITECTURE.md). tests/unit/ here holds the
#      recipe-content check and a test of the gate library, and the desc line is printed on
#      every gate run, so it should say what it actually checks.
#   2. Each test runs with git's REPOSITORY-LOCAL environment cleared. See the LOCAL CHANGE.
# stages: pre-commit pre-push ci
# desc: Unit tests over recipe content and the gate library -- no ISO, no engine.
. "$(dirname "$0")/../lib.sh"

# LOCAL CHANGE. A UNIT TEST MUST NOT SEE THE COMMIT THAT IS RUNNING IT.
#
# This gate runs inside the pre-commit hook, and git exports its repository to hooks:
# githooks(5) -- "if your hook needs to invoke Git commands in a foreign repository ... it
# should clear these environment variables". tests/unit/test_ci_lib.py does exactly that --
# it builds throwaway repositories and runs git in them -- and clears nothing. Measured under
# a real hook, by commit mode:
#
#   git commit            GIT_INDEX_FILE=.git/index, RELATIVE -- harmless, it resolves
#                         inside each fixture
#   git commit -a/<path>  GIT_INDEX_FILE is ABSOLUTE, the outer commit's pending index. The
#                         fixture's `git add -A` rewrote it -- dropping the commit's own files,
#                         adding a 3 MiB big.bin and a payload.exe whose blobs exist only in
#                         the fixture -- and the commit died with "invalid object ... Error
#                         building trees" while this gate reported success
#   linked worktree       GIT_DIR is exported. Fixture commits landed on the OUTER branch, and
#                         each fired the outer pre-commit hook, which ran this test again:
#                         unbounded recursion, 158 test processes within a few minutes
#
# Cleared here, in a subshell per test, rather than in the tests: it covers every test at
# once, including ones written later, and keeps upstream's tests verbatim. The list is git's
# own (`git rev-parse --local-env-vars`) rather than a copy of it, and the gate's own
# environment is untouched -- other gates legitimately need GIT_INDEX_FILE to read what a
# partial commit is about to record.
_repo_env=$(git rev-parse --local-env-vars 2>/dev/null)
if [ -z "$_repo_env" ]; then
    # Fail closed: an empty list would run every test with the commit's index in reach.
    fail "cannot read git's repository-local variables (git rev-parse --local-env-vars); refusing to run tests that could write into this commit"
    check_result
    exit
fi

for t in "$REPO_ROOT"/tests/unit/test_*.py; do
    [ -f "$t" ] || continue
    # shellcheck disable=SC2086  # splitting the variable list is the point
    ( unset $_repo_env; exec python3 "$t" ) >/dev/null 2>/tmp/.kitchen-unit.$$ || {
        fail "$(basename "$t")"
        sed 's/^/      /' /tmp/.kitchen-unit.$$ >&2
    }
    rm -f /tmp/.kitchen-unit.$$
done
check_result
