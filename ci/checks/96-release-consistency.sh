#!/bin/sh
# stages: pre-commit pre-push ci
# desc: build.env, the recipes, the profile, the submodule pin and the git tag all agree.
#
# This repo's own gate -- nothing upstream corresponds to it.
#
# A release here is defined by two halves: our VERSION and the exact base ISO it was
# built on. Those facts are necessarily repeated -- in build.env, inside the image as
# /etc/slax-wine-release, in the docs table, and in a git tag. Repetition that nothing
# checks is how a release ends up labelled as something it is not, so every copy is
# cross-checked against the single source.
#
# Note the collect-then-loop shape used throughout: fail() on the right of a pipe runs
# in a SUBSHELL, so _FAILED is set in a process that then exits and the gate returns 0.
# Upstream's 90-doc-coverage carried exactly that bug for the length of one test run.
#
# Note also the shape of every textual assertion below: strip leading/trailing space,
# then `grep -qxF`. Whole-line (-x) AND fixed-string (-F). A self-review found this file
# using bare `grep -q "$n"`, which is neither: an unanchored substring regex matched the
# profile's own COMMENTS, so section 5 could not fail, and section 4's unescaped dots
# meant VERSION="1x0y0" satisfied a check for 1.0.0 while BASE_VERSION= would have
# satisfied a check for VERSION=. A gate that cannot fail is worse than no gate, because
# it is believed. Never loosen these two flags.
. "$(dirname "$0")/../lib.sh"

# Whole-line, fixed-string match after whitespace normalisation. $1 = file, $2 = line.
#
# `-e "$2"` is not decoration: the profile's list entries begin with "- ", and without
# -e every grep on earth reads that leading dash as an option bundle. Caught while
# fixing this gate -- it failed loudly rather than silently, which is the only reason
# this comment exists rather than another dead check.
line_present() {
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -qxF -e "$2"
}

TMP=$(mktemp -d) || { fail "cannot create a temp dir"; check_result; exit; }
trap 'rm -rf "$TMP"' EXIT INT TERM

ENVF="$REPO_ROOT/build.env"
[ -f "$ENVF" ] || { note "build.env not present yet - skipping"; exit 0; }

# shellcheck source=/dev/null
. "$ENVF"

# ---- 1. VERSION is a version ------------------------------------------------------
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' \
    || fail "build.env: VERSION '$VERSION' is not semver"

# ---- 2. BASE_TARGET is assembled from its own parts --------------------------------
# kitchen names targets <flavour>-<arch>-<version>; keeping the parts separate makes
# them usable individually, and this stops the two spellings drifting apart.
want_target="$BASE_FLAVOUR-$BASE_ARCH-$BASE_VERSION"
[ "$BASE_TARGET" = "$want_target" ] \
    || fail "build.env: BASE_TARGET '$BASE_TARGET' != '$want_target' built from its parts"

# ---- 2b. the app version is not left behind ----------------------------------------
# APP_VERSION is not decorative: build.sh writes it into /opt/notepadpp/VERSION inside
# the ISO and into build-summary.txt. build.env once told readers that updating the app
# was "exactly two edits: APP_URL and APP_SHA256", which would ship an image that
# misreports its own application version. The URL carries the version twice, so the two
# can be cross-checked instead of merely asked for.
case "$APP_URL" in
    *"$APP_VERSION"*) : ;;
    *) fail "build.env: APP_VERSION '$APP_VERSION' does not appear in APP_URL -- did you update the URL and forget the version?" ;;
esac

# ---- 3. the base ISO matches the PINNED sources.yaml -------------------------------
# This is the assertion that earns the gate. The submodule pin decides which
# compat/sources.yaml we build against, so a bump that changes the base ISO's identity
# would otherwise be invisible until the bytes were already downloaded.
SRC="$REPO_ROOT/vendor/slax-kitchen/compat/sources.yaml"
if [ ! -f "$SRC" ]; then
    note "vendor/slax-kitchen not checked out - base cross-check skipped"
elif ! have python3; then
    note "python3 not installed - base cross-check skipped"
else
    # ONE invocation, with the heredoc attached, and its EXIT STATUS checked. The
    # contract is "print FAIL/NOTE lines to stdout"; before this, any exception
    # (malformed sources.yaml, a scalar where a mapping was expected) wrote to stderr,
    # left stdout empty, and the gate reported green -- silently skipping the one
    # cross-check that earns this gate its keep.
    if ! python3 - "$SRC" "$BASE_TARGET" "$BASE_ISO" "$BASE_SHA256" "$BASE_SIZE" \
            > "$TMP/base" 2> "$TMP/base.err" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("NOTE python3-yaml not installed - base cross-check skipped"); sys.exit(0)
src, target, iso, sha, size = sys.argv[1:6]
doc = yaml.safe_load(open(src))
if not isinstance(doc, dict):
    print(f"FAIL {src} is not a YAML mapping"); sys.exit(0)
targets = doc.get("targets")
if not isinstance(targets, dict):
    print(f"FAIL {src} has no 'targets' mapping"); sys.exit(0)
t = targets.get(target)
if t is None:
    print(f"FAIL build.env: BASE_TARGET {target!r} is not a target in the pinned sources.yaml")
    sys.exit(0)
if not isinstance(t, dict):
    print(f"FAIL {src}: target {target!r} is {type(t).__name__}, not a mapping"); sys.exit(0)
for key, ours in (("file", iso), ("sha256", sha), ("size", str(size))):
    theirs = str(t.get(key, ""))
    if ours != theirs:
        print(f"FAIL build.env: {key} {ours!r} != pinned sources.yaml {theirs!r} for {target}")
PY
    then
        fail "base cross-check crashed (is $SRC valid YAML?): $(tr '\n' ' ' < "$TMP/base.err" | tail -c 200)"
    fi
    while IFS= read -r line; do
        case "$line" in
            FAIL\ *) fail "${line#FAIL }" ;;
            NOTE\ *) note "${line#NOTE }" ;;
        esac
    done < "$TMP/base"
fi

# ---- 4. the image cannot lie about itself ------------------------------------------
# wine-desktop.yaml writes /etc/slax-wine-release inline. An ISO that misreports its own
# version is worse than one that reports nothing, because it is believed.
# The file is named in profiles/slax-wine.yaml, so its absence is a broken build, not a
# reason to skip three assertions quietly.
WD="$REPO_ROOT/recipes/available/wine-desktop.yaml"
if [ ! -f "$WD" ]; then
    fail "recipes/available/wine-desktop.yaml is missing, so /etc/slax-wine-release is unchecked"
else
    line_present "$WD" "VERSION=\"$VERSION\"" \
        || fail "wine-desktop.yaml: /etc/slax-wine-release VERSION does not match build.env ($VERSION)"
    line_present "$WD" "BASE_ISO=\"$BASE_ISO\"" \
        || fail "wine-desktop.yaml: /etc/slax-wine-release BASE_ISO does not match build.env"
    line_present "$WD" "BASE_SHA256=\"$BASE_SHA256\"" \
        || fail "wine-desktop.yaml: /etc/slax-wine-release BASE_SHA256 does not match build.env"
fi

# ---- 5. no orphan recipes ----------------------------------------------------------
# The profile is authoritative (kitchen apply --profile), so a recipe absent from it is
# never built and never tested -- it just looks like it ships.
PROFILE="$REPO_ROOT/profiles/slax-wine.yaml"
if [ -d "$REPO_ROOT/recipes/available" ] && [ -f "$PROFILE" ]; then
    find "$REPO_ROOT/recipes/available" -maxdepth 1 -name '*.yaml' > "$TMP/rec"
    while IFS= read -r r; do
        n=$(basename "$r" .yaml)
        # The LIST ENTRY, not the name anywhere in the file. Every recipe name also
        # appears in this profile's comments and in `name: slax-wine`, so the old
        # substring grep passed for a recipe the profile never built.
        line_present "$PROFILE" "- recipes/available/$n.yaml" \
            || fail "recipe is in no profile, so it is never built: $n"
    done < "$TMP/rec"
fi

# ---- 6. a tagged HEAD must be honest ------------------------------------------------
# Only on a tag: the tag has to be the version, and the docs must carry real measured
# numbers rather than the placeholder. Everything claimed in a release is checkable, and
# TBD-MEASURED is the marker for "not measured yet".
# `git describe --exact-match` exits 128 for BOTH "No names found" and "not a git
# repository", so `if tag=$(...)` silently treated a git-less tree -- a `git archive`
# export, a container without git -- as "not a release" and skipped this whole section.
# Establish repo-ness first, then ask about tags separately.
if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    note "not a git repository - release-honesty checks skipped"
else
    tag=$(git -C "$REPO_ROOT" tag --points-at HEAD 2>/dev/null | head -1)
    if [ -n "$tag" ]; then
        [ "$tag" = "v$VERSION" ] \
            || fail "tagged HEAD is '$tag' but build.env says VERSION=$VERSION (want 'v$VERSION')"
        # TBD-MEASURED is this repo's placeholder for "a number we have not measured
        # yet". It is deliberately ugly so it cannot be mistaken for a value, and this is
        # the only thing that enforces it -- so if you write a placeholder, write THIS
        # one. docs/build.md says so too.
        grep -rl 'TBD-MEASURED' "$REPO_ROOT/docs" "$REPO_ROOT/README.md" 2>/dev/null \
            > "$TMP/tbd" || true
        while IFS= read -r f; do
            [ -n "$f" ] && fail "tagged release still carries TBD-MEASURED: ${f#"$REPO_ROOT"/}"
        done < "$TMP/tbd"
    fi
fi

# ---- 7. copied gates cite the pin they were copied from ----------------------------
# Every file in ci/ carries "slax-kitchen @ <40 hex>" and "Do not edit here -- re-copy on
# a submodule bump". Nothing enforced the first half, so a pin bump left twelve headers
# naming the OLD commit while the content had in fact been refreshed -- a reader cannot
# tell a stale citation from stale content, which is the header's entire purpose.
#
# This is the invariant this gate's own `# desc:` line has always claimed to check.
if ! have git; then
    note "git not installed - provenance-header check skipped"
elif ! git -C "$REPO_ROOT/vendor/slax-kitchen" rev-parse HEAD >/dev/null 2>&1; then
    note "vendor/slax-kitchen not checked out - provenance-header check skipped"
else
    PIN=$(git -C "$REPO_ROOT/vendor/slax-kitchen" rev-parse HEAD)
    grep -rln 'slax-kitchen @ [0-9a-f]' "$REPO_ROOT/ci" > "$TMP/hdr" 2>/dev/null || true
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        got=$(sed -n 's/.*slax-kitchen @ \([0-9a-f]\{7,40\}\).*/\1/p' "$f" | head -1)
        [ -n "$got" ] || continue
        case "$PIN" in
            "$got"*) : ;;
            *) fail "${f#"$REPO_ROOT"/}: header cites slax-kitchen @ $got but the pin is ${PIN%"${PIN#???????}"}... (re-copy, or update the header)" ;;
        esac
    done < "$TMP/hdr"
fi

check_result
