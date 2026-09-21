# `notepadpp64` — the 64-bit Notepad++, on the 64-bit images

**Status: runtime-verified** on `slax64-wine-uefi`, in QEMU. On a full desktop boot the
**Notepad++ (64-bit)** tile was picked from the launcher. Its installer, itself a 32-bit program,
ran as a 32-bit process and installed into `C:\Program Files\Notepad++`; the installed
`notepad++.exe`, x86-64, launched as a **64-bit process** under `wine64-preloader`. That is the win64
install-and-run test this recipe exists for.

**Not verified: that it survives a reboot**, as for [`notepadpp32`](notepadpp32.md). And **the two
builds do not share a prefix**: each one's installer removes the other ([below](#the-two-builds-replace-each-other)).

```sh
./build.sh --64     # slax64-wine-bios and -uefi carry it; the 32-bit images cannot run it
```

One bundle, `31-notepadpp64.sb`: the twin of [`notepadpp32`](notepadpp32.md), and it says 64
wherever that one says 32 — recipe, bundle, `/opt/notepadpp64`, `npp64-installer.exe`,
`notepadpp64`, the "Notepad++ (64-bit)" tile. `31` puts it beside `30-notepadpp32.sb` in the
application band. What it adds over its twin is a Windows program that needs the 64-bit half of Wine,
installed the way people install one.

## The installer is not 64-bit

| | |
|---|---|
| asset | `npp.8.9.8.Installer.x64.exe`, staged as `npp64-installer.exe` |
| size | 6,953,384 B |
| sha256 | `7b2a949bf460fb37a3888c9048698f43222a185a48323023df1c51e78a3ca1c2` |
| type | **PE32 / Intel 80386** — measured from its header: machine `0x14c`, optional-header magic `0x10b` — Nullsoft self-extracting |
| what it installs | x86-64 binaries (PE32+) |

The hash is upstream's own published value, verbatim in `npp.8.9.8.checksums.sha256`, and
`build.sh` checks it before staging, as it does the x86 one's.

So one launch exercises both halves of Wine: a **32-bit installer**, running under `wine32`, that
installs into the **64-bit** `C:\Program Files`, and then a **64-bit program** running under
`wine64`. On a 32-bit Windows the installer starts and refuses, as it does in a 32-bit prefix
([below](#the-launcher)) — so it is not on the 32-bit images.

Updating it touches `build.env` only: the shared `APP_VERSION`, and `APP64_URL`, `APP64_SHA256` and
`APP64_SIZE`. Gate 96 §2b holds `APP_VERSION` to this URL too.

## The launcher

`/usr/local/bin/notepadpp64` installs on first use and launches thereafter, like its twin, with one
difference: **it refuses a 32-bit prefix.** One that exists without `syswow64` is a 32-bit Windows,
whose `Program Files` is where `notepadpp32` installs, so going on could start the wrong build. It
says so in a window instead. In a 64-bit prefix, `Program Files\Notepad++` can only be this build —
the 32-bit one lands in `Program Files (x86)`.

**A prefix that does not exist yet has nothing to ask**, so with `WINEARCH=win32` set the launcher
goes ahead: Wine makes a 32-bit prefix and runs the installer in it. Measured, and it still ends in a
refusal, from Notepad++'s own installer this time: *"You cannot install Notepad++ 64-bit version on
your 32-bit system"*. The launcher then reports the build not installed, and nothing was.

## Verified

```
built slax/modules/31-notepadpp64.sb (6700 KiB, 4 files)
  /opt/notepadpp64
  /usr/local/bin/notepadpp64
  /usr/share/applications/7notepadpp64.desktop
```

`31-notepadpp64.sb` is 6,860,800 B — **6.5 MiB**, on both 64-bit images.

Measured in QEMU (TCG, `-cpu Nehalem`, 3 GiB, no network card) on `slax64-wine-uefi`, 2026-09-19:

| | |
|---|---|
| the tile | "Notepad++ (64-bit)" in the launcher, beside "Notepad++ (32-bit)" |
| its installer | a 32-bit process (ELF class 1, `wine-preloader.static`) |
| installed to | `C:\Program Files\Notepad++`, in the 64-bit prefix the first click made |
| `notepad++.exe` | PE machine `0x8664`: x86-64 |
| the editor | a 64-bit process: ELF class 2, `/usr/lib/wine/wine64-preloader.static` |
| the same installer, silent (`/S`), in a fresh 64-bit prefix | exit 0: **1.7 s** under KVM, 29–32 s under emulation |
| `notepadpp64` in a `WINEARCH=win32` prefix | refused, with its message, exit 1 |
| `WINEARCH=win32 notepadpp64` with **no prefix yet** | refused before one is created, exit 1 |
| `notepadpp64` when only the 32-bit build is installed | asks first, Cancel by default ([D-17](../DECISIONS.md#d-17--one-prefix-and-the-flip-is-a-choice)) |

## The two builds replace each other

Measured in fresh 64-bit prefixes, each installer run silently, in both orders:

| installed first, then | what is left in the prefix |
|---|---|
| the 32-bit build, then the 64-bit one | only `Program Files\Notepad++`, x86-64 |
| the 64-bit build, then the 32-bit one | only `Program Files (x86)\Notepad++`, x86 |

It is Notepad++'s installers doing it, not the launchers: each launcher looks only where its own
build installs and, finding nothing there, runs its installer again, which removes the other in
turn. The tiles did the same — installing the 64-bit build from its tile removed the 32-bit build
put there minutes before.

**Since [D-17](../DECISIONS.md#d-17--one-prefix-and-the-flip-is-a-choice) each launcher asks first.**
When its own build is missing and the other one is present, it says what the installer is about to
remove and offers the second prefix, with **Cancel as the default** — a stray Return does not pick
the answer that removes something. Cancel exits 0 and says nothing more. Measured 2026-09-21 on
`slax64-wine-test` under KVM, in both directions: the dialog appears, Return leaves the other build
in place and installs nothing, and choosing to go ahead starts the installer as before. On
`slax32-wine-test` the same launcher asks nothing at all, which is the half that matters — there the
x86 build owns `Program Files` itself, and a warning would be about removing what is being
installed.

To keep both, give one its own prefix: `WINEPREFIX=/root/.wine-npp64 notepadpp64`, which is what the
dialog suggests. On a non-persistent boot that is another 1.2 GiB of RAM
([software.md](../software.md#requirements)).

| you want | use |
|---|---|
| the 32-bit build, on every image | [`notepadpp32`](notepadpp32.md) |
| the Wine it needs | [`wine`](wine.md) — the 64-bit step |
| to run without it | `noload=31-notepadpp64.sb` at the boot prompt |
