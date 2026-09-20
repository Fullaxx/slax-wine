# slax-wine

Slax with Wine on it: a Debian live system, 32-bit or 64-bit, that runs Windows programs, with a
persistent `C:` drive when you install it to a USB stick.

```sh
git clone --recurse-submodules https://github.com/Fullaxx/slax-wine
cd slax-wine && ./build.sh          # -> out/slax32-wine-bios-1.0.0.iso
                                    #    out/slax32-wine-uefi-1.0.0.iso
                                    #    out/slax64-wine-bios-1.0.0.iso
                                    #    out/slax64-wine-uefi-1.0.0.iso
```

Needs `squashfs-tools`, `xorriso`, `curl` and a `python3` with `yaml` — and root (or `sudo`) for one
step. [docs/build.md](docs/build.md) has the full list, the hook setup, and the one `sudo` trap that
is not obvious.

## What you get

| | |
|---|---|
| Wine | **8.0~repack-4**, Debian bookworm main: 32-bit on slax32-wine; both halves, `wine64` and `wine32`, on slax64-wine |
| a test application | Notepad++ 8.9.8 — the Windows installer, run under Wine: the 32-bit build on every image, and the 64-bit build too on slax64-wine |
| no browser | `05-chromium.sb` is removed to pay for Wine's size |
| four images | bios and uefi on each base — the same system on all four ([DECISIONS.md](docs/DECISIONS.md) D-16) |

## The four images

| | base | boots on | size | |
|---|---|---|---|---|
| `slax32-wine-bios-<ver>.iso` | 32-bit | BIOS | 507.3 MiB | stock Slax bootloader, no GRUB |
| `slax32-wine-uefi-<ver>.iso` | 32-bit | **BIOS *and* UEFI** | 513.5 MiB | adds a GRUB ESP, so the **ISO** boots on UEFI — a DVD, or a virtual CD. Changes nothing about USB sticks |
| `slax64-wine-bios-<ver>.iso` | 64-bit | BIOS | 815.6 MiB | stock Slax bootloader, no GRUB |
| `slax64-wine-uefi-<ver>.iso` | 64-bit | **BIOS *and* UEFI** | 821.7 MiB | adds a GRUB ESP, as above |

**A uefi image is a superset, not an alternative** — it keeps the BIOS El Torito entry and adds an EFI
one, so it boots anywhere its bios twin does. Verified on the artifacts: `xorriso -report_el_torito`
shows `isolinux.bin` in all four, and `/boot/efi.img` only in the uefi ones.

**The 64-bit images run 32-bit *and* 64-bit Windows programs**; the 32-bit ones run 32-bit programs
only. Running one program on both bases, and what else differs between them, is
[docs/testing-on-both.md](docs/testing-on-both.md).

None boots on **32-bit UEFI firmware** — no `bootia32.efi` exists anywhere upstream. That is rare
(some older Atom tablets), and a fact about the firmware.

## And slax-bottles

`./build.sh --bottles` builds **`slax-bottles-<ver>.iso`**, a separate image: **64-bit** Slax with
[Bottles](https://usebottles.com) 67.3 baked in, so it creates bottles and runs Windows programs
**with no network**. It is not slax-wine plus Bottles. Bottles ships only as an x86_64 Flatpak, and it
runs sandboxed with its own Wine, so it cannot use our Debian Wine
([DECISIONS.md](docs/DECISIONS.md) D-14).

| | |
|---|---|
| base | `slax-64bit-debian-12.2.0.iso` |
| Bottles | 67.3 from Flathub, with the GNOME 50 runtime, GL, i386 compat, Wine Gecko and Mono; every ref pinned by commit |
| offline extras | DXVK 3.1 and VKD3D-Proton 3.0.1, without which Bottles will not create a bottle offline (measured) |
| no browser | `05-chromium.sb` removed, as in slax-wine |
| size | **1241.7 MiB**. It boots BIOS and UEFI, like the slax-wine uefi images |

Using it: **[docs/using-bottles.md](docs/using-bottles.md)**.

Installing it to a USB stick so the Wine prefix survives a reboot is **[INSTALL.md](INSTALL.md)**.
What works and what does not is **[docs/using-wine.md](docs/using-wine.md)**.

## How it is built

Seven recipes over [slax-kitchen](https://github.com/Fullaxx/slax-kitchen), pinned as a submodule:
five for slax-wine, two for slax-bottles. slax-kitchen is the engine — generic, and knowing nothing
about Wine; the recipes here say *what* to change, never *how*.

| bundle | recipe |
|---|---|
| `20-wine.sb` | [`wine`](docs/50-cookbook/wine.md) — install Wine 8.0 from bookworm main, for the base it is built on |
| `21-wine-desktop.sb` | [`wine-desktop`](docs/50-cookbook/wine-desktop.md) — launcher, environment, menu cleanup |
| `30-notepadpp32.sb` | [`notepadpp32`](docs/50-cookbook/notepadpp32.md) — the 32-bit Notepad++ installer, a swappable application layer |
| `31-notepadpp64.sb` | [`notepadpp64`](docs/50-cookbook/notepadpp64.md) — the 64-bit Notepad++ installer, **slax64-wine only** |
| — | [`slax-wine-iso`](docs/50-cookbook/slax-wine-iso.md) — boot defaults, ISO identity, checksum |
| — | `uefi-bootable` — **upstream's**, applied only by the uefi profiles. Adds a GRUB ESP; builds no bundle |
| `20-flatpak.sb`, `30-bottles.sb` | [`bottles`](docs/50-cookbook/bottles.md) — **slax-bottles only**: flatpak, and Bottles with its runtimes, DXVK and VKD3D |
| — | [`slax-bottles-iso`](docs/50-cookbook/slax-bottles-iso.md) — **slax-bottles only**: the same boot default and checksum, its own identity |

All four run upstream's `remove-bundle` first — it drops `05-chromium.sb`, named explicitly rather
than inherited, and it has to come before anything that builds — then `wine`, `wine-desktop`,
`notepadpp32` and `slax-wine-iso`. The 64-bit ones add `notepadpp64`, and the uefi ones add
`uefi-bootable` last, which builds no bundle. `wine`, `wine-desktop` and `slax-wine-iso` carry a step
per base, guarded by `when: arch==…`, so one recipe list serves both.
[`ci/checks/96-release-consistency.sh`](ci/checks/96-release-consistency.sh) fails if the profiles
of a base disagree, if the 64-bit list is anything but the 32-bit one plus `notepadpp64`, if a
profile's name does not match its base or firmware, or if any drops the removal or lists it late.

`30-notepadpp32.sb` and `31-notepadpp64.sb` are meant to be replaced. Delete one from
`/slax/modules/` on a stick and drop another in — no rebuild, no remaster. That is the whole point of
the layering.

slax-bottles has a profile of its own: `remove-bundle`, then `bottles`, `slax-bottles-iso` and
`uefi-bootable`, on the 64-bit base. Gate 96 holds it to removal-first, but not to slax-wine's core
list, because it is a different system rather than another variant of the same one.

## Status

**runtime-verified, on both bases.** On a full desktop boot: the **Wine** tile appears in the launcher
and opens without an xterm wrapper, the Notepad++ installer runs under Wine and the installed editor
launches, there is **no** Wine Mono / Gecko download prompt, and the browser is gone from the
launcher. On slax64-wine the **64-bit** Notepad++ installs and runs too, as a 64-bit process, and
32-bit and 64-bit programs run in the same prefix. The two Notepad++ builds are the exception: each
one's installer removes the other ([docs/using-wine.md](docs/using-wine.md#on-slax64-wine)).

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
| where each image's size goes | [docs/sizing.md](docs/sizing.md) |
| to try one Windows program on both bases | [docs/testing-on-both.md](docs/testing-on-both.md) |
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
