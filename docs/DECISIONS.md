# Decisions

One entry per choice. Each states the decision, the alternatives actually measured, the evidence,
and **what would change the answer** — that last field is the point of the file, because slax-kitchen
and Debian both move.

The complete reference is [ARCHITECTURE.md](ARCHITECTURE.md); this is why it looks like that.

---

## D-1 · Wine 8.0 from Debian bookworm main

Four sources were priced by i386 `.deb` size, because compressed payload is what costs ISO space
([the prices](measurements.md#deb-wine-sources)):

| source | version | `.deb` | extra apt config |
|---|---|---|---|
| **Debian bookworm main** | 8.0 | the second largest | **none** |
| Debian bullseye | 5.0.3 | by far the smallest | archive.debian.org source + one foreign package |
| WineHQ bookworm | 6.0.4 | smaller than bookworm's | third-party repo + GPG key, installs to `/opt` |
| WineHQ bookworm | 10.0 / 11.0 | the largest | same |

Bullseye is dramatically smaller because Debian 11 built Wine ELF-only, before the PE-builtin
transition. It is also **EOL and frozen**, so builds would depend on an archived suite.

Bookworm is the only zero-configuration option: Slax's own `/etc/apt/sources.list` already carries
`bookworm main contrib non-free non-free-firmware` for the release, `-security` and `-updates`. It is
`oldstable`, supported into 2028.

**What would change this:** bookworm reaching EOL, or a Wine regression that matters for the target
applications. WineHQ 6.0.4 is the fallback with the best size/recency trade.

## D-2 · Drop Chromium

`05-chromium.sb` ([its size](measurements.md#l32-chromium)) is **about half** what Wine costs
([`20-wine.sb`](measurements.md#l32-wine)), not "almost exactly" it — so removing the browser takes back about
half of Wine's cost, and the image still ends up well over stock. At the time, before the firmware
(D-18), that net was the Wine bundles alone; it is now [`net-slax32-wine`](measurements.md#net-slax32-wine).
(An earlier draft of this entry claimed an image barely over stock, from a planning estimate that
turned out wrong: [`est-wine-bundle`](measurements.md#est-wine-bundle).) The browser in stock Slax is chromium 117 from September 2023 in any case — the
largest attack surface in the image, with the shortest security half-life.

**What would change this:** wanting a browser more than the space it costs. slax-kitchen's
`chromium-current` recipe installs a current one — its cookbook page measures the bundle
**on debian-64bit** ([`est-chromium-current`](measurements.md#est-chromium-current)), where the net is small
because it replaces the stock browser. Here there is nothing to replace, so budget the whole
bundle and expect the 32-bit figure to differ.

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

We followed the reasoning rather than working around it. Every profile lists upstream's
**`remove-bundle` before anything that builds**, each spelling out `drop: "^05-chromium\.sb$"` —
three profiles when this was written, eight today. The five shipped ones list it first; the three
test profiles put `serial-console`, which builds no bundle, ahead of it. That restates the recipe's
own default deliberately: the pattern decides which bundle leaves the image, and a default that
decides what ships should not be inherited silently across a pin bump — the same rule this project
already applies to `wine.yaml`'s apt keys. Upstream spells it out in all four of its own profiles
for the same reason. The removal is now performed by upstream's recipe rather than by a copy of its
logic. The cost is that the ordering argument is no longer visible in the file that depends on it,
so `wine.yaml` carries it as a comment and `ci/checks/96-release-consistency.sh` §5(a3) asserts
every shipped profile — two then, five today — lists `remove-bundle` *before* any building recipe.
The core-list comparison in §5(b) reads only `recipes/available/` paths, and `remove-bundle` is
named rather than pathed because it is upstream's.

**This has already happened.** Upstream added the stack/removal conflict check
([UPSTREAM.md](UPSTREAM.md) issue 1, `68879d9`), and the three bypasses we then reported as issue 11
are closed by `997a9ab` — it is seeded from the journal so it survives separate invocations, and
`--skip-preflight` no longer disables it. Removal-first alone would now suffice.

**What would change this:** nothing pending. The explicit `from:` stays as belt-and-braces — it
documents the stack and protects anyone building against an engine older than the pin — at the price
of hard-failing if any named bundle is ever renamed.

**Changed at the `3a44e8a` bump: `wine.yaml` no longer names its stack.** The two places above that
keep the explicit list — the end of the second paragraph and *What would change this* — describe the
decision as it stood until then; the rest stands. Once the list was held up as what it was — a
workaround for issue 1, and listed as one in [UPSTREAM.md](UPSTREAM.md) § *Local workarounds* —
neither of its reasons survived:

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
`30-notepadpp.sb` (as `30-notepadpp32.sb` was named then) and `98-dpkg-db.sb` by type, mode, owner,
size, link target and sha256, and the five PulseAudio paths are still in `20-wine.sb`. The default
stack left `05-chromium` out exactly as the named one did.

## D-4 · No Wine Mono, no Wine Gecko

Debian packages neither — not in main, contrib or non-free. Satisfying Wine's first-run prompt would
mean fetching [Mono and Gecko](measurements.md#mono-gecko-download) from winehq at runtime, on an image usually offline. `WINEDLLOVERRIDES`
suppresses the prompt instead.

**Cost, stated in [using-wine.md](using-wine.md):** .NET applications and Wine's embedded HTML
control do not work.

**What would change this:** a target application needing .NET. The MSIs can be added to the prefix on
a persistent stick without rebuilding.

## D-5 · Bundles at 20/21/30/31

slax-kitchen's canonical table allocates `00`–`09` to the platform, **`10`–`89` to forks**, `90`–`97`
to headroom, and refuses `98` (generated database) and `99` (`savechanges`). Inside the fork band this
project uses `20`–`29` for its platform and `30`–`89` for applications, starting at `20` rather than
`10` because the bottom of the fork band is where slax-kitchen's example recipes sit — and **that set
grows**: `10`–`12` when this was written, `10`–`16` today. Ceding the low end costs nothing and makes
a collision structurally impossible rather than merely unlikely.

The application band holds `30-notepadpp32` on every slax-wine image and `31-notepadpp64` beside it on
the 64-bit ones (D-16).

An earlier draft used `07`/`08`, which are slax-kitchen's. Reading the convention back to upstream is
what prompted them to consolidate four disagreeing statements into one table.

**What would change this:** upstream re-drawing the bands. Since projects now build on these images,
moving a bundle across the split would break them as well
([building-on-slax-wine.md](building-on-slax-wine.md#bundle-numbers)).

## D-6 · The installers, not the portable builds

A portable `.exe` proves Wine can load a PE binary and open a window. The NSIS installer additionally
exercises the installer runtime, registry writes, file creation inside the prefix and shortcut
generation — much closer to what a game needs. Each installer is staged under a stable name, so
updating Notepad++ touches `build.env` and nothing else.

Two installers since D-16: the x86 one (`notepadpp32`) on every image and the x64 one (`notepadpp64`)
on the 64-bit ones. Measured, the x64 installer is itself PE32, an NSIS stub; what it installs is
x86-64.

It cannot run at build time: `bundle.script`'s chroot has no `/proc` and `wineboot` needs it. So the
bundle ships the installer and the live system runs it — which doubles as the persistence
demonstration, since a non-persistent boot must repeat it.

**What would change this:** an application with no installer, or one whose installer needs a
component Wine lacks.

## D-7 · Fetch the payload, do not commit it

**Committing it would be refused.** `ci/checks/00-no-binaries.sh` has refused `*.exe` since
slax-kitchen fixed its #19 in `6ecf019`, which reached this repository with the `8adfca6` bump
(`3f8ad2d`), and in any capitalisation since it fixed its #47 in `030fe3e`, taken at `b4eb25b`. This
entry said the opposite — *"Nothing forbids committing it — `.exe` is not a forbidden extension"* —
which was true of our copy of that gate when it was written, on the morning of 2026-09-18, and
stopped being true the same afternoon. [slax-wine#3](https://github.com/Fullaxx/slax-wine/issues/3)
found it.

That was never the reason, and the reason stands. The payload is fetched because **slax-arcade needs
the same mechanism for software that cannot be published at all**, and one contract across both
projects is worth more than build-time self-containment. The proprietary case becomes "point it at a
local path instead of a URL".

**What it cost, until the `4a10303` bump:** the engine's publishing procedure could not account for
the installers. `bundle.files` copies each from `notepadpp32.files/` or its 64-bit twin, which
`build.sh` fills and git ignores, so `kitchen sources` found a file the project commit did not hold,
and refused the image
([the record](UPSTREAM.md#measured-at-7664625-a-project-built-on-our-images-and-kitchen-sources-on-them)).
That cost is gone. Since slax-kitchen `18bedc5` (#62), `kitchen sources` is a report that refuses
nothing, and names each installer as something the recipe copied in; `bd899fd` (#61) removed the
steps that refused. Each installer's recipe entry also names Notepad++'s repository as its
`upstream_source`, so each image's `SOURCES.md` lists it as a prebuilt part pointing there.

**What would change this:** needing a build with no network at all.

## D-8 · No `isohybrid`. `uefi-bootable` — **reversed**, and the original reasoning had a hole

**`isohybrid`: still not applied, and the argument stands.** A `dd`'d image is a read-only ISO9660
filesystem booted through `isolinux.cfg`, where persistence is `MENU DISABLED` — so the one route it
enables is the one that cannot keep a Wine prefix.

**`uefi-bootable`: now applied, in the `-uefi` profiles** — and what it does is **narrower** than this
entry first claimed on reversing; the correction is the useful part.

The original entry called it unnecessary because *"`bootinst.sh` … relocates the EFI loader, giving
BIOS **and** UEFI boot from an ordinary ISO."* True, and incomplete: the loader `bootinst` relocates
is `syslinux.efi`, which reads **FAT only**, so "UEFI boot" there silently meant "from a FAT32
stick" — the filesystem that caps persistence at a 16 GB container.

**The first rewrite then over-corrected**, claiming GRUB's ext4 support let "UEFI and unlimited
persistence coexist". **That is false, and boot-testing the image is what exposed it.** `uefi-bootable`
puts GRUB in an El Torito ESP at `/boot/efi.img` — an *ISO* structure. A stick has no El Torito
catalog, `bootinst` never copies it, and `slax/boot/EFI/Boot/` (what `bootinst` *does* relocate) is
**byte-for-byte identical in a base's two images**. Verified by diffing the artifacts, for each
pair.

So what the uefi image actually buys is: **the ISO boots on UEFI firmware** — optical media, or a
virtual CD — which stock Slax cannot do at all (upstream's `known-upstream-bugs.md` entry 1). It
changes nothing about sticks. Measured 2026-09-18: GRUB under x86-64 OVMF boots the 32-bit image to
`Live Kit done`.

That is less than the previous paragraph claimed, and anyone planning a USB install should read it as
"no difference". Each base ships a bios image and a uefi one (D-16); the uefi one is a superset,
larger by [the ESP](measurements.md#esp).

**This entry has now been wrong twice, both times about what the loader actually reaches**, and both
times the error survived review and was caught by measurement. Its original "what would change this"
predicted a read-only demo stick, which never happened. Treat predictions here as weaker evidence
than the tables in `docs/50-cookbook/`.

It adds [an ESP](measurements.md#esp), and the one component this project builds rather than redistributes: a
GRUB loader, **GPLv3+**, whose source package each sidecar names (see [NOTICE.md](../NOTICE.md)).

**What would change this:** `bootinst` learning to install a GRUB ESP on a stick, or `syslinux.efi`
gaining ext4 support — either would make UEFI-on-ext4 real, which it currently is not. Upstream
shipping a `bootia32.efi` would extend the uefi images to 32-bit UEFI firmware.

## D-9 · No `perchsize` in the recipe

The FAT32 perch container has a 16 GB floor that cannot be lowered, its size is fixed at creation,
and the right value depends on a stick the ISO knows nothing about. Worse, persistence is enabled by
a bare **substring** match on `perch`, so an unscoped `perchsize=` would switch persistence on for
the `toram` entry — which unmounts the medium. It belongs at the boot prompt, per stick.

**What would change this:** nothing. This is a per-medium decision by construction.

## D-10 · No `firmware-refresh`, but say so loudly — **reversed** by D-18

**Reversed on 2026-09-28:** every image now carries `firmware-refresh`, for its hardware and for
its licence files ([D-18](#d-18--refresh-the-firmware-and-ship-its-licences)). What follows is the
original reasoning, kept because its numbers were wrong in an instructive way: the recipe costs
well under the estimate ([`est-firmware`](measurements.md#est-firmware)), and it is still not tested on hardware
that needs it.

Stock Slax ships **no GPU firmware at all** — no `amdgpu`, `i915`, `radeon` or `nouveau`. A modern
AMD card does not initialise without `amdgpu`; Intel loses GuC/HuC. Under Wine that means software
rendering.

Not applied for v1.0.0: it was estimated to cost [this much](measurements.md#est-firmware), it is not
boot-tested on affected hardware upstream, and Notepad++ needs no GPU. It is called out in
[using-wine.md](using-wine.md) and [measurements.md](measurements.md#what-could-shrink-it) because someone benchmarking a game and silently getting llvmpipe would waste
days.

**What would change this:** any 3D application — which means a games variant should apply it first,
at bundle `09`, and budget ~600 MiB.

## D-11 · No `initramfs.busybox`

The shipped busybox is 1.26.2 from 2017, with reachable CVEs. slax-kitchen can replace it. Not done
here: it changes the initramfs, the one component whose failure mode is an unbootable image, and this
project has no security claim that depends on it.

**What would change this:** shipping slax-wine somewhere the initramfs is exposed to untrusted input.

## D-12 · Publish the ISOs, with pointers to their source

**Decided 2026-09-26, replacing "attach source for everything identifiable".** We publish all five
images, and we attach no source to a release:

- **What we change is in this repository**, at the commit each image's provenance sidecar records:
  the recipes, the files beside them, the boot-menu edits, the launchers, `build.sh`. The engine that
  ran them is slax-kitchen, at the commit the sidecar also records.
- **What we do not change is pointed to.** No upstream program is modified here, so each part's own
  upstream is where its source is: each image's `SOURCES.md`, from `kitchen sources`, and the table
  in [NOTICE.md](../NOTICE.md) say where.
- **No written offer.** It was there for the three static initramfs binaries whose source nobody
  could name. slax-kitchen's NOTICE.md now records what Slax's own parts are, the kernel's aufs
  revision and configuration included, and points at their upstream, and ours points at that.

This is also slax-kitchen's own policy since `bd899fd` (#61): an image travels with `SHA256SUMS` and
its provenance sidecar, what the build changed is in the repositories, and whoever publishes decides.
So a release goes through its procedure, as commands: [Cutting a release](build.md#cutting-a-release).

**What the old entry said, and why it went.** It attached source as release assets for everything
identifiable, citing GPLv2 §3's "from the same place", with a written offer for the three static
binaries and an upstream issue for their provenance. That issue was never filed: the finding was
dropped because upstream already documented the gap
([Two findings were dropped](UPSTREAM.md#two-findings-were-dropped-before-filing-in-round-one)).
Attaching would have meant [Debian's whole source for Wine](measurements.md#src-wine) alone, a
kernel patch revision nobody had then identified, and the Flathub runtimes' source for slax-bottles.

The GRUB EFI loader in the uefi images and slax-bottles is the one thing built here, from the build
host's unmodified GRUB, and it is **GPLv3+**. Each sidecar names the package and version it came
from, so its source is identifiable the same way as everything else.

**What would change this:** modifying an upstream program, whose modified source would then live
here, or an obligation a pointer cannot meet.

## D-13 · `build.sh`, not `kitchen build`

**The reason this entry gave went stale at the `8adfca6` bump, and stayed here until `b4eb25b`.**
It said `kitchen build` runs `iso_assert.py` with no `--volid`, so a custom volume id plus `test:`
always fails. That was true when it was written, at the first pin, `9776a90`, and at `bcd4f00`
after it. slax-kitchen `6419fa4` (2026-09-17) made `kitchen build` pass the recipes' volume id and
gave `kitchen test` a `--volid` — this entry's own trigger — and every pin since has carried it.
Found reviewing slax-kitchen #42, which had repeated the claim; LAYERING.md now says the same of
both.

What keeps `build.sh` is what the engine cannot know about, and none of it is a workaround:

- the application payloads, fetched and checked before apply — each Notepad++ installer by sha256,
  and Bottles, whose version and refs `build.sh` records rather than checks (D-20);
- each image's exact module list, which the structure test's `--require` and `--forbid` cannot
  express together: these bundles, and nothing else;
- the release file read back out of the bundle that shipped it, and both halves of Wine in the
  64-bit package database;
- a size ceiling per image, and one `build.env` holding the version, both bases and every
  payload pin.

It calls `kitchen` commands for what the engine does — `fetch`, `unpack`, `apply`, `pack`, and
`test --structure` — as LAYERING.md asks of a project's own driver. The structure test went through
a `kitchen` command last: until the `4a10303` bump `build.sh` ran `iso_assert.py` itself, because
`kitchen test --structure` took no size ceiling and no `--require`. slax-kitchen `ce5d51a` (#67)
added both.

**What would change this:** `kitchen build` running a project's own checks after `pack` — the exact
module list, the release file read back, both halves of Wine — which would leave `build.sh` only the
payloads to fetch.

## D-14 · slax-bottles: a second system on the 64-bit base, with no Debian Wine

**Bottles is x86-64 only.** It ships only as a Flatpak (its docs: *"We currently only offer
Bottles as a flatpak package"*), its Flathub manifest is `"only-arches": ["x86_64"]`, and Debian
packages it in no suite at all, so it cannot go on the 32-bit base. slax-kitchen's pinned
`sources.yaml` carries `debian-64bit-12.2.0`, and `slax-bottles` is built on that — the base the
`slax64-wine` images now share (D-16).

**And it carries no Debian Wine.** The obvious plan was slax-wine's recipes plus Bottles. It does
not work: Bottles runs inside the Flatpak sandbox and uses its own runners, so it cannot see
`/usr/bin/wine`, and a `20-wine` bundle would be Wine that nothing uses — [all of it](measurements.md#l64-wine) on this
base (D-16). Our other recipes do not transfer either. `notepadpp32` requires `wine-desktop`, which
requires `wine`, so naming either one pulls in Debian's Wine. What does transfer is upstream's:
`remove-bundle`, `uefi-bootable`, `serial-console` and `testkit`, all unchanged. From
`slax-wine-iso` we copied two steps, the automount removal and the checksum, into
`slax-bottles-iso`, rather than giving a recipe the slax-wine images depend on a branch for another
product. (D-16 later gave `slax-wine-iso` a step per base — for slax-wine itself, one product on two
bases.)

So this is **a different system**, not another variant of slax-wine. Gate 96 §5(b), which holds
the slax-wine profiles to one recipe list, deliberately does not compare it. §5(a3) does hold it to
removal-first.

**One image**, built uefi-bootable, so it boots BIOS and UEFI (D-8).

**What would change this:** a Bottles that can use the system's Wine — a Debian package rather than
the Flatpak — which would make `slax64-wine` plus Bottles one system instead of two. An i386 build
(its Flathub manifest allows x86_64 only today) would extend that to `slax32-wine`.

## D-15 · Bottles baked into the image, not installed on first run

The alternative was shipping only `flatpak` plus a launcher that runs `flatpak install` on first
use: a small ISO, but it needs a network, and without persistence it has to be repeated every boot.
That is the opposite of what a live stick for Windows programs is for, so the whole installation
ships in `30-bottles.sb`.

**How it gets there.** `build.sh` installs Bottles from Flathub on the **host**, into a user
installation that it points at `recipes/available/bottles.files/var/lib/flatpak`, and `bottles.yaml`
copies that tree in. It is not installed in the build chroot: `flatpak install` runs its triggers
through `bwrap`, and the chroot has an empty `/proc` and no user namespace. A user installation and
the system one have the same layout, so the live system (everything runs as root) sees an ordinary
system-wide install.

**The pin — superseded by [D-20](#d-20--let-bottles-and-its-runtimes-float-record-what-shipped),
which pins nothing.** As first decided: a single sha256 cannot describe a Flatpak installation, so
the pin is `BOTTLES_LOCK` in `build.env`: every ref the install pulls in (13 of them) with its
ostree commit. `build.sh` deploys each one at its locked commit and checks the result in both
directions: every locked ref is present at its commit, and nothing is installed that the lock does
not name. Flathub does not keep old commits forever, so a pin can go stale. When it does, the build
fails with a message saying so. It never quietly takes whatever is current.

**What it costs.** The GNOME 50 runtime, 64- and 32-bit Mesa, the i386 compat runtime, codecs, and
Wine Gecko and Mono: [the whole tree, unpacked](measurements.md#flatpak-tree). See
[measurements.md](measurements.md#inside-30-bottlessb) for the measured bundle. That
last pair is a bonus over slax-wine: Flathub **does** package Gecko and Mono (D-4 says Debian does
not), so .NET and embedded-HTML programs have a chance in a bottle that they do not have under
slax-wine.

**What does not ship.** `xdg-desktop-portal`, a `flatpak` Recommends, is dropped along with the
others. Slax runs Fluxbox, not a portal-aware desktop. How much Bottles' file access misses it has
not been measured; [using-bottles.md](using-bottles.md) gives the `flatpak override` that widens
the sandbox.

**Baking in the Flatpak was not enough; DXVK and VKD3D had to ship too.** Measured on the first
build, with no network: Bottles opens, and its wizard offers "Skip Setup". But `bottles-cli new`
then fails with *"Missing essential components … tried 3 times"*, although the Flatpak carries its
own runner (`sys-wine-11.0`). Bottles' `components_check` requires a runner, a DXVK and a VKD3D,
and it finds the last two by listing directories under its data dir. So `build.sh` fetches the
newest stable of each from the URLs Bottles' own components index names (`dxvk-3.1`,
`vkd3d-proton-3.0.1`, pinned by sha256 in `BOTTLES_COMPONENTS`), and `30-bottles.sb` ships them
unpacked under `/root/.var/app/com.usebottles.bottles/data/bottles/`. With them present, the same
command creates a bottle offline, and `notepad.exe` runs in it.

**What would change this:** the ISO size mattering more than working offline. The first-run
installer is a small recipe away.

## D-16 · slax-wine is four ISOs

slax-wine ships **bios and uefi images on each of the two bases**, the same system on all four:

| image | base | boots |
|---|---|---|
| `slax32-wine-bios` | `debian-32bit-12.2.0` | BIOS |
| `slax32-wine-uefi` | `debian-32bit-12.2.0` | BIOS, and 64-bit UEFI |
| `slax64-wine-bios` | `debian-64bit-12.2.0` | BIOS |
| `slax64-wine-uefi` | `debian-64bit-12.2.0` | BIOS, and 64-bit UEFI |

That is the whole decision, and it is not argued: the set is consistent, so that anyone can pick
whichever image they want, for any reason. Everything below is how it is built.

**One set of recipes on both bases.** `wine`, `wine-desktop` and `slax-wine-iso` carry one step per
base, guarded by `when: arch==32bit` or `arch==64bit` — upstream's own pattern (`enable-ssh`,
`memtest86plus`, `locale-timezone-keyboard`). Copies would have cascaded, because `notepadpp32`
requires `wine-desktop`, which requires `wine`. Gate 96 §5(b) holds the profiles of each base to one
recipe list, and the 64-bit list to the 32-bit one plus `notepadpp64`; §5(c) holds each profile's name
to its base and firmware.

**Notepad++ in both widths.** `notepadpp32`, the x86 installer, is on all four images; `notepadpp64`,
the x64 installer, on the two slax64 ones. Measured: the x64 installer is itself PE32, an NSIS stub,
and installs x86-64 binaries — so its tile runs a 32-bit installer under WoW64 before it runs a 64-bit
program. Every name of each — recipe, bundle, `/opt` directory, installer, command, tile, `build.env`
variables — carries its 32 or 64.

**The 64-bit Wine is both halves.** Debian's 8.0~repack-4 runs a 32-bit Windows program in a separate
32-bit Linux process, `wine32`, and makes that package only a *Recommends* of `wine64`: under
`no_recommends`, a 64-bit Wine that does not name it runs no 32-bit program at all. `wine.yaml`'s
64-bit step names `wine64`, `wine32:i386`, `libwine` for both architectures and both preloaders, and
`build.sh` refuses an image whose package database lacks `wine64`, `wine32:i386` or `libwine` for
either architecture. The kernel supports the 32-bit half: the 64-bit base's `/slax/boot/vmlinuz`
embeds its configuration, which has `IA32_EMULATION=y`, `MODIFY_LDT_SYSCALL=y`, `X86_16BIT=y` and
`X86_ESPFIX64=y`. Debian's `/usr/bin/wine` starts the 32-bit loader whenever `wine32` is installed,
and Wine hands a 64-bit program to `wine64` itself — measured, the x64 Notepad++ runs as a 64-bit
process, while `wine cmd` is the 32-bit `cmd` ([using-wine.md](using-wine.md#on-slax64-wine)).

**i386 parity.** 32-bit programs get what the 32-bit image gives them: the step names an i386 copy of
every library slax32's Wine has, whether named there or already in its base. The amd64 list is the
32-bit step's, name for name — measured, the 64-bit base has the same nine of those libraries, and
lacks the same ones (`libpulse0`, `fonts-liberation`, `libasound2-plugins`, `libvulkan1`).

**No `WINEARCH` on the 64-bit base.** New prefixes are win64, and 32-bit programs run in them through
`wine32`. A user's own `WINEARCH=win32` makes a 32-bit prefix instead, and the `slax-wine` wrapper,
which re-sources `/etc/profile.d/wine.sh`, passes it through. slax32 keeps `WINEARCH=win32`.

**Lockstep, measured.** A `Multi-Arch: same` library must be the same version on both architectures.
The base's amd64 packages date from October 2023 and apt installs today's i386 ones, so apt lifts
each amd64 twin to match, and every package pinned to one of those follows. Measured on this build:
**[base packages](measurements.md#count-wine64-lifted)**, every one an upgrade within bookworm, shipped in `20-wine.sb` — glibc
(`libc6`, `libc-bin`, `locales`: `2.36-9+deb12u3` → `+deb12u14`), systemd and udev (252.17 → 252.39,
with `libsystemd0`, `libudev1` and `libpam-systemd`), util-linux with `mount` and its libraries,
e2fsprogs, OpenSSL (3.0.11 → 3.0.20), Mesa, krb5, GnuTLS, GLib, libxml2, libcurl, FreeType, libpng
and libtiff among them. The full list is every **amd64 or `all`** row of the image's `packages.tsv` whose version
differs from `04-apps`'. slax32 has one such upgrade, `libgnutls30`. So slax64-wine boots a newer
systemd and glibc than stock Slax — its boot tests are what show that still boots — and with
`noload=20-wine.sb` its package database claims versions whose files are not loaded.

**Measured sizes:** [`20-wine.sb`](measurements.md#l64-wine), against [the 32-bit base's](measurements.md#l32-wine);
[`31-notepadpp64.sb`](measurements.md#l64-notepadpp64); [slax64-wine-bios](measurements.md#iso-slax64-wine-bios) and
[slax64-wine-uefi](measurements.md#iso-slax64-wine-uefi), [the firmware](measurements.md#firmware-total) in each (D-18). See
[measurements.md](measurements.md#slax64-wine).

**What would change this:** Debian shipping a Wine built for the new WoW64, which runs 32-bit Windows
code inside a 64-bit process — it would need no i386 libraries, and the lockstep would go away. A
bookworm point release changes the lockstep set, which the next build's `packages.tsv` lists.

## D-17 · One prefix, and the flip is a choice

On `slax64-wine-*` both Notepad++ tiles run with no `WINEPREFIX` set, so both use `/root/.wine`:
one 64-bit prefix, which is the point of a 64-bit image. **Notepad++'s own installers remove each
other** — install the x64 build and the x86 one is gone, and the other way round. Our launchers do
not do this and cannot stop it; each simply looks where its own build lives, finds nothing, and runs
its installer again.

**The prefix stays single.** One Windows running both widths is what a 64-bit image demonstrates,
and [testing-on-both.md](testing-on-both.md) uses that one prefix to show a 32-bit program and a
64-bit one in the same place. A second prefix would end the flip and cost **[a whole 64-bit prefix](measurements.md#prefix-win64) of RAM** on a
non-persistent boot, plus another first-run creation — a steep price for a test application.

**So the flip is made a choice.** When a launcher's own build is missing *and* the other one is
present, it asks before running the installer that will remove it, with the `xmessage` the image
already ships. **Cancel is the default**, because a stray Return should not pick the answer that
removes something, and Cancel exits 0 saying nothing more — the "cancelled or failed" message that
follows an installer is wrong after a deliberate decline.

**And it asks only where there is somewhere to ask.** `DISPLAY` being set is not the same as a
display that opens: Slax's desktop is on `:1`, so a stale `:0` gets *"Can't open display"* from
every GUI program in the image. The first version treated that like a decline and exited 0 in
silence — measured, with nothing installed and nothing said, which is the failure this file's own
`fail()` exists to prevent. The condition now runs `xset q` first, and when it cannot ask it says so
and exits 1. What it suggests instead is the *cheap* prefix where there is one: a second 64-bit
prefix costs [its size](measurements.md#prefix-win64), a 32-bit one for the 32-bit build
[less than half that](measurements.md#prefix-win32-slax64).

**The trap, and the reason this is a decision rather than a patch:** the check must be conditioned on
the prefix being 64-bit — `drive_c/windows/syswow64` — because in a **win32** prefix the x86 build
owns `Program Files` itself, the same directory the x64 build owns in a 64-bit one. Without that
condition slax32 would announce that installing Notepad++ is about to remove Notepad++. That
negative is worth more than the positive here, and it is tested as such.

**What would change this:** Notepad++ installers that coexist, or a prefix cheap enough to give each
build its own. `WINEPREFIX=$HOME/.wine-npp64 notepadpp64` is that second prefix today, and the dialog
names it.

## D-18 · Refresh the firmware, and ship its licences

**Decided 2026-09-26, built 2026-09-28.** Every profile lists upstream's `firmware-refresh`
directly after `remove-bundle`. It builds two bundles:

- **`09-firmware-debian.sb`** ([size](measurements.md#l32-firmware-debian)): Debian's current firmware packages
  ([how many](measurements.md#count-firmware)). Among them are those the stock
  image lacks — among them `firmware-amd-graphics`, `firmware-misc-nonfree` (Intel `i915`, NVIDIA),
  `firmware-intel-sound` and `firmware-sof-signed` — and nine of the ten stock ones, reinstalled at
  the versions Slax already had. Each brings back the `copyright` file Slax's build removed. `firmware-ipw2x00` is left alone, because its licence prompt would stop the install, and
  its `ipw2x00.LICENSE` is already in the stock image.
- **`09-firmware-linux.sb`** ([size](measurements.md#l32-firmware-linux)): [files](measurements.md#count-firmware) from
  linux-firmware at a pinned tag, each checked
  against its sha256, with the licence files linux-firmware's `WHENCE` names for them (eleven,
  under `usr/lib/firmware/LICENSES/`) and `WHENCE` itself.

**Why.** Two reasons, either enough on its own:

- **Hardware.** Stock Slax has no GPU firmware at all, so a modern AMD card does not initialise,
  Intel loses GuC/HuC, and 3D falls back to llvmpipe. Laptops that use Sound Open Firmware have no
  audio. For an image meant to run Windows programs, and one day games, that is the wrong default.
- **Licences.** Slax's build strips every firmware package's `copyright` file. What the images add
  now carries its terms, which is what the release policy asks of firmware
  ([D-12](#d-12--publish-the-isos-with-pointers-to-their-source)). Stock `01-firmware.sb` is shipped
  as Slax ships it, and its Broadcom b43 files never had a licence text.

**What it costs.**
- **Size:** [the firmware](measurements.md#firmware-total) on every image, measured. The ceilings in `build.env`
  moved with it ([Size caps](measurements.md#size-caps)).
- **Build:** a chroot step, apt, and [a download per linux-firmware file](measurements.md#count-firmware) from GitLab or git.kernel.org, which fail the
  build rather than ship a partial set.
- **Package database:** [more packages](measurements.md#count-firmware). `/usr`, `/usr/lib` and `/usr/share` become 0755 in the
  running system where stock had 0775, because `20-wine.sb` and `20-flatpak.sb` now build on top of
  the firmware bundles and record those directories as they find them.

**Not tested on hardware that needs it.** slax-kitchen boot-verified the recipe in QEMU, and our
twelve boot routes run on these images before the release; whether an AMD card initialises or SOF
audio plays on a real machine is untested here and upstream. A card
that does initialise may run a real Mesa driver instead of llvmpipe, which no test here has seen.

**What would change this:** an image too large for its medium, or firmware whose terms the
publisher cannot accept, which `remove-bundle` with `drop: 09-firmware` answers per build.


## D-19 · Release from a tag, by Actions, into a draft

**Decided 2026-09-28.** Pushing `v$VERSION` runs `.github/workflows/release.yml` on GitHub's hosted
runners:
- it runs every gate;
- it builds the five shipped images and the three test images from the tagged commit;
- it boots each test image through the four routes;
- it uploads the 32 assets to a **draft** release, with `SHA256SUMS` and generated notes.

A person reads the draft and publishes it. The procedure is [Cutting a release](build.md#cutting-a-release).

**Why.** A release by hand was a checklist of nine steps, any of which could be skipped without
anything failing, and the images went up through one person's connection ([all of a release](measurements.md#release-assets)). The
workflow does the same steps in the same order every time, from a fresh checkout of the tag, and a
runner uploads the images. Every step is a script in `ci/`, so a release can still be staged by hand, and the scripts
are tested without Actions (`tests/unit/test_release.py`).

**Alternatives weighed:**
- **Publishing at once, with no draft.** The most hands-off, but a bad build would be public until
  somebody deleted it. With a draft, a person reading the notes and the assets costs a minute.
- **A self-hosted runner** on the build machine, or on the boot host for KVM. The repository is
  public, and a self-hosted runner there runs code from whoever can trigger it, as root, since the
  build needs a chroot. Hosted runners are thrown away after each job.
- **A local command.** It could boot under KVM on the boot host, but it runs only where that host
  is reachable, and uploads from there. It survives as *By hand*, in build.md.

**What it costs.**
- **KVM is not promised.** A hosted runner's `/dev/kvm` is not writable by the job's account until
  a udev rule opens it, and nothing guarantees the device is there at all. Upstream's CI booted
  under TCG until slax-kitchen `a9008a5`, which opens it with the rule this workflow uses. The
  runners of the first rehearsal (2026-09-29) had it, and the 64-bit jobs boot under it; the
  workflow fails a job that wants KVM and still cannot write the device. The 32-bit job does not
  use it: under the runner's KVM its guest stopped after `Live Kit init` on all four routes,
  while the same image boots under KVM on the boot host, and the cause is not established. So it boots under TCG by choice, as every 32-bit boot here did before the boot host.
  Under TCG a boot is [several times slower](measurements.md#boot-tcg) than [under KVM](measurements.md#boot-kvm), with the UEFI menu
  keys spelled out
  ([UPSTREAM.md](UPSTREAM.md#measured-and-deliberately-not-filed-the-uefi-keystroke-lead-under-tcg)).
  Booting under KVM on the boot host before tagging stays in the procedure, as an optional step.
- **Disk.** A hosted runner promises less than a slax-bottles build needs
  ([`disk-bottles-build`](measurements.md#disk-bottles-build)): it stages [the Flatpak](measurements.md#disk-stage) and packs
  two [ISOs](measurements.md#iso-slax-bottles). So each build job first removes the runner's preinstalled SDKs,
  which leaves [plenty](measurements.md#runner-disk).
- **A runner's build is not a local build's twin.** The PVD timestamps and squashfs mtimes are not
  pinned ([measurements.md](measurements.md#why-a-rebuild-moves-bytes)), so every build has its own sha256. What is pinned is the same
  everywhere: the bases, the engine, the Notepad++ and DXVK/VKD3D payloads by sha256, and the
  Bottles version. The Debian packages are not, and nor are the Flatpak runtimes under Bottles
  (D-20): apt installs bookworm, and Flathub serves its runtimes, as they stand on the day of the
  build, so an update between two builds changes a version. Each image's `packages.tsv` and
  slax-bottles' `.flatpak.txt` record what its build got.
- **Trust.** Three `actions/*` actions, at the Node 24 versions upstream checked, run with write
  access to releases. Nothing from a fork can trigger the workflow, since it has no `pull_request`
  trigger.

**What would change this:** runners that guarantee KVM, which would make the optional KVM step
redundant; an image over [the asset limit](measurements.md#cap-github), which `BOTTLES_MAX_ISO_MIB` would hit first; or
a Bottles update that breaks something only a person running it would notice (D-20).

## D-20 · Let Bottles and its runtimes float, record what shipped

**Decided 2026-09-29.** Nothing of the Flatpak installation is pinned. `build.sh` installs what
Flathub's stable channel serves on the day of the build: Bottles, and under it the GNOME runtime,
the Freedesktop GL and codec extensions, and Wine's Mono and Gecko. It records what it got. The
Bottles version and every ref with its commit go into `/opt/bottles/VERSION` in the image, and into
the release's `.flatpak.txt`, and the release notes name the Bottles version from there. This
replaces D-15's pin.

**What happened.** D-15 pinned [every ref](measurements.md#count-flatpak-refs) by ostree commit in `BOTTLES_LOCK`, on 2026-09-18. The
first rehearsal of the release workflow (D-19), on 2026-09-29, could not build slax-bottles.
Flathub answered HTTP 404 for `org.gnome.Platform//50` at the locked commit. GNOME had published an
update of the same runtime, and Flathub had pruned the files of the commit it replaced. The commit's
log entry was still there, but not its content. The build machine here still built, because its
stage held the old commit. A runner starts from nothing.

**Why nothing can be pinned here.** A pin is only worth having if it can be honoured later.
- **No versions.** Flatpak installs a channel (`stable`) or a commit, never a version, so "Bottles
  67.3" can only be asked for as the commit that happens to be 67.3.
- **Commits get pruned.** Flathub keeps the current commit of each ref and prunes the old ones'
  files on its own schedule; [the GNOME one did not last long](measurements.md#flathub-commit-life).
- **Every release starts from nothing.** It is built on a fresh runner, so any commit pin, Bottles'
  included, would break at random between releases. It could never rebuild an old release either,
  which is what a pin usually buys.

So the published image is the durable record of what shipped, with its `.flatpak.txt`. A version
check without a pin was tried first, and refused unless Flathub served exactly `BOTTLES_VERSION`.
It could not ask for that version, only notice its absence, so it was dropped the same day.

**Whose job consistency is.** Flathub's model is that its stable channel is what it ships: an app
and the runtimes it names are built, tested and published together, and a consumer cannot ask for
anything else. So keeping Bottles and its runtimes consistent with each other is Flathub's job, and
upstream's, not ours. We take what the channel serves, record exactly what that was, and deal with
problems as they come up. When one does, the fix is the optional lock below, and this entry is
updated with what bit, and why.

**What is still refused.**
- **The wrong languages.** A locale subset other than `BOTTLES_LANGUAGES` fails the build.
- **A stale stage.** A stage that Flathub has anything newer for, compared ref by ref, is installed
  again from nothing, not updated in place. Measured on the same GNOME update, `30-bottles.sb`
  updated in place came out larger, and with more files, than installed fresh
  ([`bottles-inplace`](measurements.md#bottles-inplace)). `flatpak update` keeps the replaced commit's objects, because the new commit names
  the old one as its parent, so not even `flatpak repair` prunes them, and they would have shipped.
  `flatpak remote-ls --updates` did not notice a ref moved back with `update --commit`, so the
  comparison is `flatpak remote-info` against each deployed commit.
- **A Flathub that cannot be asked.** The build fails before the stage is touched; `--no-fetch`
  builds from the stage as it is.
- **A static version claim.** Gate 96 refuses a `BOTTLES_VERSION=` line in
  `/etc/slax-bottles-release`, which now points at `/opt/bottles/VERSION` instead.

**What it costs.**
- **Two builds can ship different Bottles.** Builds a week apart can ship different Bottles
  versions, not only different runtime builds, as two builds already ship different Debian security
  updates.
- **The docs name what was measured.** Where they say Bottles 67.3, that is the version the
  measurement was taken on. What a release ships is in its notes and its `.flatpak.txt`.
- **A new Bottles is not re-checked by hand.** The by-hand offline check (a bottle created,
  `cmd /c ver`) was measured on 67.3 and the 2026-09-18 runtimes, and nothing re-runs it for a new
  version. The release workflow boots the image that ships, but it never starts Bottles.
- **DXVK and VKD3D stay pinned.** They are chosen from the components index Bottles 67.3 named, by
  sha256 in `BOTTLES_COMPONENTS`, so a Bottles that wants others still gets these.

**The lock stays, for when it bites.** `BOTTLES_LOCK` set in `build.env` still forces every ref to
its commit and refuses a stage that differs in either direction. It is how a known-good set is held
while a broken Bottles or runtime is sorted out upstream, and how one build is tested against
another. It only holds while Flathub still serves those commits, so it is a stopgap, not a pin. A
release leaves it empty unless this entry says why not. `BOTTLES_RELOCK=1` prints Flathub's current
refs in that form.

**What would change this:** the first time it bites: a Flathub update that breaks Bottles in the
image. Then the lock holds the last good set, and this entry records it. Beyond that, Flathub
keeping old commits, or a copy of our own: exporting the installation at each release and building
from that copy would pin everything and rebuild any release. It was weighed on 2026-09-29, and not
taken.

## D-21 · One register for measurements, and links everywhere else

Every number this project has measured lives in [measurements.md](measurements.md), one row per
quantity with how and when it was measured. Every other page links to the row and does not repeat
the number.

**Why.** Before this, the numbers were copied wherever they were useful. An audit on 2026-09-30
found most quantities stated in three to ten places, and about fifteen of those copies disagreeing
with each other: rounded figures that no longer matched, a 32-bit prefix size in the wrong image's
column, two TCG timings for one boot, and an upload size off by a gigabyte. Nothing compared any of
them with a build. The only check, gate 96 §6, grepped every page for the `TBD-MEASURED`
placeholder, and on the first tag it matched the page that defines the marker and refused the
release. A number that has to be found across thirty files before it can be checked is not checked.

**The rules**, spelled out at the top of the register:
- **Links only.** A page that needs a number links its row and says what it is. When a number
  moves, it changes once.
- **The placeholder goes only in the register,** and gate 96 §6 reads only the register on a tag.
- **Dated records are exempt:** [UPSTREAM.md](UPSTREAM.md), released CHANGELOG entries, the
  cookbook's command transcripts, and `ci/` comments about the gates' own speed. Each is what was
  true when it was written, not a claim about now.
- **So is text an image shows its user.** A launcher's dialog cannot link a row, and there the
  number is the point: the Notepad++ launchers say how much RAM a second prefix costs. Its row
  names where it is quoted, so a change to one is a change to both.
- **Config is not a measurement.** The caps and base sizes stay in `build.env`, and the register
  says which measurement each cap came from.

**How a row is checked.** A row whose "re-measure" cell names a build-summary line is compared
with a build by `ci/measure-check.sh`, which the release procedure runs after the local builds. It
is a **report, not a gate**: a rebuild moves bytes by a squashfs block, and slax-bottles takes
whatever Flathub serves that day (D-20), so a difference is something to read and, if it is real,
to write into the register. The rows it cannot compare (timings, memory, the Flatpak refs) are
re-measured by hand, as each row says.

**What it costs.**
- **Pages read less directly.** "The image ([size](measurements.md#iso-slax-bottles))" is one
  click further from the number than "the 1299.4 MiB image".
- **Links-only is kept by review, not by a gate.** A gate that looked for numbers outside the
  register would trip on versions, timeouts and stick sizes, and false positives train people to
  ignore it. What is gated is that every link to a row resolves (gate 60).

**What would change this:** the register growing past what one page can hold, or a check that can
tell a measurement from any other number without false positives.
