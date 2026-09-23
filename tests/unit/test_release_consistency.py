#!/usr/bin/env python3
"""ci/checks/96-release-consistency.sh must read the pin from the submodule and nowhere else.

WHY THIS EXISTS. Sections 7 to 10 of gate 96 hang off "the pin", read with git inside
vendor/slax-kitchen. A bare `git -C vendor/slax-kitchen` can answer for THIS repository
instead, two ways, both measured on git 2.43.0:

  a commit from a     git exports GIT_DIR to the hooks, and GIT_DIR beats -C. The pin read
  linked worktree     back as our own HEAD, and sections 7 and 8 failed 24 times on a tree
                      that was clean -- every citation "wrong".
  an uninitialised    an empty directory, so discovery walks up and finds ours. `rev-parse
  submodule           HEAD` succeeds, the "not checked out" note can never fire, and every
                      citation is compared with the wrong commit.

The same class of bug as slax-kitchen #23, one gate over. Invisible to an ordinary run --
nothing exports GIT_DIR outside a worktree hook, and every checkout here has its
submodule -- so, like upstream's test_unit_gate.py, this puts the gate into both
situations on purpose, and checks the poison bites before trusting a pass.

AND SECTIONS 4 AND 5 MUST BITE. They hold four slax-wine images on two bases to one
recipe list, each release file to its own base, and each profile's name to what it
builds. A check nobody has seen fail is a check nobody knows works, so each is broken
here once, in a copy of this repository, and must fail naming what was broken -- while
the unbroken copy passes.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GATE = os.path.join("ci", "checks", "96-release-consistency.sh")
SUB = os.path.join(ROOT, "vendor", "slax-kitchen")

FAILURES = []


def check(name, got, want):
    if got != want:
        FAILURES.append(f"{name}: got {got!r}, want {want!r}")


def local_env_vars():
    """The names git calls repository-local -- the set a hook's environment carries."""
    return subprocess.run(["git", "rev-parse", "--local-env-vars"], capture_output=True,
                          text=True).stdout.split()


def clean_env(**extra):
    """os.environ without git's repository variables, plus whatever the case adds.

    When gate 80 runs this file those are already gone; run by hand from a hook they are
    not, and the baseline must not be the thing under test.
    """
    names = set(local_env_vars())
    env = {k: v for k, v in os.environ.items() if k not in names}
    env.update(extra)
    return env


def git(repo, *args, env=None):
    return subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True,
                          env=env if env is not None else clean_env())


def run_gate(root, env):
    """The gate that lives in `root`, run from `root`, as run-checks.sh would run it."""
    p = subprocess.run(["sh", os.path.join(root, GATE)], cwd=root, env=env,
                       capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout + p.stderr


def test_a_worktree_commit_cannot_move_the_pin():
    """GIT_DIR and GIT_INDEX_FILE exported, which is what a linked-worktree commit's hook gets."""
    if git(SUB, "rev-parse", "--show-toplevel").stdout.strip() != os.path.realpath(SUB):
        FAILURES.append("vendor/slax-kitchen is not checked out, so the GIT_DIR case cannot be "
                        "exercised -- git submodule update --init")
        return
    gitdir = git(ROOT, "rev-parse", "--absolute-git-dir").stdout.strip()
    poison = {"GIT_DIR": gitdir, "GIT_INDEX_FILE": os.path.join(gitdir, "index")}

    # The poison has to bite, or the comparison below passes for the wrong reason.
    ours = git(ROOT, "rev-parse", "HEAD").stdout.strip()
    bitten = git(SUB, "rev-parse", "HEAD", env=clean_env(**poison)).stdout.strip()
    check("with GIT_DIR exported, a bare git -C into the submodule answers for this repo",
          bitten, ours)

    rc_clean, out_clean = run_gate(ROOT, clean_env(REPO_ROOT=ROOT))
    rc_poison, out_poison = run_gate(ROOT, clean_env(REPO_ROOT=ROOT, **poison))
    # Equal, not "passes": this holds mid-bump too, when the gate is failing for real.
    check("the gate says the same with GIT_DIR exported as without", out_poison, out_clean)
    check("...and exits the same", rc_poison, rc_clean)


def test_an_uninitialised_submodule_is_not_mistaken_for_this_repo():
    """A clone made without --recurse-submodules: vendor/slax-kitchen is an empty directory."""
    tmp = tempfile.mkdtemp(prefix="gate96-")
    try:
        fx = os.path.join(tmp, "repo")
        for f in git(ROOT, "ls-files", "-z").stdout.split("\0"):
            src = os.path.join(ROOT, f)
            if not f or f.startswith("vendor/") or not os.path.isfile(src):
                continue
            dst = os.path.join(fx, f)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
        empty = os.path.join(fx, "vendor", "slax-kitchen")
        os.makedirs(empty)
        for a in (["init", "-q"], ["add", "-A"],
                  ["-c", "user.email=t@example.invalid", "-c", "user.name=t",
                   "commit", "-qm", "fixture"]):
            git(fx, *a)

        # The trap is real here, or the assertions below prove nothing.
        check("an empty submodule directory resolves to the repository around it",
              git(empty, "rev-parse", "--show-toplevel").stdout.strip(), os.path.realpath(fx))

        rc, out = run_gate(fx, clean_env(REPO_ROOT=fx))
        # Section 7's own note. Section 3 says "not checked out" too, from a missing FILE, and
        # an assertion that section 3 alone can satisfy passed against the unfixed gate.
        check("the pin read notices the submodule is not there",
              "vendor/slax-kitchen not checked out - provenance-header check skipped" in out, True)
        check("...and compares no citation with this repository's HEAD",
              "but the pin is" in out, False)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_it_refuses_rather_than_guess_when_git_will_not_name_the_variables():
    """Fails closed, as 80-unit.sh does: no list means the hook's repository stays in reach."""
    tmp = tempfile.mkdtemp(prefix="gate96-fc-")
    try:
        real = shutil.which("git")
        stub = os.path.join(tmp, "git")
        with open(stub, "w") as fh:
            fh.write('#!/bin/sh\n'
                     'case "$*" in\n'
                     '  *--local-env-vars*) exit 0 ;;\n'
                     f'esac\nexec {real} "$@"\n')
        os.chmod(stub, 0o755)
        env = clean_env(REPO_ROOT=ROOT, PATH=tmp + os.pathsep + os.environ.get("PATH", ""))
        rc, out = run_gate(ROOT, env)
        check("the gate refuses", rc != 0, True)
        check("...and says what would not answer", "--local-env-vars" in out, True)
        check("...and compared no citation with a guessed pin", "but the pin is" in out, False)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def fixture(tmp, edit=None):
    """This repository's own files as a fresh git repository, vendor/slax-kitchen left empty.

    Tracked files AND untracked ones git would track, so an uncommitted recipe or profile
    is in the copy the gate reads. `edit(fx)` runs before the commit.
    """
    fx = os.path.join(tmp, "repo")
    listing = git(ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard").stdout
    for f in listing.split("\0"):
        src = os.path.join(ROOT, f)
        if not f or f.startswith("vendor/") or not os.path.isfile(src):
            continue
        dst = os.path.join(fx, f)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    os.makedirs(os.path.join(fx, "vendor", "slax-kitchen"), exist_ok=True)
    if edit:
        edit(fx)
    for a in (["init", "-q"], ["add", "-A"],
              ["-c", "user.email=t@example.invalid", "-c", "user.name=t",
               "commit", "-qm", "fixture"]):
        git(fx, *a)
    return fx


def replace_once(fx, rel, old, new):
    """Edit one file of the fixture; the edit must apply exactly once, or it proves nothing."""
    path = os.path.join(fx, rel)
    with open(path) as fh:
        text = fh.read()
    if text.count(old) != 1:
        raise AssertionError(f"fixture edit does not apply once to {rel}: {old!r}")
    with open(path, "w") as fh:
        fh.write(text.replace(old, new))


def gate_in_fixture(edit=None):
    tmp = tempfile.mkdtemp(prefix="gate96-fx-")
    try:
        fx = fixture(tmp, edit)
        return run_gate(fx, clean_env(REPO_ROOT=fx))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def refuses(name, edit, needle):
    rc, out = gate_in_fixture(edit)
    check(f"{name}: the gate refuses", rc != 0, True)
    check(f"{name}: ...naming what was broken ({needle!r})", needle in out, True)


def test_the_unbroken_copy_passes():
    """The control. Without it, every refusal below could be the fixture's own fault."""
    rc, out = gate_in_fixture()
    check("an unedited copy of this repository passes gate 96", rc, 0)
    if rc != 0:
        FAILURES.append("  unedited copy said: " + " | ".join(
            l.strip() for l in out.splitlines() if "FAIL" in l)[:600])


def test_each_release_file_is_checked_against_its_own_base():
    """Section 4. Swap the BASE lines between wine-desktop's two steps: a file-wide grep
    still finds every line, so only a per-step check can see it."""
    def swap(fx):
        wd = "recipes/available/wine-desktop.yaml"
        for key in ("BASE_ISO", "BASE_SHA256"):
            with open(os.path.join(fx, wd)) as fh:
                lines = [l for l in fh.read().splitlines() if l.strip().startswith(key + "=")]
            if len(lines) != 2:
                raise AssertionError(f"expected two {key} lines in {wd}, found {len(lines)}")
            a, b = lines
            replace_once(fx, wd, a + "\n", "@@SWAP@@\n")
            replace_once(fx, wd, b + "\n", a + "\n")
            replace_once(fx, wd, "@@SWAP@@\n", b + "\n")
    refuses("BASE lines swapped between the 32- and 64-bit steps", swap,
            "(arch==32bit): /etc/slax-wine-release BASE_ISO does not match build.env BASE32_ISO")


def test_the_slax_wine_recipe_lists_cannot_drift():
    """Section 5(b), both halves: within an architecture, and across the two."""
    refuses("slax64-wine-uefi drops notepadpp32",
            lambda fx: replace_once(fx, "profiles/slax64-wine-uefi.yaml",
                                    "  - recipes/available/notepadpp32.yaml\n", ""),
            "slax64-wine-bios and slax64-wine-uefi disagree on the recipe list")

    def no_x64(fx):
        for kind in ("bios", "uefi", "test"):
            replace_once(fx, f"profiles/slax64-wine-{kind}.yaml",
                         "  - recipes/available/notepadpp64.yaml\n", "")
        # notepadpp64 would otherwise also fail 5(a) as a recipe in no profile; take it out
        # of the copy so that the only thing left to fail is the cross-architecture rule.
        os.remove(os.path.join(fx, "recipes/available/notepadpp64.yaml"))
    refuses("every slax64 profile drops notepadpp64", no_x64,
            "the slax64-wine recipe list is not the slax32-wine one plus notepadpp64")


def test_a_profile_name_says_what_it_builds():
    """Section 5(c): the base architecture, and the firmware."""
    refuses("slax64-wine-bios on the 32-bit base",
            lambda fx: replace_once(fx, "profiles/slax64-wine-bios.yaml",
                                    "  arch: 64bit\n", "  arch: 32bit\n"),
            "profiles/slax64-wine-bios.yaml: base arch is 32bit, but the name says 64bit")
    refuses("slax32-wine-bios with a GRUB ESP",
            lambda fx: replace_once(fx, "profiles/slax32-wine-bios.yaml",
                                    "  - recipes/available/slax-wine-iso.yaml\n",
                                    "  - recipes/available/slax-wine-iso.yaml\n  - uefi-bootable\n"),
            "profiles/slax32-wine-bios.yaml lists uefi-bootable, but the name says bios")


def test_every_test_here_is_registered():
    """A test that exists and never runs is the shape this repository keeps being warned about."""
    defined = {k for k, v in globals().items() if k.startswith("test_") and callable(v)}
    check("main() runs every test in this file", sorted(defined - {f.__name__ for f in TESTS}),
          [])


def test_a_variant_missing_from_the_register_is_refused():
    """Section 11(a). The register is the only page that answers "what are all of these,
    and how do they differ"; one missing row makes it answer wrongly while looking whole.
    Breaking the row's SHAPE rather than deleting it is the realistic failure: a reformat
    that drops the backticks leaves the name on the page and out of the register."""
    refuses("a variant with no row in docs/variants.md",
            lambda fx: replace_once(fx, "docs/variants.md",
                                    "| `slax32-wine-test` |", "| slax32-wine-test |"),
            "profiles/slax32-wine-test.yaml has no row")


def test_a_register_row_for_no_profile_is_refused():
    """Section 11(b), the other direction: a rename that reached the page and not the tree,
    or a row somebody wrote for an image that was never built."""
    refuses("a row naming a profile that does not exist",
            lambda fx: replace_once(
                fx, "docs/variants.md", "| `slax-bottles-test` |",
                "| `slax99-wine-bios` | x | x | no | x | x | x | x |\n| `slax-bottles-test` |"),
            "profiles/slax99-wine-bios.yaml does not exist")


def test_a_backticked_name_outside_the_matrix_is_not_a_variant():
    """Section 11's scan stops at the matrix. The page's other tables carry prose in their
    first cell today, but one of them could carry a name -- an upstream recipe, a script --
    and reading that as a variant fails the gate with a true sentence about the wrong
    thing. Planted exactly that and watched it happen before the bound was added."""
    def add_row(fx):
        path = os.path.join(fx, "docs/variants.md")
        with open(path, "a") as fh:
            fh.write("\n| `testkit` | an upstream recipe, not a variant | x |\n")
    rc, out = gate_in_fixture(add_row)
    check("a backticked non-variant below the matrix is ignored", rc, 0)
    if rc != 0:
        FAILURES.append("  the gate said: " + " | ".join(
            l.strip() for l in out.splitlines() if "FAIL" in l)[:300])


TESTS = [test_a_worktree_commit_cannot_move_the_pin,
         test_an_uninitialised_submodule_is_not_mistaken_for_this_repo,
         test_it_refuses_rather_than_guess_when_git_will_not_name_the_variables,
         test_the_unbroken_copy_passes,
         test_each_release_file_is_checked_against_its_own_base,
         test_the_slax_wine_recipe_lists_cannot_drift,
         test_a_profile_name_says_what_it_builds,
         test_a_variant_missing_from_the_register_is_refused,
         test_a_register_row_for_no_profile_is_refused,
         test_a_backticked_name_outside_the_matrix_is_not_a_variant,
         test_every_test_here_is_registered]


def main():
    for fn in TESTS:
        # One test crashing must not stop the rest: the count of failures is only honest
        # if every test ran. The traceback still goes to stderr, because a crash's location
        # is the useful half and a one-line summary loses it. Upstream's convention since
        # 18294f5, in every one of its test files; this is the one file here that is ours
        # rather than a copy, and ci/unit-run.py's "N of M tests did not run" line only
        # means anything over files that have the guard.
        try:
            fn()
        except Exception as e:                 # noqa: BLE001
            traceback.print_exc()
            FAILURES.append(f"{fn.__name__} crashed: {type(e).__name__}: {e}")
    if FAILURES:
        for f in FAILURES:
            print(f"FAIL {f}", file=sys.stderr)
        return 1
    print("tests/unit/test_release_consistency.py: all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
