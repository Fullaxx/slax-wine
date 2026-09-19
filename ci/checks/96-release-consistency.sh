#!/bin/sh
# stages: pre-commit pre-push ci
# desc: build.env, the recipes, the profiles, the submodule pin, the copied files, the workaround ledger and the git tag all agree.
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
[ -f "$ENVF" ] || { fail "build.env is missing, and every section of this gate reads it"; check_result; exit; }

# shellcheck source=/dev/null
. "$ENVF"

# ---- 1. VERSION is a version ------------------------------------------------------
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' \
    || fail "build.env: VERSION '$VERSION' is not semver"

# ---- 2. each BASE*_TARGET is assembled from its own parts --------------------------
# kitchen names targets <flavour>-<arch>-<version>; keeping the parts separate makes
# them usable individually, and this stops the two spellings drifting apart.
want_target="$BASE32_FLAVOUR-$BASE32_ARCH-$BASE32_VERSION"
[ "$BASE32_TARGET" = "$want_target" ] \
    || fail "build.env: BASE32_TARGET '$BASE32_TARGET' != '$want_target' built from its parts"
# The 64-bit base, held to the same rule.
want_target="$BASE64_FLAVOUR-$BASE64_ARCH-$BASE64_VERSION"
[ "$BASE64_TARGET" = "$want_target" ] \
    || fail "build.env: BASE64_TARGET '$BASE64_TARGET' != '$want_target' built from its parts"

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
    # TWICE: the 32-bit base and the 64-bit one. `set --` rather than a loop over
    # names, so each call names its four values literally.
    for base in BASE32 BASE64; do
    if [ "$base" = BASE32 ]; then
        set -- "$BASE32_TARGET" "$BASE32_ISO" "$BASE32_SHA256" "$BASE32_SIZE"
    else
        set -- "$BASE64_TARGET" "$BASE64_ISO" "$BASE64_SHA256" "$BASE64_SIZE"
    fi
    if ! python3 - "$SRC" "$base" "$@" \
            > "$TMP/base" 2> "$TMP/base.err" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("NOTE python3-yaml not installed - base cross-check skipped"); sys.exit(0)
src, var, target, iso, sha, size = sys.argv[1:7]
doc = yaml.safe_load(open(src))
if not isinstance(doc, dict):
    print(f"FAIL {src} is not a YAML mapping"); sys.exit(0)
targets = doc.get("targets")
if not isinstance(targets, dict):
    print(f"FAIL {src} has no 'targets' mapping"); sys.exit(0)
t = targets.get(target)
if t is None:
    print(f"FAIL build.env: {var}_TARGET {target!r} is not a target in the pinned sources.yaml")
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
    done
fi

# ---- 4. the image cannot lie about itself ------------------------------------------
# wine-desktop.yaml writes /etc/slax-wine-release inline. An ISO that misreports its own
# version is worse than one that reports nothing, because it is believed.
# The file is named in both shipped profiles, so its absence is a broken build, not a
# reason to skip three assertions quietly.
WD="$REPO_ROOT/recipes/available/wine-desktop.yaml"
if [ ! -f "$WD" ]; then
    fail "recipes/available/wine-desktop.yaml is missing, so /etc/slax-wine-release is unchecked"
else
    line_present "$WD" "VERSION=\"$VERSION\"" \
        || fail "wine-desktop.yaml: /etc/slax-wine-release VERSION does not match build.env ($VERSION)"
    line_present "$WD" "BASE_ISO=\"$BASE32_ISO\"" \
        || fail "wine-desktop.yaml: /etc/slax-wine-release BASE_ISO does not match BASE32_ISO"
    line_present "$WD" "BASE_SHA256=\"$BASE32_SHA256\"" \
        || fail "wine-desktop.yaml: /etc/slax-wine-release BASE_SHA256 does not match BASE32_SHA256"
fi

# The same for slax-bottles, whose release file is written by bottles.yaml. The Bottles
# version has a line of its own (BOTTLES_SOURCE carries the prose), so it is checked the
# way every other line here is -- whole-line, fixed-string. An earlier draft grepped for a
# prefix of one combined line, which is exactly the loosening this file's header forbids.
BY="$REPO_ROOT/recipes/available/bottles.yaml"
if [ ! -f "$BY" ]; then
    fail "recipes/available/bottles.yaml is missing, so /etc/slax-bottles-release is unchecked"
else
    line_present "$BY" "VERSION=\"$VERSION\"" \
        || fail "bottles.yaml: /etc/slax-bottles-release VERSION does not match build.env ($VERSION)"
    line_present "$BY" "BASE_ISO=\"$BASE64_ISO\"" \
        || fail "bottles.yaml: /etc/slax-bottles-release BASE_ISO does not match BASE64_ISO"
    line_present "$BY" "BASE_SHA256=\"$BASE64_SHA256\"" \
        || fail "bottles.yaml: /etc/slax-bottles-release BASE_SHA256 does not match BASE64_SHA256"
    line_present "$BY" "BOTTLES_VERSION=\"$BOTTLES_VERSION\"" \
        || fail "bottles.yaml: /etc/slax-bottles-release BOTTLES_VERSION does not match build.env ($BOTTLES_VERSION)"
fi

# ---- 5. no orphan recipes, and the two shipped profiles must not drift --------------
# The profiles are authoritative (build.sh drives `kitchen apply --profile`), so a recipe
# in NO profile is never built and never tested -- it just looks like it ships.
#
# There are two shipped profiles now, bios and uefi, and they are meant to build the same
# system by two boot routes. That makes them exactly the kind of pair that drifts: add a
# recipe to one, forget the other, and half the release quietly stops containing it. So
# this section asserts both halves -- coverage, and agreement.
PROFDIR="$REPO_ROOT/profiles"
CORE_A="$PROFDIR/slax32-wine-bios.yaml"
CORE_B="$PROFDIR/slax32-wine-uefi.yaml"

if [ ! -d "$REPO_ROOT/recipes/available" ]; then
    fail "recipes/available is missing, so the profiles have nothing of ours to build"
elif [ ! -d "$PROFDIR" ]; then
    fail "profiles/ is missing, so no recipe is built by anything"
else
    find "$PROFDIR" -maxdepth 1 -name '*.yaml' > "$TMP/prof"
    [ -s "$TMP/prof" ] || fail "profiles/ contains no profile"

    # (a) every recipe is named by at least one profile.
    find "$REPO_ROOT/recipes/available" -maxdepth 1 -name '*.yaml' > "$TMP/rec"
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        n=$(basename "$r" .yaml)
        seen=0
        while IFS= read -r prof; do
            [ -n "$prof" ] || continue
            # The LIST ENTRY, not the name anywhere in the file. Every recipe name also
            # appears in profile comments, so a substring grep here passed for a recipe
            # no profile built -- this gate carried that bug once already.
            if line_present "$prof" "- recipes/available/$n.yaml"; then seen=1; break; fi
        done < "$TMP/prof"
        [ "$seen" = 1 ] || fail "recipe is in no profile, so it is never built: $n"
    done < "$TMP/rec"

    # (a2) ...and the reverse: every recipe a profile NAMES actually exists. Without this
    # a typo in a path -- notepad-pp.yaml, or a .yml extension -- passes every gate and
    # fails at build time, which is exactly the class of error this section exists for.
    # Verified by introducing one: before this check, all eleven gates stayed green.
    while IFS= read -r prof; do
        [ -n "$prof" ] || continue
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$prof" \
            | sed -n 's|^- \(recipes/available/.*\)$|\1|p' > "$TMP/named" || true
        while IFS= read -r named; do
            [ -n "$named" ] || continue
            [ -f "$REPO_ROOT/$named" ] \
                || fail "${prof#"$REPO_ROOT"/} names a recipe that does not exist: $named"
        done < "$TMP/named"
    done < "$TMP/prof"

    # (a3) the browser removal is listed, and listed BEFORE anything that builds.
    #
    # lib/validate.py refuses a recipe that mixes bundle.remove with building, so the
    # removal lives in upstream's `remove-bundle` and each profile must list it. It is
    # THEIRS, so it is named rather than pathed, which means check (b) below -- which
    # compares recipes/available/ paths -- cannot see it: the two shipped profiles could
    # disagree about whether the browser is removed at all and (b) would stay green. Drop it and the image silently gains 82 MiB
    # and a three-year-old browser; list it late and check_plan_order refuses the build.
    # slax-bottles is held to removal-first too. It is NOT part of (b): it is a different
    # system, not a third boot route to the same one.
    for prof in "$CORE_A" "$CORE_B" "$PROFDIR/slax-bottles.yaml"; do
        rel=${prof#"$REPO_ROOT"/}
        # A shipped profile that is missing cannot be checked, and "cannot be checked" is
        # a failure here, not a skip (8e33450 retired the others). bios and uefi also fail
        # in (b) below; slax-bottles has no other check that would notice.
        [ -f "$prof" ] || { fail "$rel is missing, so its removal order is unchecked"; continue; }
        # Both spellings: the bare `- remove-bundle` and the object form
        # `- name: remove-bundle`, which is what these profiles actually use so that
        # `drop:` is stated rather than inherited. Matching only one would make this
        # check silently stop applying the day the other is adopted.
        rm_ln=$(grep -nE '^[[:space:]]*-[[:space:]]*(name:[[:space:]]*)?remove-bundle[[:space:]]*$' "$prof" \
                | head -1 | cut -d: -f1)
        first_build=$(grep -nE '^[[:space:]]*-[[:space:]]*recipes/available/' "$prof" \
                      | head -1 | cut -d: -f1)
        if [ -z "$rm_ln" ]; then
            fail "$rel does not list remove-bundle, so 05-chromium would ship"
        elif [ -n "$first_build" ] && [ "$rm_ln" -gt "$first_build" ]; then
            fail "$rel lists remove-bundle after a building recipe (line $rm_ln > $first_build); removal must come first"
        fi
    done

    # (b) the two shipped profiles carry an IDENTICAL core list, in the same order.
    # uefi adds `- uefi-bootable`, a bare name resolved from the engine, so comparing
    # only the recipes/available/ entries is the right comparison.
    if [ ! -f "$CORE_A" ] || [ ! -f "$CORE_B" ]; then
        fail "expected both profiles/slax32-wine-bios.yaml and -uefi.yaml; the release is a pair"
    else
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$CORE_A" \
            | grep -E '^- recipes/available/' > "$TMP/core-a" || true
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$CORE_B" \
            | grep -E '^- recipes/available/' > "$TMP/core-b" || true
        [ -s "$TMP/core-a" ] || fail "slax32-wine-bios.yaml lists no recipes"
        if ! cmp -s "$TMP/core-a" "$TMP/core-b"; then
            fail "the bios and uefi profiles disagree on the core recipe list:$(
                  diff "$TMP/core-a" "$TMP/core-b" | tr '\n' ' ')"
        fi
    fi
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

# ---- 7. copied files cite the pin they were copied from ----------------------------
# Every copied file carries "slax-kitchen @ <40 hex>" and "Do not edit here -- re-copy on
# a submodule bump". Nothing enforced the first half, so a pin bump left twelve headers
# naming the OLD commit while the content had in fact been refreshed -- a reader cannot
# tell a stale citation from stale content, which is the header's entire purpose.
#
# SCOPE IS ci/ AND tests/, not ci/ alone. Copied code stopped being ci-only the moment
# tests/unit/ arrived, and a scan that covers only the directory that happened to exist
# when it was written is how the rot it prevents gets back in through the side door.
#
# This is the invariant this gate's own `# desc:` line has always claimed to check.
#
# THE PIN IS READ FROM THE SUBMODULE AND NOWHERE ELSE. A bare `git -C vendor/slax-kitchen`
# can answer for THIS repository instead, two ways, both measured:
#
#   a commit from a     git exports GIT_DIR to the hooks, and GIT_DIR beats -C. The pin read
#   linked worktree     back as our own HEAD and sections 7 and 8 failed 24 times on a clean
#                       tree, refusing the commit.
#   an uninitialised    an empty directory, so discovery walks up and finds ours: `rev-parse
#   submodule           HEAD` succeeded, the "not checked out" note below could never fire,
#                       and every citation was compared with the wrong commit.
#
# So subgit() clears git's repository-local variables -- the names come from git, as in
# 80-unit.sh, and in a subshell, because this gate's other git calls must KEEP them to see
# the commit in progress -- and sub_ready() insists that the repository git then finds is
# the submodule's own. Found while adding section 10, which reads the submodule's history
# the same way; tests/unit/test_release_consistency.py drives both cases.
_repo_env=$(git rev-parse --local-env-vars 2>/dev/null)
subgit() { ( unset $_repo_env; git -C "$REPO_ROOT/vendor/slax-kitchen" "$@" ); }
sub_ready() {
    _subtop=$(subgit rev-parse --show-toplevel 2>/dev/null) || return 1
    [ "$_subtop" = "$(cd "$REPO_ROOT/vendor/slax-kitchen" 2>/dev/null && pwd -P)" ]
}
if ! have git; then
    note "git not installed - provenance-header check skipped"
elif [ -z "$_repo_env" ]; then
    # Fail closed, as 80-unit.sh does: without the list the hook's repository stays in
    # reach, and a pin read from there is a guess that looks like a measurement.
    fail "git rev-parse --local-env-vars answered nothing, so the pin cannot be read from the submodule alone -- refusing to guess it"
elif ! sub_ready; then
    note "vendor/slax-kitchen not checked out - provenance-header check skipped"
else
    PIN=$(subgit rev-parse HEAD)
    : > "$TMP/hdr"
    for d in ci tests; do
        [ -d "$REPO_ROOT/$d" ] || continue
        grep -rln 'slax-kitchen @ [0-9a-f]' "$REPO_ROOT/$d" >> "$TMP/hdr" 2>/dev/null || true
    done
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

# ---- 8. prose and permalinks cite the pin too --------------------------------------
# Section 7 covers the provenance headers on copied FILES. The pin is also stated in
# English -- "slax-kitchen pinned at `<hex>`" -- and embedded in permalinks into their
# docs, and nothing checked either: the 8adfca6 bump found seven stale citations by grep,
# across CHANGELOG.md, docs/build.md and five links in INSTALL.md. A grep that has to be
# remembered is not a check.
#
# A PERMALINK IS NOT EXEMPT JUST BECAUSE IT IS A PERMALINK. Pinning the URL is right --
# upstream renamed remove-chromium.md out of existence, which is exactly what a permalink
# protects a reader from -- but it should point at the docs for the engine THIS release
# ships, not at whatever was current three bumps ago.
#
# docs/UPSTREAM.md is exempt from the prose half and only from that half: it is the bump
# history, so "at the bcd4f00 bump" is a fact about the past and must not be rewritten.
# It carries no blob/tree links, so the permalink half needs no exemption.
if [ -z "${PIN:-}" ]; then
    :                                       # section 7 already said why it could not run
else
    short=${PIN%"${PIN#???????}"}

    # The markdown in scope, listed ONCE for (a) and (b): what git tracks plus what it would
    # track (untracked, not ignored) -- ci/lib.sh's own definition of "in scope", and the
    # same call section 10 makes. vendor/ drops out by itself, because a submodule is one
    # gitlink entry, not files. A walk of the disk also read the gitignored build stages:
    # recipes/available/bottles.files/ holds Flathub's runtimes, 64 .md files that are not
    # ours, 11 of them dangling symlinks.
    #
    # git's exit status is checked rather than piped away: a list that failed to build
    # would otherwise read as "no markdown, so nothing stale", which is a pass.
    if git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard -- '*.md' \
            > "$TMP/mds0" 2> "$TMP/mds.err"; then
        tr '\0' '\n' < "$TMP/mds0" | sed "s|^|$REPO_ROOT/|" > "$TMP/mds"
    else
        fail "section 8: git ls-files failed, so no markdown was checked: $(tr '\n' ' ' < "$TMP/mds.err")"
        : > "$TMP/mds"
    fi

    # (a) permalinks into their tree, in the markdown listed above
    : > "$TMP/links"
    while IFS= read -r md; do
        [ -n "$md" ] || continue
        grep -HnoE 'slax-kitchen/(blob|tree)/[0-9a-f]{7,40}' "$md" >> "$TMP/links" 2>/dev/null || true
    done < "$TMP/mds"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        got=${hit##*/}
        case "$PIN" in
            "$got"*) : ;;
            # The list holds ABSOLUTE paths, so ${hit%%:*} is one; strip it
            # to repo-relative like every other message in this gate. (The first version
            # printed /root/code/... -- a build-machine path in a gate about citations.)
            *) fail "$(printf '%s' "${hit%%:*}" | sed "s|^$REPO_ROOT/||"): permalink cites slax-kitchen @ $got but the pin is $short... (${hit#*:} -- point it at the engine this release ships)" ;;
        esac
    done < "$TMP/links"

    # (b) "pinned at `<hex>`" in prose. Newline-tolerant, because CHANGELOG.md wraps
    # between the words and the hex -- the first draft of this check missed it for
    # exactly that reason and would have passed the stale line it was written to catch.
    # Reads the markdown list built above.
    while IFS= read -r md; do
        [ -n "$md" ] || continue
        rel=${md#"$REPO_ROOT"/}
        [ "$rel" = "docs/UPSTREAM.md" ] && continue
        got=$(tr '\n' ' ' < "$md" \
              | grep -oE 'pinned at \[?`[0-9a-f]{7,40}`' \
              | sed 's/.*`\([0-9a-f]*\)`/\1/' | head -1)
        [ -n "$got" ] || continue
        case "$PIN" in
            "$got"*) : ;;
            *) fail "$rel: prose says the engine is pinned at $got but the pin is $short..." ;;
        esac
    done < "$TMP/mds"
fi

# ---- 9. "copied verbatim" has to MEAN verbatim ------------------------------------
# Section 7 checks the citation; this checks the content, and the two failures are
# opposite. A header naming the current pin over stale content is the worse of the pair,
# because it reads as verified. That is not hypothetical here: before this bump our
# copies of ci/lib.sh and 00-no-binaries.sh were missing the #19 fix while their headers
# looked fine, so the gate that calls itself the most important one in this repo accepted
# a committed .exe -- in a project whose stated premise is "fetch Windows binaries, never
# commit them".
#
# A file claiming "Copied verbatim" must differ from the vendored original by NOTHING but
# the two provenance lines. Files marked "Adapted from" are deliberately different and
# are not checked here -- their differences are stated in their own headers, which is the
# whole reason the two words are distinct.
if [ -z "${PIN:-}" ]; then
    :
else
    for d in ci tests; do
        [ -d "$REPO_ROOT/$d" ] || continue
        # ANCHORED to the header form. An unanchored search matches this very file,
        # which mentions the phrase in its own grep pattern and comments -- the first
        # version of this check failed on itself.
        grep -rlE '^# Copied verbatim from slax-kitchen @' "$REPO_ROOT/$d" 2>/dev/null || true
    done > "$TMP/verbatim"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel=${f#"$REPO_ROOT"/}
        up=$(grep -o 'slax-kitchen @ [0-9a-f]* ([^)]*)' "$f" | head -1 | sed 's/.*(\(.*\))/\1/')
        [ -n "$up" ] || { fail "$rel: says 'Copied verbatim' but names no upstream path"; continue; }
        orig="$REPO_ROOT/vendor/slax-kitchen/$up"
        [ -f "$orig" ] || { fail "$rel: upstream path no longer exists at the pin: $up"; continue; }
        grep -vE '^# (Copied verbatim from slax-kitchen @|MIT, same author\. Do not edit here)' \
             "$f" > "$TMP/stripped"
        if ! cmp -s "$TMP/stripped" "$orig"; then
            n=$(diff "$TMP/stripped" "$orig" | grep -c '^[<>]')
            fail "$rel: claims 'Copied verbatim' but differs from vendor/slax-kitchen/$up by $n line(s) -- re-copy it, or change the header to 'Adapted from' and say what differs"
        fi
    done < "$TMP/verbatim"
fi

# ---- 10. every workaround is on the ledger, and the pin has not fixed it -----------
# docs/UPSTREAM.md "Local workarounds" lists every place this repo works around a
# slax-kitchen bug, and the code marks each one `WORKAROUND <issue URL>`. This holds the
# two in step, and makes the BUMP the moment a fixed workaround is noticed:
#
#   (a) every marker outside vendor/ and the Markdown has a row that is not retired, for
#       the same issue and the same file;
#   (b) every row that is not retired names a file that still carries its marker;
#   (c) an ACTIVE row fails once the pin's history says "Closes #N" for its issue: retire
#       the workaround in that bump, or mark the row "kept after fix" and say why.
#
# WHY A GATE. The lifecycle used to say a workaround carries its issue URL so that grep
# finds it. The #23 workaround carried none, nothing noticed, and it was found at the next
# bump only by reading its Adapted header. (c) reads the VENDORED history -- what the pin
# actually contains, with no network -- and keys on the same "Closes #N" line the register
# does. An issue closed without a fix has no such line, which is the right answer: its
# workaround is still needed.
LEDGER="$REPO_ROOT/docs/UPSTREAM.md"
if [ ! -f "$LEDGER" ]; then
    fail "docs/UPSTREAM.md is missing, and with it the workaround ledger"
elif ! grep -qx '## Local workarounds' "$LEDGER"; then
    fail "docs/UPSTREAM.md has no '## Local workarounds' section, which is the ledger section 10 checks"
else
    # Table rows -> "<issue> <file> <state>". A status the rule does not know becomes "?"
    # and fails below, rather than being read as whichever state it most resembles.
    awk -F'|' '
        /^## /            { on = ($0 == "## Local workarounds"); next }
        !on               { next }
        $0 !~ /^\| *\[#/  { next }
        {
            n = $2; sub(/.*issues\//, "", n); sub(/\).*/, "", n)
            f = $3; gsub(/[` ]/, "", f)
            s = $5; sub(/^ +/, "", s)
            st = "?"
            if (s ~ /^active since /)  st = "active"
            if (s ~ /^kept after fix/) st = "kept"
            if (s ~ /^retired at /)    st = "retired"
            print n, f, st
        }' "$LEDGER" > "$TMP/rows"

    # Markers -> "<issue> <file>". Tracked files only -- work/ and out/ hold whole root
    # filesystems -- and not the Markdown, which talks ABOUT markers.
    git -C "$REPO_ROOT" ls-files > "$TMP/tracked" 2>/dev/null || true
    : > "$TMP/marks"
    while IFS= read -r f; do
        case "$f" in vendor/*|*.md) continue ;; esac
        [ -f "$REPO_ROOT/$f" ] || continue
        grep -oE 'WORKAROUND https://github\.com/Fullaxx/slax-kitchen/issues/[0-9]+' "$REPO_ROOT/$f" \
          | sed "s|.*/||; s|\$| $f|" >> "$TMP/marks"
    done < "$TMP/tracked"

    while read -r n f st; do
        [ -n "$n" ] || continue
        case "$st" in
            retired) : ;;
            active|kept)                                                            # (b)
                grep -qxF "$n $f" "$TMP/marks" || \
                    fail "docs/UPSTREAM.md Local workarounds: #$n is $st in $f, but $f carries no WORKAROUND marker for it -- retire the row, or mark the code" ;;
            *)  fail "docs/UPSTREAM.md Local workarounds: #$n ($f) -- a status begins 'active since', 'kept after fix' or 'retired at'" ;;
        esac
    done < "$TMP/rows"

    while read -r n f; do                                                           # (a)
        [ -n "$n" ] || continue
        awk -v n="$n" -v f="$f" '$1 == n && $2 == f && $3 != "retired" { ok = 1 } END { exit !ok }' "$TMP/rows" || \
            fail "$f: WORKAROUND for slax-kitchen#$n has no row in docs/UPSTREAM.md Local workarounds that is not retired -- add one, or remove the marker with the workaround"
    done < "$TMP/marks"

    if [ -n "${PIN:-}" ]; then                                                      # (c)
        while read -r n f st; do
            [ "$st" = active ] || continue
            fix=$(subgit log -E -i --format=%h \
                      --grep="^(closes|fixes|resolves) #$n([^0-9]|\$)" "$PIN" 2>/dev/null | tail -1)
            if [ -n "$fix" ]; then
                fail "$f: works around slax-kitchen#$n, which $fix closed and the pin (${PIN%"${PIN#???????}"}) contains -- retire the workaround in this bump, or mark its row 'kept after fix' and say why"
            fi
        done < "$TMP/rows"
    fi
fi

check_result
