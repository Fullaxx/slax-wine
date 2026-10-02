# Building slax-wine

`./build.sh` does the whole thing: fetch the base ISOs, fetch and verify the Notepad++ installers,
unpack, apply upstream's `remove-bundle` and then our recipes, pack, and assert the result — for
each of the four slax-wine images, bios and uefi on each base. For slax-bottles (`--bottles`) the
same steps run on the 64-bit base, and the payload is the Bottles Flatpak installation plus
DXVK/VKD3D, each pinned in `build.env`. This page is what has to be true *before* any of it works.

## Prerequisites

The engine reports on itself, and that is the authoritative answer:

```sh
vendor/slax-kitchen/kitchen doctor
```

Everything it lists as `ok` is needed by *some* recipe. What **this** project's build path actually
touches is narrower:

| | |
|---|---|
| `squashfs-tools` | `mksquashfs` / `unsquashfs` — building and reading `.sb` bundles |
| `xorriso` | rebuilding the ISO, and the module-list assertion in `build.sh` |
| `curl` | fetching the base ISO and the application payload |
| `coreutils` | `sha256sum`, `stat`, `cut` — every verification step |
| `git` | the submodule, and the provenance/tag checks in gate 96 |
| `python3` ≥ 3.9 with `yaml` and `jsonschema` | the recipe engine itself |
| `shellcheck`, `yamllint` | the commit gates only — not the build |
| a `python3` that can `import pyflakes` | the commit gates only — gate 35 lints every python file here. Stated as an **import**, not a package: apt's `python3-pyflakes` is invisible to a `python3` that resolves into a virtualenv, and on ubuntu:24.04 that package ships the module while the `pyflakes` *binary* comes from another one. The gate runs `python3 -m pyflakes`, which is true either way. Without it the gate warns and stands down, so a clone that skips this loses the check rather than failing |
| `qemu-system-x86`, `ovmf` | the **boot tests** only (`kitchen test`), not the build — and not even those if they run on a boot host, which needs `ssh`, `rsync` and `git` here instead |
| `flatpak` | **the slax-bottles variants only.** `build.sh` installs Bottles from Flathub into a staging dir with it. Not needed for slax-wine |

On Debian/Ubuntu:

```sh
sudo apt-get install squashfs-tools xorriso curl git python3 python3-yaml python3-jsonschema \
                     shellcheck yamllint python3-pyflakes
sudo apt-get install flatpak      # only for --bottles / --bottles-test / --all
```

### Privilege

Only **step 4, apply**, is elevated — `bundle.packages` needs a real chroot (`CAP_SYS_CHROOT` +
`CAP_MKNOD`). Unpack, pack and every assertion run unprivileged. If you are not root, `build.sh`
wraps that one step in `sudo -E`.

> **The trap that is not obvious.** sudoers sets `secure_path`, and that overrides `PATH` **even
> with `-E`**. So the `python3` the elevated step runs is the one on *sudo's* path — typically
> `/usr/bin/python3` — not whichever one is first on yours. A virtualenv with `yaml` installed does
> **not** help here. The real requirement is: *a `python3` on sudo's `secure_path` that can import
> `yaml` and `jsonschema`.* Check it directly:
>
> ```sh
> sudo python3 -c 'import yaml, jsonschema; print("ok")'
> ```

### Architecture

The host must be able to run **i386** binaries, because `bundle.packages` runs `apt` and `dpkg`
inside a 32-bit chroot. On x86-64 that is normally already true; on any other architecture it is not,
and no amount of `qemu-user` configuration is tested here. slax-bottles' chroot is x86-64, so an
x86-64 host covers both.

### Network

Every build needs the network during **apply**, whatever `--no-fetch` says, which covers only the
base ISOs:

- `wine` and `bottles` install packages with apt from Debian's archive, inside the chroot;
- `firmware-refresh` installs Debian's firmware packages the same way, and fetches 65 files from
  linux-firmware at a pinned tag, each checked against its sha256. It tries GitLab, then
  git.kernel.org, and a file neither serves fails the build rather than shipping a partial set.

The Bottles staging step also needs **network access to Flathub**, and much more disk than its
bundle suggests. **Budget [this much free](measurements.md#disk-bottles-build)** for a `--bottles` build,
measured piece by piece:

| | |
|---|---|
| `recipes/available/bottles.files/` | [`disk-stage`](measurements.md#disk-stage), DXVK/VKD3D included. The ostree repo and the deployed files share inodes |
| the copy `bundle.files` makes under `work/` while it builds `30-bottles.sb` | [`disk-work-copy`](measurements.md#disk-work-copy): about the stage's own size, since slax-kitchen `f5e6673` (#64) keeps the stage's hardlinks in the copy; counted per name, which is what the copy cost before, more than twice that. It is removed when the bundle is done |
| `work/bottles/` | [`disk-work-bottles`](measurements.md#disk-work-bottles): the unpacked base, plus the bundle |
| `out/slax-bottles-<ver>.iso` | [`iso-slax-bottles`](measurements.md#iso-slax-bottles) |

The squashed bundle is small again ([`lbt-bottles`](measurements.md#lbt-bottles)) because mksquashfs stores
identical files once.
Flatpak runs its install triggers through `bwrap`, and on a host without user namespaces (a
container, for instance) that prints `bwrap: Creating new namespace failed`. That is harmless: the
triggers only rebuild caches under `exports/` that Slax never reads, and `build.sh` checks what
matters: the languages deployed, and the version and commits it records. Each `./build.sh --bottles`
asks Flathub whether anything in the stage has a newer commit, and if so installs the stage again
from nothing ([the download](measurements.md#restage-download)), because updating in place would keep the old commit's objects
and ship them ([D-20](DECISIONS.md#d-20--let-bottles-and-its-runtimes-float-record-what-shipped)).
`--no-fetch` keeps the stage as it is.

## Running it

```sh
git clone --recurse-submodules https://github.com/Fullaxx/slax-wine
cd slax-wine
./build.sh                  # -> out/slax32-wine-bios-1.0.0.iso
                            #    out/slax32-wine-uefi-1.0.0.iso
                            #    out/slax64-wine-bios-1.0.0.iso
                            #    out/slax64-wine-uefi-1.0.0.iso
```

slax-bottles is a separate image on the 64-bit base (see [DECISIONS.md](DECISIONS.md) D-14), so it
is not part of the default:

```sh
./build.sh --bottles        # -> out/slax-bottles-1.0.0.iso
./build.sh --all            # every shipped image: the four slax-wine ones and slax-bottles
```

Each image is a full unpack + apply into its own `work/<variant>/`, because recipes are not
idempotent — `apply` consults its journal and refuses a second application. So the default runs
four full builds; narrow it while iterating: `./build.sh --32 --bios`.

| flag | effect |
|---|---|
| `--32` / `--64` | which base. **Both are the default** |
| `--bios` / `--uefi` / `--both` | which image(s) on each chosen base. **`--both` is the default** |
| `--test` | build the test image of each chosen base instead, `slax32-wine-test-<ver>.iso` and `slax64-wine-test-<ver>.iso`: the uefi recipes plus `serial-console` and `testkit`, so both firmware paths can be driven from one image. Not shipped; it is what `kitchen test` and `--persistence` are run against |
| `--bottles` | build `slax-bottles-<ver>.iso`: 64-bit Slax with Bottles baked in, and no Debian Wine. Uses the 64-bit base and its own module list and size ceiling (`BOTTLES_*` in `build.env`) |
| `--bottles-test` | its testkit image, `slax-bottles-test-<ver>.iso`: the counterpart of `--test` |
| `--all` | the four slax-wine images and slax-bottles: every shipped image |
| `BOTTLES_RELOCK=1` | with an empty `recipes/available/bottles.files/`: install Flathub's **current** Bottles and print its refs as a `BOTTLES_LOCK`, for pinned mode |
| `BOTTLES_LOCK` in `build.env` | **empty for a release.** Set, it forces every Flatpak ref to a named commit and refuses a stage that differs either way, a stopgap for when a Flathub update breaks something, as long as Flathub still serves those commits; a commit it has pruned fails the build ([D-20](DECISIONS.md#d-20--let-bottles-and-its-runtimes-float-record-what-shipped)) |
| `--keep-work` | leave `work/<variant>/` in place for inspection |
| `--no-fetch` | skip *downloading* the base ISOs (they are still verified). The application payloads are fetched regardless if one is missing or its hash does not match; a `--32` build never fetches the 64-bit Notepad++ |
| `ISO_DIR=…` | reuse base ISOs you already have |

`build.sh` `cd`s to the repo root before doing anything, so it is safe to invoke by absolute path.
That is not cosmetic: the profile names its recipes by relative path, and the engine resolves those
against the **current working directory**, not the repo root — which slax-kitchen's
[LAYERING.md](https://github.com/Fullaxx/slax-kitchen/blob/1d7ef68/LAYERING.md) makes the rule for
every project: build from its root.

## Commit gates

Twelve checks live in `ci/checks/`. They are not installed automatically — `.git/hooks/` is local to
each clone and is not tracked — so **after cloning, do this once**:

```sh
ln -sf ../../ci/hooks/pre-commit .git/hooks/pre-commit
ln -sf ../../ci/hooks/pre-push   .git/hooks/pre-push
```

Boot tests are separate from both, and they do not have to run on this machine: if a
`boot-host.ini` at this repository's root names one, every `kitchen test` is carried there over ssh
and booted with KVM, which is how the timings in the cookbook were taken. The vendored engine reads
it there before its own checkout. The file is gitignored and refused by `10-no-dnc.sh` if it is
ever staged, because it names somebody's machine; the template is
`vendor/slax-kitchen/boot-host.example.ini`, `kitchen boot-host check` says whether it works, and
`KITCHEN_BOOT_HOST=local` boots here instead. A configured host that cannot be reached **fails the
command** rather than quietly falling back.

Run them by hand any time:

```sh
./ci/run-checks.sh ci        # every gate, whole tree
./ci/run-checks.sh pre-commit
```

`vendor/slax-kitchen/kitchen doctor --install-hooks` makes the same two links. It links a
vendoring project's `ci/hooks/` into that project's repository since slax-kitchen `49a465f` (#66),
and refuses where `core.hooksPath` is set. Before that it looked only at the submodule, and failed
with `not a git repo`.

Six gates are copied verbatim from slax-kitchen, five are adapted, and
`96-release-consistency.sh` is ours. Two helpers they call, `ci/md-links.py` and `ci/unit-run.py`,
are copied verbatim as well, and so is `ci/yamllint.yaml`. The two hooks in `ci/hooks/` are adapted,
because this repository installs them with the `ln -sf` lines above. Each copied file's header names
the upstream commit it came from, and gate 96 fails if that commit is not the current submodule
pin — so a pin bump that forgets to re-copy (or to re-cite) cannot pass silently.

**Measured numbers live in [measurements.md](measurements.md)** and nowhere else; other pages link
to its rows. `TBD-MEASURED` is the placeholder for a number not yet measured, and it is written only
there, bare, in a row's value column. On a tagged commit gate 96 §6 scans that page, and only that
page, and refuses the tag while a bare one remains. It is deliberately ugly so it cannot be mistaken
for a value. Quoted in backticks, as it is here, it is a mention of the marker rather than a
placeholder, and the gate skips it.

## What the build asserts

Failing any of these fails the build:

- the base ISO's size and sha256 match `build.env`, which in turn matches the pinned
  `compat/sources.yaml`
- the profile's `base:` is the ISO that was unpacked, all three parts. `kitchen apply --profile`
  holds the tree to the profile's flavour and arch since
  [slax-kitchen#29](https://github.com/Fullaxx/slax-kitchen/issues/29) was fixed, and deliberately
  not to its version, which here is not free — so `build.sh` still compares all three
- each Notepad++ installer's sha256 matches `APP32_SHA256` or `APP64_SHA256`, or for slax-bottles,
  the Flatpak stage holds Bottles, with the languages `BOTTLES_LANGUAGES` names, and nothing older
  than Flathub serves (and, with `BOTTLES_LOCK` set, every ref at its commit and nothing unlisted);
  its version is recorded, not required
- **each** ISO's volume id is what its recipe set (`SLAX32-WINE`, `SLAX64-WINE`, or `SLAX-BOTTLES`),
  and each is under its ceiling (`WINE32_MAX_ISO_MIB`, `WINE64_MAX_ISO_MIB`, or `BOTTLES_MAX_ISO_MIB`)
- each ISO's `.sha256` is there and matches, and `kitchen pack` wrote its `.provenance.json`: the two
  things a project built on the image pins and reads ([building-on-slax-wine.md](building-on-slax-wine.md))
- `/slax/modules/` contains **exactly** the expected bundles — on 32-bit, eleven: five stock
  survivors, `firmware-refresh`'s two, our three, and the generated `98-dpkg-db.sb`; on 64-bit the
  same plus `31-notepadpp64.sb`. A base's bios, uefi and test images share their list, because
  `uefi-bootable` builds no bundle. slax-bottles has **ten**: the same five, the two firmware
  bundles, `20-flatpak`, `30-bottles` and the db
- a uefi ISO has an EFI El Torito entry (`--expect-uefi`) and a bios ISO does not
- the image's own `/etc/slax-*-release`, read back from its bundle, names the base it was built on
- on 64-bit, the image's package database lists `wine64:amd64`, `wine32:i386` and `libwine` for both
  architectures — `wine32` is only a Recommends of `wine64`, so this is what stands between a 64-bit
  image and one that silently runs no 32-bit Windows program

Beside each ISO the build writes `out/<image>-<ver>.packages.tsv`, every installed Debian package
with its version, read from the image's own `98-dpkg-db.sb`; for slax-bottles also
`out/slax-bottles-<ver>.flatpak.txt`, the Flatpak refs and components that shipped.
[software.md](software.md) points at them instead of carrying the lists.

`out/build-summary-<variant>.txt` records each image's sizes and package count, one file per
variant: the numbers the `summary` rows of [measurements.md](measurements.md) name.
`./ci/measure-check.sh out/` compares those rows with the summaries and reports what moved.

## What it does not do

Building is not testing. The build reaches `boot-verified`; `runtime-verified` needs a human at a
screen. See the [cookbook index](50-cookbook/README.md) for the ladder, and
[INSTALL.md](../INSTALL.md) for getting the image onto hardware.

There is **no CI on pushes or pull requests.** The one workflow, `.github/workflows/release.yml`,
runs when a version tag is pushed ([Cutting a release](#cutting-a-release)). It runs every gate
again, but only at release time, and some gate messages speak of CI re-running them as if every push
went through it. Between releases the hooks above are the only thing enforcing any of this, which is
why installing them matters.

## Cutting a release

A release is what the projects built on slax-wine pin
([building-on-slax-wine.md](building-on-slax-wine.md)), so it carries each image's checksum and
provenance sidecar as well as the image.

**A pushed tag builds it, into a draft a person publishes.** `.github/workflows/release.yml` builds
every image from the tagged commit on GitHub's hosted runners, boots the test images, and uploads
the assets to a **draft** release. Nothing publishes it but a person
([D-19](DECISIONS.md#d-19--release-from-a-tag-by-actions-into-a-draft)).

**It follows slax-kitchen's own procedure,**
[publishing-images.md](https://github.com/Fullaxx/slax-kitchen/blob/1d7ef68/docs/40-workflow/publishing-images.md),
under the pointer policy in [NOTICE.md](../NOTICE.md) and
[D-12](DECISIONS.md#d-12--publish-the-isos-with-pointers-to-their-source): no source is attached,
and each image's `SOURCES.md` says where each part's source is published. Nothing in the procedure
refuses an image since slax-kitchen `bd899fd` (#61) and `18bedc5` (#62). Until the `4a10303` bump it
refused these, on the Notepad++ installers and by its code on stock Slax's firmware and on more than
one image per release
([the record](UPSTREAM.md#measured-at-7664625-a-project-built-on-our-images-and-kitchen-sources-on-them)).

In this order:

1. **Date `[VERSION]` in `CHANGELOG.md`, and commit that first,** so every image's sidecar names the
   commit that gets tagged. The workflow refuses a tag whose entry is undated.
2. **Run `./ci/run-checks.sh ci`** on that commit: every gate, in tree scope.
3. **Optionally, boot the test images under KVM on the boot host**
   ([above](#commit-gates)). The workflow boots them too, but only under KVM if its runner happens
   to offer it, and otherwise under TCG:

   ```sh
   . ./build.env
   ./build.sh --test && ./build.sh --bottles-test
   for t in slax32-wine-test slax64-wine-test slax-bottles-test; do
       ./ci/release-boot.sh out/$t-$VERSION.iso || break
   done
   ./ci/measure-check.sh out/
   ```

   `measure-check` is a report, not a gate: it compares the `summary` rows of
   [measurements.md](measurements.md) with the build summaries in `out/`, which hold whatever was
   built, so run it after `./build.sh --all` as well to cover the shipped images. A rebuild moves a
   bundle by a 4 KiB squashfs block now and then, and slax-bottles follows Flathub
   ([why](measurements.md#why-a-rebuild-moves-bytes)), so read the differences and update a row
   only where it really moved.

4. **Tag it and push both:** `git tag v$VERSION`, then `git push origin master v$VERSION`. Gate 96
   §6 fails a tag that is not the version, and a [measurements.md](measurements.md) that still has a
   bare `TBD-MEASURED`. The tag push
   starts the workflow.
5. **The workflow.** How long it takes is [`release-run`](measurements.md#release-run).
   - `guard` runs `ci/release-guard.sh`: the tag is `v$VERSION`, the entry is dated, and the commit
     is on `origin/master`. It then creates the draft.
   - `gates` runs every gate.
   - Three `build` jobs, one per base, build that base's shipped images and its test image. Each
     boots the test image through `ci/release-boot.sh`: `--kernel`, `--bios`, `--uefi` and
     `--persistence`, each to `Live Kit done`, with `automount` absent on the two bootloader routes.
     `ci/release-stage.sh` then writes each shipped image's sources files, with the engine's one
     command per image (`kitchen sources <iso> --markdown … --json …`), and the job uploads them to
     the draft. The serial logs are kept as the run's `boot-evidence-*` artifacts.
   - `finish` writes `SHA256SUMS` with `ci/release-sums.sh`, and the notes with
     `ci/release-notes.sh`. It fails unless the draft holds exactly the assets below.
6. **Read the draft:** the notes, the assets, and the run's boot evidence. `gh release download
   v$VERSION -D <dir>`, then `sha256sum -c SHA256SUMS` in `<dir>`, checks what was uploaded.
7. **Publish it:** its **Publish** button, or `gh release edit v$VERSION --draft=false`. That is a
   person's step; nothing here publishes.

**The assets.** For each shipped image, `slax32-wine-bios`, `slax32-wine-uefi`, `slax64-wine-bios`,
`slax64-wine-uefi` and `slax-bottles`, a release carries six files:
- its `.iso`, `.iso.sha256` and `.iso.provenance.json`;
- its `.packages.tsv`;
- its `.SOURCES.md` and `.sources.json`.

It also carries slax-bottles' `.flatpak.txt`, and one `SHA256SUMS` over the other 31, so 32 files
in all. `ci/release-lib.sh` holds the list, and `tests/unit/test_release.py` holds this paragraph
to it.

The sidecar is what tells a project built on an image what it applied, and its `SOURCES.md` is what
that project's own report points back to. The test images are never published.

**GitHub's limits,** and where the release stands against them:

| limit | where it stands |
|---|---|
| **each asset under 2 GiB** ([`cap-github`](measurements.md#cap-github)) | The largest image is [slax-bottles](measurements.md#iso-slax-bottles), and `BOTTLES_MAX_ISO_MIB` stops it long before. `ci/release-stage.sh` and `ci/release-sums.sh` refuse anything larger anyway. |
| total release size, download bandwidth | no limit |
| runner disk | GitHub promises less than a slax-bottles build needs ([`disk-bottles-build`](measurements.md#disk-bottles-build)). Measured in the first rehearsal: [`runner-disk`](measurements.md#runner-disk), once the build job had removed the runner's preinstalled SDKs, which it still does first. |
| KVM | Not promised, but the runners had it in the first rehearsal, and the 64-bit jobs boot under it. The 32-bit job boots under TCG by choice: under the runner's KVM its guest stopped after `Live Kit init` on all four routes, cause not established, while it boots under KVM on the boot host. Under TCG a runner's boot is [several times slower](measurements.md#boot-runner-tcg) than [under its KVM](measurements.md#boot-runner-kvm), with the UEFI keys spelled out (`--tcg-keys`; [UPSTREAM.md](UPSTREAM.md#measured-and-deliberately-not-filed-the-uefi-keystroke-lead-under-tcg)). |

**If a run fails,** the draft stays incomplete: it has no `SHA256SUMS`, and its notes say it is
being built. Fix the cause, and use **Re-run failed jobs**: every upload replaces the asset of the
same name. Alternatively, delete the draft and the tag and push the tag again. A published release
is never touched: `guard` refuses one.

### Rehearsing

A tag push happens once, so the path is exercised first with a dispatch:

```sh
gh workflow run release.yml --ref <branch> -f tag=v$VERSION
```

GitHub dispatches only a workflow whose file is already on the default branch. After that,
`--ref` runs the branch's copy of it, so a change to the workflow can be rehearsed before it is
merged. The file's first arrival has to be merged first. That is harmless: nothing but a tag or a
dispatch starts it.

This runs every job for real, into a draft named `v$VERSION-rehearsal.<run>`. The draft creates no
tag, because a draft's tag only exists once it is published, and a rehearsal is never published.
The guard allows an undated entry and a commit not yet on `master`, and says so. Delete the draft
afterwards with `gh release delete v$VERSION-rehearsal.<run> --yes`.

### By hand

Every step is a script, so a release can be staged without Actions:
- `./build.sh --all`;
- `ci/release-boot.sh` on each test image;
- `ci/release-stage.sh out out/release/$VERSION <image>...`;
- `ci/release-sums.sh out/release/$VERSION`;
- `ci/release-notes.sh v$VERSION out/release/$VERSION`.

Then `gh release create v$VERSION --draft --notes-file …` and upload, which puts
[the whole release](measurements.md#release-assets) through your own connection.

## Upstream

The engine is pinned at [`1d7ef68`](https://github.com/Fullaxx/slax-kitchen/tree/1d7ef68). Bumping the
pin is never automatic — see [UPSTREAM.md](UPSTREAM.md).
