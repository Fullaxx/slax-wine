#!/bin/sh
# Refuse a release whose tag, version and CHANGELOG disagree, before anything is built.
#
#   ci/release-guard.sh <tag> [--tag-push]
#
# The first job of .github/workflows/release.yml: seconds of shell, ahead of the builds. Modelled on slax-kitchen's ci/release-guard.sh; the version here is build.env's.
#
#   1. the tag is v$VERSION                                     always
#   2. CHANGELOG.md has a dated "## [$VERSION] — YYYY-MM-DD"    tag pushes only
#   3. the commit is on origin/master                           tag pushes; a rehearsal
#                                                               says loudly when it cannot tell
#
# Without --tag-push the checks that only a real release needs are relaxed, so a rehearsal
# (workflow_dispatch from a branch) runs the same path before the day it matters.
set -u
: "${REPO_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
TAG=${1:-}
TAG_PUSH=0
[ "${2:-}" = "--tag-push" ] && TAG_PUSH=1
[ -n "$TAG" ] || { echo "usage: ci/release-guard.sh <tag> [--tag-push]" >&2; exit 2; }

rc=0
ok()   { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*" >&2; rc=1; }
skip() { printf '  skip %s\n' "$*" >&2; }

VERSION=$(sed -n 's/^VERSION=//p' "$REPO_ROOT/build.env" | head -1)
[ -n "$VERSION" ] || { echo "release-guard: could not read VERSION from build.env" >&2; exit 2; }
printf 'release guard  tag=%s  VERSION=%s\n' "$TAG" "$VERSION"

# ---- 1. the tag is the version -------------------------------------------------------
# Gate 96 section 6 holds a tagged HEAD to the same, but only once the tag exists; this
# refuses before any build is spent on a release under the wrong name.
if [ "$TAG" = "v$VERSION" ]; then
    ok "tag matches build.env"
else
    bad "tag is $TAG but build.env says VERSION=$VERSION (expected tag v$VERSION)"
fi

# ---- 2. the CHANGELOG entry is dated -------------------------------------------------
# docs/build.md: date the entry and commit that first, so the tag names a dated tree.
ver_re=$(printf '%s' "$VERSION" | sed 's/[.]/\\./g')
if grep -qE "^## \[$ver_re\] — [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$REPO_ROOT/CHANGELOG.md" 2>/dev/null; then
    ok "CHANGELOG.md dates $VERSION"
elif [ "$TAG_PUSH" = 1 ]; then
    bad "CHANGELOG.md has no dated '## [$VERSION] — YYYY-MM-DD' heading"
else
    skip "CHANGELOG.md does not date $VERSION yet (not a tag push, so allowed)"
fi

# ---- 3. the commit is on master ------------------------------------------------------
# A tag on a branch would publish a tree master never had. A check that could not run is
# not a pass: on a tag push, no origin/master fails.
HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo)
if [ -z "$HEAD_SHA" ]; then
    bad "not a git checkout"
elif git -C "$REPO_ROOT" rev-parse --verify -q origin/master >/dev/null 2>&1; then
    if git -C "$REPO_ROOT" merge-base --is-ancestor "$HEAD_SHA" origin/master 2>/dev/null; then
        ok "$(echo "$HEAD_SHA" | cut -c1-7) is on origin/master"
    elif [ "$TAG_PUSH" = 1 ]; then
        bad "$(echo "$HEAD_SHA" | cut -c1-7) is not on origin/master"
    else
        skip "$(echo "$HEAD_SHA" | cut -c1-7) is not on origin/master (a rehearsal from a branch)"
    fi
elif [ "$TAG_PUSH" = 1 ]; then
    bad "origin/master not fetched -- cannot verify the commit is on master"
else
    skip "origin/master not fetched -- cannot check the commit is on master"
fi

if [ "$rc" -eq 0 ]; then
    echo "release guard passed"
else
    echo "release guard failed -- nothing was built or published" >&2
fi
exit "$rc"
