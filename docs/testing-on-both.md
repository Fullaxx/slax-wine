# Testing Windows software on both architectures

slax-wine is one system on two bases ([DECISIONS.md](DECISIONS.md) D-16): `slax32-wine-*` on 32-bit
Slax and `slax64-wine-*` on 64-bit Slax, each as a bios and a uefi image. To see how a Windows program
fares on each, boot one of each and run the same program the same way. Both carry the same Wine,
8.0~repack-4 from Debian bookworm main, and the same x86 Notepad++. slax64 also carries the x64
Notepad++.

## What differs underneath, before blaming the architecture

| | slax32-wine | slax64-wine |
|---|---|---|
| Wine | `wine32` (i386) | `wine64` (amd64) **and** `wine32` (i386), from the same source version |
| a new prefix | 32-bit (`WINEARCH=win32` is set) | 64-bit; 32-bit programs run in it through `wine32` |
| 32-bit programs install to | `C:\Program Files` | `C:\Program Files (x86)` |
| 64-bit programs | do not run | run |
| a 32-bit program's address space | 3 GiB (the kernel is `VMSPLIT_3G`) | 4 GiB |
| Linux libraries | the base's, with what `20-wine.sb` adds | the base's, with what `20-wine.sb` adds — which on this base includes **newer** amd64 packages, lifted to match their i386 twins: 79 of the base's own, glibc, systemd and OpenSSL among them ([DECISIONS.md](DECISIONS.md) D-16) |

The last row matters most when a program behaves differently on the two: the Wine is the same, the
libraries under it are not quite. `out/<image>-<ver>.packages.tsv` from a build lists every package
of each, with its version and architecture.

## Running one program on both

Put the program where both images can reach it — a second stick, a partition, or a persistent
stick — then, on each:

```sh
slax-wine /path/to/setup.exe                  # slax32: the 32-bit prefix, /root/.wine
slax-wine /path/to/setup.exe                  # slax64: the 64-bit prefix, /root/.wine
```

On slax64 there is a third way, and it separates "64-bit Linux" from "64-bit Windows": a **32-bit
prefix on the 64-bit base**. Wine makes it when the prefix does not exist yet and `WINEARCH=win32`
is set; the image leaves `WINEARCH` unset on this base precisely so that this passes through the
`slax-wine` wrapper.

```sh
WINEARCH=win32 WINEPREFIX=/root/.wine32 slax-wine /path/to/setup.exe
```

`notepadpp32` uses whichever prefix `WINEPREFIX` names; `notepadpp64` refuses a 32-bit one, and says
so.

When something does not start, the first missing library is usually the answer:

```sh
WINEDEBUG=+loaddll slax-wine yourapp.exe 2>&1 | grep -i 'failed to load'
```

## What to record

One row per program: its name and version, whether the `.exe` is 32- or 64-bit, and on each of the
three — slax32, slax64 with its 64-bit prefix, slax64 with a 32-bit prefix — whether it
**installs**, **starts**, and **works**, and the first error if not.

## Results

Measured in QEMU (TCG, `-cpu Nehalem`, 3 GiB, no network card) on fresh non-persistent boots of
`slax32-wine-uefi` and `slax64-wine-uefi`, 2026-09-19. "32-bit process" and "64-bit process" are
the ELF class of the running program's Wine loader.

| program | `.exe` | slax32-wine | slax64-wine, 64-bit prefix | slax64-wine, 32-bit prefix |
|---|---|---|---|---|
| Notepad++ 8.9.8, x86 installer | PE32 | installs to `Program Files`; runs, 32-bit process | installs to `Program Files (x86)`; runs, 32-bit process | installs to `Program Files`; runs, 32-bit process |
| Notepad++ 8.9.8, x64 installer | PE32 stub installing PE32+ | not on the image | installs to `Program Files`; runs, **64-bit process**. Removes the x86 build, and the x86 installer removes it | refused, by `notepadpp64` or, in a prefix Wine is still to make, by the installer |
| `wine cmd` | Wine's | `PROCESSOR_ARCHITECTURE=x86` | `x86`, with `PROCESSOR_ARCHITEW6432=AMD64`: the 32-bit `cmd`. `/usr/lib/wine/wine64 cmd`: `AMD64` | `x86` |
| `wine notepad` | Wine's | — | 32-bit process; with `/usr/lib/wine/wine64`, 64-bit | — |

Worth knowing before a run of your own:

- **Creating a prefix is the slow part**, and happens once per prefix: about 4 minutes for a 64-bit
  one here, 90 seconds for a 32-bit one on slax64. Wine waits at most 5 minutes for it, and on
  slax32, on a busy host, it took about 9, so that first launch failed (`boot event wait timed out`)
  and the second worked. Under emulation, give the host nothing else to do, or run twice.
- **Each prefix lives in RAM** on a non-persistent boot: 1,265 MiB for a 64-bit one, 589 MiB for a
  32-bit one. A run that kept two and was making a third stalled a 3 GiB VM until it was reset.
  Delete one before making the next, or boot persistent.
- **`wine` on slax64 starts the 32-bit loader** (Debian's wrapper), and Wine hands 64-bit programs to
  `wine64` itself. So a program runs in its own width, but Wine's own tools default to 32-bit — as
  the `cmd` row shows. [using-wine.md](using-wine.md#on-slax64-wine) has the details.
