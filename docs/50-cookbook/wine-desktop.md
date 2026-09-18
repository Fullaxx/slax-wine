# `wine-desktop` — put Wine in the launcher, and hide the browser we removed

**Status: runtime-verified** — on a full desktop boot, every claim this bundle makes was observed:
the **Wine tile appears** in xlunch, clicking it opens Wine **with no xterm wrapper** (so
`Terminal=false` is doing its job), the **browser is absent** from the launcher, and there is **no
Wine Mono / Gecko download prompt** (so `/etc/profile.d/wine.sh` reached the session through
`su --login`).

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

**That does not mean a `NoDisplay`-only stub leaves the tile visible.** slax-kitchen's
`remove-chromium` page masks with `NoDisplay` alone, and it works — because `xlunch_genquick` also
ends each entry with `if [ -e "$Icon" ]; then echo ...`, and that stub ships no `Icon=` line, so the
entry is never emitted at all. Two independent mechanisms, and only one of them is written down
anywhere.

This stub sets `Hidden` explicitly *and* omits `Icon`, so it is covered twice over, and keeps
`NoDisplay` for anything else that honours the freedesktop standard. The entry degrades honestly
either way: it is named "Web Browser (not included)" and runs `/bin/true`.

## The environment reaches the desktop, and the wrapper makes sure

`/etc/profile.d/wine.sh` sets `WINEARCH=win32` and `WINEDLLOVERRIDES="mscoree,mshtml="`. The second
is what suppresses Wine's first-run "download Mono and Gecko" dialog — Debian packages neither, in
main, contrib or non-free, so that dialog could only ever be satisfied by fetching ~136 MiB from
winehq at runtime on an image that is usually offline. The cost is that .NET and embedded-HTML
applications do not run; [using-wine.md](../using-wine.md) says so.

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

`/etc/slax-wine-release` is `os-release`-shaped and deliberately carries no build date or git commit,
so two builds of the same tag produce identical bytes.
`ci/checks/96-release-consistency.sh` greps its VERSION, BASE_ISO and BASE_SHA256 against
`build.env`, so the image cannot claim a version it was not built as.

| you want | use |
|---|---|
| the Wine packages themselves | [`wine`](wine.md) |
| something to run in it | [`notepadpp`](notepadpp.md) |
| to turn the desktop changes off | `noload=21-wine-desktop.sb` at the boot prompt |
