#!/usr/bin/env python3
"""The release scripts, tested without Actions and without an ISO.

WHY THIS EXISTS. .github/workflows/release.yml runs once per release, on a pushed tag, and
a mistake in it is a draft with the wrong files or a release under the wrong name. So the
work is in ci/release-*.sh, and each one is exercised here against fixtures: the guard
against throwaway repositories, SHA256SUMS against fake assets, the notes against the same,
and the boot assertions against a stand-in `kitchen` that writes serial logs instead of
booting. Each refusal is seen to fire, not only each pass. slax-kitchen's
tests/unit/test_release.py does the same for its own release.

AND THE LISTS MUST AGREE. What a release carries is written in three places: the list in
ci/release-lib.sh that the scripts use, the build matrix in the workflow, and the paragraph
in docs/build.md that a person reads. The last two are held to the first here.
"""
import os
import re
import subprocess
import sys
import tempfile
import traceback

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CI = os.path.join(ROOT, "ci")
GUARD = os.path.join(CI, "release-guard.sh")
SUMS = os.path.join(CI, "release-sums.sh")
NOTES = os.path.join(CI, "release-notes.sh")
BOOT = os.path.join(CI, "release-boot.sh")

FAILURES = []


def check(name, got, want):
    if got != want:
        FAILURES.append(f"{name}: got {got!r}, want {want!r}")


def check_in(name, needle, haystack):
    if needle not in haystack:
        FAILURES.append(f"{name}: {needle!r} not found in output")


def clean_env(**extra):
    """os.environ without git's repository variables, which a hook's environment carries
    and which would point the fixtures' git commands at this repository (#23 upstream)."""
    names = subprocess.run(["git", "rev-parse", "--local-env-vars"], capture_output=True,
                           text=True).stdout.split()
    env = {k: v for k, v in os.environ.items() if k not in names}
    env.update(extra)
    return env


def run(argv, **kw):
    p = subprocess.run(argv, capture_output=True, text=True, env=clean_env(**kw.pop("env", {})),
                       **kw)
    return p.returncode, p.stdout + p.stderr


def version():
    with open(os.path.join(ROOT, "build.env")) as fh:
        return re.search(r"^VERSION=(\S+)$", fh.read(), re.M).group(1)


def lib_value(name):
    with open(os.path.join(CI, "release-lib.sh")) as fh:
        return re.search(rf'^{name}="([^"]*)"$', fh.read(), re.M).group(1).split()


def assets():
    rc, out = run([SUMS, "--list"])
    check("--list exits 0", rc, 0)
    return [ln for ln in out.split("\n") if ln and ln != "SHA256SUMS"]


# ---- the guard ------------------------------------------------------------------------

def fake_repo(tmp, ver, changelog_heading, on_master=True):
    """build.env and CHANGELOG.md in one commit; origin/master at it, or absent."""
    with open(os.path.join(tmp, "build.env"), "w") as fh:
        fh.write(f"VERSION={ver}\n")
    with open(os.path.join(tmp, "CHANGELOG.md"), "w") as fh:
        fh.write(f"# Changelog\n\n{changelog_heading}\n\n- x\n")
    env = clean_env(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@e",
                    GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@e")
    cmds = [["git", "init", "-q", "-b", "master"], ["git", "add", "-A"],
            ["git", "commit", "-qm", "x"]]
    if on_master:
        cmds.append(["git", "update-ref", "refs/remotes/origin/master", "HEAD"])
    for cmd in cmds:
        subprocess.run(cmd, cwd=tmp, env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def guard(tag, tag_push=False, ver="2.0.0", heading="## [2.0.0] — 2026-10-01", on_master=True):
    with tempfile.TemporaryDirectory() as tmp:
        fake_repo(tmp, ver, heading, on_master=on_master)
        argv = [GUARD, tag] + (["--tag-push"] if tag_push else [])
        return run(argv, env={"REPO_ROOT": tmp})


def test_guard_tag_is_the_version():
    rc, _ = guard("v2.0.0", tag_push=True)
    check("the matching tag passes a tag push", rc, 0)
    rc, out = guard("v2.0.1", tag_push=True)
    check("another version fails", rc, 1)
    check_in("and names the one expected", "expected tag v2.0.0", out)
    rc, _ = guard("2.0.0")
    check("the v is part of the tag", rc, 1)


def test_guard_wants_a_dated_entry_on_a_tag_push():
    rc, out = guard("v2.0.0", tag_push=True, heading="## [2.0.0] — unreleased")
    check("an undated entry fails a tag push", rc, 1)
    check_in("and says what it wants", "no dated", out)
    rc, _ = guard("v2.0.0", tag_push=True, heading="## [2.0.10] — 2026-10-01")
    check("another version's date does not count", rc, 1)
    rc, out = guard("v2.0.0", heading="## [2.0.0] — unreleased")
    check("a rehearsal may run before the date", rc, 0)
    check_in("and says so", "skip", out)


def test_guard_wants_master_on_a_tag_push():
    rc, out = guard("v2.0.0", tag_push=True, on_master=False)
    check("no origin/master fails a tag push", rc, 1)
    check_in("as unverifiable, not as passed", "cannot verify", out)
    rc, out = guard("v2.0.0", on_master=False)
    check("a rehearsal tolerates it", rc, 0)
    check_in("loudly", "skip", out)


def test_guard_usage():
    rc, _ = run([GUARD])
    check("no tag is a usage error, not a pass", rc, 2)


# ---- SHA256SUMS -----------------------------------------------------------------------

def fake_assets(d, names, with_isos=True):
    """Tiny stand-ins for every asset. An .iso.sha256 holds the real line for its .iso."""
    import hashlib
    for n in names:
        if n.endswith(".iso"):
            body = f"iso {n}\n".encode()
            with open(os.path.join(d, n + ".sha256"), "w") as fh:
                fh.write(f"{hashlib.sha256(body).hexdigest()}  {n}\n")
            if with_isos:
                with open(os.path.join(d, n), "wb") as fh:
                    fh.write(body)
    for n in names:
        if not n.endswith(".iso") and not n.endswith(".iso.sha256"):
            with open(os.path.join(d, n), "w") as fh:
                fh.write(f"{n}\n")


def sums_lines(d):
    with open(os.path.join(d, "SHA256SUMS")) as fh:
        return sorted(fh.read().split("\n")[:-1])


def test_sums_from_the_full_set():
    names = assets()
    with tempfile.TemporaryDirectory() as d:
        fake_assets(d, names)
        rc, out = run([SUMS, d])
        check("a complete set passes", rc, 0)
        lines = sums_lines(d)
        check("one line per asset", len(lines), len(names))
        rc, out = run(["sha256sum", "-c", "SHA256SUMS"], cwd=d)
        check("and it verifies", rc, 0)


def test_sums_without_the_isos():
    """The workflow's last job downloads only the small files: each ISO's line comes from
    its .iso.sha256, and its size from the draft."""
    names = assets()
    isos = [n for n in names if n.endswith(".iso")]
    with tempfile.TemporaryDirectory() as full, tempfile.TemporaryDirectory() as small:
        fake_assets(full, names)
        run([SUMS, full])
        fake_assets(small, names, with_isos=False)
        sizes = os.path.join(small, "..", os.path.basename(small) + ".sizes")
        with open(sizes, "w") as fh:
            for n in isos:
                fh.write(f"{n} {os.path.getsize(os.path.join(full, n))}\n")
        try:
            rc, out = run([SUMS, small, "--sizes", sizes])
            check("the small set with sizes passes", rc, 0)
            check("and gives the same SHA256SUMS", sums_lines(small), sums_lines(full))

            os.remove(os.path.join(small, "SHA256SUMS"))
            rc, out = run([SUMS, small])
            check("without sizes an absent ISO is missing", rc, 1)
            check_in("named", f"{isos[0]} is missing", out)
            check("and nothing is written", os.path.exists(os.path.join(small, "SHA256SUMS")),
                  False)

            with open(sizes, "w") as fh:
                for n in isos:
                    fh.write(f"{n} {2 ** 31}\n")
            rc, out = run([SUMS, small, "--sizes", sizes])
            check("a 2 GiB ISO in the draft is refused", rc, 1)
            check_in("as over the limit", "2 GiB", out)

            with open(sizes, "w") as fh:
                for n in isos:
                    fh.write(f"{n} 100\n")
            with open(os.path.join(small, isos[0] + ".sha256"), "w") as fh:
                fh.write(f"{'0' * 64}  someone-else.iso\n")
            rc, out = run([SUMS, small, "--sizes", sizes])
            check("an .iso.sha256 naming another file is refused", rc, 1)
        finally:
            os.remove(sizes)


def test_sums_refuses_a_wrong_set():
    names = assets()
    with tempfile.TemporaryDirectory() as d:
        fake_assets(d, names)
        os.remove(os.path.join(d, names[-1]))
        rc, out = run([SUMS, d])
        check("a missing asset is refused", rc, 1)
        check_in("by name", f"{names[-1]} is missing", out)
    with tempfile.TemporaryDirectory() as d:
        fake_assets(d, names)
        with open(os.path.join(d, "boot-host.ini"), "w") as fh:
            fh.write("x\n")
        rc, out = run([SUMS, d])
        check("an extra file is refused", rc, 1)
        check_in("by name", "boot-host.ini is not a release asset", out)
    with tempfile.TemporaryDirectory() as d:
        fake_assets(d, names)
        iso = [n for n in names if n.endswith(".iso")][0]
        with open(os.path.join(d, iso), "ab") as fh:
            fh.write(b"changed after it was summed\n")
        rc, out = run([SUMS, d])
        check("an ISO its .iso.sha256 disagrees with is refused", rc, 1)
        check_in("by name", f"{iso} does not match its {iso}.sha256", out)
    with tempfile.TemporaryDirectory() as d:
        fake_assets(d, names)
        big = os.path.join(d, names[0])
        with open(big, "r+b") as fh:
            fh.truncate(2 ** 31)                 # sparse: no 2 GiB is written or read
        rc, out = run([SUMS, d])
        check("a 2 GiB asset on disk is refused", rc, 1)


# ---- the lists agree ------------------------------------------------------------------

def test_the_list():
    ver = version()
    images = lib_value("RELEASE_IMAGES")
    suffixes = lib_value("RELEASE_SUFFIXES")
    names = assets()
    check("five images, six files each, and the Flatpak list", len(names),
          len(images) * len(suffixes) + 1)
    check_in("the Flatpak list", f"slax-bottles-{ver}.flatpak.txt", names)
    for img in images:
        check(f"{img} is not a test image", img.endswith("-test"), False)


def test_build_md_says_the_same():
    with open(os.path.join(ROOT, "docs", "build.md")) as fh:
        text = fh.read()
    m = re.search(r"\*\*The assets\.\*\*(.*?)The sidecar is what", text, re.S)
    if not m:
        FAILURES.append("docs/build.md: no **The assets.** paragraph")
        return
    para = m.group(1)
    for img in lib_value("RELEASE_IMAGES"):
        check_in(f"build.md names {img}", f"`{img}`", para)
    for suf in lib_value("RELEASE_SUFFIXES"):
        check_in(f"build.md names {suf}", f"`{suf}`", para)
    check_in("build.md names the Flatpak list", "`.flatpak.txt`", para)
    check_in("build.md counts them", f"{len(assets()) + 1} files", para)


def test_the_workflow_builds_every_image_once():
    with open(os.path.join(ROOT, ".github", "workflows", "release.yml")) as fh:
        wf = fh.read()
    listed = []
    for m in re.finditer(r"^\s+images: (.+)$", wf, re.M):
        listed += m.group(1).split()
    check("the matrix builds exactly the shipped images", sorted(listed),
          sorted(lib_value("RELEASE_IMAGES")))
    for script in ("release-guard.sh", "release-boot.sh", "release-stage.sh",
                   "release-sums.sh", "release-notes.sh"):
        check_in(f"the workflow runs {script}", f"./ci/{script}", wf)
    check("no pull_request trigger", bool(re.search(r"^\s+pull_request", wf, re.M)), False)
    check("nothing publishes", "--draft=false" in wf, False)


# ---- the notes ------------------------------------------------------------------------

def test_notes():
    names = assets()
    ver = version()
    with tempfile.TemporaryDirectory() as d:
        fake_assets(d, names, with_isos=False)
        sizes = os.path.join(d, "..", os.path.basename(d) + ".sizes")
        with open(sizes, "w") as fh:
            for n in names:
                if n.endswith(".iso"):
                    fh.write(f"{n} 1048576000\n")
        try:
            rc, out = run([NOTES, f"v{ver}", d, "--sizes", sizes,
                           "--run-url", "https://example.invalid/run/1"])
            check("the notes are written", rc, 0)
            for section in ("## What it is built from", "## Redistribution and source",
                            "## How it was verified"):
                check_in("section", section, out)
            check_in("the size, from the draft", "| 1000.0 MiB |", out)
            check_in("the run", "https://example.invalid/run/1", out)
            m = re.search(r"slax-kitchen\*\* pinned at \[`([0-9a-f]{7})`\]", out)
            check("the pin is a commit", bool(m), True)
            check("every link is absolute, since notes are not in the tree",
                  re.findall(r"\]\((?!https://)[^)]*\)", out), [])
            rc, out = run([NOTES, f"v{ver}", d, "--sizes", sizes])
            check_in("without a run, the notes say it was by hand", "by hand", out)
            rc, out = run([NOTES, f"v{ver}", d])
            check("an image with no size fails", rc, 1)
        finally:
            os.remove(sizes)


# ---- the boot assertions --------------------------------------------------------------

FAKE_KITCHEN = r"""#!/bin/sh
# A stand-in for `kitchen test`: writes the serial logs a boot would, from FAKE_* settings.
[ "$1" = test ] || { echo "fake kitchen: expected the test verb, got $1" >&2; exit 2; }
shift
iso=$1; route=${2#--}
d="$(dirname "$iso")/boot-tests"; b=$(basename "$iso" .iso)
mkdir -p "$d"
[ "$route" = "${FAKE_FAIL:-}" ] && exit 1
case "$route" in
    kernel)      printf 'Command line: vga=normal %s console=ttyS0\n' "${FAKE_KERNEL_AM-automount}" > "$d/$b-kernel.serial.log" ;;
    bios|uefi)   printf 'Kernel command line: BOOT_IMAGE=x %s console=tty0 console=%s\n' "${FAKE_BOOT_AM:-}" "${FAKE_CONSOLE:-ttyS0}" > "$d/$b-$route.serial.log" ;;
    persistence) : ;;
esac
printf '%s\n' "$*" >> "$d/argv"
exit 0
"""


def boot(**fake):
    with tempfile.TemporaryDirectory() as d:
        k = os.path.join(d, "kitchen")
        with open(k, "w") as fh:
            fh.write(FAKE_KITCHEN)
        os.chmod(k, 0o755)
        iso = os.path.join(d, "x-test-9.9.9.iso")
        open(iso, "w").close()
        argv = [BOOT, iso] + fake.pop("args", [])
        rc, out = run(argv, env=dict({"KITCHEN": k}, **fake))
        argvlog = ""
        if os.path.exists(os.path.join(d, "boot-tests", "argv")):
            with open(os.path.join(d, "boot-tests", "argv")) as fh:
                argvlog = fh.read()
        return rc, out, argvlog


def test_boot_passes_a_good_image():
    rc, out, argv = boot(args=["--seconds", "600", "--tcg-keys"])
    check("a good image passes", rc, 0)
    check("four routes run", argv.count("x-test-9.9.9.iso"), 4)
    check_in("--seconds reaches every route", "--persistence --seconds 600", argv)
    uefi = [ln for ln in argv.split("\n") if "--uefi" in ln][0]
    check("--tcg-keys spells out 24 presses", uefi.count("home"), 24)
    check("and only on --uefi", "home" in argv.replace(uefi, ""), False)


def test_boot_refuses():
    rc, out, _ = boot(FAKE_BOOT_AM="automount")
    check("automount on a bootloader route fails", rc, 1)
    check_in("named", "--bios: automount is on the command line", out)
    rc, out, _ = boot(FAKE_CONSOLE="tty1")
    check("a boot not on the serial entry fails", rc, 1)
    rc, out, _ = boot(FAKE_KERNEL_AM="")
    check("the control failing fails the run", rc, 1)
    check_in("and says why", "the check cannot see it", out)
    rc, out, _ = boot(FAKE_FAIL="persistence")
    check("a failed route fails the run", rc, 1)
    check_in("named", "FAIL --persistence", out)


TESTS = [
    test_guard_tag_is_the_version,
    test_guard_wants_a_dated_entry_on_a_tag_push,
    test_guard_wants_master_on_a_tag_push,
    test_guard_usage,
    test_sums_from_the_full_set,
    test_sums_without_the_isos,
    test_sums_refuses_a_wrong_set,
    test_the_list,
    test_build_md_says_the_same,
    test_the_workflow_builds_every_image_once,
    test_notes,
    test_boot_passes_a_good_image,
    test_boot_refuses,
]


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
    print("tests/unit/test_release.py: all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
