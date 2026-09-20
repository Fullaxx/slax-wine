#!/bin/sh
# Build the slax-wine and slax-bottles ISOs: fetch -> stage apps -> unpack -> apply -> pack
# -> assert.
#
# Deliberately NOT `kitchen build`: it runs tests/structure/iso_assert.py with no
# --volid, and that argument DEFAULTS to 'slax' (iso_assert.py:49 -- an argparse default,
# not a hardcoded constant; lib/build.sh is what never passes it). slax-wine-iso.yaml
# sets SLAX32-WINE or SLAX64-WINE, so every build would fail its own test. The other two
# historical objections are gone -- `apply --profile` runs no tests, and the output name
# is chosen at pack.
#
#   ./build.sh [--32|--64] [--bios|--uefi|--both|--test] [--keep-work] [--no-fetch]
#   ./build.sh --bottles|--bottles-test|--all                [--keep-work] [--no-fetch]
#
# slax-wine is FOUR IMAGES, bios and uefi on each architecture, and a bare ./build.sh
# builds all four:
#   slax32-wine-bios-<ver>.iso   32-bit base, stock bootloader. BIOS only.
#   slax32-wine-uefi-<ver>.iso   32-bit base, + a GRUB ESP. Boots BIOS *and* UEFI.
#   slax64-wine-bios-<ver>.iso   64-bit base, stock bootloader. BIOS only.
#   slax64-wine-uefi-<ver>.iso   64-bit base, + a GRUB ESP. Boots BIOS *and* UEFI.
# A uefi image is a SUPERSET, not an alternative: pack.sh adds the EFI El Torito entry
# with -eltorito-alt-boot and leaves the BIOS one. --32 or --64 picks one architecture and
# --bios or --uefi one firmware; each image is a full unpack+apply, so narrow it while
# iterating.
#
# The same recipes on all four: upstream's remove-bundle first (it drops 05-chromium.sb,
# and the engine refuses a plan where a removal follows anything that builds), then wine,
# wine-desktop, notepadpp32 and slax-wine-iso. The 64-bit images add notepadpp64, and the
# uefi images add uefi-bootable last.
#
#   --test  builds slax32-wine-test-<ver>.iso and slax64-wine-test-<ver>.iso, or one of
#           them with --32 or --64: the uefi recipes plus serial-console and testkit, so
#           both firmware paths can be exercised from one image. NOT shipped; it is the
#           artifact `kitchen test` is run against. See profiles/slax32-wine-test.yaml.
#
#   --bottles       builds slax-bottles-<ver>.iso: a DIFFERENT system on the 64-bit base,
#                   Bottles from Flathub and no Debian Wine. See profiles/slax-bottles.yaml.
#   --bottles-test  its testkit image, the counterpart of --test.
#   --all           the four slax-wine images and slax-bottles: every shipped image.
#
# --no-fetch skips DOWNLOADING the base ISOs; they are still verified, and it does NOT
# cover the application payloads, which are fetched whenever one is absent or its hash
# does not match. Fully offline therefore needs a warm isos/ AND good notepadpp32.files/
# and notepadpp64.files/ -- and, for the bottles variants, a bottles.files/ that already
# matches BOTTLES_LOCK.
#   ISO_DIR=/path/to/isos ./build.sh      # reuse ISOs you already have
#
# Only the apply step is elevated. bundle.packages needs a real chroot (CAP_SYS_CHROOT +
# CAP_MKNOD); unpack, pack and every assertion stay unprivileged.
set -eu

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)
# The cd above is inside a command substitution, so it never moved this shell. Move it
# now, because the profile names its recipes by RELATIVE path and kitchen resolves those
# against the CURRENT WORKING DIRECTORY, not the repo root: lib/apply.py:3305 is a bare
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
BSTAGE="$REPO_ROOT/recipes/available/bottles.files"

# The expected /slax/modules contents. iso_assert.py has --require but no --forbid, and
# "chromium is gone" is half the size claim, so assert the list exactly -- that also
# catches an accidental extra bundle, and it is what proves 31-notepadpp64 is on the
# 64-bit images and nowhere else. On the 32-bit base, NINE: five stock survivors, our
# three, and 98-dpkg-db.sb, which lib/pack.sh generates from the status fragments our
# bundles ship. Forgetting that last one is the easy way to fail the build on its own
# output. The 64-bit base has the same five stock survivors.
WANT_MODULES32="01-core.sb 01-firmware.sb 02-xorg.sb 03-desktop.sb 04-apps.sb 20-wine.sb 21-wine-desktop.sb 30-notepadpp32.sb 98-dpkg-db.sb"
WANT_MODULES64="01-core.sb 01-firmware.sb 02-xorg.sb 03-desktop.sb 04-apps.sb 20-wine.sb 21-wine-desktop.sb 30-notepadpp32.sb 31-notepadpp64.sb 98-dpkg-db.sb"
# slax-bottles: the same five stock survivors, flatpak, Bottles, and the generated db.
BOTTLES_WANT_MODULES="01-core.sb 01-firmware.sb 02-xorg.sb 03-desktop.sb 04-apps.sb 20-flatpak.sb 30-bottles.sb 98-dpkg-db.sb"

KEEP_WORK=0; NO_FETCH=0; ARCHES="32 64"; KINDS="bios uefi"; ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --32)            ARCHES="32"; shift ;;
        --64)            ARCHES="64"; shift ;;
        --bios)          KINDS="bios"; shift ;;
        --uefi)          KINDS="uefi"; shift ;;
        --both)          KINDS="bios uefi"; shift ;;
        # Not shipped, and not in the default: the test image adds testkit, which prints
        # to the serial console and carries a persistence marker. It exists so
        # `kitchen test --persistence` has something of OURS to assert against.
        --test)          KINDS="test"; shift ;;
        --bottles)       ONLY="bottles"; shift ;;
        --bottles-test)  ONLY="bottles-test"; shift ;;
        --all)           ONLY="all"; shift ;;
        --keep-work)     KEEP_WORK=1; shift ;;
        --no-fetch)      NO_FETCH=1; shift ;;
        *) echo "build.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
case "$ONLY" in
    "")   VARIANTS=""
          for a in $ARCHES; do for k in $KINDS; do VARIANTS="$VARIANTS $a-$k"; done; done ;;
    all)  VARIANTS="32-bios 32-uefi 64-bios 64-uefi bottles" ;;
    *)    VARIANTS=$ONLY ;;
esac

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

# ---- per-variant facts ---------------------------------------------------------------
# Everything that differs between images, in one place. 32-* and 64-* are the slax-wine
# images, slax32-wine-* and slax64-wine-*: the same system on the two bases, and the only
# difference in what they carry is that the 64-bit ones add notepadpp64. bottles and
# bottles-test are slax-bottles: another payload, another module list.
variant_config() {
    case "$1" in
        32-bios|32-uefi|32-test|64-bios|64-uefi|64-test)
            V_BITS=${1%%-*}; kind=${1#*-}
            V_IMAGE="slax$V_BITS-wine-$kind"
            if [ "$V_BITS" = 32 ]; then
                V_TARGET=$BASE32_TARGET; V_ISO=$BASE32_ISO
                V_SIZE=$BASE32_SIZE; V_SHA=$BASE32_SHA256
                V_WANT=$WANT_MODULES32; V_MAX=$WINE32_MAX_ISO_MIB
                V_PAYLOAD="notepadpp32"
                V_OWN="20-wine 21-wine-desktop 30-notepadpp32 98-dpkg-db"
                V_APP="notepadpp32 $APP_VERSION"
            else
                V_TARGET=$BASE64_TARGET; V_ISO=$BASE64_ISO
                V_SIZE=$BASE64_SIZE; V_SHA=$BASE64_SHA256
                V_WANT=$WANT_MODULES64; V_MAX=$WINE64_MAX_ISO_MIB
                V_PAYLOAD="notepadpp32 notepadpp64"
                V_OWN="20-wine 21-wine-desktop 30-notepadpp32 31-notepadpp64 98-dpkg-db"
                V_APP="notepadpp32 and notepadpp64 $APP_VERSION"
            fi
            # The summary's first line and the application id in the PVD, both named for
            # the image, with the base it was built on.
            V_TITLE="slax$V_BITS-wine $VERSION ($kind)"
            V_APPID="slax$V_BITS-wine $VERSION $kind (base $V_ISO)"
            V_RELEASE=etc/slax-wine-release; V_RELEASE_SB=21-wine-desktop ;;
        bottles|bottles-test)
            V_BITS=64
            V_IMAGE="slax-$1"
            V_TARGET=$BASE64_TARGET; V_ISO=$BASE64_ISO
            V_SIZE=$BASE64_SIZE; V_SHA=$BASE64_SHA256
            V_WANT=$BOTTLES_WANT_MODULES; V_MAX=$BOTTLES_MAX_ISO_MIB; V_PAYLOAD=bottles
            V_OWN="20-flatpak 30-bottles 98-dpkg-db"
            V_APP="$BOTTLES_APP $BOTTLES_VERSION (Flathub $BOTTLES_BRANCH)"
            V_TITLE="slax-bottles $VERSION ($1)"
            V_APPID="slax-bottles $VERSION${1#bottles} (base $BASE64_ISO)"
            V_RELEASE=etc/slax-bottles-release; V_RELEASE_SB=30-bottles ;;
        *) echo "build.sh: unknown variant $1" >&2; exit 2 ;;
    esac
    V_PROFILE="$REPO_ROOT/profiles/$V_IMAGE.yaml"
}

# ---- 1. the base ISO(s) ------------------------------------------------------------
# `kitchen fetch` verifies size+sha256 first and prints "already verified" without
# downloading, so this doubles as the verify step when the file is already here.
# Once per DISTINCT base: --all needs both the 32-bit and the 64-bit one.
mkdir -p "$ISO_DIR" "$OUT"
TARGETS=""; PAYLOADS=""
for v in $VARIANTS; do
    variant_config "$v"
    case " $TARGETS " in *" $V_TARGET "*) ;; *) TARGETS="$TARGETS $V_TARGET" ;; esac
    for p in $V_PAYLOAD; do
        case " $PAYLOADS " in *" $p "*) ;; *) PAYLOADS="$PAYLOADS $p" ;; esac
    done
done
for t in $TARGETS; do
    say "base ISO: $t"
    [ "$NO_FETCH" = 1 ] || "$K" fetch "$t" -o "$ISO_DIR"
    "$K" fetch "$t" -o "$ISO_DIR" --verify-only
done

# ---- 2a. the application payloads: Notepad++, 32- and 64-bit ------------------------
# Fetched and verified rather than committed. Not because committing is forbidden --
# .exe is not a forbidden extension and GitHub's limit is 100 MB -- but because
# slax-arcade needs the same mechanism for software that cannot be published at all, and
# one contract across both projects is worth more than build-time self-containment.
#
# One installer per recipe, each into its own stage, tagged like everything else of it:
# notepadpp32.files/opt/notepadpp32/npp32-installer.exe and the 64 equivalent. Staged
# under a stable name, so updating Notepad++ touches build.env only -- APP_VERSION and
# each installer's URL, sha256 and size -- and nothing in a recipe, a wrapper or a
# .desktop entry. A 32-bit build stages only the x86 installer.
stage_npp() {
    bits=$1
    case "$bits" in
        32) url=$APP32_URL; sha=$APP32_SHA256 ;;
        64) url=$APP64_URL; sha=$APP64_SHA256 ;;
    esac
    say "application payload: notepadpp$bits $APP_VERSION"
    dir="$REPO_ROOT/recipes/available/notepadpp$bits.files/opt/notepadpp$bits"
    exe="npp$bits-installer.exe"
    mkdir -p "$dir"
    if [ -f "$dir/$exe" ] && [ "$(sha256sum "$dir/$exe" | cut -d' ' -f1)" = "$sha" ]; then
        echo "  ok   $exe (already verified)"
    else
        rm -f "$dir/$exe"
        curl -fsSL "$url" -o "$dir/$exe"
        got=$(sha256sum "$dir/$exe" | cut -d' ' -f1)
        if [ "$got" != "$sha" ]; then
            rm -f "$dir/$exe"
            echo "build.sh: $url sha256 $got != build.env $sha" >&2
            exit 1
        fi
        echo "  ok   $exe ($(stat -c%s "$dir/$exe") bytes, sha256 verified)"
    fi
    # Provenance beside the payload, so the ISO is self-describing even though the
    # filename is deliberately version-free.
    cat > "$dir/VERSION" <<PROV
notepadpp$bits $APP_VERSION
upstream: $url
sha256:   $sha
PROV
}
stage_notepadpp32() { stage_npp 32; }
stage_notepadpp64() { stage_npp 64; }

# ---- 2b. the application payload: Bottles ------------------------------------------
# A Flatpak installation, staged on the HOST and copied in by bottles.yaml's
# bundle.files. Not installed in the build chroot: `flatpak install` runs its triggers
# through bwrap, and the chroot has an empty /proc and no user namespace.
#
# FLATPAK_USER_DIR points a --user installation at bottles.files/var/lib/flatpak. That
# layout is the same as the system installation at /var/lib/flatpak, which is where
# the live system (all root) looks.
#
# The pin is BOTTLES_LOCK in build.env: every ref, and the commit it has to be. A hash of a
# single file, as the Notepad++ payloads use, cannot express that, so the check is
# ref-by-ref against `flatpak info --show-commit`, in both directions: every locked ref is
# present at its commit, and nothing is present that the lock does not name.
FLATHUB_REPO=https://dl.flathub.org/repo/flathub.flatpakrepo
FPDIR="$BSTAGE/var/lib/flatpak"
# LC_ALL=C because two of the checks below read flatpak's labels ("Version:",
# "Subdirectories:"), and flatpak translates them.
fp() { LC_ALL=C FLATPAK_USER_DIR="$FPDIR" flatpak --user "$@"; }

# The lock as "ref commit" lines, blank lines dropped.
bottles_lock() { printf '%s\n' "$BOTTLES_LOCK" | sed -e 's/^[[:space:]]*//' -e '/^$/d'; }

# BOTTLES_LANGUAGES ("de;en") as flatpak prints a .Locale ref's subdirectories ("/de /en").
want_subdirs() {
    printf '%s\n' "$BOTTLES_LANGUAGES" | tr ';' '\n' | sed -e '/^$/d' -e 's|^|/|' | sort | tr '\n' ' ' | sed 's/ $//'
}

# Prints one line per disagreement. Silent means the stage matches build.env exactly.
bottles_drift() {
    [ -d "$FPDIR/repo" ] || { echo "no installation at $FPDIR"; return 0; }
    # The locale subset ships too. Left unset, flatpak derives it from the BUILD HOST's
    # locale -- which is how the first stage came out "en" without anyone choosing it, and
    # how a host with another LANG would have shipped something else under the same lock.
    lang=$(fp config --get languages 2>/dev/null || true)
    [ "$lang" = "$BOTTLES_LANGUAGES" ] \
        || echo "languages: have ${lang:-nothing}, build.env says $BOTTLES_LANGUAGES"
    bottles_lock | while read -r ref commit; do
        got=$(fp info --show-commit "$ref" 2>/dev/null || true)
        [ "$got" = "$commit" ] || echo "$ref: have ${got:-nothing}, lock says $commit"
        case "$ref" in
            *.Locale/*)
                sub=$(fp info "$ref" 2>/dev/null | sed -n 's/^ *Subdirectories: *//p' \
                      | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//')
                [ "$sub" = "$(want_subdirs)" ] \
                    || echo "$ref: deploys ${sub:-nothing}, BOTTLES_LANGUAGES wants $(want_subdirs)" ;;
        esac
    done
    fp list --all --columns=ref 2>/dev/null | while read -r r; do
        [ -n "$r" ] || continue
        full=$(fp info -r "$r" 2>/dev/null || echo "$r")
        bottles_lock | awk -v r="$full" '$1 == r { f = 1 } END { exit !f }' \
            || echo "$full: installed but not in BOTTLES_LOCK (unpinned)"
    done
}

stage_bottles() {
    say "application payload: $BOTTLES_APP $BOTTLES_VERSION"
    # RELOCK only means something on an EMPTY stage. On a warm one, `flatpak install`
    # keeps what is already there, so the "fresh" lock printed below would be the old one.
    if [ -n "${BOTTLES_RELOCK:-}" ] && [ -d "$FPDIR/repo" ]; then
        echo "build.sh: BOTTLES_RELOCK needs an empty stage, or it prints the lock you have." >&2
        echo "  rm -rf $BSTAGE && BOTTLES_RELOCK=1 ./build.sh --bottles" >&2
        exit 2
    fi
    if [ -z "${BOTTLES_RELOCK:-}" ] && [ -z "$(bottles_drift)" ]; then
        echo "  ok   $(bottles_lock | wc -l) refs (already at their locked commits)"
    else
        command -v flatpak >/dev/null 2>&1 || {
            echo "build.sh: the bottles variants need flatpak on the build host" >&2
            echo "  (Debian/Ubuntu: apt install flatpak)" >&2
            exit 2
        }
        mkdir -p "$FPDIR"
        fp remote-add --if-not-exists flathub "$FLATHUB_REPO"
        fp config --set languages "$BOTTLES_LANGUAGES"
        # Triggers run through bwrap and FAIL on a host without user namespaces (a
        # container, say): "bwrap: Creating new namespace failed". They only rebuild
        # desktop-file and icon caches under exports/, which Slax's launcher never reads,
        # and flatpak treats the failure as a warning. The commit check below is what
        # decides whether this stage is good.
        #
        # Guarded by `info` rather than trusting install's exit status for a ref that is
        # already there: under `set -eu` that status is the whole build.
        fp info "$BOTTLES_APP//$BOTTLES_BRANCH" >/dev/null 2>&1 \
            || fp install -y --noninteractive flathub "$BOTTLES_APP//$BOTTLES_BRANCH"
        if [ -n "${BOTTLES_RELOCK:-}" ]; then
            echo; echo "BOTTLES_RELOCK: paste this into build.env as BOTTLES_LOCK, and set"
            echo "BOTTLES_VERSION=$(fp info "$BOTTLES_APP" | sed -n 's/^ *Version: *//p')"
            echo 'BOTTLES_LOCK="'
            for r in $(fp list --all --columns=ref); do
                printf '  %s %s\n' "$(fp info -r "$r")" "$(fp info --show-commit "$r")"
            done | sort
            echo '"'
            exit 0
        fi
        # Walk every ref to its locked commit. A no-op for a ref that is already there;
        # the install above takes Flathub's CURRENT commit, which is exactly what the lock
        # exists to refuse. --no-related --no-deps because the lock names every ref itself:
        # left to its defaults, re-pinning one ref may also move its related refs (the
        # .Locale, the GL extensions) to whatever Flathub has now.
        bottles_lock | while read -r ref commit; do
            have=$(fp info --show-commit "$ref" 2>/dev/null || true)
            [ "$have" = "$commit" ] && continue
            if { [ -n "$have" ] || fp install -y --noninteractive --no-related --no-deps flathub "$ref"; } \
                && fp update -y --noninteractive --no-related --no-deps --commit="$commit" "$ref"; then
                continue
            fi
            echo "build.sh: cannot deploy $ref at $commit." >&2
            echo "  Flathub may no longer carry that commit. Bump the pin:" >&2
            echo "  rm -rf $BSTAGE && BOTTLES_RELOCK=1 ./build.sh --bottles" >&2
            exit 1
        done || exit 1
        drift=$(bottles_drift)
        if [ -n "$drift" ]; then
            echo "build.sh: the Bottles stage does not match build.env:" >&2
            printf '%s\n' "$drift" | sed 's/^/  /' >&2
            echo "  A changed BOTTLES_LANGUAGES needs a fresh stage: rm -rf $BSTAGE" >&2
            exit 1
        fi
        # A cache of remote summaries. Not content, and it would make two builds of the
        # same lock differ.
        rm -rf "$FPDIR/repo/tmp/cache"
        echo "  ok   $(bottles_lock | wc -l) refs deployed at their locked commits"
    fi
    # BOTTLES_VERSION is written into the image (/etc/slax-bottles-release, via gate 96's
    # check of bottles.yaml) and into /opt/bottles/VERSION, so it has to be the version
    # the locked commit actually is -- which only the stage can say. The same rule as
    # gate 96 section 2b for Notepad++: a version nothing checks is a suggestion.
    ver=$(fp info "$BOTTLES_APP//$BOTTLES_BRANCH" 2>/dev/null | sed -n 's/^ *Version: *//p')
    if [ "$ver" != "$BOTTLES_VERSION" ]; then
        echo "build.sh: build.env says BOTTLES_VERSION=$BOTTLES_VERSION, but the locked" >&2
        echo "  $BOTTLES_APP commit is version ${ver:-unknown}" >&2
        exit 1
    fi
    stage_bottles_components
    mkdir -p "$BSTAGE/opt/bottles"
    {
        echo "$BOTTLES_APP $BOTTLES_VERSION"
        echo "upstream: Flathub ($FLATHUB_REPO), branch $BOTTLES_BRANCH"
        echo "refs, each at the commit that shipped:"
        bottles_lock | sed 's/^/  /'
        echo "components, unpacked into Bottles' data directory (category name url sha256):"
        printf '%s\n' "$BOTTLES_COMPONENTS" | sed -e 's/^[[:space:]]*//' -e '/^$/d' -e 's/^/  /'
    } > "$BSTAGE/opt/bottles/VERSION"
}

# DXVK and VKD3D, which Bottles refuses to create a bottle without, and downloads on
# first use. See BOTTLES_COMPONENTS in build.env for the measurement that put them here.
# The tarballs are kept in bottles.files/.cache/, outside everything bottles.yaml copies,
# so a warm stage needs no network. Each one is unpacked fresh on every run: a
# half-extracted directory from an interrupted build must never ship.
#
# Staged as a mirror of where it lands, /root/.var/app/<id>/data/bottles, like every
# other stage here. (Until slax-kitchen 5627f2d this tree had to live under a neutral
# bottles-data/ instead: the provenance guard read the directory name `root` in its
# checkout-relative path as the build machine's /root. slax-kitchen #26, retired at the
# 86d27d5 bump -- see docs/UPSTREAM.md.)
BDATA="$BSTAGE/root/.var/app/com.usebottles.bottles/data/bottles"
stage_bottles_components() {
    mkdir -p "$BSTAGE/.cache"
    rm -rf "$BDATA"
    printf '%s\n' "$BOTTLES_COMPONENTS" | sed -e 's/^[[:space:]]*//' -e '/^$/d' |
    while read -r cat name url sha; do
        tgz="$BSTAGE/.cache/${url##*/}"
        if [ ! -f "$tgz" ] || [ "$(sha256sum "$tgz" | cut -d' ' -f1)" != "$sha" ]; then
            rm -f "$tgz"
            curl -fsSL "$url" -o "$tgz"
            got=$(sha256sum "$tgz" | cut -d' ' -f1)
            if [ "$got" != "$sha" ]; then
                rm -f "$tgz"
                echo "build.sh: $url sha256 $got != build.env $sha" >&2
                exit 1
            fi
        fi
        mkdir -p "$BDATA/$cat"
        tar -xzf "$tgz" -C "$BDATA/$cat" --no-same-owner
        # The tarball's top directory IS the name Bottles lists, so it has to match
        # exactly. That is what a build.env typo would get wrong without complaint.
        [ -d "$BDATA/$cat/$name" ] || {
            echo "build.sh: ${url##*/} did not unpack to $cat/$name" >&2
            exit 1
        }
        echo "  ok   $cat/$name (sha256 verified)"
    done || exit 1
}

for p in $PAYLOADS; do
    "stage_$p"
done

# ---- 3..7, once per variant --------------------------------------------------------
# The four slax-wine images are one build on two bases: the same recipes, with
# notepadpp64 added on the 64-bit base and `uefi-bootable` added to the uefi images, and
# nothing else. slax-bottles is a different system; variant_config above is the only
# place the variants differ, and everything below is shared by all of them.
#
# Each variant gets its OWN work tree under work/, because recipes are not idempotent:
# apply consults its journal and refuses a second application, so the trees cannot be
# reused between variants. Keeping them under work/ also puts the engine's kitchen-pkg-*
# scratch dir (mkdtemp beside ctx.work) inside an already-gitignored directory.
build_variant() {
    v=$1
    variant_config "$v"
    profile=$V_PROFILE
    work="$WORK/$v"
    out_iso="$OUT/$V_IMAGE-$VERSION.iso"
    applog="$OUT/apply-$v.log"
    sum="$OUT/build-summary-$v.txt"
    [ -f "$profile" ] || { echo "build.sh: no such profile: $profile" >&2; exit 2; }

    say "[$v] unpack"
    rm -rf "$work"
    "$K" unpack "$ISO_DIR/$V_ISO" -o "$work" --force

    # (a) THE PROFILE'S BASE IS THE ONE UNPACKED. `kitchen apply --profile` reads only a
    # profile's recipe list and vars (read_profile_recipes); its `base:` block is checked
    # nowhere, so a slax64 profile would build on the 32-bit ISO without a word. And the
    # engine decides `when: arch==...` from the source ISO that unpack recorded, so that
    # has to be this variant's ISO.
    # WORKAROUND https://github.com/Fullaxx/slax-kitchen/issues/29
    # The arch half of it is https://github.com/Fullaxx/slax-kitchen/issues/27, which is
    # why this checks the recorded ISO too rather than trusting the engine's fact.
    pbase=$(python3 -c 'import sys, yaml
b = yaml.safe_load(open(sys.argv[1]))["base"]
print("%s-%s-%s" % (b["flavour"], b["arch"], b["version"]))' "$profile")
    [ "$pbase" = "$V_TARGET" ] || {
        echo "build.sh: [$v] ${profile#"$REPO_ROOT"/} says base $pbase; this variant builds on $V_TARGET" >&2
        exit 1
    }
    src=$(sed -n 's/^source_iso: *//p' "$work/.kitchen/origin.yaml")
    [ "${src##*/}" = "$V_ISO" ] || {
        echo "build.sh: [$v] unpack recorded ${src##*/}, expected $V_ISO" >&2
        exit 1
    }
    echo "  ok   profile base $pbase is the ISO unpacked"

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
        --appid "$V_APPID" --force

    # Read the volid back out of the pack hints rather than hardcoding it; the recipe is
    # the one place that decides it.
    say "[$v] assert"
    volid=$(sed -n 's/^volid: *//p' "$work/.kitchen/pack.yaml" | head -1 | sed "s/^[\"']//;s/[\"']$//")
    [ -n "$volid" ] || { echo "build.sh: [$v] no volid hint -- did the profile's *-iso.yaml recipe run?" >&2; exit 1; }

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
    # --require is derived from V_OWN: the bundles this project builds for the variant.
    req=""
    for b in $V_OWN; do req="$req --require /slax/modules/$b.sb"; done
    # shellcheck disable=SC2086
    python3 "$ASSERT" "$out_iso" --volid "$volid" --max-size-mib "$V_MAX" $uefi_flag $req

    # An architecture's bios, uefi and test images share one list deliberately:
    # uefi-bootable builds NO bundle, it writes one boot/efi.img. If that ever differs
    # between them, something is wrong. The bottles variants carry their own list
    # (BOTTLES_WANT_MODULES).
    got=$(xorriso -indev "$out_iso" -lsl /slax/modules/ -- 2>/dev/null \
          | sed -n "s/.*'\\(.*\\.sb\\)'\$/\\1/p" | sort | tr '\n' ' ')
    # shellcheck disable=SC2086
    want=$(printf '%s ' $V_WANT)
    if [ "$got" != "$want" ]; then
        echo "build.sh: [$v] /slax/modules is not what was expected" >&2
        echo "  want: $want" >&2
        echo "  got:  $got"  >&2
        exit 1
    fi
    echo "  ok   modules: $got"

    # (b) THE IMAGE CANNOT CLAIM ANOTHER BASE. Gate 96 checks the recipe's copy of the
    # release file; this reads back the copy that shipped, from its bundle.
    rtmp=$(mktemp -d "$WORK/.rel.XXXXXX")
    unsquashfs -q -n -d "$rtmp/x" "$work/iso/slax/modules/$V_RELEASE_SB.sb" \
        "$V_RELEASE" >/dev/null
    if ! grep -qxF "BASE_ISO=\"$V_ISO\"" "$rtmp/x/$V_RELEASE"; then
        echo "build.sh: [$v] /$V_RELEASE in $V_RELEASE_SB.sb does not say BASE_ISO=\"$V_ISO\"" >&2
        rm -rf "$rtmp"
        exit 1
    fi
    rm -rf "$rtmp"
    echo "  ok   /$V_RELEASE names $V_ISO"

    # ---- what is installed, from the image itself ----
    # The package list the docs point at (docs/software.md) instead of carrying 600 lines
    # that would go stale at the next bookworm point release. Read from 98-dpkg-db.sb --
    # the database the booted image actually uses -- rather than from apt's output, and
    # only `install ok installed`: upstream Slax leaves 9 removed-but-configured entries.
    # `unsquashfs -d`, not `-cat`, which needs squashfs-tools 4.6.
    pkgs="$OUT/$V_IMAGE-$VERSION.packages.tsv"
    ptmp=$(mktemp -d "$WORK/.pkgs.XXXXXX")
    unsquashfs -q -n -d "$ptmp/x" "$work/iso/slax/modules/98-dpkg-db.sb" \
        var/lib/dpkg/status >/dev/null
    {
        printf 'package\tversion\tarchitecture\n'
        awk '/^Package:/ { p = $2 } /^Version:/ { v = $2 } /^Architecture:/ { a = $2 }
             /^Status:/ { s = $0 }
             /^$/ { if (p != "" && s == "Status: install ok installed") print p "\t" v "\t" a
                    p = ""; v = ""; a = ""; s = "" }
             END { if (p != "" && s == "Status: install ok installed") print p "\t" v "\t" a }' \
            "$ptmp/x/var/lib/dpkg/status" | LC_ALL=C sort
    } > "$pkgs"
    rm -rf "$ptmp"
    npkgs=$(($(wc -l < "$pkgs") - 1))
    [ "$npkgs" -gt 0 ] || { echo "build.sh: [$v] no installed packages read from 98-dpkg-db.sb" >&2; exit 1; }
    # (c) BOTH HALVES OF WINE on the 64-bit base. wine32 is only a Recommends of wine64,
    # so a 64-bit Wine can lose every 32-bit Windows program without a single error. The
    # image's own package database has to show both loaders, and libwine for both.
    if [ "$V_BITS" = 64 ] && [ "$V_PAYLOAD" != bottles ]; then
        for pa in wine64:amd64 wine32:i386 libwine:amd64 libwine:i386; do
            awk -F'\t' -v p="${pa%:*}" -v a="${pa#*:}" '$1 == p && $3 == a { f = 1 } END { exit !f }' "$pkgs" \
                || { echo "build.sh: [$v] $pa is not installed -- see $pkgs" >&2; exit 1; }
        done
        echo "  ok   wine64 and wine32 installed, libwine for amd64 and i386"
    fi
    # slax-bottles' Flatpak side: the same text the image carries at /opt/bottles/VERSION.
    fpk=""
    if [ "$V_PAYLOAD" = bottles ]; then
        fpk="$OUT/$V_IMAGE-$VERSION.flatpak.txt"
        cp "$BSTAGE/opt/bottles/VERSION" "$fpk"
    fi

    say "[$v] summary"
    {
        echo "$V_TITLE"
        echo "profile         profiles/$V_IMAGE.yaml"
        echo "base            $V_ISO ($V_SHA)"
        echo "slax-kitchen    $(git -C "$REPO_ROOT/vendor/slax-kitchen" rev-parse --short HEAD)"
        echo "app             $V_APP"
        echo
        for b in $V_OWN; do
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
        printf 'vs stock        %+d bytes\n' "$(( isz - V_SIZE ))"
        echo "sha256          $(cut -d' ' -f1 < "$out_iso.sha256")"
        echo "packages        $npkgs installed, listed in ${pkgs#"$REPO_ROOT"/}"
        [ -z "$fpk" ] || echo "flatpak         refs and components in ${fpk#"$REPO_ROOT"/}"
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
