#!/bin/sh
# Adapted from slax-kitchen @ b20e07e504f174af20ce197948c9621ce2394c3c (ci/checks/35-pyflakes.sh).
# MIT, same author. The EXECUTABLE HALF is byte-identical, so a future bump can diff it;
# ONE difference, in the prose: upstream's argument is about the size of its engine
# ("lib/apply.py alone is 4000 lines -- the half that was unchecked was the larger half"),
# and this repo owns no engine code at all. What is true here is written below instead.
# Re-adapt on a submodule bump; see docs/UPSTREAM.md.
#
# The one-invocation comment further down is upstream's measurement of upstream's 55 files
# and is kept as it stands, because the half it sits in is byte-identical on purpose. Here
# the same gate costs 0.12 s over six files in tree scope and 0.02 s in staged scope, which
# is what the pre-commit hook pays. Measured 2026-09-23, three runs and two.
# stages: pre-commit pre-push ci
# desc: pyflakes every python file.
#
# Beside 30-shellcheck, and for the same reason: every shell script in this tree is linted
# and no python file was.
#
# THE SMALLER HALF HERE, AND THAT IS THE ARGUMENT, NOT AGAINST IT. Six python files, four
# of them verbatim copies upstream already lints under this same gate. The two that
# NOTHING linted are the two that are ours: tests/unit/test_desktop_entries.py, which
# carries three local changes, and tests/unit/test_release_consistency.py, which is the
# test of gate 96 -- the gate that holds the profiles, the pin and the ledger in step. A
# defect in a test is a gate that passes while checking nothing, which is the failure mode
# this whole suite is built to avoid, and it is exactly what pyflakes catches.
#
# WHAT PUT IT UPSTREAM. 18294f5 added `import traceback` to 23 test files so one crashing
# test could not take the rest of the file with it, and in three of them the line landed
# inside a triple-quoted stub script. The guard it was adding then raised NameError
# instead of reporting the crash, and skipped every remaining test in the file (#37).
# pyflakes names all three in under a second; nothing else in that tree could say a word
# about it. It found a shipped defect on the first run too: bundle.script worked out which
# files a step had removed and never printed them, where bundle.packages does (#38). That
# is what an unused local can mean. Both commits are in the pin this gate arrived with.
#
# WHY NOT flake8 OR ruff. Neither is installed here and both bring style rules this tree
# has no opinion on. pyflakes reports what is wrong rather than what is unfashionable:
# undefined names, unused imports and locals, shadowed definitions.
#
# NO INLINE SUPPRESSION, deliberately and unavoidably -- pyflakes ignores `# noqa`. An
# "unused" import that is load-bearing is a real problem to fix rather than silence:
# tools/firmware-coverage.py read as having an unused `import urllib.request` because a
# function-local `import urllib.parse` shadowed the module binding, while lines further
# down depended on the module-level import's side effect. Deleting it would have broken
# the tool; hoisting the local import fixed both the shadowing and the report.
#
# THE MODULE, NOT A BINARY ON PATH, and that distinction broke upstream's CI the day this
# gate landed. `kitchen doctor --strict` was given a TOOLS row asking `have pyflakes`,
# which passed on the machine it was written on because pyflakes was there from a pip
# venv. In the reference container apt installs python3-pyflakes, which on ubuntu:24.04
# ships the MODULE ONLY -- the binary is a separate package, pyflakes3 -- so doctor
# reported `MISS pyflakes (apt-get install python3-pyflakes)` about a package that was
# already installed, and both container jobs failed. kitchen:346 already stated the rule
# for python3-yaml and python3-jsonschema: "Import them, the same way lib/validate.py
# does, rather than asking dpkg." `python3 -m pyflakes` is the same answer for the same
# reason, and it works whether the tool arrived from apt or from a venv -- which on THIS
# machine it did: /opt/venv, where apt's python3-pyflakes would be invisible. docs/build.md
# states the requirement as an import for that reason, not as a package name.
. "$(dirname "$0")/../lib.sh"

python3 -c "import pyflakes" 2>/dev/null \
    || { warn "python3 cannot import pyflakes - skipping (install: apt-get install python3-pyflakes)"; exit 0; }

check_files_nl | while IFS= read -r f; do
    case "$f" in
        vendor/*) continue ;;          # vendored upstream is not ours to lint
        *.py) ;;
        *) continue ;;
    esac
    [ -f "$REPO_ROOT/$f" ] || continue
    echo "$REPO_ROOT/$f"
done > "${TMPDIR:-/tmp}/.kitchen-py.$$"

# One invocation, not one per file: 55 files cost 0.65 s together and python's startup
# dominates a per-file loop. Measured 2026-09-22.
if [ -s "${TMPDIR:-/tmp}/.kitchen-py.$$" ]; then
    # shellcheck disable=SC2046  # the list is paths this gate just wrote, one per line
    python3 -m pyflakes $(cat "${TMPDIR:-/tmp}/.kitchen-py.$$") || fail "pyflakes"
fi
rm -f "${TMPDIR:-/tmp}/.kitchen-py.$$"
check_result
