#!/bin/sh
# Assemble one or more shipped images' release assets from a build's output directory.
#
#   ci/release-stage.sh <build-out> <dest> <image>...
#
#   e.g. ci/release-stage.sh out out/release/1.0.0 slax32-wine-bios slax32-wine-uefi
#
# For each image: its .iso, .iso.sha256, .iso.provenance.json and .packages.tsv from
# <build-out>, and the engine's sources report written beside them -- the one command per
# image that slax-kitchen's publishing-images.md asks for. slax-bottles also gets its
# .flatpak.txt. Files are hardlinked where they can be, copied where they cannot.
#
# The release workflow runs this once per build job, and a person can run it by hand
# (docs/build.md). ci/release-sums.sh then refuses any set that is not exactly
# ci/release-lib.sh's list.
set -eu
REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=build.env
. "$REPO_ROOT/build.env"
# shellcheck source=ci/release-lib.sh
. "$REPO_ROOT/ci/release-lib.sh"
K="$REPO_ROOT/vendor/slax-kitchen/kitchen"

[ $# -ge 3 ] || { echo "usage: ci/release-stage.sh <build-out> <dest> <image>..." >&2; exit 2; }
src=$1; dest=$2; shift 2
mkdir -p "$dest"

put() {
    [ -s "$src/$1" ] || { echo "release-stage: $src/$1 is missing or empty" >&2; exit 1; }
    ln -f "$src/$1" "$dest/$1" 2>/dev/null || cp -f "$src/$1" "$dest/$1"
}

for img in "$@"; do
    case " $RELEASE_IMAGES " in
        *" $img "*) ;;
        *) echo "release-stage: $img is not a shipped image ($RELEASE_IMAGES)" >&2; exit 2 ;;
    esac
    b="$img-$VERSION"
    printf '== %s\n' "$b"
    for s in .iso .iso.sha256 .iso.provenance.json .packages.tsv; do put "$b$s"; done
    [ "$img" != slax-bottles ] || put "$b.flatpak.txt"
    "$K" sources "$dest/$b.iso" --markdown "$dest/$b.SOURCES.md" --json "$dest/$b.sources.json"
    # build.sh checked the ISO against its .sha256 when it was packed. Check the copy here
    # too, since this is the file that gets uploaded.
    ( cd "$dest" && sha256sum -c --quiet "$b.iso.sha256" ) \
        || { echo "release-stage: $b.iso does not match its .sha256" >&2; exit 1; }
    size=$(stat -c %s "$dest/$b.iso")
    [ "$size" -le "$RELEASE_MAX_BYTES" ] \
        || { echo "release-stage: $b.iso is $size bytes, over GitHub's 2 GiB asset limit" >&2; exit 1; }
done
