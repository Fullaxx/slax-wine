# slax-wine

Slax with Wine on it: a 32-bit Debian live system that runs Windows programs, with a persistent
`C:` drive when you install it to a USB stick.

```sh
git clone --recurse-submodules https://github.com/Fullaxx/slax-wine
cd slax-wine && ./build.sh          # -> out/slax32-wine-bios-1.0.0.iso
                                    #    out/slax32-wine-uefi-1.0.0.iso
```

Needs `squashfs-tools`, `xorriso`, `curl` and a `python3` with `yaml` — and root (or `sudo`) for one
step. [docs/build.md](docs/build.md) has the full list, the hook setup, and the one `sudo` trap that
is not obvious.

## What you get

| | |
|---|---|
| Wine | **8.0~repack-4**, Debian bookworm main, 32-bit |
| a test application | Notepad++ 8.9.8 — the Windows installer, run under Wine |
| no browser | `05-chromium.sb` is removed to pay for Wine's size |
| two images | **bios** 507.3 MiB · **uefi** 513.5 MiB — same system, different boot routes |

## Which image

| | boots on | why you would pick it |
|---|---|---|
| `slax32-wine-bios-<ver>.iso` | BIOS | stock Slax bootloader, no GRUB, 6.2 MiB smaller |
| `slax32-wine-uefi-<ver>.iso` | **BIOS *and* UEFI** | adds a GRUB ESP, so the **ISO** boots on UEFI — a DVD, or a virtual CD. Changes nothing about USB sticks |

**The UEFI image is a superset, not an alternative** — it keeps the BIOS El Torito entry and adds an
EFI one, so it boots anywhere the BIOS image does. Verified on the artifacts: `xorriso
-report_el_torito` shows `isolinux.bin` in both, and `/boot/efi.img` only in the second. If in doubt,
take the UEFI one.

Neither boots on **32-bit UEFI firmware** — no `bootia32.efi` exists anywhere upstream. That is rare
(some older Atom tablets) and it is a fact about the firmware, not about this 32-bit system.

## And a third: slax-bottles

`./build.sh --bottles` builds **`slax-bottles-<ver>.iso`**, a separate image: **64-bit** Slax with
[Bottles](https://usebottles.com) 67.3 baked in, so it creates bottles and runs Windows programs
**with no network**. It is not slax-wine plus Bottles. Bottles ships only as an x86_64 Flatpak, and it
runs sandboxed with its own Wine, so it can use neither our 32-bit base nor our Debian Wine
([DECISIONS.md](docs/DECISIONS.md) D-14).

| | |
|---|---|
| base | `slax-64bit-debian-12.2.0.iso` |
| Bottles | 67.3 from Flathub, with the GNOME 50 runtime, GL, i386 compat, Wine Gecko and Mono; every ref pinned by commit |
| offline extras | DXVK 3.1 and VKD3D-Proton 3.0.1, without which Bottles will not create a bottle offline (measured) |
| no browser | `05-chromium.sb` removed, as in slax-wine |
| size | **1241.7 MiB**. It boots BIOS and UEFI, like `slax32-wine-uefi` |

Using it: **[docs/using-bottles.md](docs/using-bottles.md)**.

Installing it to a USB stick so the Wine prefix survives a reboot is **[INSTALL.md](INSTALL.md)**.
What works and what does not is **[docs/using-wine.md](docs/using-wine.md)**.

## How it is built

Six recipes over [slax-kitchen](https://github.com/Fullaxx/slax-kitchen), pinned as a submodule: four
for slax-wine, two for slax-bottles. slax-kitchen is the engine — generic, and knowing nothing about
Wine; the recipes here say *what* to change, never *how*.

| bundle | recipe |
|---|---|
| `20-wine.sb` | [`wine`](docs/50-cookbook/wine.md) — install Wine 8.0 from bookworm main |
| `21-wine-desktop.sb` | [`wine-desktop`](docs/50-cookbook/wine-desktop.md) — launcher, environment, menu cleanup |
| `30-notepadpp.sb` | [`notepadpp`](docs/50-cookbook/notepadpp.md) — the swappable application layer |
| — | [`slax-wine-iso`](docs/50-cookbook/slax-wine-iso.md) — boot defaults, ISO identity, checksum |
| — | `uefi-bootable` — **upstream's**, applied only by the uefi profile. Adds a GRUB ESP; builds no bundle |
| `20-flatpak.sb`, `30-bottles.sb` | [`bottles`](docs/50-cookbook/bottles.md) — **slax-bottles only**: flatpak, and Bottles with its runtimes, DXVK and VKD3D |
| — | [`slax-bottles-iso`](docs/50-cookbook/slax-bottles-iso.md) — **slax-bottles only**: the same boot default and checksum, its own identity |

Both images run upstream's `remove-bundle` first — it drops `05-chromium.sb`, named explicitly
rather than inherited, and it has to come before anything that builds — then the same four recipes
in the same order. The uefi one adds `uefi-bootable` after them, which is why they carry an
identical nine bundles. [`ci/checks/96-release-consistency.sh`](ci/checks/96-release-consistency.sh)
fails if the two profiles ever disagree about that core list, or if either drops the removal or
lists it late.

`30-notepadpp.sb` is meant to be replaced. Delete that one file from `/slax/modules/` on a stick and
drop another in — no rebuild, no remaster. That is the whole point of the layering.

slax-bottles has a profile of its own: `remove-bundle`, then `bottles`, `slax-bottles-iso` and
`uefi-bootable`, on the 64-bit base. Gate 96 holds it to removal-first, but not to slax-wine's core
list, because it is a different system rather than a third boot route to the same one.

## Status

**runtime-verified.** On a full desktop boot: the **Wine** tile appears in the launcher and opens
without an xterm wrapper, the Notepad++ installer runs under Wine and the installed editor launches,
there is **no** Wine Mono / Gecko download prompt, and the browser is gone from the launcher.

**UEFI and both bootloaders are now measured too** — GRUB under OVMF and isolinux each boot to
`Live Kit done`, and `automount` is confirmed gone from the kernel command line on both, against a
control that shows the check can fail.

**slax-bottles is runtime-verified in QEMU, offline:** Bottles opens when its `slax-bottles` wrapper
(the tile's `Exec=`) is run, a bottle is created from only what the image ships, and Windows programs
run in it. The tile is generated; a click on it has not been tested. BIOS, UEFI and the direct
kernel route boot to `Live Kit done`. Real hardware, and a GPU, are untested
([software.md](docs/software.md) says what that leaves open).

**What is still unverified: the USB story.** The Wine `C:` drive surviving a reboot has been seen
only on a **VM ext4 disk**, never on a stick; the FAT32 container route is untested entirely; and no
UEFI boot has gone through `bootinst`'s loader. That is the reason [INSTALL.md](INSTALL.md) exists,
and it is still the weakest-evidenced part of this project. Every page states the rung it actually
reached; the ladder is in the [cookbook index](docs/50-cookbook/README.md).

## Documentation

| you want | read |
|---|---|
| to build it | [docs/build.md](docs/build.md) |
| to put it on a stick, with persistence | [INSTALL.md](INSTALL.md) |
| to use Wine, and what is missing | [docs/using-wine.md](docs/using-wine.md) |
| to use Bottles on slax-bottles | [docs/using-bottles.md](docs/using-bottles.md) |
| what is on each ISO, and what it needs to run | [docs/software.md](docs/software.md) |
| how it all works | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| why it looks like that | [docs/DECISIONS.md](docs/DECISIONS.md) |
| how we raise engine problems upstream | [docs/UPSTREAM.md](docs/UPSTREAM.md) |
| where the 507 MiB (and slax-bottles' 1241.7 MiB) goes | [docs/sizing.md](docs/sizing.md) |
| which Slax each release is built on | [docs/base-versions.md](docs/base-versions.md) |
| what redistributing the ISO obliges | [NOTICE.md](NOTICE.md) |

## Credit

**Slax and Linux Live Kit are the work of [Tomáš Matějíček](https://github.com/Tomas-M).** This
project customizes *his*; without it there is nothing here. There is a donate link on
[slax.org](https://www.slax.org).

**Wine** is the [WineHQ project](https://www.winehq.org); **Notepad++** is
[Don Ho's](https://notepad-plus-plus.org); **Bottles** is
[the Bottles developers'](https://github.com/bottlesdevs/Bottles), redistributed as Flathub built it.
None is modified here.

MIT for this repository's own recipes, scripts and docs — see [LICENSE](LICENSE). Everything inside
a built ISO carries its own licence, and [NOTICE.md](NOTICE.md) sets out the boundary and the
obligations that come with redistributing an image.
