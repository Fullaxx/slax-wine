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
mean fetching ~136 MiB from winehq at runtime, on an image usually offline. `WINEDLLOVERRIDES`
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

**What would change this:** upstream re-drawing the bands.

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

Nothing forbids committing it — `.exe` is not a forbidden extension and GitHub's limit is 100 MB. It
is fetched because **slax-arcade needs the same mechanism for software that cannot be published at
all**, and one contract across both projects is worth more than build-time self-containment. The
proprietary case becomes "point it at a local path instead of a URL".

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
6.2 MiB larger.

**This entry has now been wrong twice, both times about what the loader actually reaches**, and both
times the error survived review and was caught by measurement. Its original "what would change this"
predicted a read-only demo stick, which never happened. Treat predictions here as weaker evidence
than the tables in `docs/50-cookbook/`.

It adds a 6.2 MiB ESP, and the image's only GPLv3 component (see [NOTICE.md](../NOTICE.md)).

**What would change this:** `bootinst` learning to install a GRUB ESP on a stick, or `syslinux.efi`
gaining ext4 support — either would make UEFI-on-ext4 real, which it currently is not. Upstream
shipping a `bootia32.efi` would extend the uefi images to 32-bit UEFI firmware.

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

The uefi images add an obligation the bios ones do not have: their GRUB ESP is **GPLv3+**, built at
release time from the build host's GRUB rather than redistributed as upstream shipped it. `build.sh`
records that GRUB's version on a `grub (ESP)` line in each uefi image's build summary
(`out/build-summary-32-uefi.txt`, `-64-uefi`, `-bottles`) so the corresponding source is
identifiable — the same standard the rest of this entry holds everything else to.

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

## D-14 · slax-bottles: a second system on the 64-bit base, with no Debian Wine

**Bottles is x86-64 only.** It ships only as a Flatpak (its docs: *"We currently only offer
Bottles as a flatpak package"*), its Flathub manifest is `"only-arches": ["x86_64"]`, and Debian
packages it in no suite at all, so it cannot go on the 32-bit base. slax-kitchen's pinned
`sources.yaml` carries `debian-64bit-12.2.0`, and `slax-bottles` is built on that — the base the
`slax64-wine` images now share (D-16).

**And it carries no Debian Wine.** The obvious plan was slax-wine's recipes plus Bottles. It does
not work: Bottles runs inside the Flatpak sandbox and uses its own runners, so it cannot see
`/usr/bin/wine`, and a `20-wine` bundle would be Wine that nothing uses — 465.9 MiB of it on this
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

**The pin.** A single sha256 cannot describe a Flatpak installation, so the pin is `BOTTLES_LOCK`
in `build.env`: every ref the install pulls in (13 of them) with its ostree commit. `build.sh`
deploys each one at its locked commit and checks the result in both directions: every locked ref
is present at its commit, and nothing is installed that the lock does not name. Flathub does not keep
old commits forever, so a pin can go stale. When it does, the build fails with a message saying so.
It never quietly takes whatever is current.

**What it costs.** The GNOME 50 runtime, 64- and 32-bit Mesa, the i386 compat runtime, codecs, and
Wine Gecko and Mono take 3.2 GB unpacked. See [sizing.md](sizing.md) for the measured bundle. That
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
**79 base packages**, every one an upgrade within bookworm, shipped in `20-wine.sb` — glibc
(`libc6`, `libc-bin`, `locales`: `2.36-9+deb12u3` → `+deb12u14`), systemd and udev (252.17 → 252.39,
with `libsystemd0`, `libudev1` and `libpam-systemd`), util-linux with `mount` and its libraries,
e2fsprogs, OpenSSL (3.0.11 → 3.0.20), Mesa, krb5, GnuTLS, GLib, libxml2, libcurl, FreeType, libpng
and libtiff among them. The full list is every **amd64 or `all`** row of the image's `packages.tsv` whose version
differs from `04-apps`'. slax32 has one such upgrade, `libgnutls30`. So slax64-wine boots a newer
systemd and glibc than stock Slax — its boot tests are what show that still boots — and with
`noload=20-wine.sb` its package database claims versions whose files are not loaded.

**Measured sizes:** `20-wine.sb` 465.9 MiB, against 166.6 MiB on the 32-bit base; `31-notepadpp64.sb`
6.5 MiB; slax64-wine-bios 815.6 MiB and slax64-wine-uefi 821.7 MiB. See [sizing.md](sizing.md).

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
64-bit one in the same place. A second prefix would end the flip and cost **1,265 MiB of RAM** on a
non-persistent boot, plus another first-run creation — a steep price for a test application.

**So the flip is made a choice.** When a launcher's own build is missing *and* the other one is
present, it asks before running the installer that will remove it, with the `xmessage` the image
already ships. **Cancel is the default**, because a stray Return should not pick the answer that
removes something, and Cancel exits 0 saying nothing more — the "cancelled or failed" message that
follows an installer is wrong after a deliberate decline. With no display there is nobody to ask, so
nothing is installed.

**The trap, and the reason this is a decision rather than a patch:** the check must be conditioned on
the prefix being 64-bit — `drive_c/windows/syswow64` — because in a **win32** prefix the x86 build
owns `Program Files` itself, the same directory the x64 build owns in a 64-bit one. Without that
condition slax32 would announce that installing Notepad++ is about to remove Notepad++. That
negative is worth more than the positive here, and it is tested as such.

**What would change this:** Notepad++ installers that coexist, or a prefix cheap enough to give each
build its own. `WINEPREFIX=$HOME/.wine-npp64 notepadpp64` is that second prefix today, and the dialog
names it.
