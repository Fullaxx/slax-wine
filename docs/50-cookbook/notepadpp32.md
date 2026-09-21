# `notepadpp32` — the 32-bit Notepad++, a swappable application layer

**Status: runtime-verified**, on both bases — **the acceptance test for this whole project passed
on each.** On a full desktop boot of `slax32-wine-uefi` and of `slax64-wine-uefi`, the **Notepad++
(32-bit)** tile was picked from the launcher, the NSIS installer ran under Wine, and the installed
editor launched, a 32-bit process on both. On 64-bit it installed to `C:\Program Files (x86)`, in a
64-bit prefix, which is where its launcher looks there. That exercises PE loading, the NSIS runtime,
registry writes and file creation in the prefix — the reason for shipping the installer rather than
a portable tree.

**Not yet verified: that it survives a reboot.** Both observations were non-persistent boots, so the
install landed in RAM. On a persistent USB it should happen once; that is
[INSTALL.md](../../INSTALL.md)'s claim and it is still untested on hardware.

```sh
./build.sh          # every slax-wine image carries it
```

One bundle, `30-notepadpp32.sb`, deliberately separable: this is the layer a games variant replaces.
Its 64-bit twin is [`notepadpp64`](notepadpp64.md), on the 64-bit images only. Everything of each
says which it is — recipe, bundle, `/opt/notepadpp32`, `npp32-installer.exe`, `notepadpp32`, the
"Notepad++ (32-bit)" tile — so an image that carries both never leaves you guessing.

## Numbering is the mechanism, not a convention

Load order is the numeric prefix, higher wins, and `union_append_bundles` inserts each bundle at aufs
branch index 1 so each arrival outranks the last. Delete `30-notepadpp32.sb` from `/slax/modules/` on
a stick and drop another `30-*.sb` in its place — no rebuild, no remaster — or swap it live with
`slax activate`.

slax-kitchen allocates `00`–`09` to the platform, **`10`–`89` to forks**, `90`–`97` to headroom, and
refuses `98` and `99`. Inside the fork band this project uses `20`–`29` for its platform and
`30`–`89` for applications; the low end is left to slax-kitchen's own example app recipes, which sit
at `10`–`16` today. `31-notepadpp64.sb` sits beside this one on the 64-bit images.

**This bundle depends on `21-wine-desktop.sb`**, whose `/etc/profile.d/wine.sh` its launcher sources,
and on `20-wine.sb`'s Wine. That is correct rather than a flaw: `20`+`21` are the platform, `30` is an
app on it.

## The installer, not the portable build

A portable `.exe` would prove only that Wine can load a PE binary and open a window. The NSIS
installer additionally exercises the installer runtime, registry writes, file creation inside the
prefix and shortcut generation — much closer to what a game needs. Updating it touches `build.env`
only: `APP_VERSION`, which both Notepad++ recipes share, and `APP32_URL`, `APP32_SHA256` and
`APP32_SIZE`. Gate 96 §2b refuses an `APP_VERSION` that is not in the URL.

| | |
|---|---|
| asset | `npp.8.9.8.Installer.exe`, staged as `npp32-installer.exe` |
| size | 6,806,520 B |
| sha256 | `9753e2eba8f0ff056d60c52a917f7760ea81227e41b1786260e1ac76db398434` |
| type | **PE32 / Intel 80386 — 32-bit**, Nullsoft self-extracting |

The hash is upstream's own published value — it appears verbatim in
`npp.8.9.8.checksums.sha256`, which Notepad++ also signs. It runs under `wine32` on both bases: natively
on 32-bit, and through Wine's 32-bit half on 64-bit.

## It cannot run at build time

`bundle.script`'s chroot has no `/proc`, and `wineboot` needs it. So the bundle ships the installer
and the live system runs it. That is not a compromise — it is the demonstration.

`/usr/local/bin/notepadpp32` installs on first use and launches thereafter. In outline:

```sh
PREFIX=${WINEPREFIX:-$HOME/.wine}
npp() { # a 64-bit prefix has syswow64, and puts 32-bit programs in "Program Files (x86)"
    if [ -d "$PREFIX/drive_c/windows/syswow64" ]; then
        echo "$PREFIX/drive_c/Program Files (x86)/Notepad++/notepad++.exe"
    else
        echo "$PREFIX/drive_c/Program Files/Notepad++/notepad++.exe"
    fi
}
[ -f "$(npp)" ] || wine /opt/notepadpp32/npp32-installer.exe
[ -f "$(npp)" ] && exec wine "$(npp)" "$@"      # "$@" goes to the editor, never the installer
```

**Where a 32-bit program lands is decided by the prefix, not the image**, so the launcher asks the
prefix. It never tries both directories: in a 64-bit prefix, `Program Files` is where `notepadpp64`
installs, and trying it would start the wrong build. It follows `WINEPREFIX`, so a 32-bit prefix
made on a 64-bit image works too. A cancelled install does not loop, and a failed one says so in a
window, because the tile runs with no terminal.

**Wine sees the installer with no prefix setup at all**, because Wine maps `Z:` to `/` by default — so
`/opt/notepadpp32/` is reachable as `Z:\opt\notepadpp32\` without touching the prefix.

## The best thing about shipping an installer

On a non-persistent boot the install lands in the RAM writable layer and is gone at shutdown, so it
must be re-run every boot. On a persistent USB it happens once and stays.

That makes Notepad++ a live demonstration of what persistence is for, which ties this bundle,
[`wine`](wine.md) and [INSTALL.md](../../INSTALL.md) into one story.

## What it proves, and what it does not

It exercises PE loading, the NSIS runtime, registry writes, file creation in the prefix, and the
common-controls GUI. It does **not** exercise DirectDraw/Direct3D, DirectSound, MSI or 16-bit code —
which for an old game are precisely the risky parts. A games variant should not inherit confidence
from this page.

Note also that stock Slax ships **no GPU firmware at all** — no `amdgpu`, `i915`, `radeon` or
`nouveau` — so 3D under Wine falls back to software rendering until slax-kitchen's
`firmware-refresh` recipe is applied. Notepad++ does not care; a game would. See
[DECISIONS.md](../DECISIONS.md).

## Verified

```
built slax/modules/30-notepadpp32.sb (6556 KiB, 4 files)
  /opt/notepadpp32
  /usr/local/bin/notepadpp32
  /usr/share/applications/7notepadpp32.desktop
```

`30-notepadpp32.sb` is 6,713,344 B — **6.4 MiB**, on every image. The installer inside it is
byte-identical to the one the untagged `30-notepadpp.sb` carried. The payload barely compresses,
because an NSIS installer is already a compressed archive.

Measured in QEMU (TCG, `-cpu Nehalem`, 3 GiB, no network card), 2026-09-19:

| | slax32-wine-uefi | slax64-wine-uefi |
|---|---|---|
| the prefix the first launch made | 32-bit | 64-bit (`syswow64` present) |
| installed to | `C:\Program Files\Notepad++` | `C:\Program Files (x86)\Notepad++` |
| `notepad++.exe` | PE machine `0x14c`: i386 | the same |
| the editor | ELF class 1, `wine-preloader.static` | ELF class 1, `wine-preloader.static` |
| in a `WINEARCH=win32` prefix | — | installs to `C:\Program Files\Notepad++` and launches, ELF class 1 |
| the same installer, silent (`/S`) | **1.3 s** under KVM, 29 s under emulation | **1.6 s** under KVM |

**Under KVM the first launch is quick**: measured 2026-09-21 on `slax32-wine-test`, the prefix
takes **23 seconds** and the editor's window follows the install immediately. Wine's five-minute
limit is nowhere near.

**Under emulation it once failed, and the failure path did its job.** Creating the prefix took about
9 minutes on a host that was also building, past the 5 minutes Wine waits: the journal said
`boot event wait timed out`. The installer never appeared, and the launcher showed its window —
*"Notepad++ (32-bit) is not installed: the installer was cancelled or failed. Run it again to
retry."* — rather than nothing. The second launch used the finished prefix, and installed and ran.
On an idle emulated host the same step took about 4 minutes; on real hardware it has not been
timed.

On slax64 the 64-bit build shares the prefix, and does not coexist with this one: each installer
removes the other build ([`notepadpp64`](notepadpp64.md#the-two-builds-replace-each-other)).

| you want | use |
|---|---|
| Wine itself | [`wine`](wine.md) |
| the launcher plumbing this relies on | [`wine-desktop`](wine-desktop.md) |
| the 64-bit build | [`notepadpp64`](notepadpp64.md) |
| to run without it | `noload=30-notepadpp32.sb` at the boot prompt |
| to swap in your own application | replace `30-notepadpp32.sb`, or copy this recipe |
