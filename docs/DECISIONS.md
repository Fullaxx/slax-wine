# Decisions

One entry per choice. Each states the decision, the alternatives actually measured, the evidence,
and **what would change the answer** — that last field is the point of the file, because slax-kitchen
and Debian both move.

The complete reference is [ARCHITECTURE.md](ARCHITECTURE.md); this is why it looks like that.

---

## D-1 · Wine 8.0 from Debian bookworm main

Four sources were priced by i386 `.deb` size, because compressed payload is what costs ISO space:

| source | version | `.deb` | extra apt config |
|---|---|---|---|
| **Debian bookworm main** | 8.0 | ~91 MiB | **none** |
| Debian bullseye | 5.0.3 | ~24 MiB | archive.debian.org source + one foreign package |
| WineHQ bookworm | 6.0.4 | ~72 MiB | third-party repo + GPG key, installs to `/opt` |
| WineHQ bookworm | 10.0 / 11.0 | ~99–103 MiB | same |

Bullseye is dramatically smaller because Debian 11 built Wine ELF-only, before the PE-builtin
transition. It is also **EOL and frozen**, so builds would depend on an archived suite.

Bookworm is the only zero-configuration option: Slax's own `/etc/apt/sources.list` already carries
`bookworm main contrib non-free non-free-firmware` for the release, `-security` and `-updates`. It is
`oldstable`, supported into 2028.

**What would change this:** bookworm reaching EOL, or a Wine regression that matters for the target
applications. WineHQ 6.0.4 is the fallback with the best size/recency trade.

## D-2 · Drop Chromium

`05-chromium.sb` is 81.7 MiB. That is **about half** what Wine costs, not "almost exactly" it —
Wine is 166.6 MiB — so removing the browser keeps the image at 507 MiB rather than 589 MiB, and the
net is still **+91.4 MiB over stock**. (An earlier draft of this entry claimed ~35 MiB over stock,
from a planning estimate `docs/sizing.md` retracts as wrong by about 50 MiB.) The browser in stock Slax is chromium 117 from September 2023 in any case — the
largest attack surface in the image, with the shortest security half-life.

**What would change this:** wanting a browser more than 82 MiB. slax-kitchen's `chromium-current`
recipe installs a current one — its cookbook page measures the bundle at 114 MiB **on
debian-64bit**, where the net is +35 MiB because it replaces the stock browser. Here there is
nothing to replace, so budget the full +114 MiB and expect the 32-bit figure to differ.

## D-3 · Remove first, and name `from:` anyway

The engine's `from:` default is now every bundle below the one being built, which for `20-wine`
includes `05-chromium`. Building against it and then deleting it produces an image whose
`libwine.so` has an unsatisfiable hard dependency on `libpulse0` — measured: absent from
`01-core`…`04-apps`, present in `05-chromium.sb`.

Removal-first fixes it by making the default correct, which is the idiom `chromium-current` uses. The
explicit `from:` list is kept as well, so reordering the steps cannot reintroduce the bug.

**This has already happened.** Upstream added the stack/removal conflict check
([UPSTREAM.md](UPSTREAM.md) issue 1, `68879d9`), and the three bypasses we then reported as issue 11
are closed by `997a9ab` — it is seeded from the journal so it survives separate invocations, and
`--skip-preflight` no longer disables it. Removal-first alone would now suffice.

**What would change this:** nothing pending. The explicit `from:` stays as belt-and-braces — it
documents the stack and protects anyone building against an engine older than the pin — at the price
of hard-failing if any named bundle is ever renamed.

## D-4 · No Wine Mono, no Wine Gecko

Debian packages neither — not in main, contrib or non-free. Satisfying Wine's first-run prompt would
mean fetching ~136 MiB from winehq at runtime, on an image usually offline. `WINEDLLOVERRIDES`
suppresses the prompt instead.

**Cost, stated in [using-wine.md](using-wine.md):** .NET applications and Wine's embedded HTML
control do not work.

**What would change this:** a target application needing .NET. The MSIs can be added to the prefix on
a persistent stick without rebuilding.

## D-5 · Bundles at 20/21/30

slax-kitchen's canonical table allocates `00`–`09` to the platform, **`10`–`89` to forks**, `90`–`97`
to headroom, and refuses `98` (generated database) and `99` (`savechanges`). Inside the fork band this
project uses `20`–`29` for its platform and `30`–`89` for applications, starting at `20` rather than
`10` because the bottom of the fork band is where slax-kitchen's example recipes sit — and **that set
grows**: `10`–`12` when this was written, `10`–`16` today. Ceding the low end costs nothing and makes
a collision structurally impossible rather than merely unlikely.

An earlier draft used `07`/`08`, which are slax-kitchen's. Reading the convention back to upstream is
what prompted them to consolidate four disagreeing statements into one table.

**What would change this:** upstream re-drawing the bands.

## D-6 · The installer, not the portable build

A portable `.exe` proves Wine can load a PE binary and open a window. The NSIS installer additionally
exercises the installer runtime, registry writes, file creation inside the prefix and shortcut
generation — much closer to what a game needs. It also makes updating two edits in `build.env`.

It cannot run at build time: `bundle.script`'s chroot has no `/proc` and `wineboot` needs it. So the
bundle ships the installer and the live system runs it — which doubles as the persistence
demonstration, since a non-persistent boot must repeat it.

**What would change this:** an application with no installer, or one whose installer needs a
component Wine lacks.

## D-7 · Fetch the payload, do not commit it

Nothing forbids committing it — `.exe` is not a forbidden extension and GitHub's limit is 100 MB. It
is fetched because **slax-arcade needs the same mechanism for software that cannot be published at
all**, and one contract across both projects is worth more than build-time self-containment. The
proprietary case becomes "point it at a local path instead of a URL".

**What would change this:** needing a build with no network at all.

## D-8 · No `isohybrid`. `uefi-bootable` — **reversed**, and the original reasoning had a hole

**`isohybrid`: still not applied, and the argument stands.** A `dd`'d image is a read-only ISO9660
filesystem booted through `isolinux.cfg`, where persistence is `MENU DISABLED` — so the one route it
enables is the one that cannot keep a Wine prefix.

**`uefi-bootable`: now applied, in `profiles/slax-wine-uefi.yaml`.** The original entry said it was
unnecessary because *"`bootinst.sh` installs extlinux, writes the MBR and relocates the EFI loader,
giving BIOS **and** UEFI boot from an ordinary ISO."* Every clause of that is true. What it left out
is the clause that mattered: **the loader `bootinst` relocates is `syslinux.efi`, which reads FAT
only.** So "UEFI boot from an ordinary ISO" silently meant "UEFI boot *from a FAT32 stick*" — and
FAT32 is exactly the filesystem that caps persistence at a 16 GB dynfilefs container.

The entry was therefore arguing to protect persistence with a premise that quietly forfeited it.
Adopting `uefi-bootable` brings GRUB, which **reads ext4**, so UEFI and unlimited persistence can
coexist for the first time.

Worth recording precisely because **the stated trigger never fired.** "What would change this"
predicted a read-only demo stick; no one ever wanted one. The thing that actually changed the answer
was noticing a constraint the entry had not written down. A "what would change this" line is a
prediction, and this one was wrong in a way worth keeping visible — the next entry's prediction may
be too.

It is not free: `uefi-bootable` costs a 6.2 MiB GRUB ESP and introduces the image's only GPLv3
component (see [NOTICE.md](../NOTICE.md)). That is why it is a second image rather than a change to
the first — the bios image stays byte-identical in size and stock in its boot path.

**What would change this:** upstream shipping a `bootia32.efi`, which would make 32-bit UEFI firmware
reachable and might justify collapsing back to one image; or `syslinux.efi` gaining ext4 support,
which would remove the reason for the split entirely.

## D-9 · No `perchsize` in the recipe

The FAT32 perch container has a 16 GB floor that cannot be lowered, its size is fixed at creation,
and the right value depends on a stick the ISO knows nothing about. Worse, persistence is enabled by
a bare **substring** match on `perch`, so an unscoped `perchsize=` would switch persistence on for
the `toram` entry — which unmounts the medium. It belongs at the boot prompt, per stick.

**What would change this:** nothing. This is a per-medium decision by construction.

## D-10 · No `firmware-refresh`, but say so loudly

Stock Slax ships **no GPU firmware at all** — no `amdgpu`, `i915`, `radeon` or `nouveau`. A modern
AMD card does not initialise without `amdgpu`; Intel loses GuC/HuC. Under Wine that means software
rendering.

Not applied for v1.0.0: it costs +90 MiB, it is not boot-tested on affected hardware upstream, and
Notepad++ needs no GPU. It is called out in [using-wine.md](using-wine.md) and
[sizing.md](sizing.md) because someone benchmarking a game and silently getting llvmpipe would waste
days.

**What would change this:** any 3D application — which means a games variant should apply it first,
at bundle `09`, and budget ~600 MiB.

## D-11 · No `initramfs.busybox`

The shipped busybox is 1.26.2 from 2017, with reachable CVEs. slax-kitchen can replace it. Not done
here: it changes the initramfs, the one component whose failure mode is an unbootable image, and this
project has no security claim that depends on it.

**What would change this:** shipping slax-wine somewhere the initramfs is exposed to untrusted input.

## D-12 · Publish the ISOs, with the licence gap documented

slax-kitchen publishes no image, because the GPLv2 source-offer obligation cannot be fully discharged
for three static binaries with no recorded version or build config. We publish anyway, attach source
as release assets for everything identifiable, and state the gap plainly in [NOTICE.md](../NOTICE.md)
with a written offer. An upstream issue asks for the missing provenance.

Two images now, and the uefi one adds an obligation the bios one does not have: its GRUB ESP is
**GPLv3+**, built at release time from the build host's GRUB rather than redistributed as upstream
shipped it. `build.sh` records that GRUB's version on a `grub (ESP)` line in
`out/build-summary-uefi.txt` so the corresponding source is identifiable — the same standard the rest
of this entry holds everything else to.

**What would change this:** upstream answering that issue — which closes the gap for every Slax
derivative, not just this one.

## D-13 · `build.sh`, not `kitchen build`

One reason remains of the original three: `kitchen build` runs `iso_assert.py` with no `--volid`
while `--volid` defaults to `slax` and `lib/build.sh` never passes it, so a custom volume id plus
`test:` always fails. (An argparse default, not a hardcoded constant — the effect is the same, but
the fix upstream is one flag, not a code change.) The other two
dissolved when profiles became authoritative — `apply --profile` runs no tests, and the output name
is chosen at `pack`.

**What would change this:** `kitchen test` gaining a `--volid` flag.
