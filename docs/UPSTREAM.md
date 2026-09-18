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

**`ci/checks/97-tier-c-ledger.sh`** (added in `e7f2bea`) and **`ci/checks/80-unit.sh`** — same
reasoning, both measured with `REPO_ROOT` pointed at this tree:

| gate | run against slax-wine | verdict |
|---|---|---|
| `97-tier-c-ledger.sh` | `exit 0` — *"tests/boot/tier-c.json not present"* | no `tests/boot/`, no ledger, no `ci/release-notes.sh`. It would note-and-skip forever |
| `80-unit.sh` | `exit 0`, **no output at all** | its loop is `for t in "$REPO_ROOT"/tests/unit/test_*.py; do [ -f "$t" ] || continue`. With no `tests/`, the body never runs and it does not even announce the skip — strictly worse than the other two |

What we **did** take from this range is upstream's **gate-count check**, folded into our adapted
`90-doc-coverage.sh` with a wider anchor. Four files here state that number in prose and nothing else
checked them; upstream's own anchor missed two of the four (`ci/` alone, and the noun `checks`).

## Filed at the `bcd4f00` bump — round three

Three issues, all found by self-review of **this** repo rather than of theirs, which is the right way
round. Each was read in code and demonstrated before filing; none blocks the bump.

| # | Issue | Why it is theirs |
|---|---|---|
| [17](https://github.com/Fullaxx/slax-kitchen/issues/17) | a `.desktop` whose `Icon=` does not resolve is silently deleted from the launcher | Slax's behaviour, but absent from `known-upstream-bugs.md`, and `remove-chromium.md` teaches a stub that works only because it omits `Icon=` |
| [18](https://github.com/Fullaxx/slax-kitchen/issues/18) | `tier-c.sh`: `--allow-dirty` accepts `--ledger` alone, so a dirty run can write a committed golden | `ci/tier-c.sh:46-47` clears the guard on *either* flag; the doc and the `die` message both say both |
| [19](https://github.com/Fullaxx/slax-kitchen/issues/19) | `00-no-binaries` can be walked past two ways | `file_size` fails open (`lib.sh:87`), and the extension list has no `.exe`/`.dll`/`.msi` |

**17 is the one that cost us something.** It deleted both of this image's launchers — the entire
point of `21-wine-desktop.sb` — and eleven green gates never noticed, because no gate can see a
runtime resolution failure. It was caught by a manual self-review and fixed with an absolute `Icon=`
path. `docs/ARCHITECTURE.md`'s register now carries the converse rule alongside the `NoDisplay` one.

**19 was two of our own long-standing candidates**, filed together because they share a blast radius
and because `9b1b797` finally supplied the argument: that commit fixed a fail-open in
`check_files_nl` and left the identical pattern in `file_size` forty lines below. The principle is
now accepted in that very file.

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
