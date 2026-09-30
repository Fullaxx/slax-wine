#!/usr/bin/env python3
"""ci/measure-check.sh, tested against a fake register and fake build summaries.

WHY THIS EXISTS. docs/measurements.md is the one page that states measured numbers (D-21),
and ci/measure-check.sh is what compares its `summary` rows with a build. It is a report,
not a gate, so nothing else notices when it reads the wrong column or the wrong summary
file: it would print "same" or "no summary" for ever and look like it works. Each verdict
is produced here on purpose, from a register and summaries whose numbers are known.

AND THE REAL REGISTER MUST PARSE. Every `summary` row in docs/measurements.md has to name
an image this repository builds, and a key build.sh writes, or the report quietly skips it.
"""
import os
import subprocess
import sys
import tempfile
import traceback

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CHECK = os.path.join(ROOT, "ci", "measure-check.sh")
REGISTER = os.path.join(ROOT, "docs", "measurements.md")

FAILURES = []


def check(name, got, want):
    if got != want:
        FAILURES.append(f"{name}: got {got!r}, want {want!r}")


def run(*args):
    p = subprocess.run([CHECK] + list(args), capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# The shapes the real register uses: an image row (bytes in the second column), a ledger
# row (a description first, then signed bytes), the ESP's "+a + b", a count with prose after
# it, a placeholder, and a row with no summary cell, which the report must not list.
FAKE_REGISTER = """# Measurements

| id | bytes | MiB | what | measured on | re-measure |
|---|---|---|---|---|---|
| <a id="iso-a"></a>`iso-a` | 1,000,000 | 1.0 | x | x | `summary slax32-wine-bios ISO` |
| <a id="iso-b"></a>`iso-b` | TBD-MEASURED | | x | x | `summary slax32-wine-test ISO` |
| <a id="iso-c"></a>`iso-c` | 2,000,000 | 1.9 | x | x | `summary slax32-wine-uefi ISO` |
| <a id="stock"></a>`stock` | 5 | 0 | x | x | `stat` it |

| id | | bytes | MiB | re-measure |
|---|---|---|---|---|
| <a id="l-wine"></a>`l-wine` | + `20-wine.sb` | +174,686,208 | +166.6 | `summary slax32-wine-bios 20-wine.sb` |
| <a id="l-gone"></a>`l-gone` | + `99-gone.sb` | +1 | 0 | `summary slax32-wine-bios 99-gone.sb` |
| <a id="esp"></a>`esp` | + `boot/efi.img` | +6,488,064 + 2,048 | +6.2 | `summary slax32-wine-uefi boot/efi.img` |
| <a id="l-bt"></a>`l-bt` | + `30-bottles.sb` | +100 | 0 | `summary slax-bottles 30-bottles.sb` |

| id | value | what | re-measure |
|---|---|---|---|
| <a id="pk"></a>`pk` | 613, in 622 database entries | x | `summary slax32-wine-bios packages` |
"""

SUMMARY_32_BIOS = """slax32-wine 1.0.0 (bios)

20-wine.sb          174690304 bytes   166.6 MiB  3801 paths

ISO             1000000 bytes  1.0 MiB
packages        613 installed, listed in out/x.packages.tsv
"""

SUMMARY_32_TEST = """slax32-wine 1.0.0 (test)

boot/efi.img          6488064 bytes  (GRUB ESP, not a bundle)

ISO             595245056 bytes  567.7 MiB
"""

SUMMARY_BOTTLES_TEST = """slax-bottles 1.0.0 (bottles-test)

30-bottles.sb     100 bytes   0.0 MiB  1 paths

ISO             7 bytes  0.0 MiB
"""


def lines_by_id(out):
    """id -> the verdict text, from the report's table."""
    rows = {}
    for ln in out.splitlines()[1:]:
        parts = ln.split()
        if len(parts) >= 6:
            rows[parts[0]] = " ".join(parts[5:])
    return rows


def write(path, text):
    with open(path, "w") as fh:
        fh.write(text)


def test_every_verdict():
    with tempfile.TemporaryDirectory() as tmp:
        reg = os.path.join(tmp, "measurements.md")
        write(reg, FAKE_REGISTER)
        out = os.path.join(tmp, "out")
        os.mkdir(out)
        write(os.path.join(out, "build-summary-32-bios.txt"), SUMMARY_32_BIOS)
        write(os.path.join(out, "build-summary-32-test.txt"), SUMMARY_32_TEST)
        write(os.path.join(out, "build-summary-bottles-test.txt"), SUMMARY_BOTTLES_TEST)
        rc, text = run(out, "--register", reg)
        check("a report exits 0 whatever it finds", rc, 0)
        got = lines_by_id(text)
        check("an ISO that agrees", got.get("iso-a"), "same")
        check("a placeholder shows the build's number", got.get("iso-b"), "placeholder")
        check("an image that was not built", got.get("iso-c"), "no summary")
        check("a ledger row read past its description, and a moved bundle",
              got.get("l-wine"), "differs by 4096")
        check("a key the summary lacks", got.get("l-gone"), "no line")
        check("the ESP's first number, from the test image when the uefi one is absent",
              got.get("esp"), "same (read from the test image)")
        check("slax-bottles falls back to slax-bottles-test", got.get("l-bt"),
              "same (read from the test image)")
        check("a count with prose after it", got.get("pk"), "same")
        check("a row with no summary cell is not listed", "stock" in got, False)
        check("an ISO row never falls back to the test image",
              "595245056" in text.split("iso-c")[1].splitlines()[0], False)


def test_it_refuses_what_it_cannot_read():
    with tempfile.TemporaryDirectory() as tmp:
        reg = os.path.join(tmp, "measurements.md")
        write(reg, "| `x` | 1 | `summary slax32-wine-bios` |\n")
        rc, text = run(tmp, "--register", reg)
        check("a summary cell without a key exits 2", rc, 2)
        check("...naming the row", "row x: cannot read" in text, True)
        write(reg, "# Measurements\n\nno rows at all\n")
        rc, text = run(tmp, "--register", reg)
        check("a register with no summary rows exits 2", rc, 2)
        rc, text = run(tmp, "--register", os.path.join(tmp, "absent.md"))
        check("no register exits 2", rc, 2)


def test_the_real_register_parses():
    """Every `summary` row names an image build.sh builds and a key it writes."""
    with tempfile.TemporaryDirectory() as tmp:
        rc, text = run(tmp)
        check("the register parses", rc, 0)
        rows = text.splitlines()[1:]
        check("the register has summary rows", len(rows) > 0, True)
        images = {"slax32-wine-bios", "slax32-wine-uefi", "slax32-wine-test",
                  "slax64-wine-bios", "slax64-wine-uefi", "slax64-wine-test",
                  "slax-bottles", "slax-bottles-test"}
        for ln in rows:
            parts = ln.split()
            if parts[1] not in images:
                FAILURES.append(f"register row {parts[0]} names no image build.sh builds: {parts[1]}")
            key = parts[2]
            if not (key in ("ISO", "packages", "boot/efi.img") or key.endswith(".sb")):
                FAILURES.append(f"register row {parts[0]} names a key build.sh does not write: {key}")


TESTS = [test_every_verdict, test_it_refuses_what_it_cannot_read, test_the_real_register_parses]


def main():
    for fn in TESTS:
        try:
            fn()
        except Exception as e:                 # noqa: BLE001
            traceback.print_exc()
            FAILURES.append(f"{fn.__name__} crashed: {type(e).__name__}: {e}")
    if FAILURES:
        for f in FAILURES:
            print(f"FAIL {f}", file=sys.stderr)
        return 1
    print("tests/unit/test_measure_check.py: all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
