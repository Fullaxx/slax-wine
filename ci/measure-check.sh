#!/bin/sh
# Compare the measurement register with the build summaries in an output directory.
#
#   ci/measure-check.sh [OUT_DIR] [--register FILE]
#
# docs/measurements.md holds every measured number. A row whose "re-measure" cell reads
# `summary <image> <key>` names a line in OUT_DIR/build-summary-<variant>.txt, which
# ./build.sh writes: <key> is ISO, a bundle's file name (20-wine.sb), boot/efi.img, or
# packages. For each such row this prints what the register says, what the build measured,
# and one of:
#
#   same          the two agree
#   differs       by how much, in the row's unit
#   placeholder   the register still says TBD-MEASURED; the build's number is shown
#   no summary    OUT_DIR has no summary for that image (it was not built)
#   no line       the summary has no line for that key
#
# A bundle or package row whose image was not built is read from that base's TEST image
# instead, and says so: the release procedure builds only the test images before a tag,
# and they carry the same bundles, built from the same recipes. An ISO row never is.
#
# A REPORT, NOT A GATE (D-21). It exits 0 whatever it finds, because a rebuild moves bytes
# by a 4 KiB squashfs block and slax-bottles takes whatever Flathub serves that day, so a
# difference is something to read, not a failure. It exits 2 only when it cannot do its
# job: no register, no summary rows in it, or a summary cell it cannot parse.
set -eu
REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)

out="$REPO_ROOT/out"
reg="$REPO_ROOT/docs/measurements.md"
while [ $# -gt 0 ]; do
    case "$1" in
        --register) reg=${2:?--register needs a file}; shift 2 ;;
        -h|--help)  sed -n '2,/^set -eu/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;;
        -*)         echo "measure-check: unknown option $1" >&2; exit 2 ;;
        *)          out=$1; shift ;;
    esac
done
[ -f "$reg" ] || { echo "measure-check: no register at $reg" >&2; exit 2; }

# The register's summary rows -> "id<TAB>image<TAB>key<TAB>value", value being the first
# cell after the id that starts with a number (or the placeholder), digits only. The
# ledger rows carry a description before their bytes, and a signed value (+6,488,064 +
# 2,048 for the ESP); the first number in the cell is the one the summary prints.
rows=$(awk -F'|' '
    /^\|/ && /`summary / {
        id = $2; gsub(/<[^>]*>|[` ]/, "", id)
        s = $0; sub(/.*`summary /, "", s); sub(/`.*/, "", s)
        n = split(s, w, " ")
        if (n != 2) { print "BAD\t" id "\t" s; next }
        val = ""
        for (i = 3; i < NF; i++) {
            c = $i; gsub(/^ +| +$/, "", c); gsub(/\*/, "", c)
            if (c ~ /^TBD-MEASURED/) { val = "TBD"; break }
            if (c ~ /^[-+]?[0-9]/) {
                sub(/^[-+]/, "", c); match(c, /^[0-9,]+/)
                val = substr(c, 1, RLENGTH); gsub(/,/, "", val); break
            }
        }
        print id "\t" w[1] "\t" w[2] "\t" val
    }' "$reg")

[ -n "$rows" ] || { echo "measure-check: $reg has no \`summary\` rows" >&2; exit 2; }
if printf '%s\n' "$rows" | grep -q '^BAD'; then
    # shellcheck disable=SC2016  # the backticks are literal: they quote the cell as written
    printf '%s\n' "$rows" | sed -n 's/^BAD\t\([^\t]*\)\t\(.*\)/measure-check: row \1: cannot read `summary \2`, want `summary <image> <key>`/p' >&2
    exit 2
fi

# slax32-wine-bios -> 32-bios, slax-bottles-test -> bottles-test: build.sh's variant names,
# which name the summary files.
variant() {
    case "$1" in
        slax-bottles*) echo "${1#slax-}" ;;
        slax32-wine-*|slax64-wine-*) v=${1#slax}; echo "${v%%-*}-${v#*-wine-}" ;;
        *) echo "" ;;
    esac
}

# A summary's number for a key: the bytes on the key's own line, or the package count.
measured() {  # $1 = summary file, $2 = key
    case "$2" in
        packages) sed -n 's/^packages  *\([0-9][0-9]*\) installed.*/\1/p' "$1" | head -1 ;;
        *)        awk -v k="$2" '$1 == k && $3 == "bytes" { print $2; exit }' "$1" ;;
    esac
}

printf '%-24s %-18s %-20s %15s %15s  %s\n' id image key register build verdict
tab=$(printf '\t')
printf '%s\n' "$rows" | while IFS="$tab" read -r id image key val; do
    v=$(variant "$image")
    sum="$out/build-summary-$v.txt"
    got=""; from=""
    if [ -n "$v" ] && [ ! -f "$sum" ] && [ "$key" != ISO ]; then
        t=${v%-*}-test
        case "$v" in bottles) t=bottles-test ;; esac
        if [ "$t" != "$v" ] && [ -f "$out/build-summary-$t.txt" ]; then
            sum="$out/build-summary-$t.txt"; from=" (read from the test image)"
        fi
    fi
    if [ -z "$v" ] || [ ! -f "$sum" ]; then
        verdict="no summary"
    else
        got=$(measured "$sum" "$key")
        if [ -z "$got" ]; then
            verdict="no line"
        elif [ "$val" = TBD ]; then
            verdict="placeholder"
        elif [ -z "$val" ]; then
            verdict="differs (the register has no number)"
        elif [ "$got" = "$val" ]; then
            verdict="same"
        else
            verdict="differs by $(( got - val ))"
        fi
    fi
    printf '%-24s %-18s %-20s %15s %15s  %s\n' "$id" "$image" "$key" \
        "${val:--}" "${got:--}" "$verdict$from"
done
exit 0
