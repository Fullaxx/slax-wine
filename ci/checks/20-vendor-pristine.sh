#!/bin/sh
# stages: pre-commit pre-push ci
# desc: vendor/slax-kitchen must stay byte-identical to its pinned commit.
#
# Adapted from slax-kitchen @ 0d20605922cb79dee0616163d112ea1053faee98 (ci/checks/20-vendor-pristine.sh), which guards
# its own vendor/linux-live the same way. Its rules and messages are taken whole, with the
# path changed; the header, rule 1's collection and the notes are this repo's.
#
# slax-kitchen is the engine this project is built on, pinned by commit. Only the
# POINTER may move, and a pointer that moves silently is the failure this prevents:
# every design decision in docs/ARCHITECTURE.md reasons about specific engine
# behaviour, so a bump has to be read as a diff. docs/UPSTREAM.md says when and how.
#
# THREE RULES, and what they do not cover:
#   1. no file under vendor/slax-kitchen/ is committed into this repository;
#   2. the submodule is checked out at its pin: `git submodule status` has no leading +;
#   3. nothing inside it is modified, staged or untracked. Ignored files do not count.
# Not covered: whether a newly recorded pin is an upstream commit. A commit made inside
# the submodule, then `git add` of the pointer, passes all three.
#
# RULE 3 IS slax-kitchen #101, and this copy had the same hole until the 0d20605 bump. It
# read only `git submodule status`, whose + means a moved pointer, while the desc above said
# byte-identical: an edited or untracked file inside the submodule leaves that line
# unchanged. Here that matters more than upstream, where nothing builds from the vendored
# tree: build.sh runs this engine, so an edited engine file changes the images while the
# gate passes. slax-rpgs measured the hole on its own copy on 2026-10-01.
#
# NOT CHECKED OUT IS A SKIP, said out loud. A clone without --recurse-submodules leaves
# vendor/slax-kitchen an empty directory with no .git, and `git -C` there answers for THIS
# repository, so rules 2 and 3 run only where the submodule is checked out.
. "$(dirname "$0")/../lib.sh"

[ -e "$REPO_ROOT/vendor/slax-kitchen" ] || { note "vendor/slax-kitchen not present yet - skipping"; exit 0; }

# Rule 1: no file inside the submodule tree may be staged directly. Collect first: fail()
# on the right of a pipe runs in a subshell and never propagates.
check_files_nl | grep '^vendor/slax-kitchen/' > /tmp/.slaxwine-vendor.$$ || true
while IFS= read -r f; do
    [ -n "$f" ] && fail "vendor/ must stay pristine, do not commit into it: $f"
done < /tmp/.slaxwine-vendor.$$
rm -f /tmp/.slaxwine-vendor.$$

_sub=$(git -C "$REPO_ROOT" submodule status vendor/slax-kitchen 2>/dev/null)
if [ ! -e "$REPO_ROOT/vendor/slax-kitchen/.git" ] || [ "${_sub#-}" != "$_sub" ]; then
    note "vendor/slax-kitchen is not checked out - rules 2 and 3 skipped (git submodule update --init --recursive)"
else
    # Rule 2: checked out at its pin.
    case "$_sub" in
        +*) fail "vendor/slax-kitchen is checked out at a commit other than its pin"
            note "if the bump is intentional, read it as a diff and record it in docs/UPSTREAM.md" ;;
    esac

    # Rule 3: nothing modified, staged or untracked inside it, the nested vendor/linux-live
    # included, which git reports as a modified path. A git that will not answer fails too,
    # as ci/lib.sh refuses one for the parent: unread is not clean. Under another uid, as in
    # upstream's CI container job, git refuses the submodule for "dubious ownership" even
    # with the parent in safe.directory: upstream reproduced that on 2026-10-24 with that
    # job's ownership in its reference container.
    #
    # A GIT HOOK EXPORTS THE PARENT'S GIT_DIR AND GIT_INDEX_FILE, and git inside the
    # submodule reads them. Under upstream's pre-commit hook this failed with "fatal:
    # .git/index: index file open failed: Not a directory", 2026-10-24, while every run
    # outside a hook passed. They are cleared here as ci/checks/80-unit.sh clears them for
    # its tests.
    _repo_env=$(git rev-parse --local-env-vars 2>/dev/null)
    # shellcheck disable=SC2086  # one variable name per word, split on purpose
    if ! _dirty=$(unset $_repo_env; git -C "$REPO_ROOT/vendor/slax-kitchen" status \
            --porcelain --untracked-files=all 2>&1); then
        fail "git will not answer for vendor/slax-kitchen, so nothing inside it was checked: $(printf '%s\n' "$_dirty" | head -1)"
        note "if that is dubious ownership: git config --global --add safe.directory $REPO_ROOT/vendor/slax-kitchen"
    elif [ -n "$_dirty" ]; then
        _n=$(printf '%s\n' "$_dirty" | wc -l | tr -d ' ')
        _some=$(printf '%s\n' "$_dirty" | head -3 | cut -c4- | tr '\n' ' ')
        fail "vendor/slax-kitchen has $_n modified or untracked path(s) inside it: $_some"
        note "see: git -C vendor/slax-kitchen status"
    fi
fi
check_result
