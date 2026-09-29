# Where the size goes

Measured on the v1.0.0 builds, not estimated. The planning estimate for the first image was **wrong
by about 50 MiB**, and the reason is worth keeping.

## slax32-wine

| | bytes | MiB |
|---|---|---|
| stock `slax-32bit-debian-12.2.0.iso` | 436,060,160 | 415.9 |
| − `05-chromium.sb` | −85,659,648 | −81.7 |
| + `09-firmware-debian.sb` (`firmware-refresh`: Debian's current firmware packages, 26 `copyright` files) | +51,118,080 | +48.8 |
| + `09-firmware-linux.sb` (`firmware-refresh`: 65 files from linux-firmware, with their licences and `WHENCE`) | +5,677,056 | +5.4 |
| + `20-wine.sb` | +174,686,208 | +166.6 |
| + `21-wine-desktop.sb` | +4,096 | +0.004 |
| + `30-notepadpp32.sb` | +6,713,344 | +6.4 |
| + `98-dpkg-db.sb` (generated at pack time) | +143,360 | +0.1 |
| **slax32-wine-bios 1.0.0** | **588,742,656** | **561.5** |
| + `boot/efi.img` (uefi image only — a FAT12 ESP, **not** a bundle), and the `/boot` directory that holds it | +6,488,064 + 2,048 | +6.2 |
| **slax32-wine-uefi 1.0.0** | **595,232,768** | **567.7** |

Net **+152,682,496 bytes** — +145.6 MiB over stock for the bios image, **+159,172,608** / +151.8 MiB
for the uefi one, of which the firmware is 54.2 MiB ([DECISIONS.md](DECISIONS.md) D-18). Both are under
`WINE32_MAX_ISO_MIB=589` (567.7 is the larger), so one cap covers both and no per-variant value is
needed. The uefi image has 21.3 MiB of headroom, the bios image 27.5 MiB.

**These are one build's bytes, and a rebuild does not always land on the same total.** A squashfs
stores an mtime per file and a creation time of its own, so two runs of one tree differ in bytes and
sometimes in size, by a 4 KiB padding block. Measured 2026-09-21 while bumping the engine to
`7f9c4f8`: rebuilding the 2026-09-20 tree gave a 64-bit `20-wine.sb` 4,096 bytes larger and a
`30-bottles.sb` 1,372,160 bytes smaller, with the same 816 and 597 packages at the same versions and
all 13 Flatpak refs at the same commits: the same refs do not mean the same bytes. Since D-20 the
refs under Bottles are not pinned either, so a Flathub update between two builds moves the bundle
too. The slax-wine totals here are from the 2026-09-28 build, the first with the firmware, and the
2026-09-29 rebuild matched them to the byte; slax-bottles' are from 2026-09-29, the first build to
take Flathub's runtimes as served.
`mksquashfs -mkfs-time 0 -all-time 0` would make the squashfs half reproducible, and is not used.

(Every ledger here adds up to the byte. An earlier version put the ESP at +6,488,064 and did not: the
uefi image also gains a root-level `/boot` directory, bios has none, and its extent is one 2 KiB
sector.)

## slax64-wine

The same system on the 64-bit base ([DECISIONS.md](DECISIONS.md) D-16):

| | bytes | MiB |
|---|---|---|
| stock `slax-64bit-debian-12.2.0.iso` | 435,853,312 | 415.7 |
| − `05-chromium.sb` | −82,903,040 | −79.1 |
| + `09-firmware-debian.sb` (`firmware-refresh`: Debian's current firmware packages, 26 `copyright` files) | +51,118,080 | +48.8 |
| + `09-firmware-linux.sb` (`firmware-refresh`: 65 files from linux-firmware, with their licences and `WHENCE`) | +5,677,056 | +5.4 |
| + `20-wine.sb` (both halves of Wine, and 79 base packages lifted to match their i386 twins) | +488,517,632 | +465.9 |
| + `21-wine-desktop.sb` | +4,096 | +0.004 |
| + `30-notepadpp32.sb` | +6,713,344 | +6.4 |
| + `31-notepadpp64.sb` | +6,860,800 | +6.5 |
| + `98-dpkg-db.sb` (generated at pack time) | +143,360 | +0.1 |
| **slax64-wine-bios 1.0.0** | **911,984,640** | **869.7** |
| + `boot/efi.img` and its `/boot` directory | +6,488,064 + 2,048 | +6.2 |
| **slax64-wine-uefi 1.0.0** | **918,474,752** | **875.9** |

`WINE64_MAX_ISO_MIB=919` is the uefi image plus 5%, and covers the bios one too.

**`20-wine.sb` is 2.8 times the 32-bit one**, and not because 64-bit code is bigger: it carries Wine
twice, `libwine` for amd64 and for i386, plus an i386 copy of the libraries 32-bit programs load —
Mesa among them, since the 64-bit base has only its own amd64 Mesa — and the 79 base packages apt
upgraded in lockstep, which ship in this bundle rather than in the base's.

**The ESP is 6.2 MiB, not a few KiB.** `grub-mkstandalone` embeds GRUB's modules into the EFI binary,
which is most of it. Worth stating because the obvious guess — "an ESP is a stub loader" — is wrong
by three orders of magnitude, and this ledger exists to replace guesses with measurements.

**No sha256 is recorded here, deliberately.**

A hash would identify one build, not the version. slax-wine packs with `genisoimage`, which stamps
PVD timestamps it cannot pin — upstream measures the difference as 19 of 212,819 sectors, all of them
timestamp fields, with the payload byte-identical. So two builds of the same tree have the same size,
the same bundles and the same package count, and different hashes. `xorriso --modification-date`
would pin them, at the cost of uppercasing the application id, which carries our version string.

For a download, the authority is the `.sha256` published beside that particular ISO.

## Why the estimate was wrong

The plan predicted a 105–120 MiB Wine bundle by reasoning from Debian's `.deb` sizes: `libwine` is a
91 MiB download for 563 MiB installed, so the compressed payload "should" be about 91 MiB plus
dependencies.

It came out at **166.6 MiB**. The gap is the compression format. A `.deb`'s payload is a *solid*
`.tar.xz` — one stream, so xz's window spans the whole archive. A squashfs bundle is built with
`-b 1024K`, so xz restarts every mebibyte and cannot exploit redundancy across block boundaries.
Wine's payload is thousands of PE modules with a great deal of cross-file similarity, which is
exactly the case that suffers.

The lesson for the app layer: **estimate bundle size from squashfs, not from `.deb` size.** The
rule from this data point is about **1.4×**: the 60 packages the `20-wine` fragment declares total
126,948,952 B (121.1 MiB) of `.deb` download, and the bundle is 174,686,208 B (166.6 MiB) — a ratio
of 1.38. Compare against *everything installed*, not one headline package; dividing the bundle by
`libwine`'s `.deb` alone gives a misleading 1.8×.

## Installed size is not a runtime cost

`libwine` is 563 MiB installed, and that number appears nowhere above. Squashfs holds it compressed
and decompresses on read, so what costs you is the 166.6 MiB in the ledger — including under `toram`,
which copies the compressed bundles into RAM rather than an installed tree.

## What could shrink it

| | saves | cost |
|---|---|---|
| `noload=30-notepadpp32.sb` at boot | a squashfs mount and an aufs branch — **not** 6.4 MiB of RAM: `copy_to_ram` runs at `init:43`, *before* `mount_bundles` at `:46`, and copies unconditionally, so under `toram` the bundle is in RAM either way | no test application |
| drop `01-firmware.sb` | ~91 MiB | no network firmware at all — wifi stops working |
| drop the two absent Recommends | a few MiB | bitmap fonts, and no PulseAudio output from Wine |

The firmware is already in: `firmware-refresh` costs **54.2 MiB** on every image, where D-10 had
estimated 90 ([DECISIONS.md](DECISIONS.md) D-18).

## slax-bottles: where the 1299.4 MiB goes

A different image on a different base ([DECISIONS.md](DECISIONS.md) D-14). Measured on the build of
2026-09-29, with the GNOME 50 runtime Flathub served that day. The 2026-09-18 one, pinned until
[D-20](DECISIONS.md#d-20--let-bottles-and-its-runtimes-float-record-what-shipped), gave 5,124,096
bytes less, all of it in `30-bottles.sb` (889.4 MiB, 1294.5 in all):

| | bytes | MiB |
|---|---|---|
| stock `slax-64bit-debian-12.2.0.iso` | 435,853,312 | 415.7 |
| − `05-chromium.sb` | −82,903,040 | −79.1 |
| + `09-firmware-debian.sb` (`firmware-refresh`: Debian's current firmware packages, 26 `copyright` files) | +51,118,080 | +48.8 |
| + `09-firmware-linux.sb` (`firmware-refresh`: 65 files from linux-firmware, with their licences and `WHENCE`) | +5,677,056 | +5.4 |
| + `20-flatpak.sb` (flatpak and its dependency closure: 36 packages in its dpkg fragment) | +8,372,224 | +8.0 |
| + `30-bottles.sb` (the Flatpak installation, DXVK, VKD3D, launcher) | +937,771,008 | +894.3 |
| + `98-dpkg-db.sb` (generated at pack time) | +135,168 | +0.1 |
| + `boot/efi.img` (the GRUB ESP, not a bundle) and its `/boot` directory | +6,488,064 + 2,048 | +6.2 |
| **slax-bottles 1.0.0** | **1,362,513,920** | **1299.4** |

`BOTTLES_MAX_ISO_MIB=1364` is that plus 5%, the same margin slax-wine uses. DXVK 3.1 and
VKD3D-Proton 3.0.1 account for **16.0 MiB** of the bundle: the build without them came to 874.8 MiB
and 1225.7 MiB.

### Inside `30-bottles.sb`

The Flatpak tree is **3,231 MiB of distinct file data unpacked**, which xz squashes to about 878 MiB
of the bundle. The ostree repo's objects are the same inodes as the deployed files, so this table
counts them once. In the bundle they cost nothing extra either: the copy made while building keeps
the hardlinks since slax-kitchen `f5e6673` (see [build.md](build.md)), and mksquashfs stores a
hardlinked file once, as it stored identical files once before that. Per ref, measured on the staged
tree by inode: "own" counts only the bytes no other ref shares.

| ref | unpacked MiB | own MiB |
|---|---|---|
| `org.gnome.Platform//50` | 976.6 | 974.9 |
| `com.usebottles.bottles//stable` (includes its own Wine 11.0) | 503.5 | 503.3 |
| `org.freedesktop.Platform.Compat.i386//25.08` | 290.6 | 289.2 |
| `org.winehq.Wine.gecko//stable-25.08` | 204.2 | 204.2 |
| `org.winehq.Wine.mono//stable-25.08` | 180.5 | 180.5 |
| `org.freedesktop.Platform.GL32.default` `//25.08` + `//25.08-extra` | 464 each | 92.8 + 92.9 |
| `org.freedesktop.Platform.GL.default` `//25.08` + `//25.08-extra` | 440 each | 88.3 + 88.3 |
| `org.freedesktop.Platform.codecs-extra` + `codecs_extra.i386` | 41.4 + 29.2 | 41.2 + 29.0 |

### What could shrink it

Nothing here has been tried. Each item is a lever with a known cost:

- **Gecko and Mono, ~385 MiB unpacked.** Dropping them brings back slax-wine's position (D-4):
  no .NET, and no embedded HTML.
- **The `-extra` GL branches, ~180 MiB of their own.** Mesa builds with extra video codecs, installed
  alongside the plain ones. Which one flatpak picks at runtime has not been measured.
- **The GNOME runtime cannot go.** Bottles is a GTK 4 / libadwaita app built against it.
