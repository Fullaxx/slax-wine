# Working with slax-kitchen upstream

slax-wine is a thin layer over an actively developed engine, pinned by commit at
`vendor/slax-kitchen`. That relationship needs a written procedure, because it will recur for any
sibling project and because an issue filed badly wastes a maintainer's time.

This page is how we raise things upstream, and the register of what is open.

---

## Engine or recipe?

slax-kitchen's own `CONTRIBUTING.md` §1 draws the line, and nearly every routing decision follows
from it:

| | |
|---|---|
| **The engine** | `kitchen`, `lib/`, `schema/`, `ci/`, the verbs. Generic. Knows nothing about Wine. |
| **Recipes** | declarative YAML. Say *what* to change, never *how*. |

A verb behaving wrongly is theirs. Our recipe being wrong is ours. When it is genuinely unclear,
upstream asks that it start here first — *"a fork maintainer who has already triaged is far more
useful to us than a raw report"*.

**Check upstream Slax first.** `vendor/slax-kitchen/docs/30-inventory/known-upstream-bugs.md`
documents fourteen defects in Slax itself. Several look exactly like toolkit bugs until you read
them — the `noautomount` substring trap is entry 12, and it shaped `slax-wine-iso.yaml`. (The missing
GPU firmware is *not* in that file, despite being the same kind of fact; it lives in
`docs/50-cookbook/firmware-refresh.md`. Check both before concluding something is unreported.)

## The evidence bar

Upstream's issue forms **require** `kitchen doctor --report` and will not let you skip it. Most
"works here, fails there" reports are answered by that block alone. Attach also:

```sh
vendor/slax-kitchen/kitchen doctor --report
vendor/slax-kitchen/kitchen status -v work
vendor/slax-kitchen/kitchen probe out/slax-wine-*.iso
```

Plus: which of the four targets exactly (`debian-32bit-12.2.0`, not "Debian"); the exact command,
copied rather than described; what you expected and what happened, with a pointer to the doc that
promised it. Not worth including: a photograph of a screen, "latest version", a description of a
recipe instead of the recipe.

## Our own bar, which is higher

Nothing leaves this repo as an issue until it is:

| | |
|---|---|
| **Read** | the code path end to end — never inferred from a commit message or a doc |
| **Demonstrated** | a concrete failure: specific inputs, the exact wrong behaviour, and why it is wrong |
| **Attacked** | actively disproved if possible — is there a guard elsewhere, a test, a doc calling it deliberate? |
| **Reproduced read-only** | with `python3 -c`, `kitchen validate`, `unsquashfs -l`, their unit tests — never by writing into their tree |
| **Gate-clean** | `vendor/slax-kitchen/ci/run-checks.sh ci` passes at the reported commit, so it is not a dirty-tree artefact |

**Disproved candidates get written down too.** The review that produced the register below cleared
roughly twenty candidates, and knowing what was checked is worth as much as knowing what was found.
Then a second, deliberately adversarial pass over the five survivors killed two more — one because
upstream already documented it, one because our own reasoning was wrong. Three were filed. That
ratio is the bar working, not the bar failing.

## Speak their idiom

Use the verification ladder from their `CONTRIBUTING.md` §5, and claim the rung actually reached:

`schema-valid` → `gate-clean` → `matrix-verified` → `artifact boot-verified` → `boot-verified` →
`runtime-verified`

`ci/checks/95-status-vocab.sh` enforces this vocabulary on their cookbook pages, and this repo
copied that gate, so our pages use it too. **Matrix-verified is not boot-verified, and boot-verified
is not runtime-verified.** A correct file in the right place is not a working feature.

## The lifecycle

```
find → verify → draft here → file upstream → record in the register
     → work around locally: mark the code, add a row to Local workarounds
     → upstream fixes → bump the submodule pin → gate 96 §10 names it → remove the workaround
```

**The tail of that is now upstream's to define, not ours.** After our first round they wrote it
down: `CONTRIBUTING.md` "What happens after you file" (triage, no PR for maintainer-side fixes,
`Closes #N`, and the `gh issue view` breakage below) and `SECURITY.md` "What happens after you
report" (reproduce, fix in the open on master, show the exploit failing, publish with the reporter
credited). Read those rather than this paragraph; what follows is only our side.

Two rules make our end of it work:

- **A local workaround is marked and listed.** The code carries `WORKAROUND <issue URL>` in a comment,
  and [Local workarounds](#local-workarounds) below carries a row for it, both from the commit that
  adds it.
- **A pin bump is never automatic.** Every design decision in [ARCHITECTURE.md](ARCHITECTURE.md)
  reasons about specific engine behaviour, so a bump gets read as a diff before it is committed —
  [Moving the pin](#moving-the-pin) is how — and `ci/checks/20-vendor-pristine.sh` fails a pointer
  that moved without one.

The first rule used to read *"carries the issue URL in a comment, so it is findable with `grep`"*,
and nothing checked it. The #23 workaround carried no URL, so the grep that was meant to find it
could not; it was found at the next bump by reading its *Adapted* header instead. A convention that
has to be remembered is not a check, so the rule now has a gate behind it.

## Moving the pin

This is what "update the pin" means here: four steps, in this order, and only the fourth moves
anything. `CLAUDE.md` points at this section; the steps live here and nowhere else.

**1. Review every new upstream commit.**

- The target is upstream's `master` tip, unless you are given a commit. List every commit between the
  pin and the target, and read each one's message **and** diff, never a subject line alone (the
  [register](#register)'s own lesson). Note each `Closes #N`, and ours above all.
- **Upstream CI on the target must be green in every job**: the gates, all four builds and the boot
  test. A red or still-running target is waited out, not pinned around. `7194e0b` was waited out,
  and `6bd59f1` was taken only once its run had finished green.

**2. Work out what it does to this repo.**

- **Build inputs.** These are `kitchen`, `lib/`, `schema/`, `compat/`, `tools/`, and the upstream
  recipes our profiles use.
  - If any of them changed, rebuild **every shipped image** — the four slax-wine ones and
    slax-bottles — and compare them with the previous build, **content rather than bytes**: the
    build stamps directory mtimes, and a squashfs is not byte-reproducible even from one run to the
    next. `kitchen diff <before> <after> --bundles` is the tool since
    [#30](https://github.com/Fullaxx/slax-kitchen/issues/30) was fixed: it compares type, mode,
    owner, size, link target and sha256 per entry and names the field that moved. **Build the
    baseline first, at the old pin**, because `out/` may hold nothing and the numbers in the docs
    are one build's, not the release's. Re-run the boot routes only if the contents changed.
  - If none changed, say so, and the previous evidence stands.
- **Copied files.** Find which of our copies changed upstream, with
  `git rev-list --count <pin>..<target> -- <path>` on each source. Those are re-copied; the rest are
  only re-cited.
- **What upstream added.** A new gate or test is adopted, or it goes under
  [Deliberately not adopted](#deliberately-not-adopted-from-upstream) with the reason.
- **What the tests say.** Upstream's changed tests run inside the pinned submodule with
  `python3 -B`, and the submodule must stay pristine. When a gate we copy changed, run it over our
  own tests too, as root and as an unprivileged user; developing as root hides a whole class of
  failure (`f3ff3a3`).
- **Anything we cite.** Check whether a permalinked page moved or changed.

**3. Retire what upstream has made redundant.**

- [Local workarounds](#local-workarounds): every **active** row whose issue the new pin closes is
  retired in this bump, or marked *kept after fix* with its reason. Gate 96 §10 names them once the
  pin is staged, but it only knows what is marked and listed.
- Every file headed *Adapted from slax-kitchen*: re-read its stated differences, and move it back
  toward *Copied verbatim* wherever upstream now makes a difference unnecessary. These headers are
  read by hand, because a difference we keep for a reason of our own has no issue to close.
- Anything else that exists only because upstream fell short gets the same question. The `3a44e8a`
  bump found two kinds: belt-and-braces kept after the fix it guarded against, and skips that
  outlived the empty tree they were written for.

**4. Move the pin, up to the commit.**

- On a branch, fetch, check the target out in `vendor/slax-kitchen`, and stage it. Gate 96 then
  names what has to follow: §7 every header, §8 every pin and permalink, §9 any stale verbatim copy,
  §10 any fixed workaround.
- Re-copy and re-cite, and run every gate in tree scope.
- Record the bump here as *Adopted at the `<pin>` bump*: the commits and their CI, what moved, what
  was retired, the proofs, and why there was or was not a rebuild.
- **Stop there, uncommitted,** and hand over what changed, what was verified and how, and the commit
  message ([`CLAUDE.md`](../CLAUDE.md) § *Before committing or pushing anything*). When the user asks
  for the commit it goes through the hook, then `master` is fast-forwarded and the branch deleted.
  **A push is its own request.**

## Local workarounds

Every place this repository works around a slax-kitchen bug, and what became of it. Gate 96 §10
holds this table and the code in step:

- every `WORKAROUND <issue URL>` comment outside `vendor/` and the Markdown has a row here that is
  not retired, for the same issue and the same file — and every such row's file still carries it;
- a row that is **active** fails the commit whose pin contains a `Closes #N` for its issue. Retire
  the workaround in that same bump, or mark the row *kept after fix* and say why.

The second half is what makes "re-evaluate" happen at the bump rather than whenever someone
remembers. It reads the vendored history, so it needs no network, and it keys on the same `Closes`
trailer the [register](#register) does. An issue closed *without* a fix has no such line, which is
the right answer: its workaround is still needed.

Status is one of three: `active since <pin>`, `kept after fix — <why>`, `retired at <pin>`. A
retired row stays, so the next reader can see what we once carried and why it went.

| Issue | File | What it does here | Status |
|---|---|---|---|
| [#23](https://github.com/Fullaxx/slax-kitchen/issues/23) | `ci/checks/80-unit.sh` | ran each unit test with git's repository-local variables cleared | retired at `3a44e8a` |
| [#1](https://github.com/Fullaxx/slax-kitchen/issues/1) | `recipes/available/wine.yaml` | named the `from:` stack instead of taking the default | retired at `3a44e8a`; kept after the fix until then, [DECISIONS.md](DECISIONS.md) D-3 |
| [#22](https://github.com/Fullaxx/slax-kitchen/issues/22) | `ci/lib.sh` | `file_size` answers 0 for a gitlink, where upstream's at `8adfca6` answered `MISSING` | retired at `337f7e7` |
| [#26](https://github.com/Fullaxx/slax-kitchen/issues/26) | `build.sh` | staged DXVK/VKD3D under `bottles-data/` instead of a `root/.var/…` mirror of where they go | retired at `86d27d5` |
| [#26](https://github.com/Fullaxx/slax-kitchen/issues/26) | `recipes/available/bottles.yaml` | took that stage from `bottles-data/`, the `src:` half of the same workaround | retired at `86d27d5` |
| [#29](https://github.com/Fullaxx/slax-kitchen/issues/29) | `build.sh` | refuses a variant whose profile declares another base, and a work tree unpacked from another ISO -- `kitchen apply --profile` checked neither | retired at `7f9c4f8`; `949074b` reads the profile's `base:` and refuses the mismatch itself, and `cc28622` measures the arch, so the recorded-source half went. The three-part comparison stays in `build.sh` **unmarked**: upstream compares flavour and arch and deliberately not version, and here the version is not free |

---

## Register

Thirteen issues filed 2026-09-15, in two rounds. **All closed**, re-verified at `9776a90` on
2026-09-16. Every row's closing commit is taken from that commit's own `Closes #N` trailer, not
inferred from its subject line — a self-review found row 13 crediting the wrong one and two issues
missing outright, in the document that exists to be the accurate register.

**Later rounds have a section each, below.** As of the `7f9c4f8` bump on 2026-09-21, **every issue
this repository has filed is closed** — the last four were
[#27](https://github.com/Fullaxx/slax-kitchen/issues/27) and
[#28](https://github.com/Fullaxx/slax-kitchen/issues/28), found building slax64-wine, and
[#29](https://github.com/Fullaxx/slax-kitchen/issues/29) and
[#30](https://github.com/Fullaxx/slax-kitchen/issues/30), from checks this repo carries because the
engine did not. Each section below names its closing commit. Only upstream's own
[#15](https://github.com/Fullaxx/slax-kitchen/issues/15) is open, and it is Slackware's.

| # | Issue | Closed by |
|---|---|---|
| [1](https://github.com/Fullaxx/slax-kitchen/issues/1) | `bundle.remove` vs the `from:` default | `68879d9`, holes closed by `997a9ab` |
| [2](https://github.com/Fullaxx/slax-kitchen/issues/2) | fragments not read into the build chroot | `7ab6793` |
| [3](https://github.com/Fullaxx/slax-kitchen/issues/3) | `iso.checksums: sign` typed boolean | `7971eb5` |
| [4](https://github.com/Fullaxx/slax-kitchen/issues/4) | `bundle.fromTarball`: `privilege: none` still admitted setuid binaries and device nodes | `89ab73d` |
| [5](https://github.com/Fullaxx/slax-kitchen/issues/5) | `check_plan_order`'s refusal named a remedy that does nothing | `7178d01` |
| [6](https://github.com/Fullaxx/slax-kitchen/issues/6) | boot job's package count could not move | `a90c901` |
| [7](https://github.com/Fullaxx/slax-kitchen/issues/7) | `release.yml` `tee` with no `pipefail` | `23fec33` |
| [8](https://github.com/Fullaxx/slax-kitchen/issues/8) | generated bundles carried the packing uid | `e80239e` |
| [9](https://github.com/Fullaxx/slax-kitchen/issues/9) | `bundle.fromTarball` declared no `network` | `fd3d82f` |
| [10](https://github.com/Fullaxx/slax-kitchen/issues/10) | chown skipped directories and symlinks | `a034f6b` |
| [11](https://github.com/Fullaxx/slax-kitchen/issues/11) | `check_plan_order` bypassed three ways | `997a9ab` |
| [12](https://github.com/Fullaxx/slax-kitchen/issues/12) | the two merge functions disagreed | `9776a90` |
| [13](https://github.com/Fullaxx/slax-kitchen/issues/13) | staging chown stripped setuid/setgid, disabling `chromium-current`'s sandbox helper | `a034f6b` |

### Open upstream, and what each means here

Neither was ours. Both were assessed against this image at the `bcd4f00` bump rather than taken on
trust, because "open upstream" is not the same as "affects us". **14 has since closed** — by
`5e7825f` (its own `Closes` trailer; the merge commit `c455733` carries none), taken at the
`337f7e7` bump. Only 15 is still open.

| # | Issue | Impact on slax-wine |
|---|---|---|
| [14](https://github.com/Fullaxx/slax-kitchen/issues/14) | `bundle.packages` tracks additions and never looks at what left | **Closed by `5e7825f`** — apt now runs with `--no-remove`, so the engine *refuses* the case this row used to measure by hand. Historical measurement, still the evidence we held before the fix: **none on this build.** `20-wine.sb` is a `bundle.packages` bundle, so this is our exposure: a package apt removes to resolve a conflict is recorded as gone while its files stay visible from the lower bundle. Counted `install ok installed` in `04-apps.sb` (567) against `98-dpkg-db.sb` (626) — **nothing present before is missing after**. +59 is the `libgnutls30`-upgrade arithmetic. Re-measure after any recipe change; it is a property of the build, not of the recipe. |
| [15](https://github.com/Fullaxx/slax-kitchen/issues/15) | persistence boot 2 wedges on both Slackware targets, passes on both Debian | **None — we are Debian.** Worth reading the other way round: it is the bug their new persistence harness found on its first four-target sweep, which is the reason to trust the harness on *our* target. |

| Advisory | Status |
|---|---|
| [GHSA-p2w2-qh4r-jr53](https://github.com/Fullaxx/slax-kitchen/security/advisories/GHSA-p2w2-qh4r-jr53) | published, patched `3ad66f6` |
| [GHSA-phcw-cwjf-g9p3](https://github.com/Fullaxx/slax-kitchen/security/advisories/GHSA-phcw-cwjf-g9p3) | published, patched `3ad66f6` |

`12` and `13` came out of the fix round rather than our review: `12` is the divergence we flagged
inside `11` and they split out, and `13` is a regression in the fix for `10` — chowning a staged file
clears `S_ISUID`, which had silently disabled `chromium-sandbox`. Both were closed by the same commit
that closed `10` (`a034f6b`) or the one after it. Worth knowing: our `20-wine.sb` contains no setuid
binary, so `13` never affected this image.

**A note on the bookkeeping.** `89ab73d` closes `4`, not `13`; `a034f6b` closes `10` *and* `13`. This
page asserted otherwise, and omitted `4` and `5` entirely while claiming the list was complete. Both
errors came from reading commit subjects instead of their `Closes` trailers. The check is one
command, and it is the one to run before editing this table:

```sh
git -C vendor/slax-kitchen log --format='%h %s%n%b' <commit> | grep -o 'Closes #[0-9]*'
```

### Verified at `9776a90`, not taken on trust

The escape that survived round one was re-tested against the real extraction path:

| case | result |
|---|---|
| two-hop symlink chain (the reopened escape) | **REFUSED** — "link target of `'e'` `'a/d/..'` resolves outside" |
| three-hop chain | **REFUSED** |
| absolute symlink (round-one case) | **REFUSED** |
| benign relative symlink (`pkg/cur -> ..`) | extracted, nothing escaped |
| benign plain tree | extracted, nothing escaped |

`_extract_members` now extracts one member at a time and runs `_under` — which resolves with
`realpath` — on both the member path and its link target, so an on-disk symlink placed by an earlier
member is followed rather than collapsed textually. That was the whole defect, and it is closed
without false-positiving on legitimate relative symlinks.

The ordering holes likewise, with the same probes that found them:

| hole | before | after |
|---|---|---|
| two `apply` invocations against one tree | exit 0 | **exit 2**, and the refusal names the earlier run from the journal |
| `--skip-preflight` | exit 0 | **exit 2** |
| `bundle.renumber` | exit 0 | **exit 2**, and renumber is now named in the rule |
| removing a bundle *above* the one built | wrongly refused | **exit 0**, correctly allowed |

The work-tree half is passed only when not `--preflight-only` — correct, since that mode has no tree
and `kitchen build` preflights before unpacking. A probe using `--preflight-only` therefore cannot
see it, which is worth remembering before reporting it as still broken.

## The fix round, assessed

Three of four held. Recording the detail because "they closed it" is not the same as "it is fixed".

**#3 — fully fixed, and better than asked.** Both halves: the schema takes a key id, and `pack.sh`
quote-strips it like `volid`/`appid`/`sysid`. They generalised past the `'True'` case we reported to
any key id PyYAML would quote (`0xDEADBEEF`, all-digits), and made the dead `!= "false"` branch live
rather than deleting it.

**#1 — partially fixed.** The in-plan case is genuinely closed, including across recipes. Three
bypasses remain and are now [#11](https://github.com/Fullaxx/slax-kitchen/issues/11). This is why our
explicit `from:` stays. *(Later: `997a9ab` closed #11, and the explicit `from:` stayed as
belt-and-braces until the `3a44e8a` bump — see [Local workarounds](#local-workarounds).)*

**#2 — fixed for the reported case**, with a latent divergence: the chroot merge lacks `merge_tree`'s
"a real status resets fragments" rule, so an add-on numbered `00`–`04` would build against packages
the final database drops. Folded into #11.

**The advisory — not closed.** `804725c` fixed single-member lexical escapes. A two-hop symlink chain
still writes outside the work tree from a `privilege: none` verb; reproduced at `7178d01` against
their own check and extraction settings, with the same "0 files left inside dest" signature their
commit cites as the before-fix tell. The cause is one word: `_under` uses `realpath` (chain-safe),
`_refuse_escaping_link` uses `normpath` (not). Filed as GHSA-phcw-cwjf-g9p3.

## What they corrected in our reports

The bar in this document is only worth having if it is checked, so:

1. **The first advisory's suggested one-liner was unusable.** `extractall(filter="data")` needs
   Python 3.11.4+; the project declares `>= 3.9` and `debian:12` ships 3.11.2. They also measured
   `filter="tar"` — it allows all three escapes. The explicit `linkname` check offered as
   belt-and-braces was **the only portable half**. The published advisory carries a correction note
   for downstream forks. Our closing caveat had anticipated it, which is the argument for always
   writing one.
2. **Issue #2's expected value was wrong.** We predicted the chromium-beneath row should declare
   **2**, matching the stock row. It is **3** — stock `05-chromium` carries `libevent-2.1-7`, a
   current chromium does not, so Firefox owes a different closure. The bug was real; the number was
   not. Naming an expected value is still right; asserting it without deriving it is not.
3. **Both fixes we suggested in #20 were worse than the bug**, and upstream said why before
   rejecting them. Recording `vars` through `in_image()` strips the leading slash, and the
   `/root/` alternative needs one — so `/root/code/x` becomes `root/code/x` and slips past: it
   would have blinded the guard to the commonest leak. "Flag only paths that exist on the builder"
   fails both ways: `/etc/hostname` exists on the builder *and* is a legitimate image path, while a
   leak naming a path the builder lacks would pass. We had even written that it was worth attacking
   before filing, and then filed the suggestions un-attacked. Their fix keeps every host-ish
   *shape* except bare `^/`, plus the paths this build actually used; see the `337f7e7` section.
4. **`gh issue view` is broken on gh 2.45.0 against this repo** — it requests deprecated
   `projectCards` and prints the deprecation notice where the body should be. We once reported
   "verifying rendering" from that output; only the `--json body` check was real. Use
   `gh api repos/OWNER/REPO/issues/N`.

## Deliberately not adopted from upstream

**`ci/checks/45-doc-yaml.sh`** (added between `06c13bb` and `9776a90`) validates fenced YAML blocks
in documentation. **Not copied**, and the reason is the same principle this repo keeps running into:
slax-wine's shipped docs contain **zero** fenced YAML blocks, so the gate could never fail here. A
check that cannot fail is worse than no check, because its green tick is believed — that is exactly
what we filed as issue 6, and what a self-review then found in three assertions of our own gate 96.

Revisit this the moment a cookbook page starts quoting recipe YAML inline. Until then the absence is
deliberate, and this paragraph exists so it is not mistaken for an oversight at the next pin bump.
Re-measured at `8adfca6`: still **zero** fenced YAML blocks in any shipped page, so the reasoning
holds unchanged. There is a second reason now, too — this repo has no `schema/` of its own (gate 40
borrows the submodule's validator), and the gate refuses to run without one, so copying it would buy
a permanent *"skipping"*.

Its helper `ci/doc-yaml.py` is a separate question, because `tests/unit/test_desktop_entries.py`
imports that module's `fences()` to read documented blocks. We do **not** copy it: the test loads it
straight out of `vendor/slax-kitchen/ci/`. Upstream's stated reason for sharing the extractor was
*"ONE extractor, not two"*, and importing theirs satisfies that more exactly than copying would —
gate 20 holds `vendor/` byte-pristine, so drift is impossible by construction rather than by
discipline. That is one of the file's two local changes, marked `LOCAL CHANGE` at the import.

The second came with slax-bottles: the walk over `recipes/` now skips **gitignored** paths, which is
`ci/lib.sh`'s own definition of "in scope". `build.sh` stages a whole Flatpak installation under
`recipes/available/bottles.files/`, and that tree holds a dozen `.desktop` files from Flathub's
runtimes, which the unmodified test failed on. None of them reaches `/usr/share/applications`, the
only directory xlunch reads. Upstream stages no payloads under `recipes/`, so it cannot meet this, and
there is nothing to report. A probe `.desktop` dropped into `recipes/available/` still fails the test.

**`ci/checks/97-tier-c-ledger.sh`** (added in `e7f2bea`) — measured with `REPO_ROOT` pointed at this
tree, it exits 0 with *"tests/boot/tier-c.json not present"*. There is no `tests/boot/`, no ledger
and no `ci/release-notes.sh` here, so it would note-and-skip forever. Still not adopted, and nor is
its unit test, `tests/unit/test_tier_c_ledger.py` (added in `5627f2d`), which tests nothing we carry.

**`ci/checks/80-unit.sh` was in this section and has left it**, which is the part worth recording.
The reasoning was sound and is now obsolete, and those are different things. Measured at the
`bcd4f00` bump it exited 0 with **no output at all** — its loop is
`for t in "$REPO_ROOT"/tests/unit/test_*.py; do [ -f "$t" ] || continue`, so with no `tests/` the
body never ran and it did not even announce the skip, strictly worse than a gate that says it is
skipping. What changed at `8adfca6` is not the gate but the premise: `6ecf019` shipped
`tests/unit/test_desktop_entries.py`, which is the machine-checkable form of the trap that deleted
both our launchers, and it reads recipe YAML — which is exactly where our `.desktop` content lives.
A gate with nothing to run is worthless; a gate with something worth running is not. Both are now
adopted, and gate 80 is green over three real entries. See *Adopted at the `8adfca6` bump* below.

**Upstream's TARGET-count rule** (`79ca8dd`, in `90-doc-coverage.sh`) — **not taken at the
`7f9c4f8` bump**, for the third time with the same reasoning. It counts `kind: Fingerprint` files
under `compat/`; this repo has no `compat/` at all, so `n` is 0 and the rule stands down on every
run. slax-wine's own "four targets" are its four images, and gate 96 section 5 holds those to the
profiles rather than to prose, which is a check that can fail. Recorded in the gate's header too, so
the next re-adaptation does not have to rediscover it.

**Upstream's no-inputs guard in `tests/unit/test_desktop_entries.py`** (`2476201`) — the same shape
and the same answer. It fails when a walk over `recipes/` finds no `.desktop` file, which is right
for a tree that ships them as files. Here every one is a recipe `content:` block — six, in four
recipes — and **zero** real `.desktop` files are tracked under `recipes/`, so the guard would fail
every run rather than catch anything. The scan that does have inputs, over the YAML blocks, carries
the identical assertion at the bottom of the same file, where it can fire for the reason it was
written. This is the third local change in that file's header.

**Two helpers were copied rather than borrowed**, which is the opposite call to `ci/doc-yaml.py`
above, and the reason is mechanical rather than stylistic. `ci/md-links.py` resolves its own root
from `__file__` and runs `git -C ROOT ls-files "*.md"`: run from `vendor/`, it would check the
submodule's documentation and report success about a tree nobody asked about. `ci/unit-run.py` takes
a path and derives no root, so borrowing would have worked; it is copied for symmetry, and because
`ci/` here is a self-contained gate suite that `96`'s sections 7 and 9 already hold to its upstream.

What we **did** take from this range is upstream's **gate-count check**, folded into our adapted
`90-doc-coverage.sh` with a wider anchor. Four files here state that number in prose and nothing else
checked them; upstream's own anchor missed two of the four (`ci/` alone, and the noun `checks`).

## Filed at the `bcd4f00` bump — round three

Three issues, all found by self-review of **this** repo rather than of theirs, which is the right way
round. Each was read in code and demonstrated before filing; none blocks the bump.

| # | Issue | Why it is theirs |
|---|---|---|
| [17](https://github.com/Fullaxx/slax-kitchen/issues/17) | a `.desktop` whose `Icon=` does not resolve is silently deleted from the launcher | Slax's behaviour, but absent from `known-upstream-bugs.md`, and the `remove-chromium` page taught a stub that works only because it omits `Icon=` |
| [18](https://github.com/Fullaxx/slax-kitchen/issues/18) | `tier-c.sh`: `--allow-dirty` accepts `--ledger` alone, so a dirty run can write a committed golden | `ci/tier-c.sh:46-47` clears the guard on *either* flag; the doc and the `die` message both say both |
| [19](https://github.com/Fullaxx/slax-kitchen/issues/19) | `00-no-binaries` can be walked past two ways | `file_size` fails open (`lib.sh:87`), and the extension list has no `.exe`/`.dll`/`.msi` |

**All three are closed.** `6ecf019` (2026-09-18, *"Three checks that passed things they should
refuse"*) landed hours after they were filed, and the `8adfca6` bump brings the fixes here. Each was
re-proved in this tree rather than taken on trust — see *Adopted at the `8adfca6` bump* below.

**17 is the one that cost us something.** It deleted both of this image's launchers — the entire
point of `21-wine-desktop.sb` — and eleven green gates never noticed, because no gate can see a
runtime resolution failure. It was caught by a manual self-review and fixed with an absolute `Icon=`
path. `docs/ARCHITECTURE.md`'s register now carries the converse rule alongside the `NoDisplay` one.

**19 was two of our own long-standing candidates**, filed together because they share a blast radius
and because `9b1b797` finally supplied the argument: that commit fixed a fail-open in
`check_files_nl` and left the identical pattern in `file_size` forty lines below. The principle is
now accepted in that very file.

## Adopted at the `8adfca6` bump

Twenty-three commits, `bcd4f00..8adfca6`. An earlier note in this project said *twelve*; that was
read off truncated output and is wrong. The number is `git rev-list --count bcd4f00..8adfca6` = 23.

**Two of the three fixes were in files this repo copies verbatim, so we were shipping defects we had
ourselves reported.** `ci/lib.sh` and `ci/checks/00-no-binaries.sh` were re-copied and each half
proved by making it fail, because a fix to a check-that-cannot-fail is worthless unverified:

| proved | before | after |
|---|---|---|
| a committed Windows binary | `payload.exe` staged with `git add -f` → **exit 0** | **exit 1**, `FAIL binary artifact must not be committed` |
| a `stat` that cannot measure | `file_size` answered `\|\| echo 0` on **both** branches → every file measured zero, gate reported `ok` | `FATAL ci/lib.sh: stat -c%s does not work here` / `Refusing to run` |

The `.exe` half matters more than its size suggests: this is the project whose stated premise is
*fetch Windows binaries, never commit them*, and the gate enforcing that premise passed one.

**`tests/unit/test_desktop_entries.py` + `ci/checks/80-unit.sh` are now gate 80.** This is the
machine-checkable form of the trap that deleted both our launchers. It reads recipe YAML, which is
where our `.desktop` content lives as inline `content:` blocks, and it scans all three of ours.
Proved by breaking each branch that applies to us and watching it go red:

- `Icon=wine` — the exact C1 regression, and Debian's own icon name → **FAIL**
- `Icon=accessories-text-editor` — the other C1 casualty, a standard freedesktop name → **FAIL**
- the chromium stub reduced to `NoDisplay` without `Hidden` → **FAIL**

Its docs half finds nothing here and that is correct, not rot: re-measured at this bump, no shipped
page contains a fenced YAML block. The no-inputs assertion at the bottom of the file still covers
the case that matters — both halves coming up empty.

**The bump was not free, and the plan for it was wrong about why.** The plan recorded *"schema
purely additive — `git diff -- schema/` has no removed lines"*, and concluded our recipes would
still validate. They did not. The new restriction is not in `schema/` at all: `cc8a664` put it in
`lib/validate.py`, a Python-level rule the JSON Schema knows nothing about —

> `bundle.remove` shares this recipe with `bundle.packages`: a recipe that removes or renumbers a
> bundle does nothing else. Put the removal in its own recipe — `remove-bundle` takes a `drop:`
> pattern — and list that first

`recipes/available/wine.yaml` did exactly that and failed. The fix follows upstream's own reasoning
rather than working around it: the `bundle.remove` step was lifted out, and all three profiles now
list upstream's `remove-bundle` **first**, each spelling out `drop: "^05-chromium\.sb$"` — a
deliberate restatement of that recipe's own default, because the pattern decides what leaves the
image and a pin bump must not be able to change it silently. Upstream does the same in all four of
its profiles. The removal is now performed by upstream's recipe instead of a copy of its logic.
Step counts are unchanged at 7 / 8 / 10.

The lesson is narrow and worth keeping: **"the schema is additive" is not "validation is
unchanged"** when the engine validates in two places. Check the validator, not just the schema.

**Their register is now 15 entries, not 14.** Issue #17 was recorded as entry 15, *"A `.desktop`
whose `Icon=` does not resolve is deleted without a word"*, and `remove-chromium.md` no longer
exists — PR #16 folded it into `remove-bundle.md`. Four prose references here pointed at the old
page; none was a markdown link, so gate 60 could not see them, and they were fixed by grep.

**One correction we posted ourselves.** Issue #18 cited `ci/tier-c.sh:45-46`; the guard is at
**46-47**. The wrong line numbers had reached both `docs/UPSTREAM.md` and the filed issue. Corrected
in both, with a comment on the issue. Citing a line number is right; citing one you did not re-read
is how a good report becomes a confusing one.

**Three gates grew, because this bump walked through three holes in them.** None was in the plan;
each was found by doing the bump and noticing what nothing would have caught.

| new check | the hole it closes |
|---|---|
| §5(a3) | §5(b) compares `recipes/available/` paths, so it cannot see `remove-bundle` — the two shipped profiles could disagree about whether the browser is removed at all, or list the removal too late, and stay green |
| §8 | the pin is also stated in English and embedded in permalinks into their docs. Nothing checked either, and this bump found **seven** stale citations by grep — across `CHANGELOG.md`, `docs/build.md` and five links in `INSTALL.md` |
| §9 | §7 checks that a provenance header cites the current pin; nothing checked that the **content** matched it. That is the worse failure of the two, because a current citation over stale content reads as verified — which is exactly how our copies of `ci/lib.sh` and `00-no-binaries.sh` carried the #19 defects through a green suite |

Each was proved by making it fail before being kept. §9 failed on itself first: an unanchored
`grep -rl 'Copied verbatim from slax-kitchen'` matched the gate's own source, which contains the
phrase in its own pattern.

**Deferred on purpose: `kitchen sources`.** `9c5a45a` added `lib/sources.py` (1,090 lines), which
works out for every file in an ISO whether it is stock Slax, a Debian package, or something the
build made — *from evidence rather than from a list someone keeps* — and can emit markdown. That is
machinery for exactly what `docs/DECISIONS.md` D-12 says we discharge by hand in `NOTICE.md`, the
one acknowledged legal gap in this project. It is kept out of this bump deliberately: rewriting a
source-attribution table is a licence-adjacent change and deserves its own pass, not a ride-along in
a correctness fix. Run it against both shipped ISOs and decide then. Recorded here so the deferral
reads as a decision rather than an oversight.

## Filed at the `8adfca6` bump — [#22](https://github.com/Fullaxx/slax-kitchen/issues/22), the #19 fix blocks every submodule bump · **closed by `337f7e7`**

Second finding, and this one is a consequence of a fix we ourselves asked for. `file_size` used to
answer `|| echo 0` on both branches; closing that turned a fail-open into a fail-closed, which is
right — and it exposed a case neither of us had looked at.

A **submodule is not a blob.** `git rev-parse :vendor/slax-kitchen` returns an oid quite happily —
the submodule's own **commit** — and `git cat-file -s` on it then fails, because that object lives
in the submodule's object store and not in this repository. `file_size` answers `MISSING`,
`00-no-binaries.sh` correctly refuses to swallow it, and the result is:

```
FAIL size could not be measured, so the limit was not applied: vendor/slax-kitchen
```

**Every commit that stages a submodule pointer fails its own pre-commit hook** — which means every
pin bump, including this one. It did not surface until now because the old `|| echo 0` answered 0
for this path and the case was invisible.

**Upstream has a submodule of its own** — `vendor/linux-live`, per its `.gitmodules` and
`docs/15-upstream/README.md` — and `git cat-file -s` fails on that gitlink in their tree exactly as
it does on ours, so their next `linux-live` pin bump should hit this too. `check_files` reaches it:
`git diff --cached --name-only --diff-filter=ACMR` lists a modified gitlink.

(An earlier draft of this section said their `docs/40-workflow/recipes-in-a-fork.md` tells forks to
vendor the engine as a submodule. It does not — that page never mentions submodules, and the claim
was checked before it reached the issue. What upstream *does* do is anticipate the arrangement:
`kitchen sources --fetch` looks for "the tree of the project that vendors it, found as the git
superproject" (`docs/90-reference/cli.md:366`).)

**We carried a local fix for one bump** — `ci/lib.sh` went *Adapted from* for the `8adfca6` pin,
reading the mode from the index and exempting only `160000`, proved narrow against a real file, an
oversized file and a planted `payload.exe`.

**Resolved at `337f7e7`, and the local fix is retired.** Upstream's gitlink branch is the same
logic, placed the same way — the two copies' executable lines differed *only* in a second fix of
theirs — so `ci/lib.sh` is back to *Copied verbatim* and gate 96 §9 enforces it again.

That second fix is the more instructive half. Writing the first test ever over `file_size`
(`tests/unit/test_ci_lib.py`) found that the `#19` probe `stat`ed `"$REPO_ROOT/ci/lib.sh"`, so
sourcing the library anywhere that file is absent refused to run. **It was latent in our copy too**
— our hook always runs from our own root, where the file exists — and the new test proved it: run
against our 8adfca6-era copy it failed three checks, each with `stat -c%s does not work here`;
against the re-copied library it passes. The probe now targets `/dev/null`.

## Filed at the `8adfca6` bump — [#20](https://github.com/Fullaxx/slax-kitchen/issues/20), the provenance guard refuses in-image paths · **closed by `ba79ce0`**

**This blocks our test image, and it blocks one of upstream's own profiles.** Both shipped images
build clean; `profiles/slax-wine-test.yaml` cannot complete `kitchen apply` at this pin.

`593af9e` added a provenance sidecar and, with it, a guard that refuses to record anything looking
like a path on the build machine — a good idea, and `provenance.in_image()` exists precisely so an
in-image path is written without its leading slash and therefore not flagged. The engine uses it
where it records image paths (`apply.py:555`, `:1042`).

**It is not used on a profile's `vars`.** `apply.py:3322` records `"vars": dict(overrides)` raw, and
`HOSTISH = (^/|/home/|/root/|/Users/|~/|\\)` matches **every** absolute path. So any profile that
overrides a var with an absolute in-image path — which is the only kind `testkit` accepts, since it
builds `"$UNION{{marker}}"` by concatenation — dies:

```
error: testkit.yaml: provenance would record a path on the build machine:
  vars.marker: '/var/lib/slax-wine-perch-marker'
```

**Upstream's own `profiles/boot-matrix.yaml` does the same thing** — `marker:
/var/lib/kitchen-perch-marker` — so their flagship boot-test profile is in the same position.
Measured against their `lib/provenance.py` at this pin:

| value | verdict |
|---|---|
| `/var/lib/slax-wine-perch-marker` (ours) | flagged |
| `/var/lib/kitchen-perch-marker` (**their boot-matrix**) | flagged |
| `/root/code/mygithub/slax-wine/work` (a real leak) | flagged — correctly |
| `var/lib/marker` (relative) | OK |
| `https://example.invalid/x` | OK |

There is **no unit test over `hostish_values` or `append_recipe`**, which is how it shipped; the
`^/` clause is the over-broad one, since the other four alternatives all name genuine host
locations. Worth attacking before filing, per this document's own bar: the fix is not obviously
"drop `^/`", because a profile var *could* legitimately carry a build-machine path. Recording the
`vars` subtree through `in_image()`, or flagging only paths that exist on the build machine outside
the work tree, both look better — and either wants the unit test that is missing.

**Both of those suggestions were wrong**, and we said "worth attacking before filing" and then did
not attack them. See *What they corrected in our reports*, item 3.

**Resolved at `ba79ce0`.** `vars` get their own rule, `HOSTISH_SHAPE`: every host-ish shape
(`/home/`, `/root/`, `/Users/`, `~/`, `\\`) *except* bare `^/`, plus the paths this build actually
used — its work tree, the kitchen checkout, and `$HOME` unless that is `/`, `/root`, `/home` or
`/Users`.
Those are facts about this build rather than guesses about somebody's filesystem. `HOSTISH` itself
is untouched, because `ci/release-verify.py` and `ci/checks/97-tier-c-ledger.sh` rely on it, and an
absolute `iso_name` really is a leak.
Provenance is now written *before* the journal, so a refusal no longer leaves a recipe journaled but
unrecorded. And the exemption is applied at **both** check sites: fixing only `append_recipe` left
the sidecar failing at pack time, which only a real build showed.

**Their stated gap does not reach us.** A builder under some unusual prefix — their example is
`/opt/somebuilder/artifacts` — is caught by neither half unless it is this build's own tree. Ours
build under `/root/…` in the container and would run under `/home/…` on the KVM host; both are shapes.
Checked in memory against the new code before bumping: all five of our overrides pass (`drop` ×3,
`marker`, `report`), while `/home/…`, `~/…` and a path under our work tree are still flagged.

**What it costs us right now:** the shipped pair is unaffected and rebuilt clean at this pin, with
the new explicit `drop:` var recorded in the sidecar without complaint. But every boot route we run
drives `slax-wine-test-*.iso`, so re-running them has to wait on this — which is why the bump sat
on a branch rather than on `master` until `ba79ce0` landed.

*(Later: `5627f2d` retired the path-shape rule altogether, closing upstream's #26. It had caught two
things in its life, and both were false, #20 among them. See
[Adopted at the `86d27d5` bump](#adopted-at-the-86d27d5-bump).)*

## In flight upstream at the `8adfca6` bump · **merged, taken at `337f7e7`**

**[PR #21](https://github.com/Fullaxx/slax-kitchen/pull/21) `Closes #14`** — *"apt may not remove a
package, and what leaves is now counted"*, opened while this bump was being prepared. Issue 14 is in
our open-upstream register above, so this retires it, and the change has teeth for us: after it,
`bundle.packages` **refuses** rather than warns when apt would drop a package to resolve a conflict.

Nothing here triggers it today — `wine` installs sixteen packages and the build's own delta line
reports `3836 added, 105 modified` with no removals — but it is the kind of change that turns a
silent accommodation into a hard failure, which is exactly what the `#19` fix did to our submodule
(`#22` above). Worth re-reading before the next pin bump rather than discovering at build time.

**That paragraph's conclusion was right and its evidence was not.** The delta line cannot show a
removal — never counting what left was the whole of `#14` — so "the delta line reports no removals"
proved nothing. The conclusion was held up by two other things: the register's own measurement
(`install ok installed` 567 in `04-apps.sb`, 626 in the merged database, nothing present before
missing after), and, re-checked before this bump, the `20-wine` dpkg fragment — all 60 stanzas
`install ok installed`, no `deinstall`, which is the shape an apt-driven removal leaves.

**Measured by the engine itself at `337f7e7`.** `5e7825f` (PR #21) landed, and our build now
answers the question three independent ways, all in the `wine` step:

- apt ran with `--no-remove` and did **not** refuse — no `apt wanted to REMOVE`
- the delta line carries no `, N vanished` suffix. `v_bundle_packages` appends it only when files
  present before are absent after (`apply.py:3204`), so **zero vanished**
- the sidecar's `wine` step has no `uninstalled` key. The verb records it (`apply.py:3252`) and
  `prov()` drops `None`, so an absent key is an **empty** before-to-after difference

## Adopted at the `337f7e7` bump

Four commits, `8adfca6..337f7e7`, carrying three `Closes` trailers: **#14** by `5e7825f` (merged as
PR #21), **#20** by `ba79ce0`, **#22** by `337f7e7`. Upstream's own CI on `337f7e7` was green before
we took it — including `build debian-32bit-12.2.0`, our exact base, and their TCG boot test.

**What moved in our tree.** Of fourteen copied files only `ci/lib.sh` changed upstream, and it is
back to *Copied verbatim* (see #22 above). The other thirteen were re-cited after checking each
source had zero upstream commits in the range, so the new citations are true rather than
refreshed. Gate 96 did the finding: §7 named all fourteen stale headers and §8 all eight prose and
permalink pins — `CHANGELOG.md`, `docs/build.md` and five links in `INSTALL.md`. §8's own message
printed those paths absolute, `/root/code/…`, which is a build-machine path in a gate about
citations; it is repo-relative now.

**Adopted: `tests/unit/test_ci_lib.py`**, verbatim, run by gate 80. It is the first test over the
code that let a `.exe` through (#19) and then refused every submodule bump (#22), and before its
header was written it had already found something: run against our 8adfca6-era `ci/lib.sh` it failed
three checks on the latent `stat` probe, and against the re-copied library it passes. It came with a
hazard of its own — see the next section — handled in our runner, not by editing the test.

**Not adopted:** `test_provenance.py` and `test_apply.py` test engine code we do not copy. They were
run instead, with the other changed test, inside the pinned submodule (`python3 -B`, so no bytecode
lands in `vendor/`): all three pass.

**The build, at `337f7e7`:**

| image | steps | assertions | bytes | modules |
|---|---|---|---|---|
| bios | 7 | 21 / 21 | 531,935,232 | 9 |
| uefi | 8 | 21 / 21 | 538,425,344 | 9 |
| test | 10 | 21 / 21 | 538,437,632 | 9 |

All three sizes match the pre-bump images to the byte. The test image is the one #20 had blocked:
`uefi-bootable` now runs after `testkit`, where the guard used to kill the apply. Its sidecar is
the one that exercises the host-ish guard in both directions, and it does: the only two absolute
paths in it are `testkit`'s in-image vars, kept with their slash, and it contains no build-machine
path. The shipped sidecars contain no absolute path of any kind — in-image paths go through
`in_image()` — so for them "no leak" is true but proves little, and is recorded as such.

**The boot routes, re-run on the KVM host** — whose own checkout had meanwhile moved to
`337f7e7`, so the harness is the pinned engine's rather than an equivalent one. The ISO was checked
by sha256 after transfer, since it is byte-for-byte the same size as the old one:

| route | result |
|---|---|
| `--kernel` (control) | `Live Kit done`; the harness's cmdline carries `automount` — **the probe can fire** |
| `--bios` | `Live Kit done` in 6 s via isolinux's serial entry; **no `automount`** |
| `--uefi` | `Live Kit done` in 6 s via GRUB under OVMF; **no `automount`** |
| `--persistence` | boot 1 `absent, creating` + `synced`; boot 2 `present, written 2026-09-18T18:07:47Z` — the timestamp boot 1 wrote. 5 s per boot |

Evidence is in `out/boot-tests/`; the `bcd4f00`-era set was kept beside it as
`out/boot-tests-bcd4f00/`, on the KVM host too.

## Filed at the `337f7e7` bump — [#23](https://github.com/Fullaxx/slax-kitchen/issues/23), a unit test that writes into the commit running it · **closed by `3a44e8a`**

Found while adopting `tests/unit/test_ci_lib.py`, the test that came with the `#22` fix, and it is
a property of that test running inside a hook, not of the fix. Filed as #23 after one more claim
was checked rather than inferred: that the fixture's `git add -A` *drops* the commit's own files.
Isolated with no hook — an absolute `GIT_INDEX_FILE` standing in for the commit's `index.lock` —
the pending index went from `seed` to `big.bin payload.exe`.

Also before filing, each of the other three tests was read for how it builds its environment,
since two pass `env=` explicitly and a clean one would be immune: `test_release.py` copies
`os.environ`, and `test_sources.py` and `test_tier_c_guard.py` pass none. All three inherit.

`80-unit.sh` runs at `pre-commit`, and git exports its repository to hooks. `githooks(5)` is
explicit about the consequence: *"if your hook needs to invoke Git commands in a foreign repository
... it should clear these environment variables."* `test_ci_lib.py` builds throwaway repositories
and runs `git add`, `git commit` and `git submodule add` in them, and clears nothing. Measured in a
throwaway outer repository whose hook ran the test, then again through **our real gate 80**:

| commit mode | what the hook receives | what happened |
|---|---|---|
| `git commit` | `GIT_INDEX_FILE=.git/index` — **relative** | harmless: it resolves inside each fixture. Test passes, commit lands |
| `git commit -a`, `git commit -- <path>` | `GIT_INDEX_FILE=` the outer commit's `index.lock` / `next-index-*.lock` — **absolute** | the fixture's `git add -A` rewrote the outer commit's pending index — dropping the commit's own files, adding a 3 MiB `big.bin` and a `payload.exe` whose blobs exist only in the fixture. The commit died: `error: invalid object ... Error building trees`. **Gate 80 reported success** |
| a linked worktree | `GIT_DIR=<repo>/.git/worktrees/<name>` | fixture commits (`one`, `seed`) landed **on the outer branch**, and each fired the outer pre-commit hook, which ran the test again: **unbounded recursion** — 62 test processes, then 158, and 2,956 fixture directories within a few minutes, before it was stopped |

Our real repository was never in the environment chain — every run used a throwaway outer repo
under `work/` — and was checked afterwards: same HEAD, same branches, same index.

**It is not confined to this test.** Four of upstream's unit tests invoke git — `test_ci_lib.py`,
`test_release.py`, `test_sources.py`, `test_tier_c_guard.py` — and none clears git's environment.
Only `test_ci_lib.py` was run under a hook here; the other three are an inference from their
source, stated as one.

**Fixed locally, at the runner rather than in the test.** Our `80-unit.sh` now runs each test in a
subshell with git's repository-local variables unset — the list comes from git itself, `git
rev-parse --local-env-vars`, not a copy of it — and fails closed if git will not produce the list.
One place covers every test, including ones not yet written, and keeps upstream's tests verbatim.
The gate's own environment is untouched, because other gates legitimately need `GIT_INDEX_FILE` to
see what a partial commit is about to record. Proved in all three modes: `commit -a`, a partial
commit and a worktree commit each land with only the outer repo's own file in the tree, the hook
fires exactly once, and no fixture commit reaches the outer branch. A deliberately broken test
still fails the gate through the subshell.

**Closed by `3a44e8a`, with the same mechanism** — cleared in the gate rather than in the tests,
names from `git rev-parse --local-env-vars`, refuse when git answers nothing — so our workaround
went at the next bump. Their commit settles the inference above: all four tests do build throwaway
repositories, and two of them had been measuring the wrong repository under a hook, and passing.

## Adopted at the `3a44e8a` bump

Two commits, `337f7e7..3a44e8a`, carrying one `Closes` trailer: **#23** by `3a44e8a`. The other,
`d877143`, is a comment and a doc line — `lib/provenance.py` now says its path-shape guard is the
belt and braces rather than the thing doing the work, and a machine's name left
`docs/60-testing/qemu.md` — so the engine that builds our images did not change. Upstream's CI on
`3a44e8a` was green before we took it, including `build debian-32bit-12.2.0` and their TCG boot
test.

**The ledger's first live test.** Staging the new pin made gate 96 fail in three sections at once:
§7 on all fifteen copied-file headers, §8 on all eight prose and permalink pins, and the new §10 on
the one row it exists for — *"ci/checks/80-unit.sh: works around slax-kitchen#23, which 3a44e8a
closed and the pin (3a44e8a) contains"*. That is the bump noticing a fixed workaround by itself,
which is the whole reason [Local workarounds](#local-workarounds) exists.

**What moved in our tree.** Of fifteen copied files only `ci/checks/80-unit.sh` changed upstream.
It is re-copied and still *Adapted*, now with one difference, the `# desc:` line. Our block went,
and with it a `# shellcheck disable=SC2086` that was never needed: gate 30 runs `-S warning`, and
SC2086 is only `info`. The other fourteen were re-cited after checking each source had zero upstream
commits in the range.

**Adopted: `tests/unit/test_unit_gate.py`**, verbatim, run by gate 80. It drives the gate against a
throwaway repository poisoned the way a linked-worktree commit really is, and asserts on the victim
— which is the regression test for the scrub we had meant to write ourselves. Tested before it was
trusted: against our `337f7e7`-era gate it failed exactly one check, *"...and what it was
protecting"*, because our refusal message lacked the words *"index in reach"*; against the re-copy
it passes, and it passes inside the pinned submodule too (`python3 -B`, so no bytecode lands in
`vendor/`).

**One flaw in it, measured rather than read.** The probe it plants calls `mkdtemp(prefix="probe-")`
and never removes the directory, so every run leaves two throwaway repositories of 184 KiB in
`/tmp` — and gate 80 runs at every commit and every push. Thirty-two of exactly that shape were
already in `/tmp` here before our first run, all dated 18:52–19:00 on 2026-09-18, the window in
which `3a44e8a` was written. Not a reason to adapt the test; a small thing to report — filed as
[#24](https://github.com/Fullaxx/slax-kitchen/issues/24), and it turned out wider than this test.

**Retired: `wine.yaml`'s explicit `from:`**, the belt-and-braces kept after issue 1 was fixed and
the ledger's other row. Its two reasons are answered in [DECISIONS.md](DECISIONS.md) D-3; the
evidence is the build.

**The build, at `3a44e8a`, without the list:**

| image | steps | assertions | bytes | modules |
|---|---|---|---|---|
| bios | 7 | 21 / 21 | 531,935,232 | 9 |
| uefi | 8 | 21 / 21 | 538,425,344 | 9 |
| test | 10 | 21 / 21 | 538,437,632 | 9 |

The sizes match the `337f7e7` images to the byte again. This time that was not left to stand for
more than it is: every file of all three images was compared with the `337f7e7` builds before the
build overwrote them.

| what | result |
|---|---|
| everything outside our four modules: base bundles, kernel, initrd, every boot config | **byte-identical**, except `/boot/efi.img` on the two GRUB images |
| `/boot/efi.img` | it holds one file, `EFI/BOOT/BOOTX64.EFI`, **identical** to the one in the `337f7e7` test ISO still on the KVM host. The FAT image around it differs in 36 bytes, the volume serial and sixteen timestamp fields, at exactly the offsets where two images of the *same* build differ |
| `20-wine`, `21-wine-desktop`, `30-notepadpp`, `98-dpkg-db` | **identical content**: 3,831 entries by type, mode, owner, size, link target and sha256. The `.sb` files differ byte for byte only because the build stamps directory mtimes, as they already did between the three images of one build |

So the image did not change, and the boot evidence recorded at the `337f7e7` bump stands for this
one. The four routes were not re-run, and that is a conclusion from the comparison above rather than
an omission. The sidecars record `kitchen.commit` `3a44e8a`, keep the test marker's leading slash,
and contain no build-machine path. They also say `711ad6f-dirty`, truthfully: the images were built
with this change in the tree, before its commit existed.

**Retired: the empty-tree skips.** This repo was built gates-first, so four checks were taught to
note-and-skip while their inputs did not exist yet, and nothing ever taught them to stop:

| gate | used to skip when | now |
|---|---|---|
| 95 | `docs/50-cookbook/` is missing | fails. The skip was its **only** difference from upstream, so it is back to *Copied verbatim* and §9 holds it there |
| 90 | `recipes/available/` is missing | fails, as upstream's does. It stays *Adapted* for its other differences |
| 96 | `build.env` is missing, which skipped the **whole** gate | fails, then stops: every section reads it |
| 96 §5 | `recipes/available/` is missing, which skipped the orphan check | fails |

Measured in a scratch copy with each input deleted: every one of those exited 0 with a *"not present
yet - skipping"* note before, and fails naming the input after. Gate 96 with no recipes was the
exception: §4 already failed on the missing `wine-desktop.yaml`, so that change adds a second, more
direct reason rather than closing a silent pass. **Gate 20's skip stays**, because it is upstream's
own line — a missing `vendor/slax-kitchen` notes and skips there too.

**Taken from `d877143`'s reasoning, not its code:** *a machine's name is not useful to anyone
else*. This page named the machine that runs our KVM boot routes three times; it now says "the KVM
host". The name told a reader nothing they could use, and the rest of this repository already
describes what a host must have rather than which host it was.

**The same class of bug as #23, in our own gate 96.** Found while writing §10, which reads the
submodule's history with the same bare `git -C vendor/slax-kitchen` that §7 used for the pin. That
call can answer for *this* repository. A commit from a linked worktree exports `GIT_DIR`, which
beats `-C`: measured with a real worktree and the real hook, the commit was refused, with every
citation "wrong" against a pin that was our own HEAD. An uninitialised submodule is an empty
directory, so discovery walks up to us: the *not checked out* branch could never fire.

The fix follows the shape of upstream's own for #23. The submodule's git runs with git's
repository-local variables cleared, and only once the repository git finds is the submodule's own;
it fails closed when git will not name the variables. `tests/unit/test_release_consistency.py`
drives all three cases. It failed six checks against the unfixed gate and passes against the fixed
one. Then the same worktree commit went through the real hook with all twelve gates green, and
landed on its own branch with its full tree. That also shows upstream's #23 fix working end to end
here, in the mode that did the most damage.

## Filed at the `3a44e8a` bump — [#24](https://github.com/Fullaxx/slax-kitchen/issues/24), five unit tests leave their fixtures in `/tmp` · **closed by `6e4470e`**

What started as `test_unit_gate.py`'s probe is five of upstream's fifteen unit tests. Each was
measured on its own at `3a44e8a`, with `TMPDIR` pointed at an empty private directory so nothing
else on the machine could add to the count:

| test | left per run | size |
|---|---|---|
| `test_apply.py` | 22 | 516 KiB |
| `test_dpkgdb.py` | 13 | 312 KiB |
| `test_qemu_boot.py` | 5 | 36 KiB |
| `test_release_assets.py` | 4 | 260 KiB |
| `test_unit_gate.py` | 2 | 372 KiB |

That is 46 entries and 1,496 KiB every time their unit gate runs, which is at every commit and every
push. All of it is test fixtures: the directories the code under test creates are named `kitchen-*`,
and none of those remained. On a development machine with the hooks installed, 2,337 of the named
ones (29 MB) had accumulated over four days, on a `/tmp` that is not a tmpfs.

The fix was tried before it was offered, which is the lesson of #20. The unit gate gives each test a
`TMPDIR` of its own and removes it afterwards, the same shape as their #23 fix. In a clone at
`3a44e8a` that took the leftovers from 46 to 0 with every test still passing, and a deliberately
failing test still failed the gate.

**Here:** of the five we carry only `test_unit_gate.py`, so our gate 80 leaves two 184 KiB
directories per run. It is deliberately **not** worked around. That would mean a second difference
in `80-unit.sh` and a row in [Local workarounds](#local-workarounds), for two small directories per
commit, and upstream's fix will arrive with a pin bump either way. *(It arrived at the `6bd59f1`
bump: gate 80 now leaves nothing — below.)*

## Adopted at the `6bd59f1` bump

Four commits, `3a44e8a..6bd59f1`, answering #24 and the issue it led to:

| commit | what | upstream CI |
|---|---|---|
| `6e4470e` | **closes #24**. The unit gate gives each test a `TMPDIR` of its own and removes it; a failing test keeps its fixtures and prints the path. `test_unit_gate.py` gains the regression test, checked against six mutations | green |
| `7194e0b` | **closes #25**, the by-hand half: the four leaking tests now clean up after themselves, and the gate's box became a **detector** — anything a *passing* test leaves turns the gate red, named | **red** |
| `f3ff3a3` | the red, fixed: `test_apply.py:1096` built a tar directory with `TarInfo`'s default `0o644`, which nobody but root can empty. The detector was right; the same leftover had printed `Permission denied` in `6e4470e`'s green run, where nothing looked | green |
| `6bd59f1` | their self-review of #23–#25: the boxes set `TMPDIR` for child processes too, "milliseconds" became "seconds" (the gate is 17 s), and the gate's three rules are written down in their `CONTRIBUTING.md` | **green**: gates, all four builds, TCG boot |

**Held, then taken.** At the first look the tip was `7194e0b` and red. We waited rather than pin the
last green commit or the red one — now a rule in [Moving the pin](#moving-the-pin) — and took
`6bd59f1` once its run had finished with every job green.

**What moved in our tree.** `ci/checks/80-unit.sh` is re-copied and still *Adapted*, one difference:
upstream's `desc` still says "the recipe engine's pure logic", so ours stays. `test_unit_gate.py`
is re-copied — §9 named it first, 137 lines stale. The other fourteen were re-cited after checking
each had zero upstream commits; §7 named all sixteen headers and §8 all eight pins, and §10 had
nothing to say, with no active workaround on the ledger.

**The detector now polices our tests too**, so it was run against them the way `f3ff3a3` says it
must be: through the gate and by hand, as root and as uid 65534 in a copy that user owns. All four
pass and leave nothing, every way. Upstream's five changed tests pass inside the pinned submodule
and leave 0 where they left 46, and the submodule stays pristine.

**No rebuild.** The range touches `ci/checks/80-unit.sh`, `tests/unit/`, `CLAUDE.md`,
`CONTRIBUTING.md` and `docs/00-overview/status.md` — nothing the build runs. The `3a44e8a` images and
the boot evidence behind them stand unchanged.

## Filed at the `6bd59f1` pin, building slax-bottles — [#26](https://github.com/Fullaxx/slax-kitchen/issues/26), the provenance guard refuses checkout-relative paths under a `root/` or `home/` directory · **closed by `5627f2d`**

**It stopped a real build, after the build.** Staging Bottles' DXVK/VKD3D the way every other stage
here is laid out, as a mirror of the destination
(`bundle.files` `src: ./bottles.files/root/.var/app/com.usebottles.bottles/data/bottles`), got:

```
error: bottles.yaml: provenance would record a path on the build machine:
  steps[1].local_inputs[1].path: 'recipes/available/bottles.files/root/.var/app/com.usebottles.bottles/data/bottles'
```

That came after `20-flatpak.sb` and the 890 MiB `30-bottles.sb` had been built (about 12 minutes
of `mksquashfs` over a 7.4 GB copy).

**Read.**

- `local_input()` records `root_relative()` (`provenance.py:199-207` at `6bd59f1`), which is
  always relative to the kitchen or project checkout, never absolute and never `..`.
- `hostish_values()` checks it with `HOSTISH` (`:142`), and `HOSTISH`'s `/root/`, `/home/`,
  `/Users/`, `~/` and `\\` alternatives are unanchored. So every hit on a `local_inputs` path is a
  directory inside the checkout that happens to have one of those names.
- An earlier version of this section named `HOSTISH_SHAPE`, which is the `vars` rule; that was
  wrong.
- Slax runs everything as root, so `/root` is where every image's user data goes, and a staging
  mirror of it always contains `root/`.

**Demonstrated end to end** in a clone at `6bd59f1`, with a three-line recipe shipping one file to
`/root/.config/demo`:

- the refusal comes after `40-root-demo.sb` is built;
- the bundle stays in `slax/modules/`;
- `kitchen status` says "nothing applied yet";
- `kitchen pack` ships the bundle with `recipes: []` in its provenance.

A staging dir that ends *at* `root` passes, because the pattern needs `/root/`, so a shallow test
misses it.

**Attacked.**

- `provenance.py:39-45`, new at `6bd59f1`, calls the guard deliberate ("BELT AND BRACES") and says
  its only catch was #20's false positive. This is the second catch, and it is false too.
- `release-verify.py` and `97-tier-c-ledger.sh` rely on `HOSTISH`, so a fix cannot simply relax the
  regex.

**Two fixes, tried in the clone:**

- **(A)** judges a `root_relative()` location as checkout-relative: refused only if absolute or `..`.
- **(D)** refuses at `Ctx.prov()`, when a value is recorded, instead of in `append_recipe` after the
  recipe has run.

With both, all 15 of their unit tests pass. The demo applies and is recorded. Forged absolute and
`..` inputs, an absolute `iso_name`, and a host path inside prose are still refused. D alone refuses
the demo before building, leaving nothing behind.

Removing the refusal outright was tried too. It fails four `vars` assertions in
`test_provenance.py`, which is the argument the issue puts to the maintainer.

**Worked around** by staging under `bottles-data/`. Both halves were marked
`WORKAROUND https://github.com/Fullaxx/slax-kitchen/issues/26`: `build.sh` at `BDATA=`, and
`bottles.yaml` at the `src:`.

**Closed by `5627f2d`, and retired when this branch took the `86d27d5` bump.** Upstream went
further than the issue asked. There is no shape rule at all now, `append_recipe` refuses nothing,
profile vars are checked before anything builds, and `finalize` refuses only strings under the
directories this build really uses (see [Adopted at the `86d27d5` bump](#adopted-at-the-86d27d5-bump),
which says nothing retires there: true on master, which never had this workaround).

- **The stage mirrors its destination again**,
  `bottles.files/root/.var/app/com.usebottles.bottles/data/bottles`. Both markers are gone, and both
  rows above say *retired*.
- **Checked before building**, against `86d27d5`'s `provenance.py` loaded in memory. The restored
  path passes, and so does an in-image `/root/...` path. An absolute path into this checkout, and
  one into the work tree, are still refused.
- **Then built.** All three images applied and packed with no refusal, `finalize` included. The
  slax-bottles sidecar records the new path with the same content digest the `bottles-data/` input
  had, gains and loses no field, and names no build-machine path.
- **Gate 96 §10 would not have let the bump through otherwise.** With one row put back to
  *active*, it failed: "works around slax-kitchen#26, which 5627f2d closed and the pin (86d27d5)
  contains".

## Adopted at the `86d27d5` bump

Three commits, `6bd59f1..86d27d5`. Upstream's CI on `86d27d5` was green in every job (gates, all four
builds, the TCG boot) before anything here moved. `5627f2d` on its own had been red.

| commit | what | here |
|---|---|---|
| `e7c0ac9` | their `CLAUDE.md`: nothing is committed or pushed until the user has inspected the work and asked, and approving a plan is not approving its commits | mirrored into ours at the user's call. Step 4 of [Moving the pin](#moving-the-pin) now stops where the commit would go, and this was the first bump handed over uncommitted |
| `5627f2d` | **closes #26**: the provenance guard's path-shape rule is retired. It had caught two things in its life, and both were false, our #20 among them. Its replacement refuses only strings under the directories this build really uses: the work tree, the kitchen checkout, a non-generic `$HOME`, and, **new, the project checkout**, which a vendored kitchen like ours never had covered. Profile vars are checked before anything builds, at the start of `kitchen apply` | a build input: rebuilt |
| `86d27d5` | refs #26: a build directory counts only where a path can begin, which fixes the false positives a short checkout (`/work`) gave `5627f2d` in CI | a build input: rebuilt |

**What the new guard means here.** At every bump we used to check by hand that no sidecar carries a
build-machine path. That check is now upstream's, in two places our build reaches:
- `kitchen apply` checks the profile vars before anything is built (`lib/apply.py:3613`)
- `kitchen pack` runs `finalize`, which checks the whole sidecar (`lib/pack.sh:228`)

Both cover this checkout for the first time. Our three builds passing them is the proof that nothing
we record names the builder, including the `drop` pattern and testkit's in-image marker and report
paths. Nothing here had worked around the old guard, since at `8adfca6` we held rather than work
around #20, so nothing retires.

**The build, at `86d27d5`:** 7/8/10 steps and 21/21 assertions each. Sizes are 531,935,232 /
538,425,344 / 538,437,632, identical to the `3a44e8a` images to the byte. Every file was compared
with those images:

| what | result |
|---|---|
| everything outside our four modules | byte-identical, except `/boot/efi.img` on the two GRUB images |
| `/boot/efi.img` | `EFI/BOOT/BOOTX64.EFI` is identical. The FAT image differs in 60 bytes: the volume serial, and 56 timestamp bytes across 8 directory entries, nothing else. Two images built on the same day differ in 36 of those: the serial, and the create and write times. The other 24 are the create, access and write dates, because this build ran the next day |
| our four modules | identical content, all 3,831 entries |
| the sidecars | no field added or removed. What changed is the kitchen and project commits, the submodule pin, and the byte hashes of artifacts whose content is identical. testkit's marker keeps its leading slash |

So the images did not change, the boot evidence stands, and the routes were not re-run.

**Copied files:** none of the sixteen changed upstream, and all were re-cited. **Not adopted:**
`tests/unit/test_tier_c_ledger.py`, which is new and tests a gate this repo deliberately does not
carry. Upstream's three changed tests pass inside the pinned submodule and leave nothing in their
`TMPDIR`, and the submodule stays pristine.

## Filed at the `86d27d5` pin, building slax64-wine — [#27](https://github.com/Fullaxx/slax-kitchen/issues/27) and [#28](https://github.com/Fullaxx/slax-kitchen/issues/28)

Both found building and boot-testing the 64-bit images, filed 2026-09-19 against `86d27d5`, which
was upstream `master`. Each was reproduced in a scratch clone, and each fix was tried there: 13 of
13 gates and 16 of 16 unit-test files pass at `86d27d5` unmodified, and again with each fix in
place. Each new test fails against `86d27d5`, which is the half that makes it worth having.

### [#27](https://github.com/Fullaxx/slax-kitchen/issues/27): `when: arch==` is read from the path the ISO was unpacked from

**Read.** `lib/unpack.sh:38` records `source_iso` as the absolute path given to `kitchen unpack`.
`_tree_facts()` (`lib/apply.py:3261-3272`) sets `arch` by substring over it, `32bit` first, and
`check_compat()` (`:3341-3357`) does the same for `arch` and `flavour`. `flavour` for `when:` is read
from `01-core`; `arch` is not. `fingerprint.py:253-268` already probes an ELF in `01-core`, and calls
that the authoritative arch.

**Demonstrated.** One stock `slax-64bit-debian-12.2.0.iso`, reached by three symlinks, run through
the stock `memtest86plus` recipe. `kitchen probe` calls it `debian-64bit-12.2.0` by every path.

| path | arch | `memtest.bin` |
|---|---|---|
| `isos/slax-64bit-debian-12.2.0.iso` | `64bit` | x86-64, PE machine `0x8664` |
| `slax-32bit-and-64bit/slax-64bit-debian-12.2.0.iso` | **`32bit`** | **i586**, PE machine `0x014c` |
| `downloads/slax.iso` | **`unknown`** | **none**, but the `memtest` menu entries are added and the recipe is journalled as applied |

**Attacked.** Nothing tests `_tree_facts()` or `check_compat()`. `--facts` overrides wholesale, and
only helps someone who knows. `kitchen build` preflights with `--facts` from the profile, but applies
without them (`lib/build.sh:324-325`, `:359`).

**Fix tried.** Read the ELF class of `01-core`'s `ls`, with `fingerprint.py`'s candidates. With no
`01-core`, fall back to the ISO's file name, never its directory. `check_compat()` then reads the same
facts. All three trees read `64bit`, and the stock 32-bit ISO still reads `32bit`.

**Not worked around.** Our `build.sh` already refuses both consequences, an image whose release file
names another base and a 64-bit one without `wine32:i386`. Nothing else here depends on the path, and
`ISO_DIR` is ours. So there is no marker and no row.

**Closed by `cc28622`**, taken at the [`7f9c4f8` bump](#adopted-at-the-7f9c4f8-bump), with the fix as
filed: the ELF class of `01-core`'s `ls`, then the ISO's **file name** alone, then `unknown`. The
five trees built at that pin each resolve the arch they should, and the skip lines say so.

### [#28](https://github.com/Fullaxx/slax-kitchen/issues/28): a key QEMU refuses is dropped in silence

**Found by being wrong about it.** Every UEFI boot test here under TCG, and slax-bottles' before it,
passed `--keys '3s,(home,1s)x22,down,down,ret'`, and our docs described it as `home` once a second.
The harness has no `(…)xN` syntax, and `send_keys()` discards QEMU's reply (`qemu_boot.py:134`). QEMU
refused `(home` and `1s)x22`, and what ran was a 3-second lead — which happened to suit this host.

**Demonstrated.** QEMU refuses `(home`, `1s)x22`, `Down` and `enter`, and accepts `home`, `down`,
`ret`. At the pin, `kitchen test <iso> --uefi --keys '2s,Down,ret'` spends its whole 32-second
ceiling and then reports four failures, the first of which blames the key *sequence* — nothing names
the refused token.

**Attacked.** Nothing between `--keys` and QMP validates a token; `Qmp.cmd()` does return the error,
and only this caller drops it; `_serial_keys()` emits only names QEMU knows, so this bites whoever
passes `--keys` by hand — which three cookbook pages tell people to do.

**Fix tried.** `send_keys()` raises `KeysRefused`, deliberately not a `RuntimeError`, which `boot()`
would file under "qemu died". `--keys '2s,Down,ret'` now exits at once naming `'Down'`. 16 of 16
unit-test files pass, and 13 of 13 gates.

**Not worked around.** Nothing here passes a key name QEMU does not know, now that we have checked.

**Closed by `a613b3b`**, taken at the [`7f9c4f8` bump](#adopted-at-the-7f9c4f8-bump). A malformed
spec now exits 2 before anything boots, and under a boot host before the tree is even sent. Every
`--keys` string in this repo parses under the new grammar; the one that does not, `'3s,(home,1s)x22,…'`,
survives only in prose that says it was refused, which is this issue's own record.

### Measured, and deliberately not filed: the UEFI keystroke lead under TCG

The same investigation found that `kitchen test --uefi` cannot pick the serial entry on this host
with the harness's own keys, and this is recorded here rather than upstream.

| | this host, idle | the same host, vCPU sharing a core |
|---|---|---|
| GRUB's 5-second menu first drawn | 3.2 s | 6.9 s |
| countdown over, default entry booting | 8.3 s | 22.8 s |

The harness sends `down,down,ret` after a fixed 2-second lead, so here the keys land *before* GRUB
exists. Its own comment (`lib/build.sh:48-52`) records the menu appearing later than 9 s on the host
it was written on, which is the point: the window moves with the machine. A lead sweep through the
harness, idle: 1 s and 2 s fail, 3 to 6 s pass, 8 to 16 s fail. On the starved core a 4 s lead fails
too, and so does the harness's 2 s. One `home` pressed inside the menu stops its countdown for good,
so `home` once a second passes on both.

**Why it is not an issue upstream.** It is a property of running without KVM. Under KVM the menu
appears in about a second (upstream's own figure, `docs/50-cookbook/uefi-bootable.md:79-80`), the
2-second lead lands inside GRUB's 5-second window, and our own KVM-host runs on 2026-09-18 passed
with the harness's keys and no `--keys` at all. **Read with the later finding**, below: under KVM
the lead lands on an *idle* machine, and missed twice on one at a load average of 12 — so the
property is the host's speed at that moment, not the accelerator alone. This project is moving to a KVM-capable host, and
[#28](https://github.com/Fullaxx/slax-kitchen/issues/28) was edited down to the half that is
independent of the accelerator. The measurements stay here for whoever meets it under TCG.

**What we do meanwhile.** Under TCG, pass the presses spelled out, since the harness has no
repetition syntax:

```sh
KEYS=$(printf '1s,home,%.0s' $(seq 24))down,down,ret
$K test "$I" --uefi --keys "$KEYS"
```

Measured on `slax32-wine-test`, on `slax64-wine-test` idle and starved, and on `slax-bottles-test`:
all four selected the serial entry. `profiles/slax32-wine-test.yaml` and
[`slax-wine-iso`](50-cookbook/slax-wine-iso.md) carry the procedure. It is not a workaround row,
because there is no issue to retire it against; on a KVM host it is simply unnecessary.

**Our record corrected.**
- `slax-wine-iso.md` and `slax-bottles-iso.md` now say what actually ran.
- Their results stand, because each of those boots selected the serial entry, as its kernel command
  line shows. Only the explanation was wrong.
- The lesson is the one already on this page: attack a finding before relying on it. A key spec that
  "worked" was never checked against what the harness accepts.

### When KVM lands: it did, on 2026-09-21, and this is what it changed

**It arrived as a boot host, not as a device.** This container still has no `/dev/kvm`; `bacon` has
one, and since the [`7f9c4f8` bump](#adopted-at-the-7f9c4f8-bump) `vendor/slax-kitchen/boot-host.ini`
sends every `kitchen test` there. `kitchen doctor` now prints `boot tests ... KVM on bacon
(qemu 8.2.2)` where it printed the TCG note, which is the signal
[`CLAUDE.md`](../CLAUDE.md) said to watch for.

**Every route was re-run with the harness's own keys — no `--keys` at all**, which is what the
checklist asked for, on all three test images as built at `7f9c4f8`:

| image | `--kernel` | `--bios` | `--uefi` | `--persistence` |
|---|---|---|---|---|
| `slax32-wine-test` | 8 s | 14 s | 12 s | 13 s |
| `slax64-wine-test` | 8 s | 14 s | 13 s | 12 s |
| `slax-bottles-test` | 15 s | 14 s | 13 s | 13 s |

Twelve routes, twelve passes, each reaching `Live Kit done`. The timings are the whole command, the
transfer to `bacon` included. The boot itself, which is what the harness times, was **4 to 6
seconds** on every one of the fifteen (six at 6 s, six at 4 s, three at 5 s, ceiling 32 s) where
TCG took 21–31. **Every `--bios` and `--uefi` log carries `console=ttyS0` and no `automount`**, and
every `--kernel` log carries both — the control that proves the check can fail. So the `automount` removal is now demonstrated through
both bootloaders on both bases *and* on slax-bottles, under KVM, with the shipped 5-second menu.

**The `--keys` chore is over, with one measured caveat.** The harness's derived
`'2s,down,down,ret'` lands inside GRUB's menu on this host — but not while the machine is busy. Both
UEFI routes failed on the first pass, run *during* a build with a load average of 12: the keys went
out before OVMF had drawn the menu, GRUB's countdown expired, the default entry booted, and nothing
reached the serial log. On the idle host the same command passed three times in a row, and `3s`,
`4s` and `6s` leads all passed under load. This is the same sensitivity the TCG measurements
recorded — *"leads of 3–6 s pass on the idle host, and fail on the busy one"* — with a smaller
margin, not a different phenomenon. **Do not run boot tests against a build in progress**, and do
not read a single UEFI failure as a regression without checking what else the machine was doing.

Worth filing upstream? The harness's lead is a fixed 2 s and nothing measures whether the menu is up
before the keys go. Reported, not filed: an outward-facing report is the user's call.

**The queue is worked, on 2026-09-21.** Re-measuring what emulation distorted was its own piece of
work, and it is done: the numbers below were taken on `bacon` under KVM, in a guest driven over its
serial console, and every page that quoted a TCG figure now carries both, with the TCG one labelled
as what a machine without an accelerator does — which CI and a container still are.

| what | under TCG | under KVM |
|---|---|---|
| a boot route to `Live Kit done` | 21–31 s | **4–6 s** |
| a 64-bit Wine prefix | ~4 min | **65 s** |
| a 32-bit prefix on slax64 | 90 s | **32 s** |
| a 32-bit prefix on slax32 | 90 s idle, 7–9 min busy | **23 s** |
| the Notepad++ x86 installer, `/S` | 29 s | **1.3–1.6 s** |
| the Notepad++ x64 installer, `/S` | 29–32 s | **1.7 s** |
| Wine's 5-minute `wineboot` limit | reached once, on a busy host | nowhere near |

Unchanged, because they are memory rather than speed: a fresh 64-bit prefix is 1,265 MiB and a
32-bit one 587–589 MiB. Pages updated: [`using-wine`](using-wine.md),
[`testing-on-both`](testing-on-both.md), [`notepadpp32`](50-cookbook/notepadpp32.md),
[`notepadpp64`](50-cookbook/notepadpp64.md), [`slax-wine-iso`](50-cookbook/slax-wine-iso.md) and
[`slax-bottles-iso`](50-cookbook/slax-bottles-iso.md).

**And the work that was waiting on the accelerator is done too.**
[slax-wine#1](https://github.com/Fullaxx/slax-wine/issues/1) — the two Notepad++ tiles replacing
each other in one prefix — is implemented as [D-17](DECISIONS.md#d-17--one-prefix-and-the-flip-is-a-choice)
and verified in the same session, in both directions and with its negative control on slax32. The
issue is left open for the user to close: that is an outward-facing action.

**What did not change**, and should not be re-opened on the strength of any of it:

- [#28](https://github.com/Fullaxx/slax-kitchen/issues/28) — QEMU refuses an unknown key name on any
  accelerator. Fixed upstream in `a613b3b`; the harness now says so instead of discarding the reply.
- The images, *at this bump*. Nothing was rebuilt for KVM's sake and all five shipped images are
  identical in content across it; what changed is the evidence's cost, not the artifact. The two
  launcher changes that followed on the same day are their own commits, and they changed exactly
  two files inside two bundles.
- The TCG measurements themselves. They stay, dated and labelled: they are true of CI, of a
  container, and of this machine before `bacon` took the boots.
## Filed at the `86d27d5` pin, from this repo's own test tooling — [#29](https://github.com/Fullaxx/slax-kitchen/issues/29) and [#30](https://github.com/Fullaxx/slax-kitchen/issues/30)

Two checks this repo carries because the engine does not. Both were filed 2026-09-20 with a fix
tried in the same scratch clone, which passes 13 of 13 gates at `86d27d5` unmodified and with each
fix.

### [#29](https://github.com/Fullaxx/slax-kitchen/issues/29): `kitchen apply --profile` never reads the profile's `base:`

**Read.** `read_profile_recipes()` (`lib/apply.py:3531`) returns recipe names and var overrides only.
Nothing in `apply.py` reads `base:`, though `schema/profile.schema.json` requires `flavour`, `arch`
and `version`, and `kitchen build` picks the ISO to fetch from them (`lib/profile.py:25`).

**Demonstrated** with upstream's own `profiles/minimal.yaml`, which declares `arch: 64bit`, applied
to a tree unpacked from the stock 32-bit ISO: `preflight ok`, the full plan, exit 0, no warning.

**Fix tried.** Compare the declared base with the tree's facts before the banner, and refuse:
`error: the profile is for arch 64bit, but this work tree is 32bit`. `--facts` still wins. 16 of 16
unit-test files pass.

**Worked around** by `build.sh`'s own guard, which refuses a variant whose profile names another
base and a tree unpacked from another ISO. Marked there, with a row in
[Local workarounds](#local-workarounds). It can retire if #29 lands — and it is only as good as the
arch fact, which is what #27 is about.

**Closed by `949074b`**, and the workaround **retired** at the [`7f9c4f8` bump](#adopted-at-the-7f9c4f8-bump).
`apply --profile` now refuses a tree that disagrees with the profile's `base:` — on `flavour` and
`arch`, deliberately not on `version`. `build.sh` keeps the three-part comparison for that reason,
unmarked, as a check of our own `build.env` rather than of theirs.

### [#30](https://github.com/Fullaxx/slax-kitchen/issues/30): `kitchen diff --bundles` compares file lists, not files

**Read.** `_bundle_paths()` (`lib/diff.py:134`) lists paths with `unsquashfs -l`; when both lists
match, `diff` prints "(same file list; contents differ)" — the same line whether or not anything
inside changed.

**Demonstrated** with upstream recipes only: one stock tree copied, `enable-ssh` applied to each
copy, each packed. `kitchen diff --bundles` reports `08-ssh.sb` changed and the images DIFFERENT.
The two bundles differ in one thing, the superblock's creation time, one second apart; every entry
inside is identical, mtimes included.

**Why it matters here.** Step 2 of [Moving the pin](#moving-the-pin) is exactly this comparison, and
the answer is the same whether a bump changed a bundle or not. Our own rebuild pair — two comment
lines in one shell script — came back as four bundles "contents differ", naming nothing.

**Closed by `a941ca2`**, taken at the [`7f9c4f8` bump](#adopted-at-the-7f9c4f8-bump), with `1eda24e`
and `fe17036` behind it. `kitchen diff --bundles` is now the tool step 2 of *Moving the pin* asks
for, and that step no longer says it cannot be.

**Fix tried.** Compare contents: type, mode, owner, size, link target and sha256 per entry, mtimes
excluded, extracting only under `--bundles` and only for a bundle whose bytes already differ. It
then names `usr/local/bin/notepadpp32` in our pair and calls the other three bundles identical. A
new `tests/unit/test_diff.py` covers both directions; 17 of 17 unit-test files pass. The issue also
records the alternative, measured: `mksquashfs -mkfs-time 0 -all-time 0` makes two runs
byte-identical, which would make bundle hashes stable across rebuilds.

**Not worked around in the repo.** The comparison scripts live in this session's scratch directory,
not in the tree; what the repo carries is the instruction in Moving the pin to compare content
rather than bytes.

## Adopted at the `7f9c4f8` bump

Fifty-two commits, `86d27d5..7f9c4f8`, 79 files, +9,893/−479. Upstream's CI on `7f9c4f8` was green in
every job before anything here moved. Four of the closures are ours — #27, #28, #29, #30 — and each
is recorded in its own section above.

| what changed upstream | here |
|---|---|
| **the boot host**: `lib/boot_host.py`, `boot-host.example.ini`, `docs/60-testing/boot-host.md`, `ci/run-boot.py` (`c1e65a3`, `46d163e`, `29c67b7`, `a2a3a7b`, `6b8a74e`, `ed1dbe6`) | adopted — see below. This is the bump that ends the TCG era here |
| **the arch and flavour facts**: measured from `01-core`, not guessed from a path or defaulted (`cc28622`, `012e720`), and `--facts` reaching the steps that run (`cadcfef`, `d200538`) | build inputs: rebuilt, and every tree's facts read back |
| **`boot.menu` refuses a payload nothing provides** (`a9e75a9`, `cb584ff`) | a build input. Our bases' menu entries all name `/slax/boot/vmlinuz`, which the ISO ships, so nothing is refused |
| **`apply --profile` holds the tree to the profile's `base:`** (`949074b`) | retires our one active workaround |
| **`kitchen diff --bundles` compares content** (`a941ca2`, `1eda24e`, `fe17036`) | the comparison below is the first to use it |
| **tools are checked before a command starts** (`7f8ded8`, `5231f13`, new `lib/need.py`) | `kitchen pack` now names a missing `unsquashfs` instead of dying mid-pack |
| **fourteen commits inside gates we copy** | nine of our sixteen copies changed; two new helpers came with them |
| tier-c, containers, `release.yml`, upstream's own docs | not ours |

**The boot host, which is the headline.** This build container has no `/dev/kvm` at all. `bacon` has
one, writable by this account, and since this bump `vendor/slax-kitchen/boot-host.ini` sends every
`kitchen test` there over ssh: the engine's own tree by `git ls-files`, the image by content-addressed
rsync, everything under `<scratch>/boot-host/`, nothing outside it touched.

The file lives **inside the submodule**, which is the one surprise worth writing down:
`lib/boot_host.py` resolves `REPO_ROOT` from its own location and reads `<REPO_ROOT>/boot-host.ini`
and nowhere else. It is `chmod 600`, ignored by the submodule's own `.gitignore` (upstream added
`/boot-host.ini` in `c1e65a3`), invisible to this repository — the superproject does not descend into
a submodule — and refused by `10-no-dnc.sh`, ours included, if it is ever staged. Our `.gitignore`
carries the name too, for a copy put at the top of this repo by mistake.

`kitchen boot-host check` is green on every line: the five tools, python 3.12.3, qemu 8.2.2, OVMF,
`/dev/kvm` writable, 134.9 GiB free, and the work directory private. `kitchen doctor` now prints
`boot tests ... KVM on bacon` where it used to print the TCG note — which is exactly the trigger
[`CLAUDE.md`](../CLAUDE.md) pointed at. A configured host that cannot be reached **fails the
command**; it never falls back to a local boot, and `KITCHEN_BOOT_HOST=local` is the way back here.

**The build, at `7f9c4f8`.** Eight images built at the old pin first, as a baseline — `out/` was
empty, and the numbers in the docs turned out to be one build's rather than the release's (see
below). Then the same eight at the new pin. Every shipped image is **identical in content**:

| image | size, both pins | what differs |
|---|---|---|
| `slax32-wine-bios` | 531,935,232 | four bundles' container bytes; 48 entries, every one matching |
| `slax32-wine-uefi` | 538,425,344 | the same four, plus `/boot/efi.img` |
| `slax64-wine-bios` | 855,173,120 | five bundles' container bytes; 49 entries, 10,997 inside `20-wine.sb` alone |
| `slax64-wine-uefi` | 861,663,232 | the same five, plus `/boot/efi.img` |
| `slax-bottles` | 1,300,676,608 | `20-flatpak`, `30-bottles` (66,254 entries), `98-dpkg-db`, plus `/boot/efi.img` |

The three test images were built and compared too: `slax32-wine-test` 538,437,632 and
`slax64-wine-test` 861,677,568, both unchanged in size and entry count, their bundles identical in
content. They are what the boot routes below ran against.

`kitchen diff --bundles` says it plainly for every one of them: *"identical content — every entry
matches; only the container's own bytes differ, as a rebuild's do"*. The five stock bundles are
byte-identical and are not even listed. `/boot/efi.img` differs in **36 bytes**, all between offsets
40 and 32,856 — the FAT volume serial and the create and write times of eight directory entries —
in a 6,488,064-byte image, so `EFI/BOOT/BOOTX64.EFI` is untouched. Both builds ran on one day; a
build a day later differs in 24 more, the date fields, as the `86d27d5` bump measured.

**The new facts, read back.** This is what `cc28622` and `012e720` change, and the apply log states
it per skipped step: `[arch=32bit, flavour=debian]` on both 32-bit trees and `[arch=64bit,
flavour=debian]` on the three 64-bit ones. Measured from the ELF class of `01-core`'s `ls` now, not
from the path the ISO sat in — and the right halves of `wine`, `wine-desktop` and `slax-wine-iso`
ran on each. `21/21` and `22/22` structure assertions, as before.

**What the baseline caught, which is not about this bump.** Rebuilding at the *old* pin did not
reproduce three of the five documented sizes: the 64-bit pair came out 4,096 bytes larger and
slax-bottles 1,372,160 bytes smaller, with identical package sets. A squashfs is not
byte-reproducible run to run — the bios and uefi images of one run already carry different sha256
for an identically sized `20-wine.sb` — and the Flatpak stage is not byte-stable across installs
either, though `BOTTLES_LOCK` pins every ref. Upstream measured the cure while fixing
[#30](#30-kitchen-diff---bundles-compares-file-lists-not-files): `mksquashfs -mkfs-time 0
-all-time 0`. Nothing here depends on those byte counts; the documents that quote them do.

**Copied files.** Nine of the sixteen changed upstream: `ci/lib.sh` (new `require_python3`),
`10-no-dnc.sh` (which now also refuses a committed `boot-host.ini`), `40-schema.sh`, `60-links.sh`,
`80-unit.sh`, `90-doc-coverage.sh`, `test_ci_lib.py`, `test_desktop_entries.py`, `test_unit_gate.py`.
The other seven were re-cited only.

**Two new files, copied rather than borrowed**, because both gates now call a helper:

- `ci/md-links.py`, which `60-links.sh` runs. It **must** be copied: it resolves its own root from
  its location and runs `git -C ROOT ls-files "*.md"`, so the vendored copy would check the
  submodule's documentation instead of ours.
- `ci/unit-run.py`, which `80-unit.sh` runs to report a test defined but never called. It takes a
  path and derives no root, so borrowing would have worked — it is copied for symmetry, and because
  `ci/` here is a self-contained gate suite.

Both carry the usual header, so sections 7 and 9 of gate 96 hold them like the rest: eighteen cited
files now, not sixteen.

**Adaptations re-applied, not worked around.** `80-unit.sh` keeps its one difference, the `# desc:`
line, and takes upstream's `KITCHEN_BOOT_HOST=local` — which matters here for the first time, since
this tree now has a boot host. `40-schema.sh` takes `require_python3` with our wording, since we have
no `compat/`. `90-doc-coverage.sh` does **not** take the new TARGET-count rule: it counts
`kind: Fingerprint` files in `compat/`, and this repo has none, so the rule would stand down on every
run — the same reason the recipe-count and upstream-issue rules were left out. `test_desktop_entries.py`
gains a **third** local change: upstream's new "no .desktop files found at all" guard is not taken,
because every `.desktop` entry here is a recipe `content:` block and no real `.desktop` file is
tracked under `recipes/` — the guard would fail every run, and the scan that does have inputs carries
the same assertion already.

**The link gate now checks the half after the `#`** (`f6d07fa`), which nothing here had ever
verified. On the tree as this bump leaves it: **213 internal links, 40 of them with a fragment**,
across 23 files, all resolving. It was 207 and 36 before this bump's own writing, and none of those
36 needed fixing — an anchor gate arriving to find nothing broken is worth recording, because the
next rename is what it is for.

**Retired:** the [#29 row](#local-workarounds), the only active one. **Kept, unmarked:** `build.sh`'s
three-part base comparison, because upstream compares `flavour` and `arch` and deliberately not
`version`.

**Tests.** Upstream's five changed or new tests that touch what we copy — `test_ci_lib`,
`test_desktop_entries`, `test_unit_gate`, `test_md_links`, `test_doc_coverage` — pass inside the
pinned submodule under `python3 -B` with a private `TMPDIR`, leave zero entries behind, and the
submodule stays pristine. The five changed gates pass here as root **and** as uid 65534. Run as that
user *without* a git config they refuse outright — "every file-scoped gate would examine ZERO files
and report success" — which is `ci/lib.sh` failing closed, and worth having seen.

**Landed upstream after this pin, and deliberately out of scope:** `12d0f9c` fixes the target-count
rule's empty-list refusal, which is the rule this repo does not adopt; `18294f5` guards each test
call so one crash cannot hide the rest, in files we copy and in twenty-one we do not. Neither is
needed here, and both come with the next bump.

## Two findings were dropped before filing, in round one

Recording them because disproved candidates are worth as much as findings.

**Static-binary provenance** — right on the facts, but already documented three times upstream
(`docs/30-inventory/initramfs-userland.md`, `NOTICE.md`, and a tracked work item). Nothing to add.

**The `NoDisplay` chromium mask** — **our error, not a stale finding.** The mechanism half was right
(`xlunch_genquick` never reads `NoDisplay`), the consequence we drew was wrong: the documented stub
also omits `Icon=`, and the generator emits nothing when `[ -e "$Icon" ]` fails, so the tile does
disappear. That claim had reached three shipped files here before it was caught. The lesson is the
one already written above: **attack a finding before filing it**, and treat "I can see the mechanism"
as a long way short of "I have seen the outcome".

**And then we over-corrected, which is the second half of the same lesson.** Having established the
tile does disappear, three of our files went on to say the `NoDisplay`-only stub therefore *works*.
Upstream reached the opposite conclusion from the same mechanism and it is the better one: it works
**by accident**, because the stub happens to ship no `Icon=`, and adding one line brings the tile
back. `6ecf019` treats that as a defect — `remove-bundle.md`'s stub now sets `Hidden=true`, and
`test_desktop_entries.py` fails `NoDisplay` without `Hidden`. Our own stub always carried both keys
and was never affected; only the prose around it was wrong. Corrected at this bump in
`recipes/available/wine-desktop.yaml`, `docs/50-cookbook/wine-desktop.md` and
`docs/ARCHITECTURE.md`. Being right about a mechanism twice in a row is not the same as being right
about what follows from it.
