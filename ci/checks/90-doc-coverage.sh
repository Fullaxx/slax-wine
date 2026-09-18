#!/bin/sh
# stages: pre-commit pre-push ci
# desc: Every recipe has a cookbook page and is linked from the index, and vice versa.
#
# Adapted from slax-kitchen @ 8adfca617cecae8681b719fa7b3684b172726131 (ci/checks/90-doc-coverage.sh).
#
# NOT taken: upstream's RECIPE-count check ("thirty recipes ship today"). With four
# recipes here that lookup table is more machinery than the drift it prevents -- left
# out deliberately rather than forgotten. Nor the UPSTREAM-ISSUE count, which anchors on
# a link to docs/30-inventory/known-upstream-bugs.md; we have no such page, so the rule
# would skip forever and be a gate that cannot fail.
#
# TAKEN: the GATE-count check, because four files here state that number in prose and
# nothing else checks them. The anchor is WIDER than upstream's, measured against this
# tree rather than copied: upstream's `ci/checks|commit gates|run-checks` misses
# docs/ARCHITECTURE.md's "ci/   twelve gates" (bare `ci/`) and docs/build.md's "Twelve
# checks live in" (the noun is `checks`, not `gates`). Both are now covered.
#
# It has now been proved in anger. Adding ci/checks/80-unit.sh took the tree from eleven
# gates to twelve, and this check named three of the four stale files on the next run.
# The fourth, docs/ARCHITECTURE.md's tree-map line, states the count a SECOND time in the
# same file, and the check reports one hit per file -- so fixing what it names is not the
# same as fixing the tree. Grep the whole tree for the old number as well.
#
# Whole-tree by design: a rename touches two directories, and checking only staged
# files would pass a commit that moves one half.
. "$(dirname "$0")/../lib.sh"

# Collect-then-loop: fail() on the right of a pipe runs in a subshell and is lost.
TMPD=$(mktemp -d) || { fail "cannot create a temp dir"; check_result; exit; }
trap 'rm -rf "$TMPD"' EXIT INT TERM

RECIPES="$REPO_ROOT/recipes/available"
COOKBOOK="$REPO_ROOT/docs/50-cookbook"
INDEX="$COOKBOOK/README.md"

[ -d "$RECIPES" ]  || { note "recipes/available not present yet - skipping"; exit 0; }
[ -d "$COOKBOOK" ] || fail "missing docs/50-cookbook"
[ -f "$INDEX" ]    || fail "missing docs/50-cookbook/README.md"

for r in "$RECIPES"/*.yaml; do
    [ -e "$r" ] || continue
    n=$(basename "$r" .yaml)
    [ -f "$COOKBOOK/$n.md" ] || \
        fail "recipe has no cookbook page: recipes/available/$n.yaml -> docs/50-cookbook/$n.md"
    # A page nobody can reach from the index is the same failure as no page.
    [ -f "$INDEX" ] && { grep -q "]($n\.md)" "$INDEX" || \
        fail "recipe is not linked from the cookbook index: $n -> docs/50-cookbook/README.md"; }
done

for d in "$COOKBOOK"/*.md; do
    [ -e "$d" ] || continue
    n=$(basename "$d" .md)
    [ "$n" = README ] && continue
    [ -f "$RECIPES/$n.yaml" ] || \
        fail "cookbook page has no recipe: docs/50-cookbook/$n.md -> recipes/available/$n.yaml"
done

# ---- the gate count stated in prose --------------------------------------------------
# A number spelled out in words is exactly the fact nobody re-checks. Adding or removing
# one gate silently falsifies every sentence that counts them, and here that is four
# files. Upstream hit this at twelve-to-thirteen and had six wrong files at once.
#
# The lookup table returns "" for an unknown count and the caller SKIPS rather than
# fails -- a gate that blocks on its own table being short teaches people to disable it.
numword() {
    case "$1" in
        1) echo one ;;      2) echo two ;;       3) echo three ;;    4) echo four ;;
        5) echo five ;;     6) echo six ;;       7) echo seven ;;    8) echo eight ;;
        9) echo nine ;;    10) echo ten ;;      11) echo eleven ;;  12) echo twelve ;;
       13) echo thirteen ;;14) echo fourteen ;; 15) echo fifteen ;; 16) echo sixteen ;;
       17) echo seventeen ;; 18) echo eighteen ;; 19) echo nineteen ;; 20) echo twenty ;;
        *)  echo ;;
    esac
}

n=$(find "$REPO_ROOT/ci/checks" -maxdepth 1 -name '*.sh' | wc -l | tr -d ' ')
want=$(numword "$n")
[ -n "$want" ] || note "90-doc-coverage: no word for $n gates; count check skipped"
if [ -n "$want" ]; then
    words='one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty'
    # ANCHORED, and the anchor is load-bearing in both directions. "gates" is an ordinary
    # word, and this repo has lines that legitimately count a SUBSET -- docs/build.md's
    # "Six gates are copied verbatim from slax-kitchen, four are adapted" is true and must
    # not fail. A line claims the TOTAL only if it also names the thing that runs them.
    anchor='commit gates|selftest|ci/checks|ci/|run-checks|doctor --strict|checks live in|build script'
    check_files_nl | grep -E '\.md$' | grep -v '^vendor/' > "$TMPD/md" || true
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$REPO_ROOT/$f" ] || continue
        hit=$(grep -niE "\b($words)\b[[:space:]*_]+(commit[[:space:]]+)?(gates|checks)\b" \
              "$REPO_ROOT/$f" | grep -iE "$anchor" | grep -ivE "\b$want\b") || true
        [ -n "$hit" ] && fail "${f}: $(echo "$hit" | head -1) -- there are $n gates (want '$want')"
    done < "$TMPD/md"
fi

check_result
