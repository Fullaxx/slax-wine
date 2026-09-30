# shellcheck shell=sh
# shellcheck disable=SC2034  # every variable here is read by the scripts that source this file
# What a slax-wine release carries, in one place. Sourced by ci/release-stage.sh, which
# assembles the assets, ci/release-sums.sh, which refuses a set that is not exactly this,
# and ci/release-notes.sh. tests/unit/test_release.py holds docs/build.md's list of assets
# and the release workflow's build matrix to the same.
#
# The five shipped images. The three test images are never published: they carry testkit,
# and exist to be booted (docs/build.md).
RELEASE_IMAGES="slax32-wine-bios slax32-wine-uefi slax64-wine-bios slax64-wine-uefi slax-bottles"

# Per image: the ISO, its checksum and provenance sidecar (kitchen pack), its package list
# (build.sh), and the sources report (`kitchen sources`, ci/release-stage.sh).
RELEASE_SUFFIXES=".iso .iso.sha256 .iso.provenance.json .packages.tsv .SOURCES.md .sources.json"

# GitHub refuses a release asset of 2 GiB or more. The largest image
# (docs/measurements.md#iso-slax-bottles) is well under it, and BOTTLES_MAX_ISO_MIB in
# build.env stops it long before this does.
RELEASE_MAX_BYTES=2147483647

# Every asset for version $1 except SHA256SUMS, one per line.
release_assets() {
    for _ri in $RELEASE_IMAGES; do
        for _rs in $RELEASE_SUFFIXES; do printf '%s-%s%s\n' "$_ri" "$1" "$_rs"; done
    done
    printf 'slax-bottles-%s.flatpak.txt\n' "$1"
}
