# `wine` — install Wine, and drop the browser to pay for it

**Status: runtime-verified** — applied to `debian-32bit-12.2.0`, all sixteen packages confirmed
installed against the package database, 21 structure assertions passed, and on a full desktop boot
**Wine ran a Windows program**: the Notepad++ installer executed and the installed editor launched.
See [`notepadpp`](notepadpp.md) for that test. No Wine Mono / Gecko prompt appeared, which confirms
`WINEDLLOVERRIDES` reached the session.

```sh
./build.sh
```

The recipe that defines the image: everything else here is integration around it.

## Two steps, and the order is the interesting part

Removal runs **first**. That looks like tidiness and is not.

`bundle.packages` assembles its build chroot from the bundles named in `from:`, and apt installs only
what that chroot says is missing. The engine's default for `from:` is now *every bundle that will sit
below this one* — which for a `20-` bundle includes `05-chromium.sb`. A recipe that took the default
and removed the browser afterwards would build against libraries it then deletes.

That is not hypothetical. Measured on this exact base:

| | |
|---|---|
| `libwine` Depends | `libpulse0 (>= 0.99.1)` — a hard dependency, not a Recommends |
| `libpulse0` in `01-core`…`04-apps` | **absent** |
| `libpulse0` in `05-chromium.sb` | **present** |

So with the default stack, apt sees it installed, skips it, and the removal deletes the only copy.
The build succeeds, every gate passes, and the merged package database is *correct* — it rightly
does not claim `libpulse0`. The image ships `libwine.so` with an unsatisfiable hard dependency, and
you find out when Wine will not start.

**The removal is not in this recipe.** It was, until the `8adfca6` bump: `cc8a664` added a
`lib/validate.py` rule that refuses a recipe mixing `bundle.remove` with anything that builds, so
every profile now lists upstream's **`remove-bundle` first**, spelling out `drop:
"^05-chromium\.sb$"` rather than inheriting that recipe's identical default. Ordering is enforced
twice — `check_plan_order` requires every removal to precede every `bundle.packages` across the
whole plan, seeded from the journal so it holds across separate `kitchen apply` invocations, and
gate 96 §5(a3) refuses a shipped profile that lists the removal late — so this recipe takes the
engine's default stack. It also named that stack explicitly until the `3a44e8a` bump. See
[DECISIONS.md](../DECISIONS.md) D-3, and [UPSTREAM.md](../UPSTREAM.md) issue 1.

Verified in the output: `98-dpkg-db.sb` declares `libpulse0`, and `20-wine.sb` ships the two
PulseAudio client libraries — `libpulse.so.0` and `libpulse-simple.so.0`, each with its versioned
target, plus `pulseaudio/libpulsecommon-16.1.so`: five paths in all.

## Sixteen packages, eight of which are free

Five are the payload. `wine32-preloader` is named explicitly because **nothing depends on it** — it
Depends on `wine32`, not the reverse — and it is the prelinked low-address loader that old 32-bit
Windows programs need.

The other eleven are `libwine` Recommends, dropped by `--no-install-recommends` and named back by
hand. Each is `dlopen()`ed rather than linked, so a missing one does not fail the install; it
silently disables a feature. Measured against `01-core`…`04-apps`:

| already present — naming them costs zero bytes | costs bytes |
|---|---|
| `libgl1` `libxcomposite1` `libxcursor1` `libxi6` `libxinerama1` `libxrandr2` `libxrender1` `libxxf86vm1` | `fonts-liberation` `libasound2-plugins` `libgnutls30` |

Eight free, three that cost. **`libgnutls30` is the one that looks free and is not**: the base
carries `3.7.9-2`, naming it *upgrades* it to `3.7.9-2+deb12u7`, so it lands in this bundle's dpkg
fragment and ships ~3.6 MB of `libgnutls.so.30.34.3` plus locale files. It is also why the merged
database comes to 635 rather than 576 + 60 = 636 — the fragment adds 59 new packages and upgrades one.

The two genuine absentees earn their place: without `fonts-liberation` Windows apps fall back to
bitmap fonts, and without `libasound2-plugins` Wine's ALSA output cannot reach PulseAudio.

**Never `ttf-mscorefonts-installer`**, which `libwine` Suggests: it is non-free and downloads from a
third party during `postinst`, turning an offline, auditable bundle into a network-dependent one
carrying a EULA.

## The bundle ships no package database

Bundles used to carry a cumulative `var/lib/dpkg/status`, and a high-numbered one shipping a short
copy would shadow a longer one. That is fixed upstream: `BUNDLE_EXCLUDE` drops `status`, and the
bundle ships `var/lib/slax-kitchen/dpkg-status.d/20-wine` — only the stanzas it changed.
`kitchen pack` merges base + fragments into a generated `98-dpkg-db.sb`.

Confirmed in the output: `20-wine.sb` contains the fragment and **no** `var/lib/dpkg/status`.

## Verified

Against `slax-32bit-debian-12.2.0.iso`:

```
removed 05-chromium.sb (-81 MiB)
unpacked 01-core.sb + 01-firmware.sb + 02-xorg.sb + 03-desktop.sb + 04-apps.sb as the build root
verified installed: wine, wine32, libwine, wine32-preloader, fonts-wine, libgl1, libgnutls30,
  libxcomposite1, libxcursor1, libxi6, libxinerama1, libxrandr2, libxrender1, libxxf86vm1,
  fonts-liberation, libasound2-plugins
delta: 3836 added, 105 modified, 3790 kept after exclusions
dpkg fragment: 60 package(s) declared (merged into 98-dpkg-db.sb at pack time)
built slax/modules/20-wine.sb (170592 KiB, 3309 files)
```

| | |
|---|---|
| `20-wine.sb` | 174,686,208 B — **166.6 MiB** |
| Wine version | `8.0~repack-4`, Debian bookworm main |
| merged database | **635 packages**, from `04-apps`' 576 plus the fragment |
| binaries present | `/usr/bin/wine`, `/usr/bin/winecfg`, `/usr/bin/winefile`, `/usr/lib/wine/wine-preloader` |

Booted under TCG (no `/dev/kvm` on the build host), all three livekit markers and every bundle in
load order:

```
* Looking for slax data
* Mounting bundles
* modules/01-core.sb   01-firmware.sb   02-xorg.sb   03-desktop.sb   04-apps.sb
* modules/20-wine.sb   21-wine-desktop.sb   30-notepadpp.sb   98-dpkg-db.sb
Live Kit done, starting slax
slax login:
```

`05-chromium.sb` appears nowhere in the log, which is the removal half of the size claim.

**The bundle is larger than a `.deb`-size estimate predicts.** `libwine`'s `.deb` is 91 MiB and its
installed size 563 MiB, but squashfs at 1 MiB blocks compresses it to 166.6 MiB — noticeably worse
than the solid `.tar.xz` inside the `.deb`. The planning estimate of 105–120 MiB was wrong by about
50 MiB, and [sizing.md](../sizing.md) carries the corrected ledger.

## What this bundle alone does not prove

Sixteen packages in the right place is not a working Wine — that took a desktop boot, and the test
that produced it lives in [`notepadpp`](notepadpp.md). This page inherits its `runtime-verified`
status from that observation rather than from anything checkable at build time; see the ladder in the
[cookbook index](README.md).

| you want | use |
|---|---|
| the launcher, and Wine's environment defaults | [`wine-desktop`](wine-desktop.md) |
| a Windows program to test it with | [`notepadpp`](notepadpp.md) |
| ISO identity and a checksum | [`slax-wine-iso`](slax-wine-iso.md) |
| to know why the image is 507 MiB | [sizing.md](../sizing.md) |
