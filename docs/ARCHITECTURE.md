# Architecture

What slax-wine is and how every part works, at the level of detail needed to change it safely a year
from now. Why it looks like this is [DECISIONS.md](DECISIONS.md); how we raise engine problems is
[UPSTREAM.md](UPSTREAM.md).

---

## The shape of the thing

slax-wine owns no engine code. It is seven recipes, eight profiles, a build script and thirteen gates,
laid over `slax-kitchen` pinned as a submodule at `vendor/slax-kitchen`. The eight images those
profiles build, what they hold in common and where they part, are in
[variants.md](variants.md).

```
build.env          version + base identity (both bases) + the Bottles pin -- the single source of truth
profiles/          eight: slax32-wine-bios, -uefi, slax64-wine-bios, -uefi and slax-bottles ship;
                   the three -test ones do not
recipes/available/ seven recipes: five for slax-wine, two for slax-bottles
build.sh           fetch -> stage -> unpack -> apply -> pack -> assert -> measure
ci/                thirteen gates; seven copied verbatim, five adapted, one ours
tests/unit/        four tests: the .desktop trap that once cost both launchers (adapted), the
                   gate library that let a .exe and then a submodule bump through (verbatim),
                   gate 80 itself, which once let a test write into the commit running it
                   (verbatim), and gate 96 (ours): its pin read, which once answered for this
                   repo, and the sections that hold four images to one recipe list
vendor/            the engine, pinned by commit
```

`kitchen apply --profile` takes the recipe list *and* any per-recipe var overrides from the profile,
so there is exactly one place that says what each image is. A recipe named by no profile is never
built — `ci/checks/96-release-consistency.sh` fails on an orphan for that reason.

### Four shipped images, one system

slax-wine is bios and uefi images on each of two bases ([DECISIONS.md](DECISIONS.md) D-16):
`slax32-wine-bios` and `-uefi` on `debian-32bit-12.2.0`, `slax64-wine-bios` and `-uefi` on
`debian-64bit-12.2.0`. All four run **upstream's `remove-bundle` and then `wine`, `wine-desktop`,
`notepadpp32` and `slax-wine-iso`, in that order**; the 64-bit ones add `notepadpp64`. `wine`,
`wine-desktop` and `slax-wine-iso` carry one step per base, guarded by `when: arch==32bit` or
`arch==64bit`, so one recipe list builds both. The uefi profiles add upstream's `uefi-bootable`
last, which builds no bundle and writes a single 6.2 MiB `boot/efi.img` — a FAT12 ESP holding GRUB.
So a base's two images carry identical bundles, nine on 32-bit and ten on 64-bit, and share one
module-list assertion in `build.sh`.

Two consequences worth holding onto:

- **A uefi image is a superset.** `pack.sh` adds its EFI entry with `-eltorito-alt-boot`, leaving
  the BIOS entry in place. `xorriso -report_el_torito` on the artifacts shows `isolinux.bin` in all
  four and `/boot/efi.img` only in the uefi ones. It boots anywhere its bios twin does.
- **What it buys is a UEFI-bootable ISO, and only that.** Stock Slax cannot boot on UEFI at all
  (upstream's `known-upstream-bugs.md` entry 1); `uefi-bootable` fixes that for the **ISO** — optical
  media, or a virtual CD. It does **nothing** for a USB stick: its GRUB lives in an El Torito ESP at
  `/boot/efi.img`, an ISO structure that `bootinst` never copies, and the directory `bootinst` *does*
  relocate — `slax/boot/EFI/Boot/` — is byte-for-byte identical in a base's two images. So sticks
  use the stock FAT-only `syslinux.efi` either way, and UEFI-on-a-stick still means FAT32 for all.
  See [INSTALL.md](../INSTALL.md).

Ordering is load-bearing: `uefi-bootable` generates its GRUB menu by *parsing* `isolinux.cfg`, so it
must run after `slax-wine-iso`, which edits that file. Its pack hint (`uefi`) is a different key from
`slax-wine-iso`'s (`volid`, `appid`, `checksums`), so the two cannot overwrite one another.

### And slax-bottles, a different system

`slax-bottles` is **not** a variant of the four above. Bottles exists only as an x86_64 Flatpak, so
it is built on `debian-64bit-12.2.0`, and it carries **no Debian Wine**: Bottles runs sandboxed with
its own runners and could not use ours ([DECISIONS.md](DECISIONS.md) D-14). Its profile is
`remove-bundle`, [`bottles`](50-cookbook/bottles.md), [`slax-bottles-iso`](50-cookbook/slax-bottles-iso.md),
`uefi-bootable`, which gives eight bundles: the five stock survivors, `20-flatpak`, `30-bottles` and
`98-dpkg-db`.

What it shares with slax-wine is the machinery, not the software: the engine pin, `VERSION`,
`build.sh` (a per-variant `variant_config` picks base, module list, size ceiling and payload), the
gates, and upstream's `remove-bundle` and `uefi-bootable`. Its Flatpak payload is staged on the
**host** by `build.sh`, pinned ref-by-ref (`BOTTLES_LOCK`), and copied in by `bundle.files`. See the
cookbook page for why it is not installed in the build chroot.

## The layer model

Slax's root filesystem is a union of numbered squashfs bundles. **Load order is the numeric prefix
and higher wins**, because `union_append_bundles` inserts each bundle at aufs branch index 1, so each
arrival outranks the last.

That is the whole mechanism. It is not a naming convention laid over something else.

| bundle | ships | may be switched off with |
|---|---|---|
| `01-core` … `04-apps` | upstream Slax, untouched | — |
| `20-wine.sb` | Wine and its dependency closure — on 64-bit, both halves and the i386 libraries | `noload=20-wine.sb` |
| `21-wine-desktop.sb` | launcher entry, env defaults, the wrapper | `noload=21-wine-desktop.sb` |
| `30-notepadpp32.sb` | the application layer: the 32-bit Notepad++ | `noload=30-notepadpp32.sb` |
| `31-notepadpp64.sb` | **slax64-wine only**: the 64-bit Notepad++ | `noload=31-notepadpp64.sb` |
| `20-flatpak.sb` | **slax-bottles only**: flatpak and bubblewrap | `noload=20-flatpak.sb` |
| `30-bottles.sb` | **slax-bottles only**: the Flatpak installation, DXVK/VKD3D, launcher | `noload=30-bottles.sb` |
| `98-dpkg-db.sb` | generated at pack time | — |
| `99-changes-N.sb` | a saved session, if any | — |

`05-chromium.sb` is **deleted**, not overridden. Removal is the one case where deleting beats
overriding: a whiteout hides a file but does not reclaim its space.

### Numbering

slax-kitchen's canonical table — `vendor/slax-kitchen/docs/10-anatomy/bundles-squashfs.md`:

| range | whose |
|---|---|
| `00`–`09` | upstream Slax and slax-kitchen — the platform |
| `10`–`89` | **forks** — applications and content |
| `90`–`97` | slax-kitchen headroom; `97` is the ceiling for a recipe |
| `98` / `99` | generated database / `savechanges` — **refused at apply time** |

Inside the fork band this project uses **`20`–`29` for its platform and `30`–`89` for
applications**, starting at `20` rather than `10`. The bottom of the fork band is left
to slax-kitchen's example recipes, which **grow**: `10`–`12` when this project started,
`10`–`16` today. Ceding the low end costs nothing and makes a collision impossible.

`98` and `99` are refused by every bundle verb, and the refusal is at apply time rather than in the
schema so there is one implementation rather than two that can drift.

### The swap contract

`30-notepadpp32.sb` and `31-notepadpp64.sb` are deliberately self-contained apart from the platform:
each launcher sources `/etc/profile.d/wine.sh` from `21-wine-desktop.sb` and runs `20-wine.sb`'s
Wine. **`20`+`21` are the platform; `30` and `31` are apps on it.** A variant replaces those only —
delete the file from `/slax/modules/` on a stick and drop another in, with no rebuild, or swap it
live with `slax activate`.

The application's `.desktop` entry ships **in the application bundle**, not in the platform bundle,
so swapping the bundle swaps its launcher. That property is what makes the swap a file operation.

## The package database

This changed under us during development and the current shape matters.

Bundles no longer ship `var/lib/dpkg/status` — `BUNDLE_EXCLUDE` drops it. `bundle.packages` instead
writes `var/lib/slax-kitchen/dpkg-status.d/<bundle>`, holding only the stanzas it added or changed.
`kitchen pack` then calls `lib/dpkgdb.py`, which walks the bundles in load order, takes the **highest
real `status` as the base**, applies every fragment above it, and generates `98-dpkg-db.sb` — below
`99-changes-N` so a saved session still wins.

For this image: `05-chromium` is removed, so the base is `04-apps` at 576 packages and the
`20-wine` fragment declares 60. **Measured result: 635 packages** — not 636, because the fragment
adds **59 new** entries and *upgrades* one. `libgnutls30` is in both: the base carries `3.7.9-2` and
apt moves it to `3.7.9-2+deb12u7`. Worth spelling out, because "576 + 60" reads like a derivation
and is not one.

The old design had every bundle carry a cumulative status, and a high-numbered bundle shipping a
short copy would shadow a longer one. That is gone, but its shadow remains in one place — see the
`from:` trap below.

## The `from:` trap

`bundle.packages` builds its chroot from the bundles named in `from:`, and apt installs only what
that chroot says is missing. **The default is now every bundle that will sit below this one.**

For a `20-` bundle that includes `05-chromium.sb`. Building against it and then removing it produces
an image whose binaries depend on files that left with the bundle. Measured here:

| | |
|---|---|
| `libwine` Depends | `libpulse0 (>= 0.99.1)` — hard, not a Recommends |
| `libpulse0` in `01-core`…`04-apps` | absent |
| `libpulse0` in `05-chromium.sb` | present |

The failure is silent: the build succeeds, all gates pass, and the merged database is *correct* —
it rightly does not claim `libpulse0`. You find out when Wine will not start.

Every profile removes first, and the engine refuses the other order, so `wine.yaml` takes the default
stack. It named the stack as well until the `3a44e8a` bump; see [DECISIONS.md](DECISIONS.md) D-3,
and [UPSTREAM.md](UPSTREAM.md) issue 1.

## Boot, and how `/etc/profile.d` reaches the desktop

```
firmware → isolinux/syslinux → vmlinuz + initrfs.img
  → find_data (scans every block device, up to 45 s)
  → persistent_changes  (only if "perch" appears in /proc/cmdline)
  → copy_to_ram         (only under "toram" -- init:43, BEFORE mount_bundles, and
                         unconditional over the whole directory, so noload= does not
                         reduce what it copies)
  → mount_bundles → init_union → union_append_bundles
  → copy_rootcopy_content → fstab_create → user_preinit
  → change_root → systemd → xorg.service
       ExecStart=/bin/su --login -c "/usr/bin/Xdetect -- :0 vt7 -ac -nolisten tcp"
  → startx → /root/.xinitrc ("startfluxbox") → /root/.fluxbox/startup → fluxbox
```

**`su --login` is the load-bearing link.** It makes the session a login shell, so `/etc/profile`
runs, and `01-core`'s `/etc/profile` ends with the standard `for i in /etc/profile.d/*.sh` loop.
That is why `WINEARCH` and `WINEDLLOVERRIDES` reach Fluxbox, xlunch, and everything launched from
them. `/usr/local/bin/slax-wine` sources the file again anyway, because being wrong about this
produces a Gecko prompt on an offline machine and nothing says why.

## Persistence

`persistent_changes()` activates only if the string `perch` appears in `/proc/cmdline`, then picks
one of two storage modes by testing whether the medium can do symlinks and the executable bit:

| medium | storage | limit |
|---|---|---|
| ext4 (any POSIX fs, not NTFS) | `mount --bind <medium>/slax/changes/<N>/` | none |
| FAT32 / NTFS | `dynfilefs` container `changes.dat`, split at 4000 MB, XFS inside | `perchsize`, floor **16000 MB** |

`/root/.wine` lives in the writable layer, so persistence covers the Wine prefix with no special
handling. `savechanges` is a **different** mechanism — a snapshot into `99-changes-N.sb` staged
through tmpfs — and is the wrong tool for a prefix, which will not fit in RAM.

Upstream already ships persistence on by default down one route only: `syslinux.cfg` (USB/HDD) has
`perchdir=resume` on the auto-booted entry, while `isolinux.cfg` (CD) has the session entries as
`MENU DISABLED`. A `dd`'d ISO boots through `isolinux.cfg` on a read-only filesystem, so it cannot
persist at all.

## Filesystem layering

Only one layer is a human choice:

| layer | filesystem | chosen by | when |
|---|---|---|---|
| the medium | FAT32 **or** ext4 | you, with `mkfs` | before anything is copied |
| the perch container (FAT32 path only) | XFS | Slax, automatically | first persistent boot, once |
| the running root | aufs union | Slax | every boot |

XFS is never a decision — it appears inside the container because FAT32 cannot store symlinks or the
executable bit, and a Wine prefix needs both. On ext4 there is no container and no XFS.

## Things that will bite you

A register, because every one of these cost time to find.

| | |
|---|---|
| **`from:` default includes a bundle you may delete** | see above. Remove first: the engine refuses the other order, and gate 96 §5(a3) refuses a profile that lists the removal late |
| **`Terminal=false` is mandatory on a `.desktop`** | `fbappselect` runs `ldd $binary \| grep libX11` and wraps in an xterm when empty. Debian's `/usr/bin/wine` is a shell script, so it always looks like a console program |
| **`NoDisplay` does not hide anything in xlunch** | `xlunch_genquick` greps `^(Name\|Icon\|Exec\|Hidden\|Terminal)=` and tests `Hidden`. Use `Hidden=true`. *(A `NoDisplay`-only stub vanishes anyway — see the next row — but only because it ships no `Icon=`; add one and the tile returns. Upstream now calls that a defect and its stub sets `Hidden=true`.)* |
| **An `Icon=` that does not resolve DELETES the entry** | `xlunch_genquick:52` ends each entry with `if [ -e "$Icon" ]`. The search covers only numeric size dirs under `hicolor`/`pixmaps`/`icons-gnome` and only appends `.png` — so `scalable/*.svg` and anything under `Adwaita/` are invisible, `$Icon` stays a bare string, and the launcher silently disappears. This cost slax-wine **both** its tiles. Use an absolute path, or verify with `xlunch_genquick 64 --desktop` |
| **`noautomount` is ignored** | `fstab_create` tests `grep -vq automount`, and `noautomount` *contains* `automount`. Remove the flag, do not negate it |
| **`perch` is a substring match** | `perchsize=` on the `toram` entry would enable persistence on the one entry that unmounts the medium |
| **FAT32 perch floor is 16 GB and cannot be lowered** | a smaller `perchsize=` is silently raised; the size is fixed at creation |
| **`kitchen build` fails on a custom volid** | `iso_assert.py`'s `--volid` *defaults* to `slax` (`:49`), and `lib/build.sh` never passes it. Not a hardcode — but the effect is the same, hence `build.sh` |
| **`bundle.fromTarball` is tar-only** | `tarfile.open`, so no `.zip` and no `.7z` |
| **Recipes are not idempotent** | `apply` consults its journal and refuses a second application. `build.sh` unpacks fresh every run |
| **A bundle name can be produced once** | two steps that both *run* and target the same bundle are refused — at run time, when the `.sb` already exists. Combine them into one `bundle.files`; or, per base, guard each with `when: arch==…` so exactly one runs, as `wine` and `wine-desktop` do |
| **Estimate bundle size from squashfs, not from `.deb`** | `-b 1024K` restarts xz every mebibyte, so a bundle is ~**1.4×** the `.deb`s it came from. Compare against ALL the packages installed (121.1 MiB for Wine's 60), never one headline `.deb` |
| **`98-dpkg-db.sb` appears in the output** | generated at pack time. An expected-modules assertion that omits it fails on its own build |
| **Piping into `tee` hides a failure** | the pipeline's status is `tee`'s. POSIX sh has no `PIPESTATUS`; record success out of band |
| **`savechanges` first session is `99-changes-99.sb`** | its arithmetic runs on the last file in `slax/modules/`, now `98-dpkg-db`. Harmless; it increments correctly |
| **`when: arch==` is measured from the tree** | `_detect_arch` unsquashes `01-core`, reads the ELF class of `usr/bin/ls` (or `bash`), and answers `32bit` or `64bit`; only if that fails does it look at `origin.yaml`'s `source_iso`, and then at the file name alone. So an unreadable or busybox-only `01-core` yields `arch=unknown` and every arch-guarded step skips. It read the ISO's whole path until [slax-kitchen#27](https://github.com/Fullaxx/slax-kitchen/issues/27), fixed in `cc28622` |
| **`flavour` can be `unknown`, and that refuses the build** | the same measurement, on `etc/debian_version`. It used to default to `debian`; since `012e720` an unreadable `01-core` answers `unknown`, and `bundle.packages` then refuses with "there is no package manager to use" instead of silently running apt. `flavour:` on the step, or `--facts flavour=debian`, overrides it |
| **`boot.menu` refuses an entry nothing provides** | since `a9e75a9` a `LINUX`/`KERNEL`/`COM32`/`INITRD` path must already be in the tree or be promised by a step that will run, or `apply` exits 1. `initrd=` inside `APPEND` is not parsed, which is why the Slax bases' four entries pass: each names `/slax/boot/vmlinuz`, which the ISO ships |
| **`apply --profile` holds the tree to the profile's `base:`** | since `949074b` it compares `flavour` and `arch` (never `version`, deliberately) and exits 2 before the banner: "the profile is for arch 64bit, but this work tree is 32bit". `--facts` still wins, and `--preflight-only` is exempt. It read only the recipe list until [slax-kitchen#29](https://github.com/Fullaxx/slax-kitchen/issues/29) |
| **`kitchen diff --bundles` compares content** | since `a941ca2` it extracts each differing bundle and compares type, mode, owner, size, link target and sha256 per entry, naming the field that moved, with mtimes excluded — so a rebuild reads "identical content" where it used to read DIFFERENT. Exit 2 means a bundle could not be read, which is not an answer. It compared file lists until [slax-kitchen#30](https://github.com/Fullaxx/slax-kitchen/issues/30) |
| **A reader command checks its tools first** | `lib/need.py`, since `7f8ded8`: `kitchen pack` wants `unsquashfs` and `mksquashfs` up front and exits 2 naming the package, rather than dying mid-pack over a half-written tree |

## What is verified, and what is not

`boot-verified`: the ISO boots to `slax login:` with all three livekit markers and all its bundles
mounted in order — nine on 32-bit, ten on 64-bit. Measured under TCG until the `7f9c4f8` bump, and
since then on `bacon` under KVM: twelve routes, `--kernel`, `--bios`, `--uefi` and `--persistence`
on all three test images, each reaching `Live Kit done` in 4–6 s.

`runtime-verified`, on a full desktop boot of each base: the **Wine tile opens from the launcher**
with no xterm wrapper, the **Notepad++ installer runs under Wine** and the installed editor launches,
there is **no Mono/Gecko prompt**, and the **browser is absent** from the launcher. On 64-bit the
**64-bit Notepad++** installs and runs as a 64-bit process too, and since
[D-17](DECISIONS.md#d-17--one-prefix-and-the-flip-is-a-choice) each launcher **asks before the
install that removes the other build** — seen both ways round on `slax64-wine-test` under KVM on
2026-09-21, and seen *not* to ask on `slax32-wine-test`, which is the half worth testing. All five slax-wine recipes claim this
rung. `slax-wine-iso` was the last, once the *effect* of removing `automount` was observed on both
bootloaders ([its page](50-cookbook/slax-wine-iso.md)), on each base.

**slax-bottles**, with no network device: all three boot routes reach `Live Kit done`, with
`automount` absent from both bootloaders' command lines — measured under TCG, and re-run under KVM at
the `7f9c4f8` bump, `--persistence` with them. Bottles opens from its wrapper, a bottle is
created from only what the image ships, and `cmd /c ver` runs in it (`notepad.exe` too, on the first,
hand-seeded run). Both of its
recipes claim `runtime-verified`, and [bottles](50-cookbook/bottles.md) says which run measured what.
Persistence on ext4 perch is observed on it too: `kitchen test --persistence` on `slax-bottles-test`,
the marker written on boot 1 and found on boot 2.

**Persistence, ext4 native perch: observed.** Two boots of `slax32-wine-test` on one ext4 perch disk
under `kitchen test --persistence` — boot 1 wrote a marker into the union and `sync`ed it, boot 2
found it (`perch-marker: present`), both reaching `Live Kit done`. The same run also boot-asserted
that all seven of our launcher files reached the assembled union with the right sizes, which is one
rung below "the tile appears" and is the half a machine can check.

**Both bootloaders, and UEFI: observed.** Measured 2026-09-18 on a KVM host against
`slax32-wine-test`: `kitchen test --bios` boots through isolinux and `--uefi` boots through GRUB under
x86-64 OVMF, each reaching `Live Kit done` in 6 s, each selecting the serial entry. Their kernel
command lines carry **no `automount`**, while the `--kernel` control — whose cmdline the harness
builds and which *does* carry it — shows it present. That pairing is what makes the negative result
mean something.

**Still unverified:** the **FAT32** persistence route entirely — dynfilefs container, XFS inside it,
`perchsize=`, `xfs_growfs` — plus `bootinst`, a stick, and real hardware. The persistence harness
deliberately uses raw ext4 on a bare file, and **no UEFI boot has ever gone through `bootinst`'s
`syslinux.efi`**, which is a different loader from the GRUB the uefi image carries. So roughly half
of what [INSTALL.md](../INSTALL.md) promises is measured and half is still read from `livekitlib`,
and the document says which is which.

The ladder is in the [cookbook index](50-cookbook/README.md), and the distinction is the one thing
this project treats as a real error.
