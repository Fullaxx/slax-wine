# Building slax-wine

`./build.sh` does the whole thing: fetch the base ISO, fetch and verify the Notepad++ installer,
unpack, apply upstream's `remove-bundle` and then our four recipes, pack, and assert the result.
This page is what has to be true *before* that works.

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
| `flatpak` | **the slax-bottles variants only.** `build.sh` installs Bottles from Flathub into a staging dir with it. Not needed for slax-wine |

On Debian/Ubuntu:

```sh
sudo apt-get install squashfs-tools xorriso curl git python3 python3-yaml python3-jsonschema \
                     shellcheck yamllint
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

The squashed bundle is small again (890.8 MiB) because mksquashfs stores identical files once. Flatpak
runs its install triggers through `bwrap`, and on a host without user namespaces (a container, for
instance) that prints `bwrap: Creating new namespace failed`. That is harmless: the triggers only
rebuild caches under `exports/` that Slax never reads, and `build.sh` checks what matters, the
deployed commits.

## Running it

```sh
git clone --recurse-submodules https://github.com/Fullaxx/slax-wine
cd slax-wine
./build.sh                  # -> out/slax-wine-bios-1.0.0.iso
                            #    out/slax-wine-uefi-1.0.0.iso
```

slax-bottles is a separate image on the 64-bit base (see [DECISIONS.md](DECISIONS.md) D-14), so it
is not part of the default:

```sh
./build.sh --bottles        # -> out/slax-bottles-1.0.0.iso
./build.sh --all            # all three shipped images
```

Each variant is a full unpack + apply into its own `work/<variant>/`, because recipes are not
idempotent — `apply` consults its journal and refuses a second application. So `--both` costs
roughly twice the wall clock; use `--bios` while iterating.

| flag | effect |
|---|---|
| `--bios` / `--uefi` / `--both` | which image(s). **`--both` is the default** — they are the release pair |
| `--test` | build `slax-wine-test-<ver>.iso` instead: the same recipes plus `serial-console`, `testkit` and `uefi-bootable`, so both firmware paths can be driven from one image. Not shipped, not part of `--both`; it is what `kitchen test --persistence` is run against. |
| `--bottles` | build `slax-bottles-<ver>.iso`: 64-bit Slax with Bottles baked in, and no Debian Wine. Uses the 64-bit base and its own module list and size ceiling (`BOTTLES_*` in `build.env`) |
| `--bottles-test` | its testkit image, `slax-bottles-test-<ver>.iso`: the counterpart of `--test` |
| `--all` | bios, uefi and bottles: every shipped image |
| `BOTTLES_RELOCK=1` | with an empty `recipes/available/bottles.files/`: install Flathub's **current** Bottles and print a fresh `BOTTLES_LOCK` to paste into `build.env`. How the pin is bumped |
| `--keep-work` | leave `work/<variant>/` in place for inspection |
| `--no-fetch` | skip *downloading* the base ISO (it is still verified). The application payload is fetched regardless if it is missing or its hash does not match |
| `ISO_DIR=…` | reuse base ISOs you already have |

`build.sh` `cd`s to the repo root before doing anything, so it is safe to invoke by absolute path.
That is not cosmetic: the profile names its recipes by relative path, and the engine resolves those
against the **current working directory**, not the repo root.

## Commit gates

Twelve checks live in `ci/checks/`. They are not installed automatically — `.git/hooks/` is local to
each clone and is not tracked — so **after cloning, do this once**:

```sh
ln -sf ../../ci/hooks/pre-commit .git/hooks/pre-commit
ln -sf ../../ci/hooks/pre-push   .git/hooks/pre-push
```

Run them by hand any time:

```sh
./ci/run-checks.sh ci        # every gate, whole tree
./ci/run-checks.sh pre-commit
```

> **Do not use `kitchen doctor --install-hooks` for this repo.** It derives its repo root from the
> `kitchen` script's own location, which here is `vendor/slax-kitchen` — a submodule, whose `.git`
> is a *file*, not a directory. It fails with `error: not a git repo`. The two `ln -sf` lines above
> are the supported way.

Six gates are copied verbatim from slax-kitchen, four are adapted, and
`96-release-consistency.sh` is ours. Each copied file's header names the upstream commit it came
from, and gate 96 fails if that commit is not the current submodule pin — so a pin bump that forgets
to re-copy (or to re-cite) cannot pass silently.

**`TBD-MEASURED`** is this repo's placeholder for a number not yet measured. Write that exact
string, nothing else: gate 96 refuses a tagged release that still contains it, and it is deliberately
ugly so it cannot be mistaken for a value.

## What the build asserts

Failing any of these fails the build:

- the base ISO's size and sha256 match `build.env`, which in turn matches the pinned
  `compat/sources.yaml`
- the payload's sha256 matches `APP_SHA256`, or for slax-bottles, every Flatpak ref is deployed at
  its `BOTTLES_LOCK` commit and nothing unlisted is installed
- **each** ISO's volume id is what its recipe set (`SLAX-WINE`, or `SLAX-BOTTLES`), and each is under
  its ceiling (`MAX_ISO_MIB`, or `BOTTLES_MAX_ISO_MIB`)
- `/slax/modules/` contains **exactly** nine bundles — five stock survivors, our three, and the
  generated `98-dpkg-db.sb`. The same list for both variants, because `uefi-bootable` builds no
  bundle. slax-bottles has **eight**: the same five, `20-flatpak`, `30-bottles` and the db
- the uefi ISO has an EFI El Torito entry (`--expect-uefi`) and the bios ISO does not

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

The engine is pinned at [`337f7e7`](https://github.com/Fullaxx/slax-kitchen/tree/337f7e7). Bumping the
pin is never automatic — see [UPSTREAM.md](UPSTREAM.md).
