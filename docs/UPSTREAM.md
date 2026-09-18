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
     → work around locally, with the issue URL in a comment
     → upstream fixes → bump the submodule pin → re-evaluate → remove the workaround
```

**The tail of that is now upstream's to define, not ours.** After our first round they wrote it
down: `CONTRIBUTING.md` "What happens after you file" (triage, no PR for maintainer-side fixes,
`Closes #N`, and the `gh issue view` breakage below) and `SECURITY.md` "What happens after you
report" (reproduce, fix in the open on master, show the exploit failing, publish with the reporter
credited). Read those rather than this paragraph; what follows is only our side.

Two rules make our end of it work:

- **A local workaround carries the issue URL in a comment**, so the thing to delete when it is fixed
  is findable with `grep -rn "slax-kitchen/issues"`.
- **A pin bump is never automatic.** Every design decision in [ARCHITECTURE.md](ARCHITECTURE.md)
  reasons about specific engine behaviour, so a bump gets read as a diff before it is committed.
  `ci/checks/20-vendor-pristine.sh` fails a pointer that moved without one.

---

## Register

Thirteen issues filed 2026-09-15, in two rounds. **All closed**, re-verified at `9776a90` on
2026-09-16. Every row's closing commit is taken from that commit's own `Closes #N` trailer, not
inferred from its subject line — a self-review found row 13 crediting the wrong one and two issues
missing outright, in the document that exists to be the accurate register.

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

Neither is ours. Both were assessed against this image at the `bcd4f00` bump rather than taken on
trust, because "open upstream" is not the same as "affects us".

| # | Issue | Impact on slax-wine |
|---|---|---|
| [14](https://github.com/Fullaxx/slax-kitchen/issues/14) | `bundle.packages` tracks additions and never looks at what left | **None on this build, measured.** `20-wine.sb` is a `bundle.packages` bundle, so this is our exposure: a package apt removes to resolve a conflict is recorded as gone while its files stay visible from the lower bundle. Counted `install ok installed` in `04-apps.sb` (567) against `98-dpkg-db.sb` (626) — **nothing present before is missing after**. +59 is the `libgnutls30`-upgrade arithmetic. Re-measure after any recipe change; it is a property of the build, not of the recipe. |
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
explicit `from:` stays.

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
3. **`gh issue view` is broken on gh 2.45.0 against this repo** — it requests deprecated
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
discipline. It is the one local change in that file, marked `LOCAL CHANGE` at the import.

**`ci/checks/97-tier-c-ledger.sh`** (added in `e7f2bea`) — measured with `REPO_ROOT` pointed at this
tree, it exits 0 with *"tests/boot/tier-c.json not present"*. There is no `tests/boot/`, no ledger
and no `ci/release-notes.sh` here, so it would note-and-skip forever. Still not adopted.

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

## Filed at the `8adfca6` bump — [#22](https://github.com/Fullaxx/slax-kitchen/issues/22), the #19 fix blocks every submodule bump

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

**Fixed locally rather than worked around**, and `ci/lib.sh` is now *Adapted from* rather than
*Copied verbatim* with the one difference stated — the convention exists for this, and gate 96 §9
would otherwise refuse the file. The mode is read from the index and only `160000` takes the branch;
`0` is the honest answer for a gitlink, which is a pointer in a tree object and contributes no file
content here. Proved narrow: the submodule measures `0`, a real staged file still measures its true
size, an oversized file still trips `TOO_BIG`, and a planted `payload.exe` still trips
`FORBIDDEN_EXT`.

The suggested upstream fix is the same shape: skip mode `160000` in `file_size`, with a unit test —
there is currently none over `file_size` either.

## Filed at the `8adfca6` bump — [#20](https://github.com/Fullaxx/slax-kitchen/issues/20), the provenance guard refuses in-image paths

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

**What it costs us right now:** the shipped pair is unaffected and rebuilt clean at this pin, with
the new explicit `drop:` var recorded in the sidecar without complaint. But every boot route we run
drives `slax-wine-test-*.iso`, so re-running them has to wait on this — which is why the bump sits
on `bump/slax-kitchen-8adfca6` rather than on `master`.

## In flight upstream, noticed while filing at this bump

**[PR #21](https://github.com/Fullaxx/slax-kitchen/pull/21) `Closes #14`** — *"apt may not remove a
package, and what leaves is now counted"*, opened while this bump was being prepared. Issue 14 is in
our open-upstream register above, so this retires it, and the change has teeth for us: after it,
`bundle.packages` **refuses** rather than warns when apt would drop a package to resolve a conflict.

Nothing here triggers it today — `wine` installs sixteen packages and the build's own delta line
reports `3836 added, 105 modified` with no removals — but it is the kind of change that turns a
silent accommodation into a hard failure, which is exactly what the `#19` fix did to our submodule
(`#22` above). Worth re-reading before the next pin bump rather than discovering at build time.

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
