# `wine-desktop` — put Wine in the launcher, and hide the browser we removed

**Status: runtime-verified**, on both bases — on a full desktop boot, every claim this bundle makes
was observed: the **Wine tile appears** in xlunch, clicking it opens Wine **with no xterm wrapper**
(so `Terminal=false` is doing its job), the **browser is absent** from the launcher, and there is
**no Wine Mono / Gecko download prompt** (so `/etc/profile.d/wine.sh` reached the session through
`su --login`).

On 64-bit, on `slax64-wine-uefi` (2026-09-19, in QEMU): the click opened Wine's file manager once the
first-run prefix was made, 258 s later under emulation, and that prefix was 64-bit, as this step's
`wine.sh` leaves it. On 32-bit the click was observed before the 64-bit step was added, and adding it
changed nothing there: the 32-bit build's `21-wine-desktop.sb` is identical, entry by entry, to the
one in the images this change started from, and its launcher again showed the Wine tile and no
browser.

That matters more than a green tick: an earlier draft of this recipe used `Icon=wine`, which
resolves to nothing, and xlunch silently dropped the entry. The tile is the whole point of the
bundle, and it is the one thing no gate can check.

```sh
./build.sh
```

A 4 KiB bundle that does the entire difference between "Wine is installed" and "Wine is on the
desktop".

## Why a bundle and not rootcopy

`rootcopy.files` would be simpler. It is also copied onto the union on **every** boot, costs that
much RAM each time, and cannot be switched off. A bundle is mounted read-only from the medium, and
`noload=21-wine-desktop.sb` at the boot prompt gives back plain Wine with no desktop changes.

At 4 KiB the RAM argument is negligible. The `noload=` argument is the real one: this bundle is the
only thing that makes the image *look* different from stock, so it is the one you want to be able to
turn off.

It also carries no `dpkg` status fragment, so unlike `20-wine.sb` it shadows nothing. That is exactly
why the integration is a separate bundle from the packages.

## `Terminal=false` is load-bearing

Slax's launcher has no static list. `fbappselect` regenerates it at launch with
`xlunch_genquick 64 --desktop`, straight from `/usr/share/applications/*.desktop`, ordered by the
filename's leading character — which is why `5wine.desktop` takes exactly the slot the browser
vacated.

The trap is two lines further down in `fbappselect`:

```sh
42: Xdep=$(ldd $whi | grep libX11)
50: if [ "$Xdep" = "" -a "$cmd" != "chromium" ... -a "$NoTerm" = "" ]; then
```

Debian's `/usr/bin/wine` is a **shell script**, so `ldd` reports no `libX11` and the heuristic
guesses "console program" — and wraps a GUI application in an xterm. Line 36 reads `Terminal=false`
as the override. Slax's own entries all set it.

## `Hidden` is the key xlunch reads, and `NoDisplay` is not

The recipe masks the leftover `5chromium.desktop` with **both** `Hidden=true` and `NoDisplay=true`,
and only the first is read by the launcher:

```sh
28: done <<< $(tac "$desktop" | egrep '^(Name|Icon|Exec|Hidden|Terminal)=' | ...)
30: if [ "$Hidden" = "true" ]; then
31:    continue
```

`NoDisplay` is not in that key set.

**A `NoDisplay`-only stub does still vanish — but by accident, and that is the part worth
knowing.** `xlunch_genquick` ends each entry with `if [ -e "$Icon" ]; then echo ...`, and a stub
with no `Icon=` line fails that test on the empty string. So the tile disappears for a reason that
has nothing to do with the key you wrote. Add a single `Icon=` line — the obvious way to make a
masked entry look tidier — and the entry you were hiding comes back.

Upstream now treats this as a defect rather than an idiom. Its `remove-bundle` page (which absorbed
the old `remove-chromium` page in PR #16) sets `Hidden=true` in the stub, and its
`tests/unit/test_desktop_entries.py` — which this repo runs as gate 80 — fails any
`NoDisplay=true` without `Hidden=true`. An earlier version of this page said the `NoDisplay`-only
form "works"; the mechanism described was right, the conclusion drawn from it was too generous.

This stub has always set `Hidden` explicitly *and* omitted `Icon`, so it was never affected, and it
keeps `NoDisplay` for anything else that honours the freedesktop standard. The entry degrades
honestly either way: it is named "Web Browser (not included)" and runs `/bin/true`.

## One bundle, a step per base

The recipe has two `bundle.files` steps, `when: arch==32bit` and `when: arch==64bit`, and both build
`21-wine-desktop.sb`; only the one matching the base runs. Three of the five files are the same file
in both — the Wine tile, the browser mask and the `slax-wine` wrapper — written once and shared
through YAML anchors. Two differ: `/etc/profile.d/wine.sh` (below) and `/etc/slax-wine-release`,
whose `BASE_ISO` and `BASE_SHA256` name the base it was built on.

## The environment reaches the desktop, and the wrapper makes sure

`/etc/profile.d/wine.sh` sets `WINEDLLOVERRIDES="mscoree,mshtml="` on both bases, and
`WINEARCH=win32` on the 32-bit one only. On the 64-bit base no `WINEARCH` is set, so a new prefix is
64-bit and runs 32-bit programs too, and a user's own `WINEARCH=win32` — for a 32-bit prefix —
survives the wrapper, which re-sources this file. `WINEDLLOVERRIDES` is what suppresses Wine's
first-run "download Mono and Gecko" dialog — Debian packages neither, in main, contrib or non-free,
so that dialog could only ever be satisfied by fetching ~136 MiB from winehq at runtime on an image
that is usually offline. The cost is that .NET and embedded-HTML applications do not run;
[using-wine.md](../using-wine.md) says so.

`profile.d` is read by login shells, and the Slax session **is** one — `02-xorg`'s `xorg.service`
runs `/bin/su --login -c "/usr/bin/Xdetect ..."`, and `01-core`'s `/etc/profile` ends with the
standard `for i in /etc/profile.d/*.sh` loop. Both halves verified by reading the shipped files.

`/usr/local/bin/slax-wine` sources it anyway and every `Exec=` goes through the wrapper, because the
failure mode of being wrong about that is a Gecko prompt on an offline machine — invisible until
somebody boots the image.

## What the mask does not cover

`5chromium.desktop` is shadowed, so the browser is gone from **xlunch** — the launcher on `Super`
and `Alt+F2`, which is how anyone actually starts a program here.

It is still in the **Fluxbox root menu** (right-click the desktop). That menu is a static file,
`/root/.fluxbox/menu` in `03-desktop.sb`, not generated from `/usr/share/applications`, so nothing a
`.desktop` file does can reach it. Its entry runs `fbliveapp chromium`, and `fbliveapp` offers to
`apt install --yes chromium chromium-sandbox` when the binary is missing — a sensible default for a
networked live system, and useless on an image that is usually offline.

Left alone deliberately: overriding `/root/.fluxbox/menu` means shipping a copy of the whole file and
re-syncing it on every Slax release, to hide one entry that says "install a browser". Worth knowing
it is there; not worth the maintenance. If you want it gone, add the file to this bundle.

## Verified

```
built slax/modules/21-wine-desktop.sb (4 KiB, 5 files)
  /usr/share/applications/5wine.desktop
  /usr/share/applications/5chromium.desktop
  /etc/profile.d/wine.sh
  /usr/local/bin/slax-wine
  /etc/slax-wine-release
```

The same five paths on the 64-bit base. `/etc/slax-wine-release` is `os-release`-shaped and
deliberately carries no build date or git commit, so two builds of the same tag produce identical
bytes. `ci/checks/96-release-consistency.sh` checks each step's VERSION, BASE_ISO and BASE_SHA256
against `build.env` — the 32-bit step's against `BASE32_*`, the 64-bit one's against `BASE64_*` — and
`build.sh` reads the built image's copy back and refuses one that names another base.

| you want | use |
|---|---|
| the Wine packages themselves | [`wine`](wine.md) |
| something to run in it | [`notepadpp32`](notepadpp32.md), and [`notepadpp64`](notepadpp64.md) on 64-bit |
| to turn the desktop changes off | `noload=21-wine-desktop.sb` at the boot prompt |
