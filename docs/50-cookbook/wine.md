# `wine` — install Wine, on both bases

**Status: runtime-verified**, on both bases. Applied to `debian-32bit-12.2.0` and to
`debian-64bit-12.2.0`, every package each step names — sixteen and thirty-five — was confirmed
installed against the package database, and the structure assertions passed. On a full desktop boot
of each, **Wine ran a Windows program**: the Notepad++ installer executed and the installed editor
launched ([`notepadpp32`](notepadpp32.md)). On 64-bit **both halves ran**: the 32-bit Notepad++ as a
32-bit process, and the 64-bit one as a 64-bit process ([`notepadpp64`](notepadpp64.md)). No Wine
Mono / Gecko prompt appeared on either, which confirms `WINEDLLOVERRIDES` reached the session.

```sh
./build.sh
```

The recipe that defines the image: everything else here is integration around it. It serves both
bases with one step each, guarded by `when: arch==32bit` and `when: arch==64bit`; both build
`20-wine.sb`, and only the one matching the base runs ([DECISIONS.md](../DECISIONS.md) D-16).

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

## 32-bit base: sixteen packages, eight of which are free

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
load order — `slax32-wine-test` through isolinux, from its serial log:

```
* Looking for slax data in /slax ...
* Mounting bundles
* modules/01-core.sb
* modules/01-firmware.sb
* modules/02-xorg.sb
* modules/03-desktop.sb
* modules/04-apps.sb
* modules/20-wine.sb
* modules/21-wine-desktop.sb
* modules/30-notepadpp32.sb
* modules/98-dpkg-db.sb
…
Live Kit done, starting slax
```

`05-chromium.sb` appears nowhere in the log, which is the removal half of the size claim.

**The bundle is larger than a `.deb`-size estimate predicts.** `libwine`'s `.deb` is 91 MiB and its
installed size 563 MiB, but squashfs at 1 MiB blocks compresses it to 166.6 MiB — noticeably worse
than the solid `.tar.xz` inside the `.deb`. The planning estimate of 105–120 MiB was wrong by about
50 MiB, and [sizing.md](../sizing.md) carries the corrected ledger.

## 64-bit base: both halves, thirty-five names

The same Wine, `8.0~repack-4`, in its two halves: `wine64` for 64-bit Windows programs, and `wine32`
— an **i386** package, so the step first runs `dpkg --add-architecture i386` (`apt.architectures`) —
for 32-bit ones, each in its own 32-bit Linux process. The 64-bit Slax kernel runs those: its embedded
config has `IA32_EMULATION=y`.

**Every half is named, because Debian makes most of them optional.** `wine32` is only a *Recommends*
of `wine64`, and both preloaders only *Suggests*; under `--no-install-recommends` a 64-bit Wine that
does not name `wine32:i386` runs no 32-bit Windows program at all, and the build would not say so.
So the step names eight: `wine`, `wine64`, `wine64-preloader`, `libwine`, `wine32:i386`,
`wine32-preloader:i386`, `libwine:i386`, `fonts-wine` — and `build.sh` refuses an image whose
package database lacks `wine64:amd64`, `wine32:i386` or `libwine` for either architecture.

**The Recommends, twice.** The eleven the 32-bit step names are named again for amd64 — the 64-bit
base has the same nine present and the same absentees — and the ten architecture-specific ones again
for **i386**, so 32-bit programs get what the 32-bit image gives them. So do the six the 32-bit base
carries without naming them (`libgl1-mesa-dri`, `libdbus-1-3`, `libkrb5-3`, `libxfixes3`, `libcups2`,
`libgssapi-krb5-2`): absent from this base for i386, so named. `libpulse0:i386` arrives as a hard
Depends of `libwine:i386`. 8 + 11 + 10 + 6 = 35 names.

**Never `:i386` on an architecture-all package** (`wine`, `fonts-wine`, `fonts-liberation`). After the
install the engine checks every name with `dpkg-query -W` as written, and an arch-all package is not
found as `:i386`, so the step would fail after a successful install.

**Lockstep.** A `Multi-Arch: same` library must be the same version on both architectures. The base
dates from October 2023 and apt installs today's i386 copies, so it lifts each amd64 twin to match,
and every package pinned to one of those follows: 79 packages on this build, among them glibc,
systemd and udev, util-linux, e2fsprogs and OpenSSL ([DECISIONS.md](../DECISIONS.md) D-16 lists
more, and `packages.tsv` every version). The 32-bit step upgrades one package, `libgnutls30`.

Against `slax-64bit-debian-12.2.0.iso`:

```
removed 05-chromium.sb (-79 MiB)
skip step 1 (bundle.packages): when arch==32bit is false [arch=64bit, flavour=debian]
unpacked 01-core.sb + 01-firmware.sb + 02-xorg.sb + 03-desktop.sb + 04-apps.sb as the build root
added foreign architecture i386
verified installed: wine, wine64, wine64-preloader, libwine, wine32:i386, wine32-preloader:i386,
  libwine:i386, fonts-wine, ... (all 35)
delta: 9196 added, 2226 modified, 10966 kept after exclusions
dpkg fragment: 329 package(s) declared (merged into 98-dpkg-db.sb at pack time)
built slax/modules/20-wine.sb (477060 KiB, 10120 files)
```

| | |
|---|---|
| `20-wine.sb` | 488,513,536 B — **465.9 MiB**, against 166.6 MiB on the 32-bit base |
| apt's closure | **60 new amd64 packages, 190 i386 ones, 79 base packages upgraded** — the fragment's 329 |
| merged database | **825 entries**, from `04-apps`' 575 plus the fragment's 250 new ones; **816 installed** |
| binaries present | `/usr/bin/wine`, `/usr/lib/wine/wine64`, `/usr/lib/wine/wine64-preloader`, `/usr/lib/wine/wine` and `/usr/lib/wine/wine-preloader` (i386) |
| `/var/lib/dpkg/arch` | ships in this bundle, listing `amd64` and `i386` |

## What this bundle alone does not prove

Packages in the right place are not a working Wine — that takes a desktop boot, and the tests that
produce it live in [`notepadpp32`](notepadpp32.md) and [`notepadpp64`](notepadpp64.md). This page
inherits its status from those observations rather than from anything checkable at build time; see
the ladder in the [cookbook index](README.md).

| you want | use |
|---|---|
| the launcher, and Wine's environment defaults | [`wine-desktop`](wine-desktop.md) |
| a Windows program to test it with | [`notepadpp32`](notepadpp32.md), and [`notepadpp64`](notepadpp64.md) on 64-bit |
| ISO identity and a checksum | [`slax-wine-iso`](slax-wine-iso.md) |
| to know where the image's size goes | [sizing.md](../sizing.md) |
