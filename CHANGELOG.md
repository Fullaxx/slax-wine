# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are semver.

A release is defined by **both** halves — the slax-wine version and the base ISO it was built on.
See [docs/base-versions.md](docs/base-versions.md).

## [1.0.0] — unreleased

Built on two bases, `slax-32bit-debian-12.2.0.iso`
(`03b85cd259883f6781b3a3f30ed409b0b6a542b8f510094594c7600bd94e546b`) and
`slax-64bit-debian-12.2.0.iso` (`61d9fdcc006938d6fd6f231e22d8af926ae8f48fdf0487b8010e69f3bd17cf70`),
with slax-kitchen pinned at `b4eb25b`.

**Four slax-wine images, one system: bios and uefi on each base** ([docs/DECISIONS.md](docs/DECISIONS.md)
D-16).

| image | size | |
|---|---|---|
| `slax32-wine-bios-1.0.0.iso` | 507.3 MiB | 32-bit base, the stock Slax bootloader |
| `slax32-wine-uefi-1.0.0.iso` | 513.5 MiB | 32-bit base, plus upstream's `uefi-bootable` |
| `slax64-wine-bios-1.0.0.iso` | 815.6 MiB | 64-bit base, the stock Slax bootloader |
| `slax64-wine-uefi-1.0.0.iso` | 821.7 MiB | 64-bit base, plus upstream's `uefi-bootable` |

A uefi image is a **superset** of its bios twin: `uefi-bootable` adds a GRUB EFI loader in an El
Torito ESP and keeps the BIOS entry, so it boots everywhere the bios image does, and the **ISO**
additionally boots on UEFI firmware. It changes nothing about USB sticks: its GRUB lives in an El
Torito ESP, which `bootinst` never copies, so every image falls back to the stock FAT-only
`syslinux.efi` there. The 32-bit images carry nine bundles; the 64-bit ones the same nine plus the
64-bit Notepad++. The 64-bit images run 64-bit Windows programs as well as 32-bit ones.

**And a different system: `slax-bottles-1.0.0.iso` (1240.4 MiB)**, on the 64-bit base, because
Bottles exists only as an x86_64 Flatpak. It carries no Debian Wine: Bottles runs its own. See
[docs/DECISIONS.md](docs/DECISIONS.md) D-14 and D-15.

### Added
- **Each Notepad++ launcher asks before the install that removes the other build**
  ([DECISIONS.md](docs/DECISIONS.md) D-17, slax-wine#1). Notepad++'s own installers remove each
  other; the prefix stays single, and the flip becomes a choice: a dialog naming what will go and
  offering a prefix of its own — the 32-bit one at 589 MiB where that is what is wanted, rather
  than another 1,265 MiB 64-bit prefix — with **Cancel as the default** and Cancel exiting 0
  silently. With no display nothing is installed. On slax32 nothing asks at all — there the x86
  build owns `Program Files` itself. Verified under KVM in both directions, with the slax32
  negative control.
- `bottles` (slax-bottles only). `flatpak` from bookworm as `20-flatpak.sb` (8.0 MiB), and as
  `30-bottles.sb` (889.5 MiB): the Bottles 67.3 Flatpak installation with its 12 runtime refs, each
  pinned by ostree commit in `BOTTLES_LOCK`, plus DXVK 3.1 and VKD3D-Proton 3.0.1, a launcher tile and
  `/etc/slax-bottles-release`. **Runtime-verified in QEMU with no network**: a bottle is created with
  the bundled `sys-wine-11.0` runner from only what the image ships, and `cmd /c ver` runs in it
  (`notepad.exe` too, on the first run, when DXVK/VKD3D were unpacked by hand). DXVK/VKD3D ship
  because, measured, Bottles refuses to create a bottle offline without them. Persistence observed
  on ext4 perch: two boots of `slax-bottles-test` on one disk, the marker written on the first and
  found on the second.
- `slax-bottles-iso` (slax-bottles only): `automount` removed, volume id `SLAX-BOTTLES`, sha256
  beside the image. Two steps copied from `slax-wine-iso`, which is itself unchanged.
- `profiles/slax-bottles.yaml` and `slax-bottles-test.yaml`; `build.sh --bottles`,
  `--bottles-test`, `--all`, and `BOTTLES_RELOCK=1` for bumping the pin.
- `docs/using-bottles.md`.
- `docs/software.md`: what each ISO removes, adds and runs, and what it needs from the machine
  (CPU, firmware, memory, GPU, storage), each figure marked measured or not. The exact versions
  are generated rather than kept by hand: every build writes `out/<image>-<ver>.packages.tsv` from
  the image's own `98-dpkg-db.sb` (626 installed packages on slax-wine, 597 on slax-bottles), and
  slax-bottles also `out/slax-bottles-<ver>.flatpak.txt`.
- `remove-bundle` — **upstream's** recipe, listed **first** by every profile. Drops
  `05-chromium.sb` (81.7 MiB), which is what pays for Wine. Each profile spells out `drop:
  "^05-chromium\.sb$"` rather than inheriting the recipe's identical default, so a later pin cannot
  change what the image deletes without the change being visible here. The engine refuses any plan
  where a removal follows something that builds, and `ci/checks/96-release-consistency.sh` §5(a3)
  additionally refuses a shipped profile that drops the removal or lists it late.
- `wine` — Wine 8.0~repack-4 from Debian bookworm main as `20-wine.sb`, built on a stack that no
  longer contains the browser, with one step per base. On 32-bit, the i386 Wine (166.6 MiB). On
  64-bit, both halves — `wine64`, and `wine32` from **i386** through `apt.architectures`, with an
  i386 copy of every library the 32-bit image gives its programs (465.9 MiB). `wine32` is only a
  Recommends of `wine64`, so it is named, and `build.sh` refuses a 64-bit image without it.
- `wine-desktop` — launcher entry, the `WINEDLLOVERRIDES` default (and `WINEARCH=win32` on the
  32-bit base only), the `slax-wine` wrapper and `/etc/slax-wine-release`, as `21-wine-desktop.sb`
  (4 KiB). One step per base; the three files both share are written once, as YAML anchors.
- `notepadpp32` — the 32-bit Notepad++ 8.9.8 NSIS installer and its launcher as
  `30-notepadpp32.sb` (6.4 MiB), on every image. Its launcher finds the installed editor from the
  prefix's own architecture — `Program Files (x86)` in a 64-bit prefix — and follows `WINEPREFIX`.
- `notepadpp64` — the 64-bit Notepad++ 8.9.8 installer and its launcher as `31-notepadpp64.sb`
  (6.5 MiB), on the 64-bit images. The installer is itself PE32 and installs x86-64 binaries, so it
  exercises a 32-bit installer under WoW64 and then a 64-bit program.
- `slax-wine-iso` — `automount` removed from the boot line, ISO identity (`SLAX32-WINE` or
  `SLAX64-WINE`, one step per base), sha256 beside the image. The removal is
  **runtime-verified**: absent from the kernel command line on both the isolinux and GRUB boot
  paths, against a control boot that shows the check can detect it.
- `build.sh`, twelve commit gates, and the engineering documentation set. Gate 80 runs
  upstream's `tests/unit/test_desktop_entries.py`, which refuses a `.desktop` whose `Icon=` Slax's
  launcher generator would fail to resolve — the trap that silently deleted **both** of this
  image's launchers before it was caught by hand.
- `uefi-bootable` — **upstream's** recipe, applied only by the uefi profiles. Builds no bundle;
  adds one 6.2 MiB `boot/efi.img`.
- `docs/testing-on-both.md`: running one Windows program on both bases, and what differs underneath.
- `build.sh --32`/`--64` with `--bios`/`--uefi`/`--both`/`--test`; a bare `./build.sh` builds all
  four slax-wine images. It now also refuses a profile whose base is not the ISO it unpacked, an
  image whose release file names another base, and a 64-bit image without both halves of Wine. The
  first of those covers an engine gap, filed upstream as
  [slax-kitchen#29](https://github.com/Fullaxx/slax-kitchen/issues/29); the other two catch what
  [#27](https://github.com/Fullaxx/slax-kitchen/issues/27) can do to an arch-guarded build.

### Fixed
- **The Notepad++ question is asked only where there is a display to ask on.** `DISPLAY` being set
  is not the same as a display that opens — Slax's desktop is on `:1`, so a stale `:0` fails — and
  the first version read that failure as a decline and exited 0 in silence, installing nothing and
  saying nothing. It now tests with `xset q` first and says so instead.
- `notepadpp64` refuses `WINEARCH=win32` **before** a prefix exists. It already refused a 32-bit
  prefix it found on disk; with the variable set and no prefix yet, `wine` created a 32-bit one and
  ran the x64 installer in it, so the user got "the installer was cancelled or failed" a minute
  later instead of the accurate refusal straight away.

### Known limitations
- **Persistence: half observed, half still not.** The **ext4 native perch** path now survives a
  reboot in a VM — two boots on one disk, marker written and `sync`ed on the first, found on the
  second. The **FAT32 route is untested**: no dynfilefs container, no XFS, no `perchsize=`, no
  `xfs_growfs`, and nothing has run `bootinst` or booted from a real stick. So the Wine `C:` drive
  surviving on the kind of stick most people will use is still read from source, not measured.
- **UEFI from a stick is untested, on any image.** The `slax32-wine-uefi` ISO itself now boots under
  x86-64 OVMF — measured, GRUB to `Live Kit done` in 6 s. But a `bootinst`-prepared stick uses
  `syslinux.efi`, a different loader in a different place, and **nobody has booted that**. The uefi
  image does not change it: its GRUB is an El Torito structure that never reaches a stick.
- **slax64-wine's Linux is newer than stock Slax's.** Installing Wine's i386 half lifted 79 of the
  base's own packages to today's bookworm versions, inside `20-wine.sb` — glibc, systemd and udev,
  util-linux, e2fsprogs and OpenSSL among them (D-16 lists them). Measured, under TCG: it boots on
  all three routes and its ext4 persistence holds across two boots. Booted with `noload=20-wine.sb`,
  its package database claims those versions while the base's older files are the ones loaded.
  slax32-wine has one such upgrade, `libgnutls30`.
- **slax64-wine has only been run in QEMU**, under TCG, like slax-bottles. Real hardware is untested.
- **The two Notepad++ builds do not share a prefix.** On slax64-wine each one's installer removes the
  other build, measured in both orders, so the two tiles reinstall over each other in `/root/.wine`.
  Since D-17 the launcher **asks before letting that happen**, with Cancel as the default, and a
  separate prefix for one of them keeps both — but the installers' behaviour is theirs, and nothing
  here changes it.
- **A Wine prefix is large, and without persistence it lives in RAM**: Wine copies its Windows-side
  libraries into it, 1,265 MiB for a 64-bit prefix and 589 MiB for a 32-bit one. Making one takes
  65 s under KVM and about 4 minutes under emulation, and Wine waits at most 5: past that, the
  first launch fails and the second works, which happened once on a busy emulated host.
- slax-wine has no Wine Mono or Wine Gecko, so .NET and embedded-HTML applications do not run.
  Debian packages neither; the first-run prompt is suppressed rather than satisfied. (slax-bottles
  ships both, as Flathub runtimes.)
- **slax-bottles has only been run in QEMU**, under TCG. Real hardware is untested, and with it the
  whole GPU path: DXVK 3.x needs a Vulkan 1.4 driver, the runtime's Mesa has one, and whether a real
  GPU initialises under Slax's 6.1 kernel with no GPU firmware is unknown. A bottle surviving a
  reboot is not tested either, though the writable layer it lives in is. Offline, its first-run
  wizard cannot finish and offers "Skip Setup", which is expected. See
  [docs/using-bottles.md](docs/using-bottles.md).
- No GPU firmware, because stock Slax ships none — 3D under Wine falls back to software rendering.
- No browser: `05-chromium.sb` is removed. It is gone from the xlunch launcher; the Fluxbox
  right-click menu still carries a "Web Browser" entry that offers to `apt install` one, because
  that menu is a static file in a stock bundle. See
  [wine-desktop](docs/50-cookbook/wine-desktop.md).
- **No 32-bit UEFI.** Slax ships only `bootx64.efi` and no `bootia32.efi`, so machines with 32-bit
  UEFI firmware and no legacy/CSM cannot boot any of these images at all. 64-bit UEFI from a FAT32
  stick is expected to work but has **not** been tested here — only a direct-kernel boot was run.
- Releases are **unsigned by choice** — this project has no signing key. (`iso.checksums: sign`
  was unusable upstream when this was written; that was our issue 3 and it was fixed in `7971eb5`,
  which is in the pinned engine.)
