#!/bin/sh
# Build the slax-wine ISO: fetch -> stage app -> unpack -> apply -> pack -> assert.
#
# Deliberately NOT `kitchen build`: it runs tests/structure/iso_assert.py with no
# --volid, and that argument DEFAULTS to 'slax' (iso_assert.py:49 -- an argparse default,
# not a hardcoded constant; lib/build.sh is what never passes it). slax-wine-iso.yaml
# sets SLAX-WINE, so every build would fail its own test. The other two historical objections are gone --
# `apply --profile` runs no tests, and the output name is chosen at pack.
#
#   ./build.sh [--keep-work] [--no-fetch]
#
# --no-fetch skips DOWNLOADING the base ISO; it is still verified, and it does NOT cover
# the application payload, which is fetched whenever it is absent or its hash does not
# match. Fully offline therefore needs a warm isos/ AND a good notepadpp.files/.
#   ISO_DIR=/path/to/isos ./build.sh      # reuse ISOs you already have
#
# Only the apply step is elevated. bundle.packages needs a real chroot (CAP_SYS_CHROOT +
# CAP_MKNOD); unpack, pack and every assertion stay unprivileged.
set -eu

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)
# The cd above is inside a command substitution, so it never moved this shell. Move it
# now, because the profile names its recipes by RELATIVE path and kitchen resolves those
# against the CURRENT WORKING DIRECTORY, not the repo root: lib/apply.py:2761 is a bare
# `if os.path.isfile(n)`, and the search path is recipe_search_path() + [os.getcwd()].
# Without this line `/path/to/slax-wine/build.sh` run from anywhere else died with
# "recipe not found: recipes/available/wine.yaml" -- but only at step 4, AFTER step 3
# had already `rm -rf`'d the work tree and step 2 had downloaded the payload.
cd "$REPO_ROOT" || { echo "build.sh: cannot cd to $REPO_ROOT" >&2; exit 2; }
# shellcheck source=build.env
. "$REPO_ROOT/build.env"

K="$REPO_ROOT/vendor/slax-kitchen/kitchen"
ASSERT="$REPO_ROOT/vendor/slax-kitchen/tests/structure/iso_assert.py"
ISO_DIR=${ISO_DIR:-$REPO_ROOT/isos}
WORK=${WORK:-$REPO_ROOT/work}
OUT=${OUT:-$REPO_ROOT/out}
OUT_ISO="$OUT/slax-wine-$VERSION.iso"
STAGE="$REPO_ROOT/recipes/available/notepadpp.files"

# The expected /slax/modules contents. iso_assert.py has --require but no --forbid, and
# "chromium is gone" is half the size claim, so assert the list exactly -- that also
# catches an accidental extra bundle. NINE: five stock survivors, our three, and
# 98-dpkg-db.sb, which lib/pack.sh generates from the status fragments our bundles ship.
# Forgetting that last one is the easy way to fail the build on its own output.
WANT_MODULES="01-core.sb 01-firmware.sb 02-xorg.sb 03-desktop.sb 04-apps.sb 20-wine.sb 21-wine-desktop.sb 30-notepadpp.sb 98-dpkg-db.sb"

KEEP_WORK=0; NO_FETCH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-work) KEEP_WORK=1; shift ;;
        --no-fetch)  NO_FETCH=1; shift ;;
        *) echo "build.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

say() { printf '\n== %s\n' "$*"; }

[ -x "$K" ] || {
    echo "build.sh: vendor/slax-kitchen is empty -- run:" >&2
    echo "  git submodule update --init --recursive" >&2
    exit 2
}

# ---- 1. the base ISO ---------------------------------------------------------------
# `kitchen fetch` verifies size+sha256 first and prints "already verified" without
# downloading, so this doubles as the verify step when the file is already here.
say "base ISO"
mkdir -p "$ISO_DIR" "$OUT"
[ "$NO_FETCH" = 1 ] || "$K" fetch "$BASE_TARGET" -o "$ISO_DIR"
"$K" fetch "$BASE_TARGET" -o "$ISO_DIR" --verify-only

# ---- 2. the application payload ----------------------------------------------------
# Fetched and verified rather than committed. Not because committing is forbidden --
# .exe is not a forbidden extension and GitHub's limit is 100 MB -- but because
# slax-arcade needs the same mechanism for software that cannot be published at all, and
# one contract across both projects is worth more than build-time self-containment.
#
# Staged under a stable name so updating the app is two edits in build.env and nothing
# in the recipe, the wrapper or the .desktop entry.
say "application payload: $APP_NAME $APP_VERSION"
mkdir -p "$STAGE/opt/notepadpp"
APP_FILE="$STAGE/opt/notepadpp/npp-installer.exe"
if [ -f "$APP_FILE" ] && [ "$(sha256sum "$APP_FILE" | cut -d' ' -f1)" = "$APP_SHA256" ]; then
    echo "  ok   npp-installer.exe (already verified)"
else
    rm -f "$APP_FILE"
    curl -fsSL "$APP_URL" -o "$APP_FILE"
    got=$(sha256sum "$APP_FILE" | cut -d' ' -f1)
    if [ "$got" != "$APP_SHA256" ]; then
        rm -f "$APP_FILE"
        echo "build.sh: $APP_URL sha256 $got != build.env $APP_SHA256" >&2
        exit 1
    fi
    echo "  ok   npp-installer.exe ($(stat -c%s "$APP_FILE") bytes, sha256 verified)"
fi
# Provenance beside the payload, so the ISO is self-describing even though the filename
# is deliberately version-free.
cat > "$STAGE/opt/notepadpp/VERSION" <<PROV
$APP_NAME $APP_VERSION
upstream: $APP_URL
sha256:   $APP_SHA256
PROV

# ---- 3. unpack ---------------------------------------------------------------------
# Fresh every run. Recipes are NOT idempotent -- apply consults its journal and refuses
# a second application -- so a clean tree is the only supported starting point.
say "unpack"
rm -rf "$WORK"
"$K" unpack "$ISO_DIR/$BASE_ISO" -o "$WORK" --force

# ---- 4. apply ----------------------------------------------------------------------
# The profile is authoritative: it carries the ordered recipe list and any per-recipe
# vars, so there is exactly one place that says what this image is.
say "apply"
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo -E"
# Piping into tee would hide a failure: the pipeline's status is tee's, which is
# always 0, so `set -e` never fires. POSIX sh has no PIPESTATUS, so the success of the
# real command is recorded out of band. slax-kitchen's upstream-watch job was silently
# inert for exactly this reason.
# Give the tree back whether apply succeeded or not. bundle.packages runs as root and
# writes INTO work/iso/slax/modules/, so a root-owned work/ is left behind either way --
# and step 3's `rm -rf "$WORK"` is the first thing the NEXT run does, unprivileged. On
# the success path only, one failed build wedged every subsequent one with nothing but a
# bare "Permission denied" and no documented recovery.
#
# (Not the scratch dir: bundle.packages does put kitchen-pkg-* beside work/, but removes
# it in a `finally: shutil.rmtree(...)`, so that is not what this is for.)
give_back_work() {
    [ -n "$SUDO" ] || return 0
    [ -e "$WORK" ] || return 0
    $SUDO chown -R "$(id -u):$(id -g)" "$WORK" 2>/dev/null || true
}
rm -f "$OUT/.apply-ok"
{ $SUDO "$K" apply --profile "$REPO_ROOT/profiles/slax-wine.yaml" -w "$WORK" \
    && touch "$OUT/.apply-ok"; } 2>&1 | tee "$OUT/apply.log"
[ -f "$OUT/.apply-ok" ] || {
    give_back_work
    echo "build.sh: apply failed -- see $OUT/apply.log" >&2
    exit 1
}
rm -f "$OUT/.apply-ok"
give_back_work

# ---- 5. pack -----------------------------------------------------------------------
# --appid carries the version, because a CLI flag beats a recipe hint and that keeps
# every version string out of the YAML where it could drift from the git tag.
say "pack"
"$K" pack -s "$WORK/iso" -o "$OUT_ISO" \
    --appid "slax-wine $VERSION (base $BASE_ISO)" --force

# ---- 6. assert ---------------------------------------------------------------------
# Read the volid back out of the pack hints rather than hardcoding it here; the recipe
# is the one place that decides it.
say "assert"
VOLID=$(sed -n 's/^volid: *//p' "$WORK/.kitchen/pack.yaml" | head -1 | sed "s/^[\"']//;s/[\"']$//")
[ -n "$VOLID" ] || { echo "build.sh: no volid hint -- did slax-wine-iso.yaml run?" >&2; exit 1; }

python3 "$ASSERT" "$OUT_ISO" --volid "$VOLID" --max-size-mib "$MAX_ISO_MIB" \
    --require /slax/modules/20-wine.sb \
    --require /slax/modules/21-wine-desktop.sb \
    --require /slax/modules/30-notepadpp.sb \
    --require /slax/modules/98-dpkg-db.sb

got=$(xorriso -indev "$OUT_ISO" -lsl /slax/modules/ -- 2>/dev/null \
      | sed -n "s/.*'\\(.*\\.sb\\)'\$/\\1/p" | sort | tr '\n' ' ')
want=$(printf '%s ' $WANT_MODULES)
if [ "$got" != "$want" ]; then
    echo "build.sh: /slax/modules is not what was expected" >&2
    echo "  want: $want" >&2
    echo "  got:  $got"  >&2
    exit 1
fi
echo "  ok   modules: $got"

# ---- 7. measure --------------------------------------------------------------------
# One source for the docs' ## Verified sections, the release notes and the CI log.
say "summary"
SUM="$OUT/build-summary.txt"
{
    echo "slax-wine $VERSION"
    echo "base            $BASE_ISO ($BASE_SHA256)"
    echo "slax-kitchen    $(git -C "$REPO_ROOT/vendor/slax-kitchen" rev-parse --short HEAD)"
    echo "app             $APP_NAME $APP_VERSION"
    echo
    for b in 20-wine 21-wine-desktop 30-notepadpp 98-dpkg-db; do
        f="$WORK/iso/slax/modules/$b.sb"
        [ -f "$f" ] || continue
        sz=$(stat -c%s "$f")
        printf '%-18s %10s bytes  %6.1f MiB  %s paths\n' "$b.sb" "$sz" \
            "$(awk -v n="$sz" 'BEGIN{printf "%.1f", n/1048576}')" \
            "$(unsquashfs -l "$f" 2>/dev/null | grep -c squashfs-root)"
    done
    echo
    isz=$(stat -c%s "$OUT_ISO")
    printf 'ISO             %s bytes  %.1f MiB\n' "$isz" \
        "$(awk -v n="$isz" 'BEGIN{printf "%.1f", n/1048576}')"
    printf 'vs stock        %+d bytes\n' "$(( isz - BASE_SIZE ))"
    echo "sha256          $(cut -d' ' -f1 < "$OUT_ISO.sha256")"
    echo
    echo "--- apply delta lines ---"
    grep -E 'delta:|built slax/modules|removed|installed:' "$OUT/apply.log" || true
} > "$SUM"
cat "$SUM"

[ "$KEEP_WORK" = 1 ] || rm -rf "$WORK"
say "done -> $OUT_ISO"
