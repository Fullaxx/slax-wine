#!/bin/sh
# Write a release's SHA256SUMS, refusing any set of assets that is not exactly the release.
#
#   ci/release-sums.sh <dir> [--sizes FILE]
#   ci/release-sums.sh --list
#
# <dir> holds the assets. An ISO may be absent from it, which is how the release workflow's
# last job runs: it downloads only the small files from the draft, not 3.4 GB of images.
# An absent ISO's line is then taken from its .iso.sha256 -- which build.sh checked against
# the ISO when it was packed, and ci/release-stage.sh again before the upload -- and the
# ISO must be listed in FILE, one "name bytes" per line, as the draft reports it.
#
# Refused: an asset missing from both, an asset of 2 GiB or more, a malformed .iso.sha256 or
# one that disagrees with the ISO beside it, and any file in <dir> that is not an asset.
# --list prints what a release must carry, SHA256SUMS included.
set -eu
REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=build.env
. "$REPO_ROOT/build.env"
# shellcheck source=ci/release-lib.sh
. "$REPO_ROOT/ci/release-lib.sh"

if [ "${1:-}" = --list ]; then
    { release_assets "$VERSION"; echo SHA256SUMS; } | sort
    exit 0
fi
[ $# -ge 1 ] || { echo "usage: ci/release-sums.sh <dir> [--sizes FILE] | --list" >&2; exit 2; }
dir=$1; shift
sizes=""
if [ "${1:-}" = --sizes ]; then sizes=${2:?--sizes needs a file}; fi

rc=0
bad() { echo "release-sums: $*" >&2; rc=1; }

want=$(release_assets "$VERSION" | sort)
for f in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    [ "$n" = SHA256SUMS ] && continue
    printf '%s\n' "$want" | grep -qxF "$n" || bad "$n is not a release asset"
done

out=$(mktemp)
trap 'rm -f "$out"' EXIT
for n in $want; do
    if [ -f "$dir/$n" ]; then
        s=$(stat -c %s "$dir/$n")
        if [ "$s" -gt "$RELEASE_MAX_BYTES" ]; then
            bad "$n is $s bytes, over GitHub's 2 GiB asset limit"; continue
        fi
        line=$(cd "$dir" && sha256sum "$n")
        # An ISO's own .iso.sha256 is an asset too; two sums for one file must agree.
        if [ "${n%.iso}" != "$n" ] && [ -f "$dir/$n.sha256" ] && [ "$line" != "$(cat "$dir/$n.sha256")" ]; then
            bad "$n does not match its $n.sha256"; continue
        fi
        printf '%s\n' "$line" >> "$out"
        continue
    fi
    case "$n" in
        *.iso)
            s=""
            [ -z "$sizes" ] || s=$(awk -v n="$n" '$1 == n { print $2; exit }' "$sizes")
            if [ -z "$s" ]; then bad "$n is missing"; continue; fi
            [ "$s" -le "$RELEASE_MAX_BYTES" ] || bad "$n is $s bytes, over GitHub's 2 GiB asset limit"
            if [ ! -f "$dir/$n.sha256" ]; then bad "$n: no $n.sha256 to take its line from"; continue; fi
            line=$(cat "$dir/$n.sha256")
            printf '%s\n' "$line" | grep -qxE "[0-9a-f]{64}  $(printf '%s' "$n" | sed 's/[.]/\\./g')" \
                || { bad "$n.sha256 is not one '<sha256>  $n' line"; continue; }
            printf '%s\n' "$line" >> "$out" ;;
        *)  bad "$n is missing" ;;
    esac
done

[ "$rc" -eq 0 ] || { echo "release-sums: SHA256SUMS not written" >&2; exit 1; }
cp "$out" "$dir/SHA256SUMS"
echo "release-sums: $(wc -l < "$dir/SHA256SUMS") assets in $dir/SHA256SUMS"
