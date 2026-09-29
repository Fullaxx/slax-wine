#!/bin/sh
# Print a release's notes, from the tree and the assets rather than from memory.
#
#   ci/release-notes.sh <tag> <asset-dir> [--sizes FILE] [--run-url URL]
#
# The image sizes come from the ISOs in <asset-dir>, or, where one is absent, from FILE
# ("name bytes" per line, as the draft reports it; see ci/release-sums.sh). The bases come
# from build.env, the engine pin from this commit's own tree, and the Bottles version from
# slax-bottles' .flatpak.txt. --run-url names the
# workflow run that built the release; without it the notes say the release was built by
# hand. Everything else links to the tag, so the notes carry no claim the tree does not.
set -eu
REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=build.env
. "$REPO_ROOT/build.env"
# shellcheck source=ci/release-lib.sh
. "$REPO_ROOT/ci/release-lib.sh"

[ $# -ge 2 ] || { echo "usage: ci/release-notes.sh <tag> <asset-dir> [--sizes FILE] [--run-url URL]" >&2; exit 2; }
TAG=$1; dir=$2; shift 2
sizes=""; run_url=""
while [ $# -gt 0 ]; do
    case "$1" in
        --sizes)   sizes=${2:?--sizes needs a file}; shift 2 ;;
        --run-url) run_url=${2:?--run-url needs a URL}; shift 2 ;;
        *) echo "release-notes: unknown option $1" >&2; exit 2 ;;
    esac
done

REPO=${GITHUB_REPOSITORY:-Fullaxx/slax-wine}
BLOB="https://github.com/$REPO/blob/$TAG"
# The gitlink this commit records, not the submodule's checkout: the pin is what the tree says.
PIN=$(git -C "$REPO_ROOT" ls-tree HEAD vendor/slax-kitchen | awk '{ print substr($3, 1, 7) }')
[ -n "$PIN" ] || { echo "release-notes: cannot read the slax-kitchen pin from HEAD" >&2; exit 1; }

# The Bottles version is whatever Flathub served (D-20), so it comes from what shipped: the
# first line of slax-bottles' .flatpak.txt, "com.usebottles.bottles <version>".
fpk="$dir/slax-bottles-$VERSION.flatpak.txt"
BOTTLES_GOT=$(awk -v app="$BOTTLES_APP" 'NR == 1 && $1 == app { print $2 }' "$fpk" 2>/dev/null || true)
[ -n "$BOTTLES_GOT" ] || { echo "release-notes: cannot read the Bottles version from $fpk" >&2; exit 1; }

size_of() {
    if [ -f "$dir/$1" ]; then stat -c %s "$dir/$1"
    elif [ -n "$sizes" ]; then awk -v n="$1" '$1 == n { print $2; exit }' "$sizes"
    fi
}
what() {
    case "$1" in
        slax32-wine-bios) echo "32-bit base, the stock Slax bootloader" ;;
        slax32-wine-uefi) echo "32-bit base; also boots on 64-bit UEFI" ;;
        slax64-wine-bios) echo "64-bit base; runs 64-bit Windows programs too" ;;
        slax64-wine-uefi) echo "64-bit base; also boots on 64-bit UEFI" ;;
        slax-bottles)     echo "64-bit base, Bottles $BOTTLES_GOT as a Flatpak, offline" ;;
    esac
}

cat <<EOF
Slax with Wine, in four images, and Slax with Bottles, in one. What changed is in
[CHANGELOG.md]($BLOB/CHANGELOG.md), and which image to take is in [INSTALL.md]($BLOB/INSTALL.md).

| image | size | |
|---|---|---|
EOF
for img in $RELEASE_IMAGES; do
    n="$img-$VERSION.iso"
    s=$(size_of "$n")
    [ -n "$s" ] || { echo "release-notes: no size for $n" >&2; exit 1; }
    printf '| `%s` | %s MiB | %s |\n' "$n" "$(awk -v b="$s" 'BEGIN { printf "%.1f", b / 1048576 }')" "$(what "$img")"
done

cat <<EOF

Check the download first, in the directory you saved it to:

\`\`\`sh
sha256sum -c --ignore-missing SHA256SUMS
\`\`\`

## What it is built from

- **slax-kitchen** pinned at [\`$PIN\`](https://github.com/Fullaxx/slax-kitchen/tree/$PIN).
- **\`$BASE32_ISO\`**, sha256 \`$BASE32_SHA256\`.
- **\`$BASE64_ISO\`**, sha256 \`$BASE64_SHA256\`.
- **slax-wine** at \`$TAG\`. Each image's \`.iso.provenance.json\` records both commits and every
  step applied.

## Each image comes with

\`.iso.sha256\`, \`.iso.provenance.json\`, \`.packages.tsv\` (every installed package and version),
\`SOURCES.md\` and \`sources.json\`. slax-bottles also has \`.flatpak.txt\`, every Flatpak ref with its
ostree commit. One \`SHA256SUMS\` covers every file in the release.

## Redistribution and source

No source is attached. What slax-wine changed is this repository, at the tag. Each image's
\`SOURCES.md\` says where every other part's source is published: Slax, each Debian source package on
snapshot.debian.org, linux-firmware at its tag, Notepad++, the Bottles Flatpak, DXVK and
VKD3D-Proton, and GRUB. The policy, and the licences, are in [NOTICE.md]($BLOB/NOTICE.md).

## How it was verified

EOF
if [ -n "$run_url" ]; then
    cat <<EOF
Built and tested from the tagged commit by [the release workflow]($run_url), on GitHub's hosted
runners:

- **The commit gates:** all of them, \`./ci/run-checks.sh ci\`.
- **The builds:** the five images here and the three test images. Each build asserts its module
  list, size ceiling, volume id and release file.
- **The boot routes:** \`--kernel\`, \`--bios\`, \`--uefi\` and \`--persistence\` on each test image,
  in QEMU. Every route reaches \`Live Kit done\`, the persistence marker survives the second boot,
  and \`automount\` is absent from the kernel command line on the isolinux and GRUB routes. Each
  serial log is in the run's \`boot-evidence\` artifacts.
EOF
else
    cat <<EOF
Built and tested by hand from the tagged commit, as [docs/build.md]($BLOB/docs/build.md) describes.
EOF
fi

cat <<EOF

Nothing has been run on real hardware. The rest of what is untested or missing, including
persistence and UEFI from a USB stick, is under *Known limitations* in the CHANGELOG.

Releases are **unsigned by choice**; \`SHA256SUMS\` is the check.
EOF
