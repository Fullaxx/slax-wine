# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are semver.

A release is defined by **both** halves — the slax-wine version and the base ISO it was built on.
See [docs/base-versions.md](docs/base-versions.md).

## [1.0.0] — unreleased

Built on `slax-32bit-debian-12.2.0.iso`
(`03b85cd259883f6781b3a3f30ed409b0b6a542b8f510094594c7600bd94e546b`), with slax-kitchen pinned at
`86d27d5`.

**Two images, same system.** `slax-wine-bios-1.0.0.iso` (507.3 MiB) uses the stock Slax bootloader.
`slax-wine-uefi-1.0.0.iso` (513.5 MiB) adds upstream's `uefi-bootable` recipe — a GRUB EFI loader in
an El Torito ESP — and is a **superset**: it keeps the BIOS entry, so it boots everywhere the first
does, and the **ISO** additionally boots on UEFI firmware. It changes nothing about USB sticks: its
GRUB lives in an El Torito ESP, which `bootinst` never copies, so both images fall back to the stock
FAT-only `syslinux.efi` there. Both carry the same nine bundles.

**And a third image, a different system: `slax-bottles-1.0.0.iso` (1241.7 MiB).** Built on
`slax-64bit-debian-12.2.0.iso` (`61d9fdcc006938d6fd6f231e22d8af926ae8f48fdf0487b8010e69f3bd17cf70`),
because Bottles exists only as an x86_64 Flatpak. It carries no Debian Wine: Bottles runs its own. See
[docs/DECISIONS.md](docs/DECISIONS.md) D-14 and D-15.

### Added
- `bottles` (slax-bottles only). `flatpak` from bookworm as `20-flatpak.sb` (8.0 MiB), and as
  `30-bottles.sb` (890.8 MiB): the Bottles 67.3 Flatpak installation with its 12 runtime refs, each
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
- `wine` — Wine 8.0~repack-4 from Debian bookworm main as `20-wine.sb` (166.6 MiB), built on a
  stack that no longer contains the browser.
- `wine-desktop` — launcher entry, `WINEARCH`/`WINEDLLOVERRIDES` defaults, the `slax-wine` wrapper
  and `/etc/slax-wine-release`, as `21-wine-desktop.sb` (4 KiB).
- `notepadpp` — the Notepad++ 8.9.8 NSIS installer and its launcher as `30-notepadpp.sb` (6.4 MiB),
  the swappable application layer.
- `slax-wine-iso` — `automount` removed from the boot line, ISO identity, sha256 beside the image.
  The removal is **runtime-verified**: absent from the kernel command line on both the isolinux
  and GRUB boot paths, against a control boot that shows the check can detect it.
- `build.sh`, twelve commit gates, and the engineering documentation set. Gate 80 runs
  upstream's `tests/unit/test_desktop_entries.py`, which refuses a `.desktop` whose `Icon=` Slax's
  launcher generator would fail to resolve — the trap that silently deleted **both** of this
  image's launchers before it was caught by hand.
- `uefi-bootable` — **upstream's** recipe, applied only by `profiles/slax-wine-uefi.yaml`. Builds no
  bundle; adds one 6.2 MiB `boot/efi.img`.

### Known limitations
- **Persistence: half observed, half still not.** The **ext4 native perch** path now survives a
  reboot in a VM — two boots on one disk, marker written and `sync`ed on the first, found on the
  second. The **FAT32 route is untested**: no dynfilefs container, no XFS, no `perchsize=`, no
  `xfs_growfs`, and nothing has run `bootinst` or booted from a real stick. So the Wine `C:` drive
  surviving on the kind of stick most people will use is still read from source, not measured.
- **UEFI from a stick is untested, on either image.** The `slax-wine-uefi` ISO itself now boots under
  x86-64 OVMF — measured, GRUB to `Live Kit done` in 6 s. But a `bootinst`-prepared stick uses
  `syslinux.efi`, a different loader in a different place, and **nobody has booted that**. The uefi
  image does not change it: its GRUB is an El Torito structure that never reaches a stick.
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
  UEFI firmware and no legacy/CSM cannot boot this image by any route. 64-bit UEFI from a FAT32
  stick is expected to work but has **not** been tested here — only a direct-kernel boot was run.
- Releases are **unsigned by choice** — this project has no signing key. (`iso.checksums: sign`
  was unusable upstream when this was written; that was our issue 3 and it was fixed in `7971eb5`,
  which is in the pinned engine.)
