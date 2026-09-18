#!/bin/sh
# Build the slax-wine ISO: fetch -> stage app -> unpack -> apply -> pack -> assert.
#
# Deliberately NOT `kitchen build`: it runs tests/structure/iso_assert.py with no
# --volid, and that argument DEFAULTS to 'slax' (iso_assert.py:49 -- an argparse default,
# not a hardcoded constant; lib/build.sh is what never passes it). slax-wine-iso.yaml
# sets SLAX-WINE, so every build would fail its own test. The other two historical objections are gone --
# `apply --profile` runs no tests, and the output name is chosen at pack.
#
#   ./build.sh [--bios|--uefi|--both] [--keep-work] [--no-fetch]
#
# TWO IMAGES, and --both is the default because they are the release pair:
#   slax-wine-bios-<ver>.iso   stock bootloader. BIOS only.
#   slax-wine-uefi-<ver>.iso   + a GRUB ESP. Boots BIOS *and* UEFI -- it is a SUPERSET,
#                              not an alternative, because pack.sh adds the EFI El Torito
#                              entry with -eltorito-alt-boot and leaves the BIOS one.
# Same base, same nine bundles, and the same recipe list: upstream's remove-bundle first
# (it drops 05-chromium.sb, and the engine refuses a plan where a removal follows
# anything that builds), then our four. Use --bios while iterating; each variant is a
# full unpack+apply, so --both costs roughly twice the wall clock.
#
#   --test  builds slax-wine-test-<ver>.iso: the same recipes plus serial-console and
#           testkit, and uefi-bootable so both firmware paths can be exercised from one
#           image. NOT shipped and NOT part of --both; it is the artifact `kitchen test
#           --persistence` is run against. See profiles/slax-wine-test.yaml.
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
# against the CURRENT WORKING DIRECTORY, not the repo root: lib/apply.py:2842 is a bare
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
STAGE="$REPO_ROOT/recipes/available/notepadpp.files"

# The expected /slax/modules contents. iso_assert.py has --require but no --forbid, and
# "chromium is gone" is half the size claim, so assert the list exactly -- that also
# catches an accidental extra bundle. NINE: five stock survivors, our three, and
# 98-dpkg-db.sb, which lib/pack.sh generates from the status fragments our bundles ship.
# Forgetting that last one is the easy way to fail the build on its own output.
WANT_MODULES="01-core.sb 01-firmware.sb 02-xorg.sb 03-desktop.sb 04-apps.sb 20-wine.sb 21-wine-desktop.sb 30-notepadpp.sb 98-dpkg-db.sb"

KEEP_WORK=0; NO_FETCH=0; VARIANTS="bios uefi"
while [ $# -gt 0 ]; do
    case "$1" in
        --bios)      VARIANTS="bios"; shift ;;
        --uefi)      VARIANTS="uefi"; shift ;;
        --both)      VARIANTS="bios uefi"; shift ;;
        # Not shipped, and not in --both: the test image adds testkit, which prints to
        # the serial console and carries a persistence marker. It exists so
        # `kitchen test --persistence` has something of OURS to assert against.
        --test)      VARIANTS="test"; shift ;;
        --keep-work) KEEP_WORK=1; shift ;;
        --no-fetch)  NO_FETCH=1; shift ;;
        *) echo "build.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

say() { printf '\n== %s\n' "$*"; }

# Only the apply step is elevated; set this once rather than per variant.
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo -E"

# Give the tree back whether apply succeeded or not. bundle.packages runs as root and
# writes INTO <work>/iso/slax/modules/, so a root-owned tree is left behind either way --
# and `rm -rf` on it is the first thing the NEXT run does, unprivileged. Running this on
# the success path only meant one failed build wedged every subsequent one, with nothing
# but a bare "Permission denied" and no documented recovery.
#
# (Not the scratch dir: bundle.packages does put kitchen-pkg-* beside the work tree, but
# removes it in a `finally: shutil.rmtree(...)`, so that is not what this is for.)
give_back_work() {
    [ -n "$SUDO" ] || return 0
    [ -e "$1" ] || return 0
    $SUDO chown -R "$(id -u):$(id -g)" "$1" 2>/dev/null || true
}

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

# ---- 3..7, once per variant --------------------------------------------------------
# Two images, one build: same base, same core four recipes, same nine bundles. The UEFI
# profile adds `uefi-bootable` as a fifth recipe and nothing else. Everything below is
# shared, which is the point -- a difference between the two images can only come from
# that one recipe.
#
# Each variant gets its OWN work tree under work/, because recipes are not idempotent:
# apply consults its journal and refuses a second application, so the trees cannot be
# reused between variants. Keeping them under work/ also puts the engine's kitchen-pkg-*
# scratch dir (mkdtemp beside ctx.work) inside an already-gitignored directory.
build_variant() {
    v=$1
    profile="$REPO_ROOT/profiles/slax-wine-$v.yaml"
    work="$WORK/$v"
    out_iso="$OUT/slax-wine-$v-$VERSION.iso"
    applog="$OUT/apply-$v.log"
    sum="$OUT/build-summary-$v.txt"
    [ -f "$profile" ] || { echo "build.sh: no such profile: $profile" >&2; exit 2; }

    say "[$v] unpack"
    rm -rf "$work"
    "$K" unpack "$ISO_DIR/$BASE_ISO" -o "$work" --force

    # The profile is authoritative: it carries the ordered recipe list, so there is
    # exactly one place that says what this image is.
    say "[$v] apply"
    rm -f "$OUT/.apply-ok"
    { $SUDO "$K" apply --profile "$profile" -w "$work" \
        && touch "$OUT/.apply-ok"; } 2>&1 | tee "$applog"
    [ -f "$OUT/.apply-ok" ] || {
        give_back_work "$work"
        echo "build.sh: [$v] apply failed -- see $applog" >&2
        exit 1
    }
    rm -f "$OUT/.apply-ok"
    give_back_work "$work"

    # --appid carries the version, because a CLI flag beats a recipe hint and that keeps
    # every version string out of the YAML where it could drift from the git tag.
    #
    # No --uefi flag for the uefi variant: v_boot_uefi writes the pack hint `uefi: true`
    # and pack.sh reads it, switching to the xorriso backend on its own.
    say "[$v] pack"
    "$K" pack -s "$work/iso" -o "$out_iso" \
        --appid "slax-wine $VERSION $v (base $BASE_ISO)" --force

    # Read the volid back out of the pack hints rather than hardcoding it; the recipe is
    # the one place that decides it.
    say "[$v] assert"
    volid=$(sed -n 's/^volid: *//p' "$work/.kitchen/pack.yaml" | head -1 | sed "s/^[\"']//;s/[\"']$//")
    [ -n "$volid" ] || { echo "build.sh: [$v] no volid hint -- did slax-wine-iso.yaml run?" >&2; exit 1; }

    # The uefi image genuinely HAS an EFI El Torito entry, so its absence must stop being
    # asserted -- and its presence must start being. Getting this wrong in either
    # direction is a check that cannot fail.
    # `if`, not `[ ... ] && ...`. Under `set -e` an AND-OR list whose first command fails
    # is ignored MID-script, but is fatal as the LAST command of a function -- verified in
    # sh, dash and bash. Both of the `&&` forms this file used to have were safe only
    # because something happened to follow them, which is a property of the line order
    # rather than of the code. Two of these, so spell them out.
    #
    # DERIVED FROM THE PROFILE, not from the variant name. This keyed off `$v = uefi`
    # until the test profile also took uefi-bootable, at which point the build failed its
    # own assertion -- correctly, and that is the only reason it was noticed. A name is
    # not evidence about an artifact; the recipe list is. `kitchen build` derives the same
    # flag the same way (lib/build.sh: `case " $RECIPES " in *" uefi-bootable "*`).
    uefi_flag=""
    if grep -qE '^[[:space:]]*-[[:space:]]*uefi-bootable[[:space:]]*$' "$profile"; then
        uefi_flag="--expect-uefi"
    fi
    # shellcheck disable=SC2086
    python3 "$ASSERT" "$out_iso" --volid "$volid" --max-size-mib "$MAX_ISO_MIB" $uefi_flag \
        --require /slax/modules/20-wine.sb \
        --require /slax/modules/21-wine-desktop.sb \
        --require /slax/modules/30-notepadpp.sb \
        --require /slax/modules/98-dpkg-db.sb

    # WANT_MODULES is shared deliberately: uefi-bootable builds NO bundle, it writes one
    # boot/efi.img. If this ever differs between the variants, something is wrong.
    got=$(xorriso -indev "$out_iso" -lsl /slax/modules/ -- 2>/dev/null \
          | sed -n "s/.*'\\(.*\\.sb\\)'\$/\\1/p" | sort | tr '\n' ' ')
    want=$(printf '%s ' $WANT_MODULES)
    if [ "$got" != "$want" ]; then
        echo "build.sh: [$v] /slax/modules is not what was expected" >&2
        echo "  want: $want" >&2
        echo "  got:  $got"  >&2
        exit 1
    fi
    echo "  ok   modules: $got"

    say "[$v] summary"
    {
        echo "slax-wine $VERSION ($v)"
        echo "profile         profiles/slax-wine-$v.yaml"
        echo "base            $BASE_ISO ($BASE_SHA256)"
        echo "slax-kitchen    $(git -C "$REPO_ROOT/vendor/slax-kitchen" rev-parse --short HEAD)"
        echo "app             $APP_NAME $APP_VERSION"
        echo
        for b in 20-wine 21-wine-desktop 30-notepadpp 98-dpkg-db; do
            f="$work/iso/slax/modules/$b.sb"
            [ -f "$f" ] || continue
            sz=$(stat -c%s "$f")
            printf '%-18s %10s bytes  %6.1f MiB  %s paths\n' "$b.sb" "$sz" \
                "$(awk -v n="$sz" 'BEGIN{printf "%.1f", n/1048576}')" \
                "$(unsquashfs -l "$f" 2>/dev/null | grep -c squashfs-root)"
        done
        if [ -f "$work/iso/boot/efi.img" ]; then
            printf '%-18s %10s bytes  (GRUB ESP, not a bundle)\n' "boot/efi.img" \
                "$(stat -c%s "$work/iso/boot/efi.img")"
            # The ONLY GPLv3+ component in the image, and the only one built here rather
            # than redistributed as upstream shipped it -- grub-mkstandalone links the
            # host's GRUB into BOOTX64.EFI. NOTICE.md says the corresponding source is
            # whichever GRUB the build host had, so record which one that was. Without
            # this line that sentence would be a promise nothing keeps.
            printf '%-18s %s\n' "grub (ESP)" \
                "$(grub-mkstandalone --version 2>/dev/null | head -1 || echo unknown)"
        fi
        echo
        isz=$(stat -c%s "$out_iso")
        printf 'ISO             %s bytes  %.1f MiB\n' "$isz" \
            "$(awk -v n="$isz" 'BEGIN{printf "%.1f", n/1048576}')"
        printf 'vs stock        %+d bytes\n' "$(( isz - BASE_SIZE ))"
        echo "sha256          $(cut -d' ' -f1 < "$out_iso.sha256")"
        echo
        echo "--- apply delta lines ---"
        grep -E 'delta:|built slax/modules|removed|installed:' "$applog" || true
    } > "$sum"
    cat "$sum"

    [ "$KEEP_WORK" = 1 ] || rm -rf "$work"
    say "[$v] done -> $out_iso"
}

for v in $VARIANTS; do
    build_variant "$v"
done
