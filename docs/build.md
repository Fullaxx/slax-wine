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

The Bottles staging step needs **network access to Flathub**, and much more disk than its bundle
suggests. **Budget about 14 GB free** for a `--bottles` build, measured piece by piece:

| | |
|---|---|
| `recipes/available/bottles.files/` | **3.2 GB**, plus 79 MB of DXVK/VKD3D. The ostree repo and the deployed files share inodes |
| the copy `bundle.files` makes under `work/` while it builds `30-bottles.sb` | **7.4 GB**. `copytree` does not preserve hardlinks, so every shared file is written twice. It is removed when the bundle is done |
| `work/bottles/` | 0.4 GB unpacked base, plus the 0.9 GB bundle |
| `out/slax-bottles-<ver>.iso` | 1.2 GB |

The squashed bundle is small again (889.5 MiB) because mksquashfs stores identical files once. Flatpak
runs its install triggers through `bwrap`, and on a host without user namespaces (a container, for
instance) that prints `bwrap: Creating new namespace failed`. That is harmless: the triggers only
rebuild caches under `exports/` that Slax never reads, and `build.sh` checks what matters, the
deployed commits.

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
| `BOTTLES_RELOCK=1` | with an empty `recipes/available/bottles.files/`: install Flathub's **current** Bottles and print a fresh `BOTTLES_LOCK` to paste into `build.env`. How the pin is bumped |
| `--keep-work` | leave `work/<variant>/` in place for inspection |
| `--no-fetch` | skip *downloading* the base ISOs (they are still verified). The application payloads are fetched regardless if one is missing or its hash does not match; a `--32` build never fetches the 64-bit Notepad++ |
| `ISO_DIR=…` | reuse base ISOs you already have |

`build.sh` `cd`s to the repo root before doing anything, so it is safe to invoke by absolute path.
That is not cosmetic: the profile names its recipes by relative path, and the engine resolves those
against the **current working directory**, not the repo root.

## Commit gates

Thirteen checks live in `ci/checks/`. They are not installed automatically — `.git/hooks/` is local to
each clone and is not tracked — so **after cloning, do this once**:

```sh
ln -sf ../../ci/hooks/pre-commit .git/hooks/pre-commit
ln -sf ../../ci/hooks/pre-push   .git/hooks/pre-push
```

Boot tests are separate from both, and they do not have to run on this machine: if
`vendor/slax-kitchen/boot-host.ini` names one, every `kitchen test` is carried there over ssh and
booted with KVM, which is how the timings in the cookbook were taken. The file is gitignored and
refused by `10-no-dnc.sh` if it is ever staged, because it names somebody's machine; the template
is `vendor/slax-kitchen/boot-host.example.ini`, `kitchen boot-host check` says whether it works, and
`KITCHEN_BOOT_HOST=local` boots here instead. A configured host that cannot be reached **fails the
command** rather than quietly falling back.

Run them by hand any time:

```sh
./ci/run-checks.sh ci        # every gate, whole tree
./ci/run-checks.sh pre-commit
```

> **Do not use `kitchen doctor --install-hooks` for this repo.** It derives its repo root from the
> `kitchen` script's own location, which here is `vendor/slax-kitchen` — a submodule, whose `.git`
> is a *file*, not a directory. It fails with `error: not a git repo`. The two `ln -sf` lines above
> are the supported way.

Seven gates are copied verbatim from slax-kitchen, five are adapted, and
`96-release-consistency.sh` is ours. Two helpers they call, `ci/md-links.py` and `ci/unit-run.py`,
are copied verbatim as well. Each copied file's header names the upstream commit it came
from, and gate 96 fails if that commit is not the current submodule pin — so a pin bump that forgets
to re-copy (or to re-cite) cannot pass silently.

**`TBD-MEASURED`** is this repo's placeholder for a number not yet measured. Write that exact
string, nothing else: gate 96 refuses a tagged release that still contains it, and it is deliberately
ugly so it cannot be mistaken for a value.

## What the build asserts

Failing any of these fails the build:

- the base ISO's size and sha256 match `build.env`, which in turn matches the pinned
  `compat/sources.yaml`
- the profile's `base:` is the ISO that was unpacked — `kitchen apply --profile` does not check that
  itself ([slax-kitchen#29](https://github.com/Fullaxx/slax-kitchen/issues/29))
- each Notepad++ installer's sha256 matches `APP32_SHA256` or `APP64_SHA256`, or for slax-bottles,
  every Flatpak ref is deployed at its `BOTTLES_LOCK` commit and nothing unlisted is installed
- **each** ISO's volume id is what its recipe set (`SLAX32-WINE`, `SLAX64-WINE`, or `SLAX-BOTTLES`),
  and each is under its ceiling (`WINE32_MAX_ISO_MIB`, `WINE64_MAX_ISO_MIB`, or `BOTTLES_MAX_ISO_MIB`)
- `/slax/modules/` contains **exactly** the expected bundles — on 32-bit, nine: five stock
  survivors, our three, and the generated `98-dpkg-db.sb`; on 64-bit the same plus
  `31-notepadpp64.sb`. A base's bios, uefi and test images share their list, because `uefi-bootable`
  builds no bundle. slax-bottles has **eight**: the same five, `20-flatpak`, `30-bottles` and the db
- a uefi ISO has an EFI El Torito entry (`--expect-uefi`) and a bios ISO does not
- the image's own `/etc/slax-*-release`, read back from its bundle, names the base it was built on
- on 64-bit, the image's package database lists `wine64:amd64`, `wine32:i386` and `libwine` for both
  architectures — `wine32` is only a Recommends of `wine64`, so this is what stands between a 64-bit
  image and one that silently runs no 32-bit Windows program

Beside each ISO the build writes `out/<image>-<ver>.packages.tsv`, every installed Debian package
with its version, read from the image's own `98-dpkg-db.sb`; for slax-bottles also
`out/slax-bottles-<ver>.flatpak.txt`, the Flatpak refs and components that shipped.
[software.md](software.md) points at them instead of carrying the lists.

`out/build-summary-<variant>.txt` records every number the docs quote, one file per variant. If one
moves, something changed.

## What it does not do

Building is not testing. The build reaches `boot-verified`; `runtime-verified` needs a human at a
screen. See the [cookbook index](50-cookbook/README.md) for the ladder, and
[INSTALL.md](../INSTALL.md) for getting the image onto hardware.

There is **no CI yet** — deliberately deferred until the image has been tested on real hardware. Some
gate messages mention CI re-running them; that is aspirational until `.github/workflows/` exists.
Until then the hooks above are the only thing enforcing any of this, which is why installing them
matters.

## Upstream

The engine is pinned at [`b20e07e`](https://github.com/Fullaxx/slax-kitchen/tree/b20e07e). Bumping the
pin is never automatic — see [UPSTREAM.md](UPSTREAM.md).
