# `bottles` — Flatpak, and Bottles with everything it needs offline

**Status: runtime-verified** — in QEMU, with **no network device**: Bottles 67.3 opens on the Slax
desktop, `bottles-cli new` creates a bottle with the bundled runner, and in that bottle `cmd /c ver`
prints `Microsoft Windows 10.0.19045` and `notepad.exe` opens a window. Measured twice: on the first
build with DXVK/VKD3D added by hand, which is what showed they were needed, and on the shipped build
with nothing added. Slax's launcher generator emits the **Bottles** tile and no browser tile.
**Not yet verified:** a human clicking that tile, real hardware, and bottles surviving a reboot on a
persistent stick.

```sh
./build.sh --bottles        # -> out/slax-bottles-1.0.0.iso
```

**slax-bottles only.** This recipe is 64-bit and is in no slax-wine profile. Bottles exists only as
an x86_64 Flatpak, so it cannot go on slax-wine's 32-bit base
([DECISIONS.md](../DECISIONS.md) D-14).

## Two bundles

| bundle | verb | what | size |
|---|---|---|---|
| `20-flatpak.sb` | `bundle.packages` | `flatpak` from bookworm main, and its closure (36 packages, bubblewrap among them) | 8.0 MiB |
| `30-bottles.sb` | `bundle.files` | `/var/lib/flatpak` (Bottles plus 12 runtime refs), DXVK and VKD3D, the launcher, the browser mask, `/etc/slax-bottles-release` | 890.8 MiB |

`20-` is this image's platform and `30-` its application: the same split as slax-wine's
`20-wine`/`30-notepadpp` (D-5). `noload=30-bottles.sb` gives a Slax with flatpak and nothing in it,
and no tile either, because the launcher ships in the same bundle. `noload=20-flatpak.sb` is the
one that leaves a tile to click. The wrapper then says flatpak is missing, rather than failing
silently.

## How Bottles gets into the image

Not in the build chroot. `flatpak install` runs its triggers through `bwrap`, and the chroot has an
empty `/proc` and no user namespace. Instead `build.sh`:

1. installs `com.usebottles.bottles//stable` from Flathub into a **user** installation pointed at
   `recipes/available/bottles.files/var/lib/flatpak`. The layout is the same as the system
   installation, which is where the live system (all root) looks;
2. moves each of the 13 refs to the commit locked in `BOTTLES_LOCK`, and fails unless every locked
   ref is at its commit **and** nothing unlisted is installed;
3. fetches DXVK and VKD3D, checks them against `BOTTLES_COMPONENTS`, and unpacks them into Bottles'
   data directory;
4. writes `/opt/bottles/VERSION`: every ref, commit and component that shipped.

`bundle.files` then copies the tree with `copytree(symlinks=True)`, so flatpak's `active`/`current`
links survive. Hardlinks do not. The ostree repo's objects are the same inodes as the deployed
files, so the 3.2 GB stage becomes a 7.4 GB copy while the bundle is built. mksquashfs then stores
each identical file once, which is why the bundle is 890.8 MiB. [build.md](../build.md) has the disk
budget.

Measured in the guest: `flatpak list` shows all eleven visible refs at their locked commits, and
`xlunch_genquick 64 --desktop` (the generator behind the launcher) emits
`Bottles;/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/com.usebottles.bottles.svg;…`,
so the icon path resolves through flatpak's symlinks, and nothing for the masked browser. The boot
tests' testkit report finds every shipped file in the assembled union, on BIOS and on UEFI.
`bwrap` works (flatpak's first-run `ldconfig` ran inside it), and the session D-Bus Bottles wants is
already there: Slax starts one at `/run/user/0/bus`.

## Why DXVK and VKD3D ship, measured

The first build shipped the Flatpak alone. Offline, Bottles opened, but:

```
$ bottles-cli new --bottle-name offline1 --environment application --runner sys-wine-11.0
Missing essential components. Installing…
No dxvk found.
Connection status: offline …
...
Fail to install components, tried 3 times.
Bottle creation failed
```

The runner was not the problem: the Flatpak carries `sys-wine-11.0`. Bottles'
`manager.py:components_check` requires a runner, **a DXVK and a VKD3D**, and finds the last two with
`os.listdir` on `data/bottles/{dxvk,vkd3d}`. With `dxvk-3.1` and `vkd3d-proton-3.0.1` unpacked there,
the same command succeeded, and DXVK/VKD3D were linked into the new prefix. On the rebuilt image,
which ships them, a clean boot with no network did the same: `bottles-cli new` succeeded in 19½
minutes under TCG, and the fresh bottle is **386 MiB**. The final shipped build (after the
self-review fixes) was checked the same way: the tile is generated, Bottles opens from the
`slax-bottles` wrapper, `flatpak remotes` lists flathub, and a new bottle runs `cmd /c ver`. That
bottle came to **491 MiB**; the two figures are recorded as measured, not reconciled.

Both come from the URLs Bottles' own components index names, at the index commit Bottles 67.3 pins
(`bottlesdevs/components` `f63f670`): the newest *stable* entry of each. That index publishes md5
only. The sha256 values in `build.env` were taken from files whose md5 matched it.

## The launcher

`/usr/share/applications/5bottles.desktop` runs `/usr/local/bin/slax-bottles`, which checks that
flatpak and the app are there and then `exec`s `flatpak run … com.usebottles.bottles`. Two traps it
avoids, both documented in [ARCHITECTURE.md](../ARCHITECTURE.md):

- **`Icon=` is an absolute path.** Flatpak exports the Bottles icon **only** as scalable SVG, which
  `xlunch_genquick` never searches, so a bare `Icon=com.usebottles.bottles` would delete the tile.
  The path goes through `/var/lib/flatpak/exports/`, which follows the active deploy.
- **`Terminal=false`**, or `fbappselect` wraps the shell-script wrapper in an xterm.

Flatpak's own exported `.desktop` is not used. It lives under `exports/`, which xlunch never reads,
and its `Exec=` carries `@@u` field codes.

The chromium mask stub that slax-wine ships in `21-wine-desktop` ships here instead, byte for byte,
because that recipe is not in this image.

## What it proves, and what it does not

Proven, in QEMU (TCG, `-cpu Nehalem`, no network): the Flatpak runs on Slax's aufs root as root, a
bottle can be created with nothing but what is on the ISO, and a Windows GUI program runs in it.

Not proven:

- **Real hardware**, and with it any GPU path. Under emulation this is llvmpipe throughout.
- **`-cpu max`**: there Bottles segfaulted in an AVX2 gather instruction. We read that as QEMU's AVX2
  emulation under TCG rather than the image (the same image runs under `-cpu Nehalem`, and starts
  under `-cpu qemu64`, x86-64-v1), but it has not been checked on a real AVX2 CPU.
- **Persistence** of `/root/.var/app/com.usebottles.bottles` on a stick.
- **The GUI's New Bottle dialog**: the bottle was created with `bottles-cli`, which calls the same
  manager.

See [using-bottles.md](../using-bottles.md) for the user-facing side.
