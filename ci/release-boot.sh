#!/bin/sh
# The four boot routes on one test image, and what the release asserts about them.
#
#   ci/release-boot.sh <test-iso> [--seconds N] [--tcg-keys]
#
# --kernel, --bios, --uefi and --persistence, one after another, through `kitchen test`:
# each has to reach `Live Kit done`, and the persistence marker has to survive into the
# second boot. Then the kernel command line of each serial log:
#   --bios, --uefi   no `automount` (slax-wine-iso, slax-bottles-iso removed it) and
#                    console=ttyS0 (the serial entry was the one booted)
#   --kernel         `automount` PRESENT: the harness adds it, and this is the control
#                    that shows the check can see it at all
#
# It boots wherever `kitchen test` does: the boot host boot-host.ini names, or here with
# KITCHEN_BOOT_HOST=local, which is what the release workflow does on its runners.
# --tcg-keys spells out the UEFI menu keys for a machine without KVM, where the harness's
# own lead lands before GRUB draws its menu (docs/UPSTREAM.md, "the UEFI keystroke lead
# under TCG"); under KVM it is harmless, only slower. --seconds raises the ceiling per boot.
#
# Evidence lands in <dir of iso>/boot-tests/, as `kitchen test` puts it.
set -eu
REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
# KITCHEN is for tests/unit/test_release.py, which checks the assertions below against a
# stand-in that writes serial logs instead of booting anything.
K=${KITCHEN:-$REPO_ROOT/vendor/slax-kitchen/kitchen}

[ $# -ge 1 ] || { echo "usage: ci/release-boot.sh <test-iso> [--seconds N] [--tcg-keys]" >&2; exit 2; }
iso=$1; shift
seconds=""; keys=""
while [ $# -gt 0 ]; do
    case "$1" in
        --seconds)  seconds=${2:?--seconds needs a number}; shift 2 ;;
        --tcg-keys) keys="$(printf '1s,home,%.0s' $(seq 24))down,down,ret"; shift ;;
        *) echo "release-boot: unknown option $1" >&2; exit 2 ;;
    esac
done
[ -f "$iso" ] || { echo "release-boot: no such ISO: $iso" >&2; exit 2; }

rc=0
bad() { echo "release-boot: FAIL $*" >&2; rc=1; }

for route in kernel bios uefi persistence; do
    printf '\n== %s --%s\n' "${iso##*/}" "$route"
    set -- "$iso" "--$route"
    [ -z "$seconds" ] || set -- "$@" --seconds "$seconds"
    [ "$route" != uefi ] || [ -z "$keys" ] || set -- "$@" --keys "$keys"
    "$K" test "$@" || bad "--$route"
done

ev="$(dirname "$iso")/boot-tests"
b=$(basename "$iso" .iso)
# The 64-bit kernel prints "Command line:", the 32-bit one "Kernel command line:".
cmdline() { grep -a -m1 'ommand line:' "$1" 2>/dev/null | tr -d '\r' || true; }

for route in bios uefi; do
    line=$(cmdline "$ev/$b-$route.serial.log")
    if [ -z "$line" ]; then bad "--$route: no kernel command line in $b-$route.serial.log"; continue; fi
    case " $line " in *" automount "*) bad "--$route: automount is on the command line" ;; esac
    case "$line" in *console=ttyS0*) ;; *) bad "--$route: the serial entry was not booted" ;; esac
done
line=$(cmdline "$ev/$b-kernel.serial.log")
case " $line " in
    *" automount "*) ;;
    *) bad "--kernel: automount absent where the harness adds it; the check cannot see it" ;;
esac

if [ "$rc" -eq 0 ]; then
    printf '\nrelease-boot: %s passed all four routes\n' "${iso##*/}"
else
    printf '\nrelease-boot: %s FAILED\n' "${iso##*/}" >&2
fi
exit "$rc"
