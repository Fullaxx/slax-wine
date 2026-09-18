# Using Wine in slax-wine

What works, what does not, and the two things that surprise people.

## First run

Open the launcher (`Super`, or `Alt+F2`) and pick **Wine**, or run `slax-wine` from a terminal.
The tile is `runtime-verified` territory and has not been confirmed on hardware yet — if it is not
there, `slax-wine` from a terminal does the same thing.

The first `wine` call creates the prefix at `/root/.wine`. It takes **10–30 seconds with no
feedback**, which looks like nothing happening. It is not. After that, launches are immediate.

There is **no Mono/Gecko download prompt**, because `/etc/profile.d/wine.sh` sets
`WINEDLLOVERRIDES="mscoree,mshtml="`. Debian packages neither Wine Mono nor Wine Gecko — not in main,
contrib or non-free — so that dialog could only ever be satisfied by fetching about 136 MiB from
winehq at runtime, on an image that is usually offline.

**The cost is real and worth knowing: .NET applications and anything relying on Wine's embedded HTML
control will not run.** If you need them, `winetricks` is reachable — the stock `sources.list`
already enables `contrib` — or fetch the MSIs yourself onto a persistent stick.

## Notepad++, and why it installs itself

The image ships the **installer**, not an unpacked copy. Picking Notepad++ from the launcher — or
running `notepadpp` from a terminal, which is the same wrapper — runs it under Wine the first time
and launches the installed copy thereafter. `notepadpp somefile.txt` opens that file.

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
| `wine64` | this is a 32-bit image by design |

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
