# Where the 507 MiB goes

Measured on the v1.0.0 build, not estimated. The planning estimate was **wrong by about 50 MiB**, and
the reason is worth keeping.

## The ledger

| | bytes | MiB |
|---|---|---|
| stock `slax-32bit-debian-12.2.0.iso` | 436,060,160 | 415.9 |
| − `05-chromium.sb` | −85,659,648 | −81.7 |
| + `20-wine.sb` | +174,686,208 | +166.6 |
| + `21-wine-desktop.sb` | +4,096 | +0.004 |
| + `30-notepadpp.sb` | +6,713,344 | +6.4 |
| + `98-dpkg-db.sb` (generated at pack time) | +131,072 | +0.1 |
| **slax-wine 1.0.0** | **531,935,232** | **507.3** |

Net **+95,875,072 bytes** — +91.4 MiB over stock.

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
| `noload=30-notepadpp.sb` at boot | a squashfs mount and an aufs branch — **not** 6.4 MiB of RAM: `copy_to_ram` runs at `init:43`, *before* `mount_bundles` at `:46`, and copies unconditionally, so under `toram` the bundle is in RAM either way | no test application |
| drop `01-firmware.sb` | ~91 MiB | no network firmware at all — wifi stops working |
| drop the two absent Recommends | a few MiB | bitmap fonts, and no PulseAudio output from Wine |

And what would grow it: slax-kitchen's `firmware-refresh` adds **+90 MiB** for the GPU firmware stock
Slax ships none of. Not applied here — Notepad++ needs no GPU — but a games variant will want it, and
should budget ~600 MiB. See [DECISIONS.md](DECISIONS.md).
