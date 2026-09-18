#!/bin/sh
# stages: pre-commit pre-push ci
# desc: Every recipe has a cookbook page and is linked from the index, and vice versa.
#
# Adapted from slax-kitchen @ 9776a9042394deac25638847269154eb5cebc9ca (ci/checks/90-doc-coverage.sh). Upstream's version
# also checks that prose spelling out the recipe count ("thirty recipes ship today")
# matches reality; with four recipes here that lookup table would be more machinery
# than the drift it prevents, so it is left out deliberately rather than forgotten.
#
# Whole-tree by design: a rename touches two directories, and checking only staged
# files would pass a commit that moves one half.
. "$(dirname "$0")/../lib.sh"

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

check_result
