# Using Wine in slax-wine

What works, what does not, and the two things that surprise people. What is installed, and what
the image needs from the machine, is [software.md](software.md). Everything here holds on all four
images; what differs on the 64-bit ones, `slax64-wine-*`, has [its own section](#on-slax64-wine).

## First run

Open the launcher (`Super`, or `Alt+F2`) and pick **Wine**, or run `slax-wine` from a terminal.
Both work — the tile has been confirmed on a full desktop boot.

The first `wine` call creates the prefix at `/root/.wine`, and until that is done the program you
asked for does not appear: a busy cursor, and at most a small *"The Wine configuration … is being
updated"* window. It is not stuck. Wine copies its Windows-side libraries into the prefix —
**1,265 MiB for a 64-bit prefix, 589 MiB for a 32-bit one** — and it takes a while. Measured
2026-09-21 **under KVM**, on an idle host: **65 seconds** for a 64-bit prefix on slax64, **32
seconds** for a 32-bit one there, and **23 seconds** on slax32. Real hardware has not been timed.
It happens once per prefix.

Under **emulation** (QEMU without KVM) the same steps took about 4 minutes, 90 seconds and — on a
host that was also building — 7 to 9 minutes. Those numbers still describe a machine without an
accelerator, which is what CI and a container are.

**If it takes more than 5 minutes, the first launch fails.** Wine waits at most that long for the
prefix, then gives up (`boot event wait timed out` in the journal). Under KVM that limit is a long
way off; under emulation on a busy host it was reached once, and the Notepad++ tile said so in a
window, with the second launch working.

**Without persistence the prefix lives in RAM**, so a 64-bit one costs 1.2 GiB of memory, and every
extra prefix as much again ([software.md](software.md#requirements)). `rm -rf` one you no longer need.

There is **no Mono/Gecko download prompt**, because `/etc/profile.d/wine.sh` sets
`WINEDLLOVERRIDES="mscoree,mshtml="`. Debian packages neither Wine Mono nor Wine Gecko — not in main,
contrib or non-free — so that dialog could only ever be satisfied by fetching about 136 MiB from
winehq at runtime, on an image that is usually offline.

**The cost is real and worth knowing: .NET applications and anything relying on Wine's embedded HTML
control will not run.** If you need them, `winetricks` is reachable — the stock `sources.list`
already enables `contrib` — or fetch the MSIs yourself onto a persistent stick.

## Which prefix you get, and what you can choose

A Wine prefix is a whole fake Windows: one directory, one architecture, fixed when it is created.
`WINEARCH` decides that at creation and **cannot change it afterwards** — point Wine at an existing
prefix with the other value and it refuses, measured:

```
wine: WINEARCH set to win32 but '/root/.wine' is a 64-bit installation.
```

A **win64** prefix runs both widths, exactly as a 64-bit Windows does: 64-bit programs in
`C:\Program Files`, 32-bit ones in `C:\Program Files (x86)`, with `windows/system32` holding the
64-bit DLLs and `windows/syswow64` the 32-bit ones — the same inverted naming Windows uses. A
**win32** prefix runs 32-bit programs only, has one `Program Files`, and no `syswow64`. That is
also how the launchers tell the two apart.

Splitting programs across prefixes **by architecture is not the normal thing to do** — one prefix
runs both. People keep separate prefixes per *application*, for its dependencies and overrides,
which is what Bottles and Lutris automate. Here a second prefix is an escape hatch with a price,
and the sizes below are the price.

### slax32-wine — one build, one width

`wine64` is not installed on this base, so there is no width to choose. The only variable is which
prefix.

| you run | prefix | what happens |
|---|---|---|
| `notepadpp32`, tile or command — **the default** | `/root/.wine`, **win32** | made on first run: **23 s**, **587 MiB**. Installs to `C:\Program Files\Notepad++`, runs as a 32-bit process |
| `WINEPREFIX=/root/.npp32 notepadpp32` | yours, **win32** | a second win32 prefix, another ~587 MiB, same layout |
| `WINEARCH=win64 …` | — | refused, measured: *"wine: WINEARCH set to win64 but '/root/.wine' is a 32-bit installation."* There is no `/usr/lib/wine/wine64` on this base to make one with |
| the D-17 question | — | never asked: one build, and it owns `Program Files` |

### slax64-wine — two builds sharing one Windows

| you run | prefix | what happens |
|---|---|---|
| either tile — **the default** | `/root/.wine`, **win64** | made on first run: **65 s**, **1,265 MiB**. x64 → `C:\Program Files\Notepad++`, x86 → `C:\Program Files (x86)\Notepad++`; both run. Whichever is installed **second removes the first**, so the second tile asks before doing it ([D-17](DECISIONS.md#d-17--one-prefix-and-the-flip-is-a-choice)) |
| `WINEPREFIX=/root/.wine-npp64 notepadpp64` | yours, **win64** | a second 64-bit prefix, another 1,265 MiB; the builds stop colliding |
| `WINEARCH=win32 WINEPREFIX=/root/.wine-npp32 notepadpp32` | yours, **win32** | **589 MiB**, less than half. The x86 build installs to `C:\Program Files` there |
| `WINEARCH=win32 notepadpp64` | — | refused by the launcher, before a prefix is made |
| `notepadpp64` pointed at a win32 prefix | that one | refused by the launcher, with its message |
| `WINEARCH=win32` against the existing win64 prefix | — | refused by **Wine**, with the message above |

**Install somewhere else and the tile will not find it.** Each launcher looks only where the
installer puts things by default, so a Notepad++ installed to another directory is invisible to it:
measured on slax32, `/S "/D=C:\npp-elsewhere"` put the editor there, the default location stayed
empty, and the next click **ran the installer again** rather than starting what was already
installed. The launcher's arguments go to the **editor**, not to its location, so passing the path
does not help: start an install of your own by hand, with
`wine '/root/.wine/drive_c/npp-elsewhere/notepad++.exe'`.

**The removal is Notepad++'s installer, not ours and not Wine's.** Measured 2026-09-23 in a 64-bit
prefix: with the x86 build installed, `Uninstall\Notepad++` reads *Notepad++ (32-bit x86)* and its
`UninstallString` points at `C:\Program Files (x86)\Notepad++\uninstall.exe`. Run the x64
installer silently and that registration is gone along with the whole directory, leaving only
`C:\Program Files\Notepad++` — whose own registration, in the 64-bit view, reads *Notepad++ (64-bit
x64)*. Each build registers under the same name in its own view, so installing one removes the
other's registration and files. Our launchers delete nothing; they run the installer and
start the editor. Untested on real Windows.

## Notepad++, and why it installs itself

The image ships the **installer**, not an unpacked copy. Picking **Notepad++ (32-bit)** from the
launcher — or running `notepadpp32` from a terminal, which is the same wrapper — runs it under Wine
the first time and launches the installed copy thereafter. `notepadpp32 somefile.txt` opens that
file. The 64-bit images also have **Notepad++ (64-bit)**, `notepadpp64`, which works the same way.

That is deliberate: a portable `.exe` would prove only that Wine can load a PE binary, while an
installer exercises the NSIS runtime, the registry, file creation inside the prefix and shortcut
generation — far closer to what a real application needs.

**On a live CD or a `dd`'d stick the install happens into RAM and is gone at shutdown**, so you do it
again every boot. On a stick with persistence it happens once. That is the clearest demonstration of
what persistence buys, and [INSTALL.md](../INSTALL.md) explains how to get it.

## Your C: drive

`WINEPREFIX` defaults to `/root/.wine`, which lives in the writable layer — so persistence covers it
with no special setup.

| stick | where it physically lands |
|---|---|
| ext4 | `slax/changes/1/root/.wine` — browsable from any Linux machine |
| FAT32 | inside `slax/changes/1/changes.dat` — readable only from a booted Slax |

**Do not use `savechanges` for a prefix.** It is a different mechanism — a snapshot into a permanent
`99-changes-N.sb` — and it stages through tmpfs, so the entire changeset must fit in RAM. A prefix
with Windows software in it is exactly the workload that breaks that. Persistence is the right tool.

## Running as root

The Slax desktop runs as root, so Wine does too. Wine 8.0 warns and runs. For a Windows binary you do
not fully trust, the `guest` account still exists:

```sh
su - guest
WINEPREFIX=/home/guest/.wine wine something.exe
```

`/root/.fluxbox/startup` bind-mounts `/home/guest/Desktop`, `Documents`, `Downloads` and the rest
over root's, so those directories are already shared between the two.

The `guest` account is vestigial here — it exists upstream because Chromium refuses to run as root,
and this image has no Chromium. It is kept because deleting a user means rebuilding `01-core` and
risks locking out root, which is wildly out of proportion.

## What is not in the image

| | why |
|---|---|
| a web browser | `05-chromium.sb` is removed to pay for Wine's size |
| Wine Mono / Wine Gecko | not packaged by Debian; see above |
| GPU firmware | **stock Slax ships none at all** — no `amdgpu`, `i915`, `radeon` or `nouveau`. 3D under Wine falls back to software rendering. slax-kitchen's `firmware-refresh` recipe fixes it for +90 MiB |
| `wine64`, on `slax32-wine-*` | the 32-bit base has the 32-bit Wine only; the `slax64-wine-*` images have both |

## When something does not start

```sh
WINEDEBUG=+loaddll wine yourapp.exe 2>&1 | grep -i 'failed to load'
```

names the missing library. The recipe installs Wine's hard dependencies and eleven of `libwine`'s
twenty-four `Recommends`.

Of the twelve not named, **six are genuinely absent** and are each one `apt install` away on a
persistent system: `gstreamer1.0-plugins-good` (media playback inside Wine), `libvulkan1`,
`libosmesa6`, `libsdl2-2.0-0`, `libodbc2` and `libv4l-0`.

The other **six are already in the base image** — `libcups2`, `libgssapi-krb5-2`, `libdbus-1-3`,
`libgl1-mesa-dri`, `libkrb5-3` and `libxfixes3` — so there is nothing to install and nothing is
disabled by their absence from the recipe. (12 named + 6 absent + 6 present = 24.)

`wineserver -k` kills a stuck prefix.

On the 64-bit images the same holds for each half: the Recommends are installed for amd64 and for
i386 alike, because a 32-bit program loads the i386 copies ([wine](50-cookbook/wine.md) has the
ledger). To add one for 32-bit programs, name the architecture: `apt install libvulkan1:i386`.

## On slax64-wine

**The prefix is 64-bit, and runs both widths** — the table in
[Which prefix you get](#which-prefix-you-get-and-what-you-can-choose) above has the defaults, the
alternatives and what each costs, and is the one place they are written down.

**A 32-bit prefix is one variable away**, for a program that misbehaves in a 64-bit one — or to
compare the two bases like for like ([testing-on-both.md](testing-on-both.md)):

```sh
WINEARCH=win32 WINEPREFIX=/root/.wine32 slax-wine setup.exe
```

The 64-bit images set no `WINEARCH` of their own, so this passes through the `slax-wine` wrapper.

**`wine` starts the 32-bit loader.** Debian's `/usr/bin/wine` runs `/usr/lib/wine/wine` whenever
`wine32` is installed, and Wine hands a 64-bit program to `wine64` itself — so `slax-wine setup.exe`
and the tiles run each program in its own width. Wine's own tools are the exception: `wine cmd` and
`wine notepad` start their **32-bit** builds (`cmd` reports `PROCESSOR_ARCHITECTURE=x86`). For the
64-bit ones, name the loader: `/usr/lib/wine/wine64 cmd` reports `AMD64`. Measured, both.

**Notepad++ in both widths, one at a time.** Each launcher looks only where its own build installs,
and **each Notepad++ installer removes the other**, so picking the other tile starts its installer
again — and **asks first**, naming what is about to go, with Cancel as the default
([DECISIONS.md](DECISIONS.md#d-17--one-prefix-and-the-flip-is-a-choice)). Keeping both means a
second prefix, and which one is cheaper depends on which build moves: the table
[above](#which-prefix-you-get-and-what-you-can-choose) has both, and it is what each dialog
suggests.

**The Linux underneath is newer than on 32-bit.** Installing Wine's i386 half lifted 79 of the base's
own packages — glibc, systemd, OpenSSL among them — to today's bookworm versions ([DECISIONS.md](DECISIONS.md)
D-16). Keep that in mind before blaming a difference between the two bases on 32 versus 64 bits.
