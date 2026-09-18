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

## D-3 · Remove first, in a recipe of its own

The engine's `from:` default is now every bundle below the one being built, which for `20-wine`
includes `05-chromium`. Building against it and then deleting it produces an image whose
`libwine.so` has an unsatisfiable hard dependency on `libpulse0` — measured: absent from
`01-core`…`04-apps`, present in `05-chromium.sb`.

Removal-first fixes it by making the default correct. The explicit `from:` list is kept as well, so
reordering the steps cannot reintroduce the bug.

**The removal no longer lives in `wine.yaml`, and that is now a rule rather than a preference.**
`cc8a664` (in the `8adfca6` bump) added a `lib/validate.py` rule that refuses a recipe mixing
`bundle.remove` with anything that builds: *"a recipe that removes or renumbers a bundle does
nothing else. Put the removal in its own recipe — `remove-bundle` takes a `drop:` pattern — and list
that first."* Our recipe did exactly that and stopped validating.

We followed the reasoning rather than working around it. All three profiles now list upstream's
**`remove-bundle` first**, each spelling out `drop: "^05-chromium\.sb$"`. That restates the recipe's
own default deliberately: the pattern decides which 81.7 MiB leaves the image, and a default that
decides what ships should not be inherited silently across a pin bump — the same rule this project
already applies to `wine.yaml`'s apt keys. Upstream spells it out in all four of its own profiles
for the same reason. The removal is now performed by upstream's recipe rather than by a copy of its
logic. The cost is that the ordering argument is no longer visible in the file that depends on it,
so `wine.yaml` carries it as a comment and `ci/checks/96-release-consistency.sh` §5(a3) asserts both
shipped profiles list `remove-bundle` *before* any building recipe — the core-list comparison in
§5(b) reads only `recipes/available/` paths, and `remove-bundle` is named rather than pathed because
it is upstream's.

**This has already happened.** Upstream added the stack/removal conflict check
([UPSTREAM.md](UPSTREAM.md) issue 1, `68879d9`), and the three bypasses we then reported as issue 11
are closed by `997a9ab` — it is seeded from the journal so it survives separate invocations, and
`--skip-preflight` no longer disables it. Removal-first alone would now suffice.

**What would change this:** nothing pending. The explicit `from:` stays as belt-and-braces — it
documents the stack and protects anyone building against an engine older than the pin — at the price
of hard-failing if any named bundle is ever renamed.

**Changed at the `3a44e8a` bump: `wine.yaml` no longer names its stack.** Everything above stands
except that last paragraph. Once the list was held up as what it was — a workaround for issue 1, and
listed as one in [UPSTREAM.md](UPSTREAM.md) § *Local workarounds* — neither of its reasons survived:

- **The order has two guards without it.** The engine refuses a removal that follows a build, across
  the whole plan and across separate invocations, and gate 96 §5(a3) refuses a shipped profile that
  lists `remove-bundle` late. A third statement of the same rule added nothing either lacks.
- **"An engine older than the pin" cannot build this repo.** `build.sh` runs the vendored engine,
  and gate 20 holds `vendor/` byte-identical to the pin.
- **A named stack has a failure of its own.** It goes stale the moment a bundle is added below 20,
  and then — upstream's `verbs.md` — apt reinstalls libraries the image already has, and those copies
  shadow the originals. The default cannot drift that way, and it is what 34 of upstream's 35
  recipes use.

Proved by building rather than argued: with the list gone, all three images came out with the same
contents as the `337f7e7` builds. That covers every entry of `20-wine.sb`, `21-wine-desktop.sb`,
`30-notepadpp.sb` and `98-dpkg-db.sb` by type, mode, owner, size, link target and sha256, and the
five PulseAudio paths are still in `20-wine.sb`. The default stack left `05-chromium` out exactly as
the named one did.

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

**`uefi-bootable`: now applied, in `profiles/slax-wine-uefi.yaml`** — for a **narrower** reason than
this entry first claimed on reversing, and the correction is the useful part.

The original entry called it unnecessary because *"`bootinst.sh` … relocates the EFI loader, giving
BIOS **and** UEFI boot from an ordinary ISO."* True, and incomplete: the loader `bootinst` relocates
is `syslinux.efi`, which reads **FAT only**, so "UEFI boot" there silently meant "from a FAT32
stick" — the filesystem that caps persistence at a 16 GB container.

**The first rewrite then over-corrected**, claiming GRUB's ext4 support let "UEFI and unlimited
persistence coexist". **That is false, and boot-testing the image is what exposed it.** `uefi-bootable`
puts GRUB in an El Torito ESP at `/boot/efi.img` — an *ISO* structure. A stick has no El Torito
catalog, `bootinst` never copies it, and `slax/boot/EFI/Boot/` (what `bootinst` *does* relocate) is
**byte-for-byte identical in both images**. Verified by diffing the two artifacts.

So what the uefi image actually buys is: **the ISO boots on UEFI firmware** — optical media, or a
virtual CD — which stock Slax cannot do at all (upstream's `known-upstream-bugs.md` entry 1). It
changes nothing about sticks. Measured 2026-09-18: GRUB under x86-64 OVMF boots the 32-bit image to
`Live Kit done`.

That is still worth a second image — it is a superset for 6.2 MiB, and it fixes a real upstream
limitation — but it is worth less than the previous paragraph claimed, and anyone planning a USB
install should read it as "no difference".

**This entry has now been wrong twice, both times about what the loader actually reaches**, and both
times the error survived review and was caught by measurement. Its original "what would change this"
predicted a read-only demo stick, which never happened. Treat predictions here as weaker evidence
than the tables in `docs/50-cookbook/`.

It is not free: a 6.2 MiB ESP and the image's only GPLv3 component (see [NOTICE.md](../NOTICE.md)) —
which is why it is a second image rather than a change to the first.

**What would change this:** `bootinst` learning to install a GRUB ESP on a stick, or `syslinux.efi`
gaining ext4 support — either would make UEFI-on-ext4 real, which it currently is not. Upstream
shipping a `bootia32.efi` would extend both images to 32-bit UEFI firmware.

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
